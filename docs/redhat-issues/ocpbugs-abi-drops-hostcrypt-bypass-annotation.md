# Draft bug: Agent-based Installer drops the `hostcrypt-check-bypassed` annotation from the cluster's install-config

**Status:** draft, not filed. Proposed component: Installer / Agent-based Installation. The loss happens in the installer's agent manifest generation; a fix may also need assisted-service. After filing, add the DIA customer link (mdm 1463, affected_by) per the standing rule.

---

## Description

To install a FIPS cluster from a host that is not in FIPS mode, `openshift-install` accepts `OPENSHIFT_INSTALL_SKIP_HOSTCRYPT_VALIDATION=1`. The resulting cluster is unsupported, and the documentation says it is for testing only. When the variable is set, the installer:

- warns that the host-crypto validation was bypassed and that the cluster is not supportable;
- adds `install.openshift.io/hostcrypt-check-bypassed: "true"` to the install-config's `metadata.annotations`, so the cluster permanently records the bypass.

With the Agent-based Installer, the annotation does not reach the cluster:

- It is present in the installer's own asset. `.openshift_install_state.json` → `*agent.OptionalInstallConfig` → `config.metadata.annotations`.
- It is missing from the installed cluster. `kube-system/cluster-config-v1` → `data.install-config` has `metadata: {name: <cluster-name>}`, with no annotations.

So nothing in `cluster-config-v1` records that the host-crypto check was bypassed. Anyone who later inspects the cluster's install-config, support included, sees what looks like a normal FIPS install. The annotation's purpose is to keep that record.

## Cause (from the installer source, `release-4.22`)

- **Where the annotation is set.** `validateFIPSconfig` in `pkg/types/validation/installconfig.go` sets `c.Annotations[hostCryptBypassedAnnotation] = "true"` on the in-memory install-config when the variable is set and the host check fails.
- **IPI and UPI keep it.** `pkg/asset/manifests/operators.go` builds `cluster-config-v1` from `redactedInstallConfig(*installConfig.Config)`. That function deep-copies the whole `InstallConfig`, including `metav1.ObjectMeta`, and blanks only the pull secret and platform credentials. The annotation is therefore written to the cluster.
- **The Agent-based Installer doesn't pass the install-config through.** It generates ZTP manifests (`AgentClusterInstall`, `ClusterDeployment`, and others), and assisted-service builds the cluster's install-config from them. The only install-config fields the installer forwards beyond the ZTP spec go in the `agent-install.openshift.io/install-config-overrides` annotation on the `AgentClusterInstall` (`pkg/asset/agent/manifests/agentclusterinstall.go`). The struct behind it, `agentClusterInstallInstallConfigOverrides`, carries `fips`, `platform`, `capabilities`, `networking`, `cpuPartitioningMode`, `additionalTrustBundlePolicy`, `featureSet` and `featureGates`. It has no `metadata` or annotations, so the bypass annotation never leaves the installer.

This is the same pattern as OCPBUGS-140771: an install-config field that the Agent-based Installer doesn't carry into assisted-service's model.

**Possible fix:** forward `metadata.annotations`, or at least `install.openshift.io/hostcrypt-check-bypassed`, in the install-config overrides. Not checked: whether assisted-service's override merge accepts `metadata.annotations`, since its install-config generation isn't in the installer tree. If it doesn't, assisted-service needs a matching change.

## Version

- OpenShift 4.22.22, `openshift-install-fips` extracted from the mirrored release, `openshift-install agent create image`.
- Install host: RHEL 9, FIPS mode **not** enabled.
- Platform `external` (`platformName: oci`), 3 control plane and 3 compute nodes, disconnected (oc-mirror v2 to a mirror registry for Red Hat OpenShift).

## How reproducible

Observed once end to end. The code path above is deterministic, so it should happen on every Agent-based install that uses the bypass.

## Steps to reproduce

1. On a host that is not in FIPS mode, set `fips: true` in `install-config.yaml`.
2. `export OPENSHIFT_INSTALL_SKIP_HOSTCRYPT_VALIDATION=1`
3. `openshift-install-fips agent create image --dir <dir>`. Both warnings are printed.
4. Check the installer state:

   ```
   grep hostcrypt-check-bypassed <dir>/.openshift_install_state.json
   ```

   The annotation is present.
5. Boot the nodes and run `openshift-install-fips agent wait-for install-complete`.
6. Check the installed cluster:

   ```
   oc get cm cluster-config-v1 -n kube-system -o jsonpath='{.data.install-config}' | grep -A3 '^metadata:'
   ```

## Actual results

```yaml
metadata:
  name: <cluster-name>
```

No annotations. The cluster otherwise installs correctly in FIPS mode (`fips: true` in the stored install-config; `fips_enabled=1` and the FIPS crypto policy on every node).

## Expected results

The stored install-config keeps `metadata.annotations`, including `install.openshift.io/hostcrypt-check-bypassed: "true"`, so the bypass stays visible on the running cluster.

## Additional info

- Related: OCPBUGS-140771. The Agent-based Installer drops `imageDigestSources[].sourcePolicy` from the cluster's IDMS; the cause looks the same.
- IPI behaviour was established by reading the code (`redactedInstallConfig`); no IPI install was run to confirm it.
- Code references are from `openshift/installer` `release-4.22`. `main` has the same structure.
