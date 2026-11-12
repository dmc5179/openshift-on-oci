# OC3 simulated disconnected install: results

**Run:** 2026-11-11 to 2026-11-12, OC3 `us-gov-ashburn-1`, from `ocibastion`.
**Plan:** [docs/test-plans/oc3-simulated-disconnected-install.md](../test-plans/oc3-simulated-disconnected-install.md).
**Stack:** fork `dmc5179/oci-openshift`, branch `disconnected`, commit `b52fd21`.
**Result:** **Pass.** OpenShift 4.22.18 installed and running with every container image
pulled from a private mirror registry, NTP from the OCI metadata service, and the OCI CCM and
CSI working. One installer bug was found and worked around. No OCIDs, secrets or tenancy
identifiers appear in this file.

## What was built

| Item | Detail |
|---|---|
| Mirror registry | mirror registry for Red Hat OpenShift 2.0.12, rootless on the bastion, `mirror.sim.internal:8443`, data on a new 200 GB block volume (`/var/lib/mirror`). Its own root CA is trusted on the bastion and passed to the cluster as `additional_trust_bundle`. |
| Mirrored content | oc-mirror v2, mirror to mirror: OpenShift 4.22.18 with the update graph (193 images), `secrets-store-csi-driver-operator` (7), and 20 additional images (Oracle CCM/CSI `v1.35.0`, six `sig-storage` sidecars, the autoscaler set, must-gather, support-tools, UBI, the OCI Vault provider). 220/220 in about 17 minutes, 34 GB. |
| Registry DNS | Private DNS view `sim-internal` with zone `sim.internal`, attached to the cluster VCN's resolver. The bastion uses `/etc/hosts`. |
| Network | **Kept** (bring-your-own-network). The old stack forgot its 25 network resources (`terraform state rm module.network`) and destroyed the remaining 66. The new stack ran with `use_existing_network = true`. |
| Cluster | `ocp-deployment`, 3 control plane + 3 compute, VM.Standard.E5.Flex, platform `external`/`oci`, FIPS off |
| Install inputs | install-config `imageDigestSources` with `sourcePolicy: NeverContactSource`; ITMS (19 repos) with `mirrorSourcePolicy: NeverContactSource`; pull secret with **only** the mirror's credentials; `additionalNTPSources: [169.254.169.254]`; `oci_driver_version = v1.35.0`; the ISO built with `openshift-install` **extracted from the mirror** |

## How "disconnected" was enforced

Blocking the cluster VCN's NAT gateway was dropped by decision, because a mistake there could
not be recovered from. Image isolation was enforced with `NeverContactSource` instead. A new,
opt-in fork variable, `mirror_source_policy`, puts it on both `imageDigestSources` and the
stack's ITMS. With it, every mirrored source is `blocked = true` in `registries.conf`, so those
images can come only from the mirror. Non-image traffic was checked separately: NTP, telemetry
(the pull secret holds only the mirror), and any contact with public registries in the node
journals.

## Results

| Check | Result |
|---|---|
| Install | `agent wait-for install-complete` exit 0. Bootstrap complete, then the cluster initialised. |
| Cluster health | 4.22.18 Available. All cluster operators Available, none Degraded. 6/6 nodes Ready. |
| SSH as `core` + `sudo podman images`, all 6 nodes | Works on every node, so ignition applied the key. Every pull in the journals went to `mirror.sim.internal:8443`. **Zero** contact with quay.io, registry.redhat.io, ghcr.io or registry.k8s.io. |
| Mirror sets | Stack ITMS: 19 entries, all `NeverContactSource`. **Installer IDMS: policy missing** (finding 1). After the fix: 32/32 `registries.conf` entries blocked on every node. |
| NTP | chrony on every node selected `169.254.169.254`, offsets of a few microseconds |
| CCM | All nodes have `oci://` provider IDs, no `uninitialized` taint, zero x509/timeout errors |
| CSI | 50 GiB block volume PVC bound, attached, written and read (test removed) |
| Ingress / API | Console 200, `/readyz` 200, `oc login` as kubeadmin through the load balancers |
| Negative test | An unmirrored tag from a blocked source (`ghcr.io/oracle/cloud-provider-oci:v1.34.0`) failed with `ImagePullBackOff`: the mirror was tried, with no fallback to ghcr.io |
| Pull secret / telemetry | Cluster pull secret holds only `mirror.sim.internal:8443`. Insights operator Available. |
| Day 2: catalogs | Default sources disabled. The mirrored `redhat-operator-index` CatalogSource is READY and the ClusterCatalog Serving. |
| Day 2: operator | `secrets-store-csi-driver-operator.v4.22.0-202611031655` installed from the mirror (CSV Succeeded). **Left installed** for OCI Vault step 4. |
| Day 2: must-gather | Ran from `mirror.sim.internal:8443/openshift4/ose-must-gather:latest`, exit 0, 119 MB (kept on the bastion) |
| Day 2: rollout | Adding the policies through IDMS/ITMS rolled out by the MCO **without node reboots** |

## Findings

1. **Agent-based Installer drops `imageDigestSources[].sourcePolicy` (bug).** The policy works
   during the installation, but the installed cluster's IDMS `image-digest-mirror` has no
   `mirrorSourcePolicy`. After the MCO takes over, the release sources are no longer blocked.
   The cause is assisted-service: its `installcfg.ImageDigestSource` has no `SourcePolicy`
   field, `setImageDigestMirrorSet` doesn't copy it, and `GetImageRegistries` ignores `blocked`.
   `openshift-install`'s own `ConvertImageDigestMirrorSet` is correct. Workaround: patch the IDMS
   after installation. Draft bug:
   [docs/redhat-issues/ocpbugs-abi-drops-imagedigestsources-sourcepolicy.md](../redhat-issues/ocpbugs-abi-drops-imagedigestsources-sourcepolicy.md).
2. **`oc adm release extract` from the mirror needs `--idms-file`.** Without it, `oc` resolves
   the installer's component image at its quay.io name and fails `unauthorized` with
   mirror-only credentials.
3. **The installer extracted from the mirror warns** that `imageDigestSources` has no source
   matching its release image, because its release image is the mirror path. This was harmless
   here: the release came straight from the mirror, and its components through the IDMS. A
   customer following the documented disconnected flow will see the same warning.
4. **Default catalog sources** (`registry.redhat.io/redhat/*-index:v4.22`) sit in
   `ImagePullBackOff` until disabled, as the disconnected docs say. With the mirror-only pull
   secret they couldn't pull anyway.
5. **oc-mirror's generated ITMS maps whole organisations** (`ghcr.io/oracle`,
   `quay.io/openshift`, `registry.redhat.io/rhel9` and others), which is broader than the
   stack's repository-level ITMS. Its IDMS and ITMS have no `mirrorSourcePolicy`, so the policy
   was added before applying. The `UpdateService` resource was not applied, because the
   OpenShift Update Service operator isn't installed.
6. **mirror registry installer quirks on this bastion.**
   - It SSHes to the host's own hostname by default, and `OpenShiftBastion` doesn't resolve; fix
     with `--targetHostname localhost`.
   - Rootless needs `loginctl enable-linger` so the registry survives logout and reboot.
   - It supports only local storage (KCS 7029097), so Object Storage was not an option.
7. **The environment contains hand-made objects outside any terraform state.**
   - The LPG `openshift-to-bastion` and its route.
   - Control plane NSG rules from the bastion (TCP 22/6443/22623).
   - An LB NSG rule (TCP 22624 from an unknown public IP).

   All survived because the network was kept. A full stack destroy would have removed them
   silently. For this test, TCP 22 from the bastion was added to the compute NSG.
8. **Bring-your-own-network removed the peering-route workaround.** The new stack doesn't
   manage the route table or the LPG, so the bastion route survived both applies.
9. **Bastion monitoring.** The private subnet only admits the cluster VCN, but the hand-made
   NSG rules gave the bastion SSH and API access to the control plane, so `wait-for` worked.

## Changes made during the run

| Where | Change |
|---|---|
| Fork `disconnected` | `1462b0a` docs and `generate-ocp-artifacts.sh` (OCA/autoscaler outputs); `ec5e7b1` ITMS and custom CA in `dynamic_custom_manifest`; `b52fd21` `mirror_source_policy` variable. All pushed. |
| Upstream PR #94 / #97 | `094842d` ITMS appended to `dynamic_custom_manifest`, merged into #97 (`a4aee08`). `mirror_source_policy` held back until after this test. |
| OC3, bastion | 200 GB block volume `openshift-bastion-mirror`; mirror registry; tools in `~/bin-4.22.18`; `/etc/hosts` entries; `~/oc3-private/` (mode 600: tfvars, auth files, CA, OCIDs) |
| OC3, network | Bastion VCN security list: TCP 8443 from <cluster-private-subnet-cidr>. Compute NSG: TCP 22 from the bastion. Private DNS view and zone `sim.internal`, attached to the cluster VCN. |
| OC3, old stack | `~/oci-openshift-rhel` at `fcecaad`, archived (`~/archive/`), network forgotten, rest destroyed. State now empty. Kept read-only until sign-off. |
| OC3, new stack | `~/oci-openshift-disconnected` at `b52fd21`; 29 + 39 resources; the cluster above |

## Open items

1. File the bug draft (finding 1) and add the DIA customer link.
2. Propose `mirror_source_policy` upstream with PR #94, citing this run and finding 1.
3. Add this evidence to OSDOCS-24411: a no-egress *image* install works, and here is what it
   needs.
4. Decide whether to keep `NeverContactSource` on this cluster (it is the cluster of record
   now), and whether to keep the `sim.internal` zone and the extra NSG and security list rules.
5. Delete `~/oci-openshift-rhel` once signed off; the archive keeps it.
6. OCI Vault step 4 can now run on this cluster: the operator is installed. Reinstall the
   provider from `tests/oci-vault/manifests/`, with its image already in the mirror.
