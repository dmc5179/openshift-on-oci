# Test plan: simulated fully disconnected OpenShift 4.22 install in OC3

**Status:** in progress, 2026-11-11. Steps through the old-stack destroy are done.

> **Changed on 2026-11-11: keep the network (bring-your-own-network).** The
> VCN is kept rather than destroyed. Its provenance was checked against
> terraform state and OCI `CreatedBy`/`CreatedOn` tags. The VCN, subnets,
> route tables, security lists, NSGs, gateways and the `ocp-demo.com` zone
> were all created by the 13 Aug terraform run, using Kristen's API key, which
> is the bastion's terraform identity. Only the LPG `openshift-to-bastion`
> was made by hand.
>
> - **Old stack:** `terraform state rm module.network` (25 resources
>   forgotten, not deleted), then `terraform apply` of a 66-resource destroy
>   plan: instances, LBs, `ocp-demo.com` zone and records, IAM, image, bucket.
>   Done 2026-11-11.
> - **New stack:** `use_existing_network = true` with the existing VCN,
>   subnets and compartment. Its pass 1 plan validated against the kept
>   network: 29 to add, no network objects.
> - **H2 (peering route helper) and H3 (recreate the LPG) are no longer
>   needed.** The new stack doesn't manage the route table or the LPG, so
>   both survive every apply.
> - The `sim.internal` view is already attached to this VCN's resolver.
> - **More hand-made objects, found 2026-11-11 after pass 2** (the provenance
>   check had covered top-level VCN objects only, not NSG rules):
>   `cluster-controlplane-nsg` allows TCP 22, 6443 and 22623 from the bastion
>   (<bastion-private-ip>/32), and `cluster-lb-nsg` allows TCP 22624 from an unknown public IP (/32)
>   (an unknown host). They survived because the network was kept. For this
>   test, TCP 22 from <bastion-private-ip>/32 was added to `cluster-compute-nsg`, so the
>   workers can be checked by SSH too.
> - **Node check by SSH (Dan's practice), 2026-11-11, about 13 minutes after boot:**
>   `ssh core@<node> sudo podman images` worked on all 6 nodes, so ignition
>   applied the key. Every pull in the journal went to `mirror.sim.internal:8443`,
>   with zero contact with quay.io, registry.redhat.io, ghcr.io or
>   registry.k8s.io. Both release sources are `blocked = true` on 5 of 6 nodes.
>   The exception is cp-1, the rendezvous host, which had the mirror lines but
>   no `blocked` entries during bootstrap. Recheck after it reboots into the
>   cluster.
>
> Steps below that destroy or recreate the VCN, LPG or peering route
> (T3.2, T3.4–T3.5 as first written, T4.4, the H2 part of T4.5 and T5.5)
> are superseded by this note.

## Goal

Rebuild the OC3 cluster with a **fresh checkout** of the fork's `create-cluster`
stack (`dmc5179/oci-openshift`, branch `disconnected`) so that the cluster
**cannot pull a mirrored image from anywhere but the mirror**, and prove that:

- every container image comes from a private mirror registry on the bastion,
  including the release, Oracle's CCM and CSI driver, and the CSI sidecars;
- the nodes keep time from the OCI metadata service (169.254.169.254);
- the OCI integrations (CCM, CSI, load balancers) work through the service
  gateway alone;
- the Day 2 disconnected tasks (OperatorHub, catalogs, signatures, must-gather)
  work from the mirror.

## Starting point (inspected 2026-11-11)

| Item | Current state |
|---|---|
| Running cluster | `ocp-deployment`, OpenShift 4.22.9, 3 control plane + 3 workers. Installed around 8 Sep. Pulls from the internet. No IDMS or ITMS. |
| Its stack | `/home/cloud-user/oci-openshift-rhel` on `ocibastion`. Fork `disconnected` at **`fcecaad`** (8 Sep), many commits behind today's branch. Local state in `terraform-stacks/create-cluster/terraform.tfstate`. Module names from that era (`rootfs_storage`, not `boot_artifacts`). |
| Its tfvars | `oci-openshift-rhel/openshift-on-oci.tfvars`, the local copy **v3** (8 Sep). It matches the stack directory whose state was last written 8 Sep 19:49. **v1 is not this deployment's file.** v1 is `~/openshift-on-oci.tfvars`, the same file as the `common.auto.tfvars` in `~/oci-openshift`, an upstream v1.6.0 checkout used in early August (with `webserver_*`, `object_storage_*` and `network_compartment_ocid`, all since removed). v2 is `openshift-on-oci.tfvars.working` (14 Aug). v2 and v3 have the same values and differ only in comments. **Proof:** the running cluster's SSH key (MachineConfigs `99-master-ssh` and `99-worker-ssh`) and the install directory's `install-config.yaml` both hash to the v2/v3 key, not v1's. Bash history shows applies with all three files (`../../openshift-on-oci.tfvars`, `../../../openshift-on-oci.tfvars`, and a since-deleted `../../../openshift-on-oci.tfvars.rootfs`), always with `openshift_image_source_uri` overridden on the command line. That is why the image PAR in state matches no file. Using a single tfvars file outside the repo removes this ambiguity in the new setup. |
| Tag namespaces | Created on 6 Aug by the `create-instance-role-tags` and `create-resource-attribution-tags` stacks in **`~/oci-openshift`** (upstream v1.6.0, its own state). The cluster stack reuses them (`use_existing_tags = true`). **Leave both stacks and that directory alone.** |
| Peering | The cluster VCN has one LPG, `openshift-to-bastion`, PEERED with the bastion VCN <bastion-vcn-cidr>. It is **not in terraform state**; it was created by hand. The private route table has `<bastion-vcn-cidr> → LPG` (the helper's rule), `0.0.0.0/0 → NAT`, and the service gateway rule for "All … Services In Oracle Services Network". |
| NAT gateway | `block-traffic: false` |
| Security lists | Private subnet: ingress only from <cluster-vcn-cidr>. Public subnet: TCP from anywhere. So the bastion reaches the API load balancer over the peering, but not the nodes directly. |

## Approach: retire the old stack, build a fresh one

**Recommended: destroy the old stack with its own checkout, then create a new
stack from a fresh checkout and fresh state.** Migrating the `fcecaad` state
in place to today's code would mean `moved` blocks or `terraform state mv` for
renamed modules (`rootfs_storage` → `boot_artifacts`, among others), and
reviewing every replacement plan. That's more work and risk than a rebuild,
and it would test a migration path no customer uses. A fresh build is also
what a real enclave deployment looks like.

Reasons to destroy *before* creating, rather than run both side by side:

- The IAM dynamic group and policy names derive from `cluster_name` and must be
  unique in the tenancy.
- The LB and DNS names collide.
- Reusing <cluster-vcn-cidr> keeps the bastion side of the peering, the
  `<cluster-vcn-cidr>` route in the bastion VCN, unchanged.

Running both side by side would need a new cluster name, a new CIDR, a second
LPG pair and new bastion routes.

## What makes it a simulation (harness only, not the official workflow)

| Harness step | Why | Survives `terraform apply`? |
|---|---|---|
| **H1. Dropped 2026-11-11.** No NAT block. Replaced by `mirror_source_policy = "NeverContactSource"`, which is a stack setting, not a harness step (see below). | — | — |
| **H2. Re-add the bastion peering route** (`scripts/add-bastion-peering-route.sh`) | The bastion is in a separate VCN. Each apply recreates the private route table and drops the route. | No. Run it after **every** apply. |
| **H3. Recreate the cluster-side LPG and peer it** (one-off, after the new VCN exists) | The LPG was never in terraform. It is deleted with the old VCN. | It isn't terraform-managed. Created once per VCN. |

**How "disconnected" is enforced without touching the network.** The new
tfvars sets `mirror_source_policy = "NeverContactSource"`. This variable was
added to the fork on 2026-11-11, uncommitted at the time of writing. The stack
then renders:

- `sourcePolicy: NeverContactSource` on both install-config `imageDigestSources`;
- `mirrorSourcePolicy: NeverContactSource` on every entry of its ImageTagMirrorSet.

The Agent-based Installer writes those sources into the agent's
`registries.conf` as `blocked = true` from first boot. This was checked with
4.22.18 `agent create cluster-manifests`: both release sources were rendered
`blocked = true`, with only the mirror as location. The cluster then carries
the policy in its IDMS and ITMS. Every mirrored source (the release, the
Oracle CCM and CSI driver, the sig-storage sidecars) is therefore pulled from
the mirror or not at all. A missing image fails loudly instead of being
fetched from the internet. References: KCS 7078704, 7106542, 7131556.

**What it does not cover.** It blocks image pulls from the *mirrored* sources
only. Images from other registries, and non-image traffic, can still reach the
internet through the NAT, so the test checks those separately:

- NTP: T6.6 checks that chrony selects 169.254.169.254 and not a public pool;
- telemetry: the mirror-only pull secret has no `cloud.openshift.com`, T6.11;
- other outbound HTTP: noted in the T8.1 write-up.

Environment preparation is not a workaround. A real enclave also provides
these:

- a registry host;
- DNS for it;
- firewall rules to reach it;
- a CA for it.

## Inputs and secrets

| Item | Where | Notes |
|---|---|---|
| New tfvars | Local `~/workspace/openshift-on-oci/oc3-private/oc3-disconnected.tfvars`, git-excluded, mode 600. Copied to the bastion as `~/oc3-private/oc3-disconnected.tfvars`. | Built from the fork template at `disconnected@ec5e7b1` with every value from v3 carried over. The changes from v3 are listed below. |
| Pull secret for the cluster | Bastion `~/oc3-private/mirror-only.json` | Mirror credentials only. Passed as `TF_VAR_redhat_pull_secret`. |
| Pull secret for oc-mirror | Bastion `~/oc3-private/merged.json` | Red Hat pull secret plus the mirror |
| Mirror CA | Bastion `~/oc3-private/mirror-ca.pem` | Passed as `TF_VAR_additional_trust_bundle` |
| OCIDs used by commands | Bastion `~/oc3-private/ids.env`, mode 600 | `NAT_OCID`, `RT_OCID`, `VCN_OCID`, `CMP_OCID`, `LPG_OCID` and `BASTION_LPG_OCID`, written by the snippet in T4.3. **Don't paste them anywhere.** |

New tfvars compared with v3:

| Variable | v3 | New | Why |
|---|---|---|---|
| `oci_driver_version` | `v1.34.0` | `v1.35.0` | The 4.22 mapping, and what the imageset mirrors. The v1.34.0 developer image is gone since v1.6.2. |
| `private_registry` | — | `"MIRROR_FQDN:8443"` | Placeholder. Set to the final `<MIRROR>` in T2.1. |
| `additional_ntp_sources` | — (didn't exist at `fcecaad`) | `["169.254.169.254"]` | The default, but stated explicitly |
| `create_openshift_instances` | `false` | `true` | Template convention: the file holds the pass 2 value, and pass 1 overrides it to false on the command line |
| `openshift_image_source_uri` | an expired PAR | not set | Disconnected installs build it from the ISO uploaded in pass 2 |
| `enable_fips`, `use_oracle_cloud_agent`, `use_autoscaling_operator`, `set_proxy` | `false` | `false` | Unchanged. Listed so the choice is explicit. |
| `redhat_pull_secret`, `additional_trust_bundle` | not in the file | not in the file | Supplied through `TF_VAR_` at apply time |

Everything else is v3's value: OCIDs, region, cluster name, zone, CIDRs,
shapes and counts, tags, the SSH key, and `rendezvous_ip` <rendezvous-ip>.

## Official references (OpenShift 4.22)

- *Disconnected environments*: mirror registry for Red Hat OpenShift (§4), oc-mirror plugin v2 (§5), OLM in disconnected environments (§10).
  https://access.redhat.com/documentation/en-us/openshift_container_platform/4.22/html-single/disconnected_environments/index
  - Mirror registry prerequisites: RHEL 8/9, Podman ≥ 3.4.2, OpenSSL, an FQDN that resolves through DNS, 2+ vCPUs, 8 GB RAM.
  - Mirror-to-mirror: `oc mirror -c <isc> --workspace file://<dir> docker://<registry> --v2`. Results go to `working-dir/cluster-resources`: IDMS, ITMS, CatalogSource, ClusterCatalog, UpdateService and the signature ConfigMap.
  - Signature mirroring is on by default (§5.11). Keep it.
  - Disable the default catalogs with `oc patch OperatorHub cluster --type json -p '[{"op":"add","path":"/spec/disableAllDefaultSources","value":true}]'` (§10.2).
- *Installing an on-premise cluster with the Agent-based Installer*, §2.1.1 (`imageDigestSources`) and §3.5 (verify that the host can pull the release images).
  https://access.redhat.com/documentation/en-us/openshift_container_platform/4.22/html-single/installing_an_on-premise_cluster_with_the_agent-based_installer/index
- *Installing on Oracle Distributed Cloud*, chapter 2. Its "disconnected" text assumes outbound access (OSDOCS-24411). This test produces evidence that the images need no egress.
- KCS 7078704 (`mirrorSourcePolicy` values), 7106542 (block a registry and use a mirror instead), 7131556 (pods pulling from external registries despite a mirror). Also installer `pkg/types/installconfig.go` (`imageDigestSources[].sourcePolicy`) and `pkg/asset/agent/mirror/registriesconf.go` (rendered as `blocked`).
  https://access.redhat.com/documentation/en-us/openshift_container_platform/4.22/html-single/installing_on_oracle_distributed_cloud/index
- KCS 7129169: oc-mirror v2 exits silently if `/tmp` is `noexec`. Set `TMPDIR`.
- KCS 7111547: Agent-based installs fail disconnected if the release digest isn't in the mirror.

Placeholders:

| Placeholder | Meaning |
|---|---|
| `<MIRROR_FQDN>` | Registry hostname, for example `mirror.sim.internal` |
| `<MIRROR>` | `<MIRROR_FQDN>:8443` |
| `<BASTION_IP>` | The bastion's private IP |
| `NEW` | `~/oci-openshift-disconnected`, the fresh checkout |
| `OLD` | `~/oci-openshift-rhel` |
| `TFV` | `~/oc3-private/oc3-disconnected.tfvars` |

---

## Phase 0: Go/no-go and backup

| # | Step | Pass criteria |
|---|---|---|
| T0.1 | Confirm nobody needs `ocp-deployment`. **It will be destroyed.** | Explicit go from Dan |
| T0.2 | Archive the old stack, excluding provider binaries: `mkdir -p ~/archive && chmod 700 ~/archive && tar --exclude='.terraform' -czf ~/archive/oci-openshift-rhel-fcecaad-$(date +%F).tgz -C ~ oci-openshift-rhel ocp-deployment-agentBasedInstallation* && chmod 600 ~/archive/*.tgz`. Also keep the kubeconfig. | Archive exists and is readable only by cloud-user |
| T0.3 | Record the current state: `oc get clusterversion,co,nodes`, `oc get idms,itms`, and the route rules shown above. | Saved under `~/archive/` |
| T0.4 | Check bastion resources: `nproc`, `free -g`, `df -h` on the planned `quayRoot` and workspace filesystems. | ≥ 2 vCPU, ≥ 8 GB RAM, ≥ 100 GB free |
| T0.5 | Check clients: `oc version --client` and `oc-mirror --v2 version` (4.22), `terraform version` (1.15.8 today), `podman --version`, `findmnt /tmp` (KCS 7129169). | OK |

## Phase 1: Prove the egress cut on the old cluster (dropped)

**Dropped 2026-11-11 by decision:** no NAT changes on either VCN. Image
egress is enforced by `NeverContactSource` instead (see "What makes it a
simulation"). Traffic to the OCI APIs already uses the service gateway, whose
Oracle Services Network route is more specific than the NAT's 0.0.0.0/0, so it
takes the same path as on today's cluster.

## Phase 2: Mirror registry and content (bastion only, old cluster still up)

| # | Step | Pass criteria |
|---|---|---|
| T2.1 | Choose `<MIRROR_FQDN>`. Add `<BASTION_IP> <MIRROR_FQDN>` to the bastion's `/etc/hosts`. Set `private_registry = "<MIRROR>"` in `TFV`. The cluster-side DNS is created in T4.5, on the new VCN. | — |
| T2.2 | Open 8443/tcp: `sudo firewall-cmd --add-port=8443/tcp --permanent && sudo firewall-cmd --reload`, plus the bastion VCN security list or NSG, ingress TCP 8443 from <cluster-private-subnet-cidr>. That list isn't terraform-managed, so this persists. | — |
| T2.3 | Install the mirror registry (disconnected docs §4.4): `./mirror-registry install --quayHostname <MIRROR_FQDN> --quayRoot <dir> --initUser <user> --initPassword <pw>` | `curl -s https://<MIRROR>/health/instance` returns 200 (after T2.4) |
| T2.4 | Trust and auth: copy `<quayRoot>/quay-rootCA/rootCA.pem` to `~/oc3-private/mirror-ca.pem` and into `/etc/pki/ca-trust/source/anchors/`, then `sudo update-ca-trust`. `podman login <MIRROR>`. Build `merged.json` and `mirror-only.json`, both mode 600. | `podman login` succeeds without `--tls-verify=false` |
| T2.5 | From an old node (the internet stays open, so this only proves the peering path to the mirror): `curl -sm10 --resolve <MIRROR_FQDN>:8443:<BASTION_IP> --cacert <ca> https://<MIRROR>/health/instance`. The CA can be pasted into `/tmp` on the node. | 200. The nodes can reach the mirror over the peering. |
| T2.6 | **Mirror to mirror** using `NEW/docs/imageset-config.yaml` (clone first, T4.1). Add `ghcr.io/oracle/oci-secrets-store-csi-driver-provider:v0.5.1` if vault step 4 will run here. Command: `TMPDIR=~/tmp-ocm oc mirror -c imageset-config.yaml --workspace file://$HOME/oc-mirror-ws docker://<MIRROR> --v2 --authfile ~/oc3-private/merged.json` | Exit 0. `~/oc-mirror-ws/working-dir/cluster-resources/` has the IDMS, ITMS, CatalogSource, signature ConfigMap and UpdateService. |
| T2.7 | Release check (Agent-based docs §3.5): `oc adm release info --registry-config ~/oc3-private/mirror-only.json <MIRROR>/openshift/release-images:4.22.18-x86_64` | 4.22.18, with the same digest as quay.io |
| T2.8 | Extract the installer from the mirror. `--idms-file` is required: without it, `oc` resolves the installer's component image at its quay.io name and fails `unauthorized` with the mirror-only auth file (seen 2026-11-11). Command: `oc adm release extract --registry-config ~/oc3-private/mirror-only.json --idms-file <WS>/working-dir/cluster-resources/idms-oc-mirror.yaml --command=openshift-install --to ~/bin-4.22.18/from-mirror <MIRROR>/openshift/release-images:4.22.18-x86_64` | `openshift-install version` shows 4.22.18, with the release image at `<MIRROR>/openshift/release-images@sha256:…` |

## Phase 3: Retire the old stack

| # | Step | Pass criteria |
|---|---|---|
| T3.1 | Load the IDs from `OLD` state (T4.3 snippet with `cd OLD/terraform-stacks/create-cluster`). Find the **bastion-side** LPG (bastion VCN, peer CIDR <cluster-vcn-cidr>) and save it as `BASTION_LPG_OCID` in `ids.env`. It survives and is reused in H3. | `ids.env` has the old cluster-side `LPG_OCID` and `BASTION_LPG_OCID` |
| T3.2 | **Remove what terraform doesn't own** from the old VCN, or the VCN delete fails. First the helper's route: rewrite the private route table's rules without the `<bastion-vcn-cidr>` entry (`oci network route-table update --rt-id $RT_OCID --route-rules file://rules-without-peering.json --force`). Then delete the old cluster-side LPG: `oci network local-peering-gateway delete --local-peering-gateway-id $LPG_OCID --force`. The bastion-side LPG goes to REVOKED. That is expected. | The VCN has no LPG |
| T3.3 | Check the boot-artifact bucket for objects that aren't in state, such as an ISO uploaded by script: `oci os object list --bucket-name <bucket> --all`. Delete any such object, or the bucket delete fails. | Only `agent.x86_64-rootfs.img`, which is in state. As of 2026-11-11 that was the only object. |
| T3.4 | **Destroy plan with the old checkout and v3:** `cd OLD/terraform-stacks/create-cluster && TF_VAR_redhat_pull_secret="$(cat ~/oc3-private/merged.json)" terraform plan -destroy -var-file=../../openshift-on-oci.tfvars -var create_openshift_instances=true -out destroy.plan` | The plan destroys exactly the 91 managed resources in the old state (counted 2026-11-11). **No `oci_identity_tag*` resources.** Review before applying. |
| T3.5 | `terraform apply destroy.plan` | Destroy complete. The cluster instances, image, LBs, DNS zone, IAM dynamic groups and policies, bucket and VCN are gone. |
| T3.5a | The bastion home directory has its own, hand-edited copies of `add-bastion-peering-route.sh` and `generate-ocp-artifacts.sh` (`~/`). Don't use them with the new stack: use the copies in `NEW/scripts/`, which take OCIDs from the environment. Move the home copies into `~/archive/` so they can't be run by accident. | Only `NEW/scripts/` versions in use |
| T3.6 | Leave `OLD` in place, read-only, with its now-empty state, until the test passes. Then delete it (T8.3). It stays in the T0.2 archive. Don't touch `~/oci-openshift` (tag stacks). | — |

## Phase 4: Fresh checkout, pass 1, network harness

| # | Step | Pass criteria |
|---|---|---|
| T4.1 | `git clone -b disconnected https://github.com/dmc5179/oci-openshift.git ~/oci-openshift-disconnected && cd ~/oci-openshift-disconnected && git log -1 --format='%h %s'`. Record the SHA in the results (`ec5e7b1` or later). The repo's `.gitignore` already covers `*.tfvars`, but the tfvars stays in `~/oc3-private/` anyway. | Clean checkout |
| T4.2 | `cd NEW/terraform-stacks/create-cluster && terraform init`. The bastion is online. Optionally exercise the offline bundle instead (`scripts/build-offline-bundle.sh` / `install-offline-bundle.sh`). | Init OK, providers pinned by the lock file |
| T4.3 | **Pass 1:** `export TF_VAR_redhat_pull_secret="$(cat ~/oc3-private/mirror-only.json)" TF_VAR_additional_trust_bundle="$(cat ~/oc3-private/mirror-ca.pem)"; terraform apply -var-file=$TFV -var='create_openshift_instances=false'`. Then refresh `ids.env` from the new state with the snippet below. | Network, LBs, DNS, IAM, bucket and PARs created. No instances. |
| T4.4 | **H3:** create the new cluster-side LPG and connect it: `oci network local-peering-gateway create --compartment-id $CMP_OCID --vcn-id $VCN_OCID --display-name openshift-to-bastion`, then `oci network local-peering-gateway connect --local-peering-gateway-id <new> --peer-id $BASTION_LPG_OCID`. Save the new `LPG_OCID`. The bastion VCN's `<cluster-vcn-cidr> → bastion LPG` route is unchanged. | `peering-status: PEERED` |
| T4.5 | **H2:** `ROUTE_TABLE_OCID=$RT_OCID LPG_OCID=$LPG_OCID NEW/scripts/add-bastion-peering-route.sh`. **Registry DNS:** create a private zone (for example `sim.internal`) in the **new** VCN's default resolver view, with an A record `<MIRROR_FQDN>` → `<BASTION_IP>`. Keep it separate from the stack's zone so terraform never touches it. No NAT change. | Route present, the zone resolves from the VCN (checked in T6.1) |

Snippet to write `ids.env` from whichever state directory you're in. It never
prints the values:

```bash
terraform show -json | python3 -c '
import json,sys
s=json.load(sys.stdin)
def walk(m):
    for r in m.get("resources",[]): yield r
    for c in m.get("child_modules",[]): yield from walk(c)
for r in walk(s["values"]["root_module"]):
    t,v=r["type"],r["values"]
    if t=="oci_core_vcn": print("VCN_OCID="+v["id"]); print("CMP_OCID="+v["compartment_id"])
    if t=="oci_core_route_table" and v["display_name"]=="private": print("RT_OCID="+v["id"])
    if t=="oci_core_nat_gateway": print("NAT_OCID="+v["id"])
' > ~/oc3-private/ids.env.new && grep -v -E '^(VCN|CMP|RT|NAT)_OCID=' ~/oc3-private/ids.env 2>/dev/null >> ~/oc3-private/ids.env.new
mv ~/oc3-private/ids.env.new ~/oc3-private/ids.env && chmod 600 ~/oc3-private/ids.env && . ~/oc3-private/ids.env
```

## Phase 5: Artifacts, ISO, pass 2

| # | Step | Pass criteria |
|---|---|---|
| T5.1 | `NEW/scripts/generate-ocp-artifacts.sh ocp-deployment NEW/terraform-stacks/create-cluster` | Exit 0 |
| T5.2 | Inspect `~/ocp-deployment-agentBasedInstallation`. `install-config.yaml` has `imageDigestSources` → `<MIRROR>/openshift/release{,-images}`, `additionalTrustBundle`, `sourcePolicy: NeverContactSource` on both entries, `additionalTrustBundlePolicy: Always`, and a pull secret with only `<MIRROR>`. The ITMS manifest has `mirrorSourcePolicy: NeverContactSource` on every entry. `agent-config.yaml` has `additionalNTPSources: [169.254.169.254]`, `rendezvousIP: <rendezvous-ip>` and `bootArtifactsBaseURL` (the rootfs PAR). `openshift/` has the 9 required manifests plus `manifest_image_tag_mirror_set.yaml` and `manifest_oci_custom_ca.yaml`. | All present |
| T5.3 | Layout cross-check: every mirror target in `imageDigestSources` and the ITMS exists in the mirror (`skopeo inspect --authfile ~/oc3-private/mirror-only.json docker://<target>:<tag>`), and matches oc-mirror's `idms-oc-mirror.yaml` and `itms-oc-mirror.yaml`. | No missing paths |
| T5.4 | ISO, built with the mirror-extracted installer: `cd ~/ocp-deployment-agentBasedInstallation && ~/bin-4.22.18/openshift-install agent create image --dir .` | ISO and rootfs created. The release came from `<MIRROR>`. |
| T5.5 | **Pass 2:** `cd NEW/terraform-stacks/create-cluster && terraform apply -var-file=$TFV -var="iso_file_path=$HOME/ocp-deployment-agentBasedInstallation/agent.x86_64.iso" -var="rootfs_file_path=$HOME/ocp-deployment-agentBasedInstallation/boot-artifacts/agent.x86_64-rootfs.img"`. **Then immediately H2.** | Instances launched. Route re-added. |
| T5.6 | Monitor with the `etc_hosts_entry` output in the bastion's `/etc/hosts`: `~/bin-4.22.18/openshift-install agent wait-for bootstrap-complete --dir ~/ocp-deployment-agentBasedInstallation`, then `wait-for install-complete`. **Caveat:** the private subnet only admits <cluster-vcn-cidr>, so the bastion can't reach the agent REST API on <rendezvous-ip>:8090, and bootstrap-phase progress may not show. Once the API load balancer answers, `wait-for` and `oc` work. Record what the bastion could and couldn't see. | Install completes |

## Phase 6: Verification

| # | Check | Pass criteria |
|---|---|---|
| T6.1 | `oc debug node/<n> -- chroot /host getent hosts <MIRROR_FQDN>`, and `grep -B1 -A3 'blocked = true' /etc/containers/registries.conf` | Mirror resolves. Every mirrored source (the release, `ghcr.io/oracle/...`, `registry.k8s.io/sig-storage/...`) is `blocked = true`. |
| T6.2 | `oc get clusterversion,co,nodes` | 4.22.18. All operators Available, none Degraded (note any that degrade only because there's no internet). Nodes Ready. |
| T6.3 | `oc get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded` and `oc get events -A \| grep -iE 'pull\|back-off'` | No pull failures |
| T6.4 | **Images came from the mirror:** registries.conf on the nodes lists the mirrors; `journalctl -u crio \| grep -c <MIRROR>` is non-zero; the Quay usage logs show pulls of the release, `oracle/cloud-provider-oci` and `sig-storage/*`. Because the sources are blocked, every successful pull of a mirrored image came through the mirror. | Evidence for the release, CCM, CSI and sidecars |
| T6.5 | `oc get idms,itms -o yaml` | The release IDMS. The stack's `image-tag-mirror` ITMS covering `ghcr.io/oracle` and `registry.k8s.io/sig-storage`. |
| T6.6 | `oc debug node/<n> -- chroot /host chronyc -n sources -v; chronyc tracking`, on a control plane node and a worker | 169.254.169.254 selected (`^*`), offset < 100 ms |
| T6.7 | CCM: every node has `spec.providerID: oci://...` and no `uninitialized` taint. No x509 or timeout errors in the CCM logs. | Pass |
| T6.8 | CSI: a PVC on the default OCI block StorageClass, plus a pod writing to it, then delete the pod and check the volume detaches | Pass |
| T6.9 | Console and `oc login` from the bastion through the load balancers | Pass |
| T6.10 | Negative test: a tag that isn't mirrored, from a blocked source: `oc run nc-test --image=ghcr.io/oracle/cloud-provider-oci:v1.34.0 --restart=Never -n default -- true` | `ErrImagePull`. The event shows the mirror was tried and the source is blocked, not a fetch from ghcr.io. Delete the pod. |
| T6.11 | `oc get secret/pull-secret -n openshift-config -o jsonpath='{.data.\.dockerconfigjson}' \| base64 -d \| jq -r '.auths\|keys[]'` and `oc get co insights` | Only `<MIRROR>`. Insights state recorded. |

## Phase 7: Day 2 disconnected operations

| # | Step | Pass criteria |
|---|---|---|
| T7.1 | Disable the default catalogs (§10.2) | No default CatalogSources |
| T7.2 | oc-mirror's generated `idms-oc-mirror.yaml` and `itms-oc-mirror.yaml` have no `mirrorSourcePolicy`. Add `mirrorSourcePolicy: NeverContactSource` to each entry, so the operator images are held to the same rule, then `oc apply -f ~/oc-mirror-ws/working-dir/cluster-resources/`. Record how the oc-mirror ITMS overlaps with the stack's `image-tag-mirror`, and whether the MCPs settle. | The CatalogSource is READY. The MCPs are Updated. The operator sources are `blocked = true`. |
| T7.3 | Install `secrets-store-csi-driver-operator` from the mirrored catalog (`NEW` copy of `tests/oci-vault/manifests/10-operator.yaml`, with `source` set to the oc-mirror CatalogSource) | CSV Succeeded |
| T7.4 | `oc adm must-gather --image=<MIRROR>/openshift4/ose-must-gather:latest` | Completes |
| T7.5 | Optional: an incremental mirror of a later 4.22.z, apply its signature ConfigMap, then `oc adm upgrade --to-image=<MIRROR>/openshift/release-images@sha256:...` | The upgrade completes with no internet |
| T7.6 | Optional: mirror-to-disk on a connected host, then disk-to-mirror on the bastion, to exercise the enclave transfer path | Same content as T2.6 |

## Phase 8: Exit

| # | Step |
|---|---|
| T8.1 | Results under `docs/analysis/`: pass/fail per test, the fork SHA, deviations from the docs, and anything that needed the internet. |
| T8.2 | Decide whether to keep `NeverContactSource` on this cluster. To relax it later, edit the IDMS and ITMS to `AllowContactingSource`; that rolls out without node reboots. Remove the `sim.internal` zone if it isn't needed. |
| T8.3 | Once passed, delete `OLD` (the archive keeps it). The new stack in `NEW` is now the OC3 cluster's stack of record. |
| T8.4 | Feed the evidence into OSDOCS-24411 and OCPSTRAT-3871 (DIA customer link per the standing rule), and Oracle-side findings into the Open Items doc. |

## Known risks

| Risk | Mitigation |
|---|---|
| A mirrored image is missing or at the wrong path | With `NeverContactSource` the pull fails with no fallback. T5.3 checks every path before the ISO is built. |
| The old-stack destroy fails on an out-of-band object (LPG, extra bucket objects) | T3.2 and T3.3. If something else turns up, delete it and re-run T3.5. Nothing outside the cluster depends on these resources. |
| Something new can't be recreated (quota, IAM name not yet released) | Destroy and create are a few minutes apart, so retry. IAM deletes can take minutes to propagate. |
| oc-mirror signature lookups fail for unsigned Oracle and `registry.k8s.io` images | `test-mirror-images.sh` has passed with this imageset. Don't use `--remove-signatures`, because it drops the release signatures too. |
| The peering route is lost after an apply | H2 straight after every apply |
| The bastion can't see bootstrap progress (port 8090 blocked) | T5.6 caveat. Rely on the API load balancer and the console of the rendezvous instance. |
| The vault access request (pending with the OC3 owners) names dynamic group `ocp-deployment_compute_nodes` | The same name is recreated. Recheck any policy they've already written once the new stack exists. |

## Observations to carry forward

- `mirror_source_policy` (fork, 2026-11-11) belongs upstream with PR #94. A
  disconnected install that can silently fall back to the source isn't
  disconnected, and KCS 7131556 describes customers hitting exactly that.
- The stack always creates an internet gateway and a NAT gateway. A real
  enclave has neither. Making them optional under
  `is_disconnected_installation` would let the stack match one.
- The private route table is fully managed by the stack, which is the cause of
  H2. A variable for extra route rules, or `use_existing_network`, would
  remove it.
- The LPG (H3) is outside terraform. A real deployment would either manage it
  in the stack or use an existing network.
