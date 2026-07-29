# OpenShift Oracle New Region — Analysis Report

---

## Table of Contents

1. [Question 1: Oracle Golang Modules](#question-1-oracle-golang-modules)
   - [Oracle Modules in the Broader OpenShift Ecosystem](#oracle-modules-in-the-broader-openshift-ecosystem)
   - [How OpenShift on OCI Works Today](#how-openshift-on-oci-works-today)
2. [Question 2: Oracle Go SDK Support for Private/Government Regions](#question-2-oracle-go-sdk-support-for-privategovernment-regions)
   - [Built-in Government Realms](#built-in-government-realms)
   - [Registering Unknown/Custom Regions](#registering-unknowncustom-regions)
   - [Endpoint Construction](#endpoint-construction)
   - [Environment Variables for Isolated Regions](#environment-variables-for-isolated-regions)
   - [Custom CA Certificates](#custom-ca-certificates)
3. [Key Takeaway for the Oracle IL6 Effort](#key-takeaway-for-the-oracle-il6-effort)

---

## Question 1: Oracle Golang Modules

### Oracle Modules in the Broader OpenShift Ecosystem

| Go Module | Role | Owner | In Installer? | In Cluster? |
|-----------|------|-------|---------------|-------------|
| `github.com/oracle/oci-go-sdk/v65` | Core OCI API client SDK — provides client libraries for all OCI services (compute, networking, identity, load balancing, block storage, file storage, object storage, DNS, container engine, etc.) | Oracle | **No** | Yes (transitive dep via CCM) |
| `github.com/oracle/oci-cloud-controller-manager` | Kubernetes Cloud Controller Manager (CCM) + CSI driver for OCI. Implements NodeController and ServiceController. Has built-in OpenShift awareness (`openshiftNodeLabelId`, `openshiftOSLabelKey`, `OpenShiftTagNamesapcePrefix`). | Oracle | **No** | Yes (deployed as DaemonSet) |
| `github.com/oracle/cluster-api-provider-oci` | Cluster API (CAPI) infrastructure provider for OCI. Supports both self-managed (VMs) and OKE-managed clusters. | Oracle | **No** | Experimental/TechPreview only |

**Key OCI Go SDK sub-packages:**

- `v65/common` — region configuration, authentication, base client
- `v65/core` — compute, networking, block volume
- `v65/identity` — IAM, compartments, tenancy
- `v65/loadbalancer` — load balancer service
- `v65/filestorage` — file storage (NFS)
- `v65/objectstorage` — object storage (S3-compatible)
- `v65/containerengine` — OKE (Oracle Kubernetes Engine)
- `v65/dns` — DNS management

### How OpenShift on OCI Works Today

OpenShift does **not** have IPI (Installer Provisioned Infrastructure) support for OCI. OCI is handled as an **external platform** (`platform: external`, `platformName: oci`). The supported installation methods are **Assisted Installer** (OCP 4.14+) and **Agent-based Installer**.

The deployment flow:

1. **Infrastructure** is provisioned via Terraform from the [`oracle-quickstart/oci-openshift`](https://github.com/oracle-quickstart/oci-openshift) repository (HCL, not Go).
2. **Installer** runs with `platform: external`, `platformName: oci`, `cloudControllerManager: External`.
3. **CCM** (`oracle/oci-cloud-controller-manager`) is deployed as a DaemonSet via custom manifests from the `oracle-quickstart/oci-openshift` repo.
4. **CSI driver** (also part of `oracle/oci-cloud-controller-manager`) is deployed similarly for block/file storage.
5. Node identity is established via OCI Instance Metadata Service (IMDS) at `169.254.169.254/opc/v2/instance/`.

---

## Question 2: Oracle Go SDK Support for Private/Government Regions

**The OCI Go SDK fully supports private/isolated government cloud regions.** No SDK source code modifications are required. The SDK was designed from the start for disconnected, air-gapped, and sovereign environments.

### Built-in Government Realms

The SDK ships with hardcoded support for these government/sovereign realms:

| Realm Key | Domain | Purpose | Example Regions |
|-----------|--------|---------|-----------------|
| `oc1` | `oraclecloud.com` | Commercial public cloud | `us-ashburn-1`, `us-phoenix-1`, `eu-frankfurt-1` |
| `oc2` | `oraclegovcloud.com` | US Gov (Intelligence Community) | `us-langley-1`, `us-luke-1` |
| `oc3` | `oraclegovcloud.com` | US Gov (FedRAMP) | `us-gov-ashburn-1`, `us-gov-phoenix-1` |
| `oc4` | `oraclegovcloud.uk` | UK Government | `uk-gov-london-1` |
| `oc8` | `oraclecloud8.com` | Japan Sovereign | `ap-chiyoda-1` |
| `oc9` | `oraclecloud9.com` | Dedicated | `me-dcc-muscat-1` |
| `oc10`–`oc52` | `oraclecloud10.com`–`oraclecloud52.com` | Various dedicated/sovereign regions | (varies) |
| `oc14` | `oraclecloud14.com` | EU Sovereign | (varies) |
| `oc19` | `oraclecloud19.com` | EU Sovereign | `eu-frankfurt-2`, `eu-madrid-2` |

The SDK defines Go constants such as `RegionUSGovAshburn1`, `RegionUSGovPhoenix1`, `RegionUSLangley1`, `RegionUSLuke1`, `RegionUKGovLondon1`, etc.

### Registering Unknown/Custom Regions

If Oracle's new private government regions are not yet hardcoded in the SDK, there are **five mechanisms** to register them without modifying SDK source code:

#### Method A: Regions Configuration File (recommended for air-gapped environments)

Create `~/.oci/regions-config.json`:

```json
[
  {
    "realmKey": "oc99",
    "realmDomainComponent": "my-private-gov-cloud.mil",
    "regionKey": "PGC1",
    "regionIdentifier": "us-private-gov-1"
  }
]
```

#### Method B: Environment Variable (`OCI_REGION_METADATA`)

```bash
export OCI_REGION_METADATA='{"realmKey":"oc99","realmDomainComponent":"my-private-gov-cloud.mil","regionKey":"PGC1","regionIdentifier":"us-private-gov-1"}'
```

#### Method C: Programmatic Registration (`common.AddRegionSchemaForPlc()`)

```go
import "github.com/oracle/oci-go-sdk/v65/common"

common.AddRegionSchemaForPlc(map[string]string{
    "regionIdentifier":     "us-private-gov-1",
    "regionKey":            "pgc1",
    "realmKey":             "oc99",
    "realmDomainComponent": "my-private-gov-cloud.mil",
})
```

This populates the SDK's internal `shortNameRegion`, `realm`, and `regionRealm` maps, enabling automatic endpoint construction for the custom region.

#### Method D: Instance Metadata Service (IMDS) Lookup

When running inside an OCI instance:

```go
common.EnableInstanceMetadataServiceLookup()
```

The SDK queries `http://169.254.169.254/opc/v2/instance/regionInfo` for the region's metadata. Useful when running within a Dedicated/Isolated Region where the instance already knows its region.

#### Method E: Developer Tool Configuration File

Use `~/.oci/developer-tool-configuration.json` (or a path set via `OCI_DEVELOPER_TOOL_CONFIGURATION_FILE_PATH`). Combined with `OCI_ALLOW_ONLY_DEVELOPER_TOOL_CONFIGURATION_REGIONS=true`, this restricts the SDK to only your custom-defined regions.

### Endpoint Construction

The SDK constructs service endpoints using a template pattern:

```
https://{serviceEndpointPrefix}.{regionIdentifier}.oci.{realmDomainComponent}
```

Examples:

- **Commercial:** `https://compute.us-ashburn-1.oraclecloud.com`
- **US Gov:** `https://compute.us-gov-phoenix-1.oraclegovcloud.com`
- **Custom private:** `https://compute.us-private-gov-1.my-private-gov-cloud.mil`

Once a custom region is registered with its realm domain component, all service endpoints are constructed automatically.

**Direct host override** is also available per service client:

```go
client, _ := compute.NewComputeClientWithConfigurationProvider(configProvider)
client.Host = "https://compute.us-private-gov-1.my-private-gov-cloud.mil"
```

**Realm-specific endpoint templates** can be enabled for non-standard URL patterns:

```go
client.SetCustomClientConfiguration(common.CustomClientConfiguration{
    RealmSpecificServiceEndpointTemplateEnabled: common.Bool(true),
})
```

Or globally:

```bash
export OCI_REALM_SPECIFIC_SERVICE_ENDPOINT_TEMPLATE_ENABLED=true
```

**Dotted region names:** If the region identifier contains a `.`, the SDK uses `{service}.{region}` directly, allowing fully qualified domain names to be passed as the region.

**Fallback for completely unknown regions:** Without registered metadata, the SDK falls back to the `oc1` realm (`oraclecloud.com`). Override with:

```bash
export OCI_DEFAULT_REALM=my-private-gov-cloud.mil
```

### Environment Variables for Isolated Regions

| Variable | Purpose |
|----------|---------|
| `OCI_REGION_METADATA` | JSON blob defining custom region metadata |
| `OCI_DEFAULT_REALM` | Fallback realm domain for unknown regions |
| `OCI_REALM_SPECIFIC_SERVICE_ENDPOINT_TEMPLATE_ENABLED` | Enable per-realm endpoint templates |
| `OCI_SDK_AUTH_CLIENT_REGION_URL` | Auth endpoint URL for instance principals in custom realms |
| `OCI_DEFAULT_CERTS_PATH` | Custom CA bundle path for internal CAs |
| `OCI_DEFAULT_CLIENT_CERTS_PATH` | Custom client certificate path |
| `OCI_DEFAULT_CLIENT_CERTS_PRIVATE_KEY_PATH` | Custom client certificate key path |
| `OCI_DEFAULT_REFRESH_INTERVAL_FOR_CUSTOM_CERTS` | Cert refresh interval in minutes (default 30) |
| `OCI_METADATA_BASE_URL` | Override IMDS base URL |
| `OCI_DEVELOPER_TOOL_CONFIGURATION_FILE_PATH` | Custom developer tool config file location |
| `OCI_ALLOW_ONLY_DEVELOPER_TOOL_CONFIGURATION_REGIONS` | Restrict to only custom-defined regions |

### Custom CA Certificates

For isolated regions with internal certificate authorities:

```bash
export OCI_DEFAULT_CERTS_PATH="/path/to/custom-ca-bundle.pem"
export OCI_DEFAULT_CLIENT_CERTS_PATH="/path/to/client-cert.pem"
export OCI_DEFAULT_CLIENT_CERTS_PRIVATE_KEY_PATH="/path/to/client-key.pem"
```

### Instance Principal Authentication in Custom Realms

```bash
export OCI_SDK_AUTH_CLIENT_REGION_URL="https://identity.us-private-gov-1.my-private-gov-cloud.mil"
```

---

## Key Takeaway for the Oracle IL6 Effort

### SDK Comparison

The Oracle Go SDK's region registration model is **fundamentally more flexible** than some others.

The Oracle SDK provides all of this **out of the box** through its realm/region registration system. The four pieces of information needed — `realmKey`, `realmDomainComponent`, `regionKey`, `regionIdentifier` — enable all service endpoints to be derived automatically without any SDK source modifications.

### Recommended Configuration Approach for Private OCI Regions

For the Oracle IL6 equivalent, the recommended approach:

1. **Register the custom region** using `~/.oci/regions-config.json` (file-based, no internet needed) or `common.AddRegionSchemaForPlc()` (programmatic), providing realm key, realm domain component, region key, and region identifier.
2. **Set custom CA certificates** via `OCI_DEFAULT_CERTS_PATH` if the region uses an internal certificate authority.
3. **Enable realm-specific endpoint templates** via `OCI_REALM_SPECIFIC_SERVICE_ENDPOINT_TEMPLATE_ENABLED=true` so endpoint construction uses the correct domain for the realm.
4. **Optionally override `client.Host`** per service client if endpoint URLs differ from the standard template pattern.
5. If using instance principal authentication, set `OCI_SDK_AUTH_CLIENT_REGION_URL` to the region's identity endpoint.

---

## Sources

- Oracle OCI Adding Regions documentation: https://docs.oracle.com/en-us/iaas/Content/API/Concepts/sdk_adding_new_region_endpoints.htm
- OCI Go SDK (pkg.go.dev): https://pkg.go.dev/github.com/oracle/oci-go-sdk/v65/common
- OCI Go SDK GitHub: https://github.com/oracle/oci-go-sdk
- Oracle Cloud Isolated Regions: https://www.oracle.com/government/govcloud/isolated/
- Oracle Dedicated Regions: https://docs.oracle.com/en-us/iaas/Content/General/Concepts/dedicatedregions.htm
- Oracle Sovereign Cloud Realms: https://blogs.oracle.com/cloud-infrastructure/sovereign-cloud-realms-enhanced-isolation
- Oracle Regions and Availability Domains: https://docs.oracle.com/en-us/iaas/Content/General/Concepts/regions.htm
- Oracle Cloud for Sovereignty: https://www.oracle.com/cloud/sovereign-cloud/
- OCI Cloud Controller Manager: https://github.com/oracle/oci-cloud-controller-manager
- Cluster API Provider OCI: https://github.com/oracle/cluster-api-provider-oci
- Oracle Quickstart for OpenShift: https://github.com/oracle-quickstart/oci-openshift
