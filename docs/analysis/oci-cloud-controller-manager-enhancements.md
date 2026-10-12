# OCI Cloud Controller Manager — Region Discovery and Isolated Realm Support

Analysis of [oracle/oci-cloud-controller-manager](https://github.com/oracle/oci-cloud-controller-manager) for deploying OpenShift on OCI in isolated realms (OC6, OC7, OC11, OC12).

## Repo Overview

This single repository builds **all five** OCI cloud provider binaries into one container image:

| Binary | Purpose |
|--------|---------|
| `oci-cloud-controller-manager` | Cloud Controller Manager — clears the `node.cloudprovider.kubernetes.io/uninitialized` taint, manages LB services |
| `oci-csi-controller-driver` | CSI controller — block volume and FSS provisioning, attach, snapshot |
| `oci-csi-node-driver` | CSI node — mounts volumes on nodes |
| `oci-flexvolume-driver` | Legacy FlexVolume driver |
| `oci-volume-provisioner` | Legacy volume provisioner |

The Makefile builds all five via `make build`. The Dockerfile copies all resulting binaries into a single image (e.g. `ghcr.io/oracle/cloud-provider-oci:v1.34.0`).

## Vendored OCI Go SDK

**Version:** `v65.110.0` (from `go.mod`)

The vendored SDK at `vendor/github.com/oracle/oci-go-sdk/v65/common/regions.go` contains hardcoded realm maps for: OC1, OC2, OC3, OC4, OC8, OC9, OC10, OC14, OC15, OC19, OC20, OC21, OC23, OC24, OC26, OC29, OC35, OC42, OC51, OC52.

**OC6, OC7, OC11, and OC12 are absent** from the hardcoded maps. These realms must be registered at runtime via one of the SDK's dynamic registration mechanisms.

## Region Discovery: CCM vs CSI Asymmetry

The CCM and CSI drivers use different region discovery paths despite being built from the same repo and vendoring the same SDK. This asymmetry is significant for isolated realm support.

### CCM Region Discovery

The CCM calls `common.EnableInstanceMetadataServiceLookup()` in its `init()` function at `pkg/cloudprovider/providers/oci/ccm.go` line 174. This enables the full SDK region resolution cascade when the SDK encounters an unknown region string:

1. **Hardcoded realm maps** — `shortNameRegion` and `regionRealm` in `regions.go`
2. **`~/.oci/regions-config.json`** — file-based custom region registration
3. **`~/.oci/developer-tool-configuration.json`** — developer tool config file
4. **`OCI_REGION_METADATA` env var** — JSON blob with `regionIdentifier`, `realmKey`, `realmDomainComponent`, `regionKey`
5. **IMDS** — queries `http://169.254.169.254/opc/v2/instance/regionInfo` (only because `EnableInstanceMetadataServiceLookup()` was called)

Additionally, the CCM's own config parsing in `pkg/cloudprovider/providers/oci/config/config.go` has a separate metadata client that queries `http://169.254.169.254/opc/v2/instance/` to fill in `auth.region` if it is blank in the cloud-provider config Secret. This populates the config struct but does **not** register the region with the SDK's endpoint construction maps.

### CSI Driver Region Discovery

The CSI controller driver (`cmd/oci-csi-controller-driver/main.go`) and CSI node driver (`cmd/oci-csi-node-driver/main.go`) **never call `EnableInstanceMetadataServiceLookup()`**. This means the SDK's IMDS fallback (step 5 above) is disabled. The resolution cascade for the CSI driver is:

1. **Hardcoded realm maps** — same as CCM
2. **`~/.oci/regions-config.json`** — same as CCM
3. **`~/.oci/developer-tool-configuration.json`** — same as CCM
4. **`OCI_REGION_METADATA` env var** — same as CCM
5. ~~IMDS~~ — **NOT available** (never opted in)

The CSI driver's config parsing (`providercfg.FromFile()` → `ReadConfig()` → `AuthConfig.Complete()`) uses the same `config.go` code as the CCM, so it does query the instance metadata endpoint to fill in `auth.region` in the config struct. But without `EnableInstanceMetadataServiceLookup()`, the SDK itself will not query IMDS when it encounters an unknown region during endpoint construction.

### Practical Impact

For realms **in** the hardcoded maps (OC1, OC3, etc.), both CCM and CSI work identically — the SDK recognizes the region and constructs correct endpoints.

For realms **not** in the hardcoded maps (OC6, OC7, OC11, OC12):

| Component | Without env var injection | With `OCI_REGION_METADATA` env var |
|-----------|--------------------------|-------------------------------------|
| **CCM** | Falls through to IMDS (step 5) — **works** if IMDS returns valid regionInfo | Region registered at SDK level — **works** |
| **CSI** | Falls through to step 4, finds nothing, falls back to OC1 — **broken** | Region registered at SDK level — **works** |

The CSI driver's reliance on `OCI_REGION_METADATA` is why the upstream `oracle-quickstart/oci-openshift` terraform stack already injects this env var into the CSI template (`01-oci-csi.yml.tpl`). Without it, the CSI driver in an unrecognized realm constructs endpoints using the OC1 domain (`oraclecloud.com`), which fail.

## `OCI_REALM_SPECIFIC_SERVICE_ENDPOINT_TEMPLATE_ENABLED`

The vendored SDK supports this env var at `vendor/.../common/client.go` lines 860-867. The `BaseClient.IsOciRealmSpecificServiceEndpointTemplateEnabled()` method checks:

1. A per-client `RealmSpecificServiceEndpointTemplateEnabled` config field (a `*bool`)
2. If nil, the `OCI_REALM_SPECIFIC_SERVICE_ENDPOINT_TEMPLATE_ENABLED` env var

When enabled, the SDK uses realm-specific endpoint URL templates instead of the default OC1 pattern. This is important for isolated realms where the API endpoint URL structure may differ from commercial.

Neither the CCM nor the CSI driver sets this programmatically — it must be injected as an env var in the pod spec.

## Workload Identity Caveat

When `useWorkloadIdentity: true` is set in the cloud-provider config, the `auth.region` field is **required** and cannot be auto-discovered. The code at `config.go` line 371-373 enforces this:

```go
region := cfg.Auth.Region
if region == "" {
    return nil, errors.New("auth.region must be set when useWorkloadIdentity is true")
}
```

The current OpenShift-on-OCI deployment uses instance principals (`useInstancePrincipals: true`), not workload identity, so this is not currently a concern. But if workload identity is adopted in the future, the cloud-provider config Secret must include the region explicitly.

## Summary: What's Needed for OC6/7/11/12

No source code changes to the CCM or CSI are required. The vendored SDK (v65.110.0) already supports runtime region registration. The following env vars must be injected into the CCM and CSI DaemonSet pod specs:

| Env Var | Purpose | CCM | CSI |
|---------|---------|-----|-----|
| `OCI_REGION_METADATA` | Registers the unknown realm's region with the SDK | Needed (IMDS would also work as fallback, but explicit is safer) | **Required** (no IMDS fallback) |
| `OCI_REALM_SPECIFIC_SERVICE_ENDPOINT_TEMPLATE_ENABLED` | Tells the SDK to use realm-specific endpoint URL templates | Needed | Needed |

These env vars are injected by the terraform changes in `oci-openshift-mine`:
- `manifest-templates/01-oci-ccm.yml.tpl` — CCM DaemonSet (new template, replacing static YAML)
- `manifest-templates/01-oci-csi.yml.tpl` — CSI Deployment and DaemonSet (updated existing template)

The `OCI_REGION_METADATA` value comes from the IMDS query in `shared_modules/meta/region-meta.tf`, which runs on the bastion during `terraform apply`. If terraform runs inside the target realm, IMDS provides the region metadata automatically. If terraform runs outside the realm, the operator must set `OCI_REGION_METADATA` as a shell env var or provide `~/.oci/regions-config.json` on the bastion.

## Potential Upstream Enhancement

The CSI driver not calling `EnableInstanceMetadataServiceLookup()` appears to be an oversight rather than an intentional design choice — the CCM calls it, and both drivers share the same config parsing code. Filing an upstream issue to add the call to the CSI driver's `init()` or `main()` would eliminate the asymmetry and make `OCI_REGION_METADATA` injection optional for environments where IMDS is available.
