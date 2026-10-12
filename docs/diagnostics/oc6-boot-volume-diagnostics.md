# OC3 vs OC6 — boot volume / iPXE diagnostic commands

> **STATUS: HYPOTHESIS DISPROVED — 2026-10-09. Retained for the commands and as a record of
> what was eliminated. Do not re-run expecting a result.**
>
> The theory below was that the custom image fell back to iSCSI boot, triggering OCI's default
> iPXE script, which injected the `ip=` kernel argument. It was tested and failed:
>
> - OC6 instance and image both returned `boot-volume-type: PARAVIRTUALIZED`, so no iPXE
>   script runs at all.
> - OC6 returned exactly one global image capability schema, so the `[0]` indexing theory
>   does not apply either.
> - The agent ISO was separately confirmed to contain UEFI boot bits, ruling out a
>   legacy-boot fallback.
>
> The `ip=` argument is real but was **not** the cause of the OC6 install failure. The actual
> root cause was that the OCI day-0 manifests (CCM, CSI, cluster network) were missing from the
> `openshift/` directory when the agent ISO was built — `generate-ocp-artifacts.sh` had not been
> run against the install directory. Without the CCM, nodes keep the
> `node.cloudprovider.kubernetes.io/uninitialized` taint, CNI never starts, and the cluster
> cannot bootstrap. The accompanying `systemd-network-generator` failure was cosmetic: it emits
> `systemd-networkd` units, and RHCOS uses NetworkManager, so nothing consumes them.
>
> The malformed `ip=` argument remains unexplained and may still be worth reporting to Oracle,
> but it is not a cluster-breaking issue.

Short set of read-only OCI CLI queries to run in **OC6** and compare against **OC3**.
Everything here is a `get`/`list`; nothing modifies state.

## Why

OC6 control plane nodes boot with a kernel argument that OC3 nodes do not have:

```
ip=02-00-17-00-24-27:dhcp
```

The "interface name" is a MAC address with hyphens. At 17 characters it exceeds the Linux
`IFNAMSIZ` limit of 15, so `systemd-network-generator` fails with *"Failed to start Generate
network units from kernel command line"* and the node gets no network configuration.

The argument is **not** in the agent ISO (verified by extracting `isolinux.cfg` and `grub.cfg`
and by raw-scanning both the agent ISO and the stock RHCOS ISO), not in the generated
manifests, not in the OpenShift installer source, and not in the Terraform.

Working hypothesis: it is injected at boot by **OCI's default iPXE script**. Per Oracle's SDK
documentation, `PARAVIRTUALIZED` is the default boot volume type *for platform images only* —
a custom (BYOI) image falls back to iSCSI boot unless its image capability schema says
otherwise. On the iSCSI path the default iPXE script network-boots the volume from
`169.254.0.2`, which needs networking in the initramfs, hence an injected `ip=` naming the
booting NIC by MAC. Oracle's docs state that with a paravirtualized attachment "no iPXE script
is used" — consistent with ordinary Oracle Linux VMs in the same tenancy being unaffected.

These commands confirm or disprove that.

## Prerequisites

- OCI CLI configured for the target realm.
- **OC6 only:** `~/.oci/regions-config.json` must be present, or the CLI will not resolve
  endpoints for the realm.
- Needs the OCIDs of: one control plane instance, and the custom compute image the cluster
  was launched from.

## The commands

Run each in **both** realms and keep the output side by side.

### 1. Instance boot volume type — most decisive

```bash
oci compute instance get \
  --instance-id <control-plane-instance-ocid> \
  --query 'data."launch-options"'
```

This is the one that settles it. Look at `boot-volume-type`.

### 2. Custom image launch options

```bash
oci compute image get \
  --image-id <custom-image-ocid> \
  --query 'data."launch-options"'
```

Isolates whether the divergence happens at image-creation time or at instance-launch time.

### 3. Global image capability schema list

```bash
oci compute global-image-capability-schema list \
  --query 'data[].{name:"current-version-name"}'
```

The Terraform selects `[0]` from this list when attaching a capability schema to the custom
image. If the realms return different counts or ordering, that index is unstable.

### 4. Boot volume attachment type (confirmatory)

```bash
oci compute boot-volume-attachment list \
  --compartment-id <compartment-ocid> \
  --availability-domain <ad-name> \
  --instance-id <control-plane-instance-ocid> \
  --query 'data[].{type:"attachment-type",state:"lifecycle-state"}'
```

### 5. Node kernel command line (from the node itself, not the CLI)

```bash
cat /proc/cmdline
```

Capture verbatim. Specifically note whether `console=ttyS0` is present — the OpenShift
installer bakes that into the ISO for the OCI external platform, so if it appears alongside the
bad `ip=`, the ISO's own arguments survived and something appended afterwards.

## Known OC3 values (reference)

| Query | OC3 result |
|---|---|
| 3. global image capability schema list | exactly **one** entry: `05e51b3b-43a6-4829-a9da-7e41f3cf9210` |
| 1. instance `boot-volume-type` | *not yet captured — please run as the control* |

OC3 is the control case: same Terraform, same ISO content, cluster installs successfully.

## How to read the results

| Finding | Meaning |
|---|---|
| OC6 instance `boot-volume-type: ISCSI` | Hypothesis **confirmed**. iPXE is in play and the `ip=` injection is explained end to end. |
| OC6 instance `boot-volume-type: PARAVIRTUALIZED` | Hypothesis **disproved**. The `ip=` is coming from somewhere else and this line of investigation is wrong. |
| OC6 returns **multiple** capability schemas in query 3 | The Terraform's `[0]` index is unstable across realms — a bug we can fix in our stack today. |
| OC6 returns **one** schema, but instance is still `ISCSI` | OC6 is not honouring the `PARAVIRTUALIZED` descriptor for custom BYOI images — an Oracle realm capability gap. |

## If confirmed

The fix is in our Terraform, not in any OpenShift configuration. Boot volume type is an OCI
compute API property set at instance launch, so nothing in `install-config.yaml`,
`agent-config.yaml`, or the `openshift/` manifests can influence it — those are all read after
the kernel is already running.

`shared_modules/compute/main.tf` currently sets no `launch_options` on either instance resource
(`control_plane_node` line 11, `compute_node` line 61); both inherit whatever the image
capability schema resolved to. Pinning it explicitly would bypass iPXE:

```hcl
launch_options {
  boot_volume_type = "PARAVIRTUALIZED"
}
```

Two caveats: it must stay conditional on shape, since bare-metal instances cannot use
paravirtualized boot volumes and must remain on the iSCSI path (key off the existing
`is_control_plane_iscsi_type` / `is_compute_iscsi_type` locals); and `launch_options` has other
attributes (`network_type`, `remote_data_volume_type`, `firmware`) where OCI may reject a
partial block or apply unintended defaults, so it needs a real plan/apply rather than being
assumed correct.
