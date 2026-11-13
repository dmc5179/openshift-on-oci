# Draft issue: boot volumes created at 10 VPUs/GB regardless of the requested `boot_volume_vpus_per_gb`

**Status:** draft, 2026-11-12. Track with Oracle: add to the "Open Items for Oracle" doc, and/or
open an issue on `oracle-quickstart/oci-openshift`. The workaround is in the fork (`c21f5d9`).
Isolation experiment run 2026-11-12. Result: OCI ignores boot volume VPUs in OC3, at launch and on
update, for custom and platform images alike. Not a Terraform, provider or custom-image issue.
Reproduced again on the FIPS rebuild the same day: all 6 new boot volumes at 10.

---

## Summary

The `create-cluster` stack requests boot volume performance per node type
(`control_plane_boot_volume_vpus_per_gb`, `compute_boot_volume_vpus_per_gb`), passed to OCI as
`source_details.boot_volume_vpus_per_gb` on `oci_core_instance`. In an OC3 deployment, every
boot volume came up at **10 VPUs/GB** (the "Lower Cost" tier). The request was **100** for
control plane and **30** for compute.

For OpenShift this matters a lot: etcd lives on the control plane boot volume. Red Hat's
*Installing on Oracle Distributed Cloud* recommends 60 VPUs for a basic environment and 100 or
more for heavy production. 10 VPUs/GB is well below either.

## Environment

- Realm OC3, region `us-gov-ashburn-1`.
- Terraform provider `oracle/oci` 9.12.1; fork `dmc5179/oci-openshift` `disconnected` (based on
  upstream v1.6.2). The same values were used in the September deployment, whose boot volumes
  are believed to have had the same problem (not measured before it was destroyed).
- Instances: VM.Standard.E5.Flex, launched from a **custom image** imported from the agent ISO
  (paravirtualized), with boot volumes of 1024 GB (control plane) and 300 GB (compute).

## Observed

| Item | Value |
|---|---|
| Requested | 100 VPUs/GB (3 control plane), 30 VPUs/GB (3 compute) |
| Actual (`oci bv boot-volume get` → `vpus-per-gb`) | **10** on all 6 boot volumes |
| Instance `source-details` from the API | No `boot-volume-vpus-per-gb` returned |
| Terraform state after create | `"10"` |
| Effect on Terraform | A permanent diff on a ForceNew field: **every later plan replaces all instances**, which would destroy the cluster |
| OCI Audit | `LaunchInstance` events don't record the request body, so they can't show whether the value was sent |

## Workaround (in place)

`lifecycle { ignore_changes = [source_details[0].boot_volume_vpus_per_gb, defined_tags] }` on
both instance resources (fork `c21f5d9`). With the requested values restored in the tfvars, a plan
against the live cluster reports no changes. This only prevents the destructive diff; **the boot
volumes still run at 10 VPUs/GB.**

## Isolation experiment results (2026-11-12)

All test instances and volumes were deleted afterwards.

| Test | Requested | Result |
|---|---|---|
| V1. CLI `LaunchInstance`, **custom image** (agent ISO import) | `bootVolumeVpusPerGB` 30 | Boot volume **10**; instance `source-details` returns no VPU value |
| V2. CLI `LaunchInstance`, **OCI platform image** | 30 | Boot volume **10**; no VPU value returned |
| V3. Terraform, one-instance config, `TF_LOG=DEBUG` | 30 | The provider **sent 30**. The API returned 10, and the provider reported an inconsistent result after apply |
| V4. Standalone **block volume** create | 30 | **30** (honoured) |
| V4b. Block volume update | 20 | **20** (honoured) |
| V5. `UpdateBootVolume` with `vpusPerGB` on a running instance's boot volume | 30 | Call accepted (one transient `Conflict`, then success); value **stays 10** |
| V6. Same, rechecked after 15 minutes | 30 | Still **10** |
| FIPS rebuild, `create-cluster` stack | 100 control plane, 30 compute | All 6 boot volumes **10** |

Conclusion: in OC3, boot volume performance is fixed at 10 VPUs/GB. The API accepts a VPU setting at
launch and on update but doesn't apply it, while block volumes in the same compartment and region
honour VPU settings. Terraform and the stack send the value correctly.

## Questions for Oracle

1. Is boot volume performance (`bootVolumeVpusPerGB` at launch, `vpusPerGB` on
   `UpdateBootVolume`) supported in OC3? If not, can the API reject the request instead of
   silently applying 10?
2. If it is supported, why do both paths leave the boot volume at 10, for platform images too?
3. What is the supported way to get at least 60 VPUs/GB for etcd on OC3 control plane nodes? For
   example, can a block volume host `/var/lib/etcd`? Red Hat supports a separate disk for
   `/var/lib/etcd` through a MachineConfig at install time.
4. Does the same happen in other realms, including OC6?

## Optional next step (needs approval)

Ask Oracle before changing anything on the live cluster. Moving etcd to a block volume is a
cluster design change, not a quick mitigation.
