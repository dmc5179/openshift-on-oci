# Upstream issue — CSI drivers never enable the SDK's IMDS region lookup

**Repo:** oracle/oci-cloud-controller-manager
**Status:** FILED 2026-11-06 as [oracle/oci-cloud-controller-manager#555](https://github.com/oracle/oci-cloud-controller-manager/issues/555)

Notes for us (not part of the issue):

- Checked against `93969b5` (2026-09-28, release-1.36) from a fresh clone.
- Found by reading source, not by watching it fail. Our fork injects
  `OCI_REGION_METADATA` into the CSI pods, so we have never run the CSI driver
  without it in an unknown realm. The issue says so.
- Our OC3 cluster cannot reproduce it: the vendored SDK knows the OC3 regions.
  A before/after needs OC6 or another realm missing from the SDK.
- Offered a PR rather than sending one: the repo requires the OCA, which is
  unsigned, and Oracle may know a reason for the asymmetry.

---

## Title

CSI controller and node drivers never call EnableInstanceMetadataServiceLookup(), so they cannot resolve regions the SDK does not know

## Body

### Summary

The cloud controller manager enables the OCI Go SDK's instance-metadata (IMDS)
region lookup; the CSI controller and node drivers do not. In a realm or region
that the vendored SDK has no entry for, the CCM can still resolve its region
from IMDS, but the CSI drivers fall back to the commercial `oraclecloud.com`
domain and build endpoints that do not exist — unless `OCI_REGION_METADATA` or
`~/.oci/regions-config.json` is supplied.

### Detail

Checked at `93969b53c3a17ea558b98ed31605cf69de9f37a5` (release-1.36), vendored
`oci-go-sdk/v65 v65.110.0`.

The only non-vendored call to `common.EnableInstanceMetadataServiceLookup()` is
in the `init()` of the CCM provider package:

https://github.com/oracle/oci-cloud-controller-manager/blob/93969b53c3a17ea558b98ed31605cf69de9f37a5/pkg/cloudprovider/providers/oci/ccm.go#L161-L175

Because it is in `init()`, any binary importing that package would get it. The
CSI binaries do not import it:

```
$ for c in oci-cloud-controller-manager oci-csi-controller-driver oci-csi-node-driver; do
    printf '%s: ' "$c"
    GOFLAGS=-mod=vendor go list -deps ./cmd/$c \
      | grep -cx 'github.com/oracle/oci-cloud-controller-manager/pkg/cloudprovider/providers/oci'
  done
oci-cloud-controller-manager: 1
oci-csi-controller-driver: 0
oci-csi-node-driver: 0
```

In the vendored SDK, `StringToRegion` resolves an unrecognised region through
`checkAndAddRegionMetadata`, which tries the regions config file, then
`OCI_REGION_METADATA`, then `setRegionFromInstanceMetadataService`. That last
step returns immediately unless `visitIMDS` is set, and only
`EnableInstanceMetadataServiceLookup()` sets it. With no match,
`Region.SecondLevelDomain()` returns `OCI_DEFAULT_REALM` if set, otherwise the
oc1 domain.

So for a region the SDK does not know, with no config file or environment
variable:

| Component | Region resolution |
|---|---|
| CCM | Falls through to IMDS and gets the correct realm domain |
| CSI controller and node drivers | Skip IMDS, fall back to `oraclecloud.com`, and call endpoints that do not exist |

### Why it matters

This affects isolated and dedicated realms newer than the vendored SDK. Today
deployments have to inject `OCI_REGION_METADATA` into the CSI pods for storage
to work, while the CCM in the same cluster works without it. The OpenShift on
OCI Terraform stack (oracle-quickstart/oci-openshift) does this injection into
its CSI template for exactly this reason.

We found this by reading the source while adding isolated-realm support to that
stack, not by watching the driver fail: we already inject the variable, so we
have not run the CSI driver without it in an affected realm.

### Suggested change

Call `common.EnableInstanceMetadataServiceLookup()` at startup in
`cmd/oci-csi-controller-driver/main.go` and `cmd/oci-csi-node-driver/main.go`,
or move the call somewhere both the CCM and the CSI drivers import. The CSI
drivers already rely on the instance metadata endpoint: the shared config code
in `pkg/cloudprovider/providers/oci/config/config.go`, which they use, queries
it to fill in the region or compartment when either is missing.

If the asymmetry is deliberate, it would help to document that the CSI drivers
require `OCI_REGION_METADATA` or a regions config file in realms the SDK does
not know.

Happy to send a PR for the first option if you would take it.
