# Draft bug: Agent-based Installer drops `imageDigestSources[].sourcePolicy` from the installed cluster's IDMS

**Status:** filed 2026-11-12 as [OCPBUGS-140771](https://redhat.atlassian.net/browse/OCPBUGS-140771). Component
Installer / Agent-based Installation (assisted-service). After filing, add the DIA customer
link (mdm 1463, affected_by) per the standing rule.

---

## Description

With the Agent-based Installer, setting `sourcePolicy: NeverContactSource` on
`imageDigestSources` in `install-config.yaml` takes effect only during the installation. The
`ImageDigestMirrorSet` created in the installed cluster (`image-digest-mirror`) has no
`mirrorSourcePolicy`. When the Machine Config Operator takes over `registries.conf`, the
mirrored sources fall back to the default, `AllowContactingSource`. Nodes can then contact the
public source registry again whenever a pull from the mirror fails.

For a disconnected installation this defeats the reason for setting the policy. The point of
`NeverContactSource` is that a cluster never reaches the source registry, and fails loudly if
an image is missing from the mirror. KCS 7131556 describes customers seeing exactly this kind of
unexpected external traffic from disconnected clusters.

## Version

- OpenShift 4.22.18, Agent-based Installer (`openshift-install agent create image`).
  `openshift-install` was extracted from the mirrored release.
- Platform `external` (`platformName: oci`), 3 control plane + 3 compute nodes, fully mirrored
  with oc-mirror v2 to a mirror registry for Red Hat OpenShift.

## How reproducible

Always (by code inspection; observed once end to end).

## Steps to reproduce

1. In `install-config.yaml`, set:

   ```yaml
   imageDigestSources:
   - mirrors:
     - mirror.example.com:8443/openshift/release
     source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
     sourcePolicy: NeverContactSource
   - mirrors:
     - mirror.example.com:8443/openshift/release-images
     source: quay.io/openshift-release-dev/ocp-release
     sourcePolicy: NeverContactSource
   ```

2. Create the agent ISO and install the cluster.
3. During the installation, on a node: `grep -B1 -A3 'ocp-release' /etc/containers/registries.conf`.
4. After the installation:
   - `oc get idms image-digest-mirror -o yaml`;
   - on any node, `grep -B1 -A3 'ocp-release' /etc/containers/registries.conf`.

## Actual results

- **Step 3 (installation):** the sources are rendered `blocked = true`. This matches
  `openshift-install agent create cluster-manifests`, whose `mirror/registries.conf` also has
  `blocked = true`.
- **Step 4 (installed cluster):** `image-digest-mirror` has `source` and `mirrors` but no
  `mirrorSourcePolicy`. On every node, the two release sources are mirrored but **not**
  `blocked`. In our cluster, `registries.conf` had 21 entries with only 19 blocked; the 19 came
  from an ImageTagMirrorSet that did carry the policy.

## Expected results

The installed cluster's IDMS carries `mirrorSourcePolicy: NeverContactSource` for every source
that had `sourcePolicy: NeverContactSource` in `install-config.yaml`. That is what
`openshift-install` itself does when it generates the IDMS.

## Root cause (code)

- `openshift/installer` propagates the policy correctly:
  - `pkg/asset/manifests/imagedigestmirrorset.go`, `ConvertImageDigestMirrorSet`, sets
    `MirrorSourcePolicy: imageDigestSource.SourcePolicy`;
  - `pkg/asset/agent/mirror/registriesconf.go:214` renders `Blocked` from it.
- In Agent-based installs, assisted-service rebuilds the cluster's install-config from the
  agent's mirror configuration, and drops the policy at three points (`master`; the same on
  `release-ocm-2.15`):
  - `internal/installcfg/installcfg.go`: `type ImageDigestSource struct` has only `Source` and
    `Mirrors`, with no `SourcePolicy` field.
  - `internal/installcfg/builder/builder.go`, `setImageDigestMirrorSet`, builds
    `installcfg.ImageDigestSource{Source: …, Mirrors: …}` (lines 247 and 259 on `master`, 202
    and 214 on `release-ocm-2.15`).
  - `pkg/mirrorregistries/parser.go`, `GetImageRegistries`, converts `registries.conf` to
    `ImageDigestMirrors`/`ImageTagMirrors` without reading `blocked`, so `MirrorSourcePolicy` is
    never set.

The release image source mappings therefore reach the installed cluster without a policy.

## Workaround

After the installation, patch the IDMS:

```bash
oc patch idms image-digest-mirror --type json -p '[
  {"op":"add","path":"/spec/imageDigestMirrors/0/mirrorSourcePolicy","value":"NeverContactSource"},
  {"op":"add","path":"/spec/imageDigestMirrors/1/mirrorSourcePolicy","value":"NeverContactSource"}]'
```

Verified 2026-11-12: the MCO rolled the change out without node reboots, and every source was
then `blocked = true`.

## Additional info

- No existing OCPBUGS or assisted-service issue found. OCPBUGS-139144 (duplicate
  `imageDigestSources` with conflicting `sourcePolicy`) is related but different.
- The rendezvous host showed the mirrors without `blocked` even during bootstrap, while the
  other five nodes were blocked. That is consistent with its configuration coming from the same
  assisted-service path.
- A suggested fix needs all three changes: add `SourcePolicy` to `installcfg.ImageDigestSource`;
  carry `blocked = true` into `MirrorSourcePolicy` in `GetImageRegistries`; and copy it in
  `setImageDigestMirrorSet`. The ImageTagMirrorSet path in the parser needs the same.
