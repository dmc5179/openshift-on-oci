# Draft issue: boot volumes created at 10 VPUs/GB regardless of the requested `boot_volume_vpus_per_gb`

**Status:** draft, 2026-11-12. Track with Oracle: add to the "Open Items for Oracle" doc, and/or
open an issue on `oracle-quickstart/oci-openshift`. The workaround is in the fork (`c21f5d9`).
Root cause unknown; isolation experiment below, not yet run.

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

## Questions for Oracle

1. Is `source_details.boot_volume_vpus_per_gb` honoured on `LaunchInstance` for instances
   launched from a **custom image**, in OC3 or in general?
2. If it is, why do these boot volumes report 10, and why does the instance not return the
   requested value?
3. Should the stack instead set performance after launch (`UpdateBootVolume` with
   `vpusPerGB`), or through a volume performance policy?

## Isolation experiment (needs approval: creates two short-lived instances)

1. Launch a small instance from the **same custom image** with `bootVolumeVpusPerGB = 30` in
   `source-details`, using the CLI rather than Terraform, then read the boot volume's
   `vpus-per-gb`.
2. Launch a small instance from an **OCI platform image** with the same setting.
3. Run `terraform apply` with `TF_LOG=DEBUG` on a throwaway one-instance config, to see whether
   the provider sends the field.

Expected readings:
- 10 from the custom image and 30 from the platform image: a custom-image limitation.
- 10 from both: a realm or API problem.
- 30 from the CLI but 10 from Terraform: a provider problem.

## Optional mitigation on the live cluster (needs approval)

`oci bv boot-volume update --boot-volume-id <boot-volume-ocid> --vpus-per-gb 100` (control plane)
and `30` (compute). OCI documents changing boot volume performance online. That would also show
whether the API accepts the value after launch.
