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
4. [Phase 2: Isolated Realm Support (OC6, OC7, OC11, OC12)](#phase-2-isolated-realm-support-oc6-oc7-oc11-oc12)
   - [Realm Status in Public SDKs](#realm-status-in-public-sdks)
   - [Where Region/Realm Information Flows Today](#where-regionrealm-information-flows-today)
   - [`OCI_REALM_SPECIFIC_SERVICE_ENDPOINT_TEMPLATE_ENABLED`](#oci_realm_specific_service_endpoint_template_enabled)
   - [Concrete Gaps and Proposed Terraform Changes](#concrete-gaps-and-proposed-terraform-changes)
   - [OCIR Hardcoded Domain Explained](#ocir-hardcoded-domain-explained)
   - [Proposed Terraform Changes](#proposed-terraform-changes)
   - [Summary of Required Changes](#summary-of-required-changes)

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

## Phase 2: Isolated Realm Support (OC6, OC7, OC11, OC12)

### Realm Status in Public SDKs

OC6, OC7, OC11, and OC12 are **not hardcoded in any public Oracle SDK** — not the Go SDK, not the Python SDK/CLI, and not the OCI Terraform provider. The latest SDK releases define OC1–OC4, OC8–OC10, OC14, OC15, OC19–OC21, OC23–OC24, OC26, OC29, OC35, OC42, OC51, OC52 — but OC6/7/11/12 are conspicuously absent. They appear only in OCI Cloud@Customer known-issues documentation noting billing API limitations. These are classified/restricted realms for national-security-grade isolated regions.

This means every component in the OpenShift-on-OCI stack that constructs OCI API endpoints must be told about these realms explicitly. Without registration, the Go SDK falls back to OC1 (`oraclecloud.com`), producing incorrect endpoints that will fail silently or with auth errors.

### Where Region/Realm Information Flows Today

The current terraform stack has a **partial** region metadata pipeline. Here is the full flow:

```
IMDS (169.254.169.254/opc/v2/instance/regionInfo)
  ↓
meta module (region-meta.tf) → region_metadata output (JSON string)
  ↓
manifest module (locals.tf) → templatefile("01-oci-csi.yml.tpl")
  ↓
CSI DaemonSet env: OCI_REGION_METADATA  ← ONLY the CSI driver gets this
```

| Component | Gets `OCI_REGION_METADATA`? | Gets `regions-config.json`? | Relies on IMDS? | Will it work in OC6/7/11/12? |
|-----------|---------------------------|---------------------------|-----------------|------------------------------|
| **Terraform provider** | No (uses own SDK chain) | Yes (if file exists on host) | Optional (`visitIMDS=true`) | Only if region is registered via env var or regions-config.json |
| **CSI driver** | **Yes** (via template) | No | Yes (runs on OCI nodes) | **Probably yes** — if IMDS returns correct regionInfo in isolated realms |
| **CCM** | **No** | No | Yes (runs on OCI nodes with hostNetwork) | **Unknown** — depends on whether the Go SDK version in the CCM image has IMDS lookup enabled, and whether IMDS returns correct data |
| **CAPOCI autoscaler** | No | No | Yes (`ENABLE_INSTANCE_METADATA_SERVICE_LOOKUP=true`) | Unknown — same IMDS dependency |
| **OCIR module** | No | No | No | **Broken** — hardcoded `.ocir.io` domain |

### `OCI_REALM_SPECIFIC_SERVICE_ENDPOINT_TEMPLATE_ENABLED`

This environment variable tells the OCI SDK (Go and Python) to use realm-specific endpoint URL templates instead of the default OC1 pattern. It is supported by:

- **OCI Python SDK / CLI** — documented in the official SDK
- **OCI Go SDK** — `common.CustomClientConfiguration{RealmSpecificServiceEndpointTemplateEnabled: true}` or the env var
- **OCI Terraform provider** — `realm_specific_service_endpoint_template_enabled` attribute in the provider block

This is **critical for isolated realms** where the API endpoint URL pattern differs from commercial OC1. Without it, endpoint construction uses the OC1 template even when the correct realm domain component is known.

Currently, **nothing in the terraform stack or manifests sets this variable**. It needs to be:

1. Set in the Terraform provider block for terraform operations
2. Injected as an env var in the CCM DaemonSet for CCM API calls
3. Injected as an env var in the CSI DaemonSet (alongside `OCI_REGION_METADATA`)
4. Injected as an env var in the CAPOCI controller (if autoscaler is used)

### Concrete Gaps and Proposed Terraform Changes

#### Gap 1: CCM Has No Region Metadata Injection

The CCM manifest is loaded via `file()` (a static YAML file at `oci-ccm-csi-drivers/v1.34.0/01-oci-ccm.yml`) — no templating. The only env var it gets is `OPENSHIFT_NODE_LABEL_ID`. In isolated realms where the Go SDK doesn't recognize the region, the CCM will fail to construct API endpoints.

**Proposed fix:** Convert the CCM YAML to a `.tpl` template (like the CSI driver already is) and conditionally inject `OCI_REGION_METADATA` and `OCI_REALM_SPECIFIC_SERVICE_ENDPOINT_TEMPLATE_ENABLED`:

```yaml
env:
  - name: OPENSHIFT_NODE_LABEL_ID
    value: node.openshift.io/os_id=rhel
  %{~ if region_metadata != "" ~}
  - name: OCI_REGION_METADATA
    value: '${region_metadata}'
  - name: OCI_REALM_SPECIFIC_SERVICE_ENDPOINT_TEMPLATE_ENABLED
    value: "true"
  %{~ endif ~}
```

**Files to change:**
- Rename `oci-ccm-csi-drivers/v1.34.0/01-oci-ccm.yml` → `manifest-templates/01-oci-ccm.yml.tpl`
- Update `manifest/main.tf` to use `templatefile()` instead of `file()` for the CCM
- Update `manifest/locals.tf` to produce the rendered CCM
- Add `OCI_REALM_SPECIFIC_SERVICE_ENDPOINT_TEMPLATE_ENABLED` to the CSI template as well

#### Gap 2: OCIR Domain Hardcoded to `.ocir.io`

See [OCIR Hardcoded Domain Explained](#ocir-hardcoded-domain-explained) below for the full trace of this issue.

#### Gap 3: Terraform Provider Needs Realm-Specific Endpoint Template Support

The OCI Terraform provider supports `realm_specific_service_endpoint_template_enabled` in the provider block. For isolated realms, this should be enabled.

**Proposed fix:** Add a variable `enable_realm_specific_endpoints` (default `false`) and set it in the provider block:

```hcl
provider "oci" {
  region = var.region
  realm_specific_service_endpoint_template_enabled = var.enable_realm_specific_endpoints
}
```

Combined with `OCI_REGION_METADATA` set as an environment variable before running terraform (or `~/.oci/regions-config.json` on the bastion), this tells the provider to use realm-aware endpoint URLs.

#### Gap 4: No `regions-config.json` Mounting in CCM/CSI Containers

As a defense-in-depth measure for environments where IMDS may not return `regionInfo` correctly, the CCM and CSI containers could mount a `regions-config.json` ConfigMap at `/root/.oci/regions-config.json`. The Go SDK checks this path automatically.

**Proposed fix (optional, lower priority):** Add a terraform variable for a custom `regions-config.json` content. When set, create a ConfigMap and mount it in the CCM and CSI DaemonSets. This provides a fallback that doesn't depend on either IMDS or env vars.

#### Gap 5: CSI Driver Names Use `oraclecloud.com`

The CSI driver registration names (`blockvolume.csi.oraclecloud.com`, `fss.csi.oraclecloud.com`) contain `oraclecloud.com`. These are **Kubernetes-internal CSI driver identifiers**, not API endpoints. They are baked into the `cloud-provider-oci` binary and must match what the driver registers with the Kubernetes CSI framework.

**Assessment:** These are **likely safe** in isolated realms because they are identity strings, not network endpoints. However, this must be verified against the actual `cloud-provider-oci` binary shipped for isolated realm use. If Oracle ships a different binary for isolated realms with different CSI driver names, the manifests would need to match.

**Action:** Verify with Oracle whether the CSI driver names change in isolated realm builds. No terraform change needed unless they do.

#### Gap 6: CAPOCI Autoscaler Needs Region Metadata

The CAPOCI controller has `ENABLE_INSTANCE_METADATA_SERVICE_LOOKUP=true` set via sed substitution in the provider installer job. It does not receive `OCI_REGION_METADATA` or `OCI_REALM_SPECIFIC_SERVICE_ENDPOINT_TEMPLATE_ENABLED`.

**Proposed fix:** Add these env vars to the CAPOCI deployment patch in `locals.tf` (the autoscaler provider installer script), conditional on `region_metadata` being non-empty.

### IMDS as the Primary Region Discovery Mechanism

A key architectural question: **will IMDS work correctly in OC6/7/11/12?**

The terraform stack already queries IMDS for `regionInfo` in `region-meta.tf`. All OCI DaemonSets (CCM, CSI, OCA) run with `hostNetwork: true` and can reach the link-local IMDS at `169.254.169.254`. If IMDS returns correct `regionInfo` in isolated realms — which it should, since the instance knows what realm it's in — then:

- The CSI driver already works (it gets `OCI_REGION_METADATA` from the terraform template)
- The CCM would work **if** it also gets `OCI_REGION_METADATA` (Gap 1 above)
- The CAPOCI controller would work **if** IMDS lookup is enabled (already done) and the Go SDK version supports the realm

The risk is if IMDS behavior differs in isolated realms, or if the Go SDK version in the CCM/CSI container images does not support IMDS-based region discovery. This needs testing in an actual OC6/7/11/12 environment.

### Terraform Running Outside the Target Realm

If terraform runs from a bastion **inside** the isolated realm, IMDS provides region metadata automatically. If terraform runs from **outside** (e.g., a connected jump host), then:

1. `region-meta.tf` IMDS lookup returns `{}` (curl timeout/fail)
2. `region_metadata` is empty string
3. No `OCI_REGION_METADATA` is injected into manifests
4. The Terraform provider itself needs `~/.oci/regions-config.json` or `OCI_REGION_METADATA` env var to know the realm

For the OC3 Gov Cloud deployment, terraform ran from a bastion inside OC3, so IMDS worked. The same pattern should be followed for OC6/7/11/12 — run terraform from inside the target realm.

### OCIR Hardcoded Domain Explained

OCIR (Oracle Cloud Infrastructure Registry) is OCI's container image registry, similar to ECR on AWS. In the terraform stack, it is used **exclusively** for the Oracle Cloud Agent (OCA) — the privileged DaemonSet that provides iSCSI management, monitoring, and OS management on OpenShift nodes.

#### What OCIR Does in This Stack

The OCA container image is not pulled from a public registry. It is exported from the OCI Marketplace into a tenancy-specific OCIR repository, and the terraform stack constructs the full image pull URL so the OCA DaemonSet manifest knows where to pull from. The flow is:

1. `oci_marketplace_listing_packages` — queries the Marketplace to find the OCA listing version
2. `oci_artifacts_container_images` — queries OCIR for container images in the tenancy's OCA repository
3. Filters images by the Marketplace version to find the correct tag
4. Constructs the pull URL: `${region_key}.ocir.io/${namespace}/${image_display_name}`

#### Where the Hardcoded Domain Is

**File:** `terraform-stacks/shared_modules/ocir/main.tf` (line 40)

```hcl
locals {
  oca_version = try(data.oci_marketplace_listing_packages.marketplace_listing_packages.listing_packages[0].package_version, "NA")

  all_images = flatten([
    for collection in data.oci_artifacts_container_images.oca_container_images.container_image_collection : collection.items
  ])

  filtered_images = [
    for img in local.all_images :
    img if can(img.display_name) && length(regexall(local.oca_version, img.display_name)) > 0
  ]

  namespace = data.oci_objectstorage_namespace.namespace_details.namespace

  image_pull_command = "${lower(var.region)}.ocir.io/${local.namespace}/${try(local.filtered_images[0].display_name, "no-image-found")}"
}
```

The `.ocir.io` suffix on line 40 is the hardcoded OC1 (commercial) OCIR domain. This is the **only place** in the stack that constructs an OCIR URL.

#### Why It Breaks in Other Realms

Each OCI realm has its own OCIR domain. The pattern is `${region_key}.ocir.${realmDomainComponent}`:

| Realm | OCIR Domain Pattern | Example |
|-------|-------------------|---------|
| OC1 (commercial) | `${region_key}.ocir.io` | `iad.ocir.io` |
| OC3 (US Gov FedRAMP) | `${region_key}.ocir.oraclegovcloud.com` | `ric.ocir.oraclegovcloud.com` |
| OC4 (UK Gov) | `${region_key}.ocir.oraclegovcloud.uk` | `lhr.ocir.oraclegovcloud.uk` |
| OC6/7/11/12 (isolated) | `${region_key}.ocir.${realmDomainComponent}` | Unknown — realm domains are classified |

With the current code, deploying in OC3 with OCA enabled would produce a pull URL like `ric.ocir.io/...` instead of `ric.ocir.oraclegovcloud.com/...`. The image pull would fail with a DNS resolution error or registry auth error.

#### Current Mitigation

For the OC3 Gov Cloud deployment, this issue is **masked** because `use_oracle_cloud_agent = false` and the `module "ocir"` is gated with `count = var.use_oracle_cloud_agent ? 1 : 0`. The OCIR module never runs, so the hardcoded domain is never used. Additionally, the Gov Cloud Marketplace API itself returns 404, so even if OCA were enabled, the Marketplace lookup would fail before reaching the OCIR URL construction.

#### Where the Resulting URL Goes

The OCIR pull URL flows through:

1. `shared_modules/ocir/output.tf` → outputs `image_pull_command`
2. `create-cluster/main.tf` → passes to `module "manifests"` as `oca_image_pull_link`
3. `shared_modules/manifest/locals.tf` → injects into the OCA DaemonSet YAML as the container `image:` field
4. The manifest is written to `openshift/manifest_oca.yaml` and baked into the agent ISO
5. At runtime, kubelet on each node pulls from this URL

So a wrong OCIR domain would cause every node's kubelet to fail pulling the OCA image — but only when OCA is enabled, which it currently is not.

### Proposed Terraform Changes

#### Change 1: Add `enable_realm_specific_endpoints` to the Terraform Provider

**File:** `terraform-stacks/create-cluster/variables.tf`

```hcl
variable "enable_realm_specific_endpoints" {
  description = "Enable realm-specific service endpoint templates in the OCI Terraform provider. Required for isolated realms (OC6, OC7, OC11, OC12) where API endpoint URL patterns differ from commercial OC1."
  type        = bool
  default     = false
}
```

**File:** `terraform-stacks/create-cluster/main.tf` — update both provider blocks

The default provider block is implicit (no `provider "oci" {}` block exists for the default — it uses the region from `var.region`). A provider block would need to be added or the attribute set via environment variable. The `oci.home` provider block at the top of `main.tf`:

```hcl
provider "oci" {
  alias  = "home"
  region = local.home_region
  realm_specific_service_endpoint_template_enabled = var.enable_realm_specific_endpoints
}
```

For the default (non-aliased) provider, the same attribute would need to be set, or the operator can export the environment variable before running terraform:

```bash
export OCI_REALM_SPECIFIC_SERVICE_ENDPOINT_TEMPLATE_ENABLED=true
```

This is the simpler approach and covers both the default and home providers without adding a provider block.

#### Change 2: Add `OCI_REALM_SPECIFIC_SERVICE_ENDPOINT_TEMPLATE_ENABLED` to CSI Template

**File:** `terraform-stacks/shared_modules/manifest/manifest-templates/01-oci-csi.yml.tpl`

The CSI template already conditionally injects `OCI_REGION_METADATA` in two places (controller at line 120, node driver at line 292). Add the realm-specific endpoint var inside the same conditional blocks.

Controller container (around line 120):
```yaml
        %{~ if region_metadata != "" ~}
        env:
          - name: OCI_REGION_METADATA
            value: '${region_metadata}'
          - name: OCI_REALM_SPECIFIC_SERVICE_ENDPOINT_TEMPLATE_ENABLED
            value: "true"
        %{~ endif ~}
```

Node driver container (around line 292):
```yaml
            %{~ if region_metadata != "" ~}
            - name: OCI_REGION_METADATA
              value: '${region_metadata}'
            - name: OCI_REALM_SPECIFIC_SERVICE_ENDPOINT_TEMPLATE_ENABLED
              value: "true"
            %{~ endif ~}
```

#### Change 3: Convert CCM to a Template and Inject Region Metadata

**Current state:** The CCM manifest at `oci-ccm-csi-drivers/v1.34.0/01-oci-ccm.yml` is loaded via `file()` in `manifest/main.tf` line 14 and line 36. It has a single env var (`OPENSHIFT_NODE_LABEL_ID`) and no mechanism to receive region metadata.

**Proposed:** Create `manifest-templates/01-oci-ccm.yml.tpl` by copying the CCM YAML and adding conditional env vars to the `oci-cloud-controller-manager` container:

```yaml
      containers:
        - name: oci-cloud-controller-manager
          image: ${oci_image_source}
          env:
            - name: OPENSHIFT_NODE_LABEL_ID
              value: node.openshift.io/os_id=rhel
            %{~ if region_metadata != "" ~}
            - name: OCI_REGION_METADATA
              value: '${region_metadata}'
            - name: OCI_REALM_SPECIFIC_SERVICE_ENDPOINT_TEMPLATE_ENABLED
              value: "true"
            %{~ endif ~}
```

Then update `manifest/locals.tf` to render it:

```hcl
  oci_ccm = templatefile("${path.module}/manifest-templates/01-oci-ccm.yml.tpl", {
    region_metadata  = var.region_metadata
    oci_image_source = lookup(local.oci_image_sources, var.oci_driver_version, local.default_oci_driver_image)
  })
```

And update `manifest/main.tf` to use the rendered local instead of `file()`:

```hcl
# line 14 (dynamic_custom_manifest output)
    ${local.oci_ccm}
# line 36 (manifest_oci_ccm output)
  value = trimspace(local.oci_ccm)
```

#### Change 4: Parameterize the OCIR Domain

**File:** `terraform-stacks/shared_modules/ocir/variables.tf` — add:

```hcl
variable "realm_domain_component" {
  description = "The realm domain component for OCIR URL construction. Leave empty for OC1 (commercial, uses .ocir.io). Set to the realm domain for other realms (e.g. 'oraclegovcloud.com' for OC3)."
  type        = string
  default     = ""
}
```

**File:** `terraform-stacks/shared_modules/ocir/main.tf` — update the image pull URL:

```hcl
locals {
  # ...existing locals...

  ocir_domain = var.realm_domain_component != "" ? "ocir.${var.realm_domain_component}" : "ocir.io"

  image_pull_command = "${lower(var.region)}.${local.ocir_domain}/${local.namespace}/${try(local.filtered_images[0].display_name, "no-image-found")}"
}
```

**File:** `terraform-stacks/create-cluster/main.tf` — pass realm domain to ocir module:

```hcl
module "ocir" {
  source = "./shared_modules/ocir"
  count  = var.use_oracle_cloud_agent ? 1 : 0

  compartment_ocid           = var.compartment_ocid
  oca_repo_name              = var.oracle_cloud_agent_repo_name
  oca_marketplace_listing_id = var.oca_marketplace_listing_id
  realm_domain_component     = var.realm_domain_component
  region                     = local.current_region_key
}
```

**File:** `terraform-stacks/create-cluster/variables.tf` — add:

```hcl
variable "realm_domain_component" {
  description = "The OCI realm domain component (e.g. 'oraclegovcloud.com' for OC3, 'oraclecloud14.com' for OC14). Used for OCIR URL construction and passed to manifests. Leave empty for commercial OC1."
  type        = string
  default     = ""
}
```

### Summary of Required Changes

| Priority | Gap | Change | Files |
|----------|-----|--------|-------|
| **P0** | CCM missing `OCI_REGION_METADATA` | Convert CCM YAML to template, inject env vars | `manifest-templates/01-oci-ccm.yml.tpl`, `manifest/main.tf`, `manifest/locals.tf` |
| **P0** | `OCI_REALM_SPECIFIC_SERVICE_ENDPOINT_TEMPLATE_ENABLED` not set anywhere | Add to CCM template, CSI template, provider block | `01-oci-ccm.yml.tpl`, `01-oci-csi.yml.tpl`, `create-cluster/main.tf` |
| **P1** | OCIR domain hardcoded `.ocir.io` | Parameterize with `realm_domain_component` | `shared_modules/ocir/main.tf`, `shared_modules/ocir/variables.tf` |
| **P1** | Terraform provider missing realm-specific endpoints | Add `enable_realm_specific_endpoints` variable | `create-cluster/main.tf`, `create-cluster/variables.tf` |
| **P2** | CAPOCI missing region metadata | Add env vars to CAPOCI deployment patch | `manifest/locals.tf` |
| **P2** | No `regions-config.json` fallback in containers | Optional ConfigMap mount | `manifest-templates/*.tpl` |
| **Verify** | CSI driver names contain `oraclecloud.com` | Confirm these are identity strings not endpoints | Oracle liaison |

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
