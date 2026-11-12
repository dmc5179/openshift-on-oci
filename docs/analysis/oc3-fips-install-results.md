# OC3 FIPS install from a non-FIPS bastion: results

Date: 2026-11-12. Plan: [`docs/test-plans/oc3-fips-rebuild-plan.md`](../test-plans/oc3-fips-rebuild-plan.md).
Baseline: the non-FIPS run in [`oc3-disconnected-install-results.md`](oc3-disconnected-install-results.md).

## Summary

- **The FIPS install worked.** OpenShift 4.22.22 was installed with the Agent-based Installer, `platform: external` (OCI), and the same simulated disconnected setup as the baseline: mirror registry on the bastion, existing VCN (BYON), `NeverContactSource`.
- **The bastion is not in FIPS mode.** `openshift-install-fips` ran with `OPENSHIFT_INSTALL_SKIP_HOSTCRYPT_VALIDATION=1`. Red Hat documents this bypass as unsupported and for testing only.
- **Every node is in FIPS mode.** The Oracle cloud controller manager (CCM) and storage driver (CSI) showed no crypto or TLS errors.
- **Every regression test matched the non-FIPS result.**
- **New finding:** the installer's `hostcrypt-check-bypassed` annotation never reaches the cluster (see below).
- **Reproduced on FIPS:** OCPBUGS-140771. The installer-created IDMS again had no `mirrorSourcePolicy`, and was patched after install as before.

## Install

| Step | Result |
|---|---|
| Destroy the non-FIPS cluster | 68 resources destroyed. VCN, LPG peering, NSGs, bastion and DNS view intact |
| Terraform pass 1 | 29 added |
| Agent ISO | Built. Both expected warnings shown: host-crypto validation bypassed, and the cluster is not supportable |
| Terraform pass 2 | 39 added, 9 changed |
| `agent wait-for install-complete` | Complete |
| Post-install (same as the baseline) | IDMS patched to `NeverContactSource`; samples `Removed`; default catalogs disabled; oc-mirror cluster resources applied; all MachineConfigPools Updated; mirrored CatalogSource READY |

## Phase 4 checks

| Check | Result |
|---|---|
| 4.1 FIPS on nodes | ✅ All 6 nodes: `/proc/sys/crypto/fips_enabled` = 1, `update-crypto-policies --show` = FIPS, `fips=1` on the kernel command line |
| 4.2 Stored install-config | ✅ `fips: true`. ⚠️ No `install.openshift.io/hostcrypt-check-bypassed` annotation (see finding) |
| 4.3 Install verification | ✅ All cluster operators Available and not Degraded; 6 nodes Ready; every `[[registry]]` in `registries.conf` is `blocked = true` on every node; chrony selects 169.254.169.254 on every node; 6 `oci://` providerIDs; no `uninitialized` taints |
| 4.4 CCM and CSI under FIPS | ✅ 3 CCM pods Running. No `x509`, `tls:`, handshake, crypto or FIPS errors in CCM or CSI logs. Paravirtualized and iSCSI volumes attached; OCI reports the iSCSI attachment as `iscsi`, and data was written and read back |
| 4.5-B Samples | ✅ `Removed`, as in the baseline fix, so no direct pulls from registry.redhat.io |
| 4.5-D Load balancers | ✅ Classic LB (100 Mbps shape) provisioned and reachable from the bastion. ✅ NLB provisioned and served traffic on its private and public IPs **from a cluster node**. ❌ The NLB was not reachable from the bastion (see note) |
| 4.5-E Snapshot and restore | ✅ `VolumeSnapshotClass` recreated; snapshot ready; restored PVC contains the original data |
| 4.5-G Registry and build | ✅ Registry `Managed` on a 100 Gi `oci-bv` PVC. A Docker-strategy build pulled its `FROM` through the mirror, pushed to the internal registry, and the image ran |
| 4.5-H OLM v1 | ✅ `ClusterExtension` for `secrets-store-csi-driver-operator`, from the mirrored ClusterCatalog: Installed, pod Running |
| 4.6 Diff against the non-FIPS baseline | ✅ CCM and CSI images identical. MachineConfigs: the only addition is `99-master-fips` / `99-worker-fips`; none are missing |

Kept on the cluster: the registry (Managed, 100 Gi PVC), `oci-bv-snapclass`, the secrets-store `ClusterExtension`. All test namespaces and the LBs and NLBs they created were deleted; OCI shows 3 LBs (the cluster's own) and 0 NLBs.

### Test notes

- **Build timing.** The first build attempt failed with `InvalidOutputReference` because its objects were created just as the registry operator reported Available. New objects created a few minutes later built and ran. This is the same behaviour as the baseline, not a FIPS issue: create image streams and BuildConfigs only after the registry has settled.
- **NLB annotation.** The CCM rejects `oci-network-load-balancer.oraclecloud.com/is-preserve-source` unless `externalTrafficPolicy: Local` (`annotation cannot be set when externalTrafficPolicy is set to Cluster`). The first attempt was a test-manifest error.
- **NLB reachability from the bastion.** With `is-preserve-source: "false"` and `externalTrafficPolicy: Local`, the NLB worked from inside the VCN on both IPs, and the kube-proxy health-check endpoint returned 200. It failed from the bastion on both IPs:
  - The private IP fails because of the known routing gap: the public subnet has no route back to the bastion VCN.
  - The public front end also failing from the bastion is a network ingress problem, not a FIPS problem. The baseline D test reached it, and the later non-FIPS L regression hit the same failure intermittently.
  - Still open: the NLB front-end ingress rules in the public subnet.

## Finding: the bypass annotation is not recorded on the cluster

With `OPENSHIFT_INSTALL_SKIP_HOSTCRYPT_VALIDATION=1`, `openshift-install` adds `install.openshift.io/hostcrypt-check-bypassed: "true"` to the install-config's `metadata.annotations`. It appears in the installer state, under `.openshift_install_state.json` → `agent.OptionalInstallConfig.config.metadata.annotations`.

On the installed cluster, `kube-system/cluster-config-v1` → `install-config` has `metadata: {name: ocp-deployment}` and no annotations. With the Agent-based Installer, nothing on the running cluster shows that the host-crypto check was bypassed, which defeats the purpose of the marker (support can't tell an unsupported FIPS install).

The likely cause is the same as OCPBUGS-140771: with the Agent-based Installer, assisted-service generates the cluster's install-config again and drops fields it does not model. Not filed yet.

## Egress

Not measured on this cluster. The baseline flow-log analysis is in the archive. Its two public destinations were:
- hairpin traffic to the apps LB on 443;
- NTP on udp/123 to the default public pool, alongside the IMDS NTP source.

The chrony configuration is the same, so the default-pool finding is expected to apply here too, but that hasn't been verified on this cluster.
