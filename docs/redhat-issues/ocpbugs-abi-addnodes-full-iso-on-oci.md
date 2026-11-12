# Draft bug: `oc adm node-image create` builds a full ISO for external/OCI clusters, and the node fails to install with EBUSY

**Status:** filed 2026-11-12 as [OCPBUGS-140852](https://redhat.atlassian.net/browse/OCPBUGS-140852). Component
Installer / Agent based installation. After filing, add the DIA customer link (mdm 1463,
affected_by) per the standing rule.

---

## Description

Adding a worker to an Agent-based OpenShift cluster on Oracle Cloud Infrastructure (platform
`external`, `platformName: oci`) with the supported `oc adm node-image create` fails. On OCI the
generated ISO is imported as a custom image and becomes the instance's boot volume. The node
image is a **full** ISO, with the root filesystem embedded, so the live agent keeps the boot
disk in use. When it tries to write RHCOS to that same disk, coreos-installer fails with
`EBUSY`.

The original cluster installation doesn't have this problem, because for the external platform
the installer always builds a **minimal** ISO and the root filesystem is fetched into memory
from `bootArtifactsBaseURL`. The add-nodes workflow never sets the minimal-ISO flag, even when
`bootArtifactsBaseURL` is set in `nodes-config.yaml`.

## Version

- OpenShift 4.22.18, `oc` 4.22.18, cluster installed with the Agent-based Installer, platform
  `external` / `oci`, disconnected (mirror registry, `NeverContactSource`).

## Steps to reproduce

1. On OCI, launch the new worker instance (a MAC address is needed for
   `oc adm node-image create`, and OCI only assigns one at launch).
2. `oc adm node-image create --mac-address=<instance-mac> --hostname=<name>`.
3. Upload `node.iso` to Object Storage, import it as a custom image (paravirtualized, UEFI
   capability schema as for the cluster image), and boot the instance from it (here by
   replacing the instance's boot volume with that image; the MAC is unchanged).
4. `oc adm node-image monitor --ip-addresses <ip>`.

## Actual results

The host registers and validates (`Host is ready to be installed`), starts installing, then:

```
Host: <name>, reached installation stage Failed: failed after 3 attempts, last error:
failed executing /usr/bin/nsenter [...]
Caused by:
    0: couldn't reread partition table: device is in use
    1: EBUSY: Device or resource busy
```

No node joins.

## Expected results

For an external-platform cluster, the add-nodes ISO is minimal (root filesystem from
`bootArtifactsBaseURL`), as the installation ISO is, so the node can install onto its boot
disk and join.

## Root cause (code)

`openshift/installer`, `pkg/asset/agent/image/agentartifacts.go` (release-4.22):

- Install workflow:
  `a.MinimalISO = agentconfig.Config.MinimalISO || agentManifests.AgentClusterInstall.Spec.PlatformType == hiveext.ExternalPlatformType`,
  with the comment "External platform will always create a minimal ISO".
- Add-nodes workflow (`case workflow.AgentWorkflowTypeAddNodes`): only `BootArtifactsBaseURL`
  is copied from `ClusterInfo`. `MinimalISO` is never set, so `agentimage.go` always builds a
  full ISO.
- `nodes-config.yaml` already accepts `bootArtifactsBaseURL` (`joiner/addnodesconfig.go`,
  `joiner/clusterinfo.go` `retrieveBootArtifactsBaseURL`), but it has no effect on the ISO type.

## Suggested fix

In the add-nodes branch, set `MinimalISO` when the cluster's platform is external (OCI), as the
install workflow does, and require `bootArtifactsBaseURL` in that case. Alternatively, allow
`minimalISO: true` in `nodes-config.yaml`.

## Additional info

- Possible unsupported workaround, not yet tested: convert the generated ISO with
  `coreos-installer iso extract minimal-iso --output-rootfs <rootfs.img> --rootfs-url <url> node.iso minimal.iso`,
  hosting the rootfs at `<url>` (for example an Object Storage PAR).
- A related documentation gap: neither Red Hat's add-nodes procedure nor Oracle's "Adding Nodes
  to a Cluster" says how to get the MAC address on OCI, where it exists only after launch. The
  flow that worked here was: launch the instance on any image, read the MAC, build the node
  image, then replace the instance's boot volume with it.
