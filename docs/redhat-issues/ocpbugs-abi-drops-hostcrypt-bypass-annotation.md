# Draft bug: Agent-based Installer drops the `hostcrypt-check-bypassed` annotation from the cluster's install-config

**Status:** draft, not filed. Proposed component: Installer / Agent-based Installation (assisted-service). After filing, add the DIA customer link (mdm 1463, affected_by) per the standing rule.

---

## Description

To install a FIPS cluster from a host that is not in FIPS mode, `openshift-install` accepts `OPENSHIFT_INSTALL_SKIP_HOSTCRYPT_VALIDATION=1`. The resulting cluster is unsupported, and the documentation says it is for testing only. When the variable is set, the installer:

- warns that the host-crypto validation was bypassed and that the cluster is not supportable;
- adds `install.openshift.io/hostcrypt-check-bypassed: "true"` to the install-config's `metadata.annotations`, so the cluster permanently records the bypass.

With the Agent-based Installer, the annotation does not reach the cluster:

- It is present in the installer's own asset. `.openshift_install_state.json` → `*agent.OptionalInstallConfig` → `config.metadata.annotations`.
- It is missing from the installed cluster. `kube-system/cluster-config-v1` → `data.install-config` has `metadata: {name: <cluster-name>}`, with no annotations.

So nothing on the running cluster shows that FIPS was set up from a non-FIPS host. Support and Insights can't tell this unsupported install apart from a supported FIPS install. The marker exists to prevent exactly that.

The likely cause is the same as OCPBUGS-140771. With the Agent-based Installer, assisted-service generates the cluster's install-config again from its own model. Fields it doesn't carry, here `metadata.annotations`, are lost.

## Version

- OpenShift 4.22.22, `openshift-install-fips` extracted from the mirrored release, `openshift-install agent create image`.
- Install host: RHEL 9, FIPS mode **not** enabled.
- Platform `external` (`platformName: oci`), 3 control plane and 3 compute nodes, disconnected (oc-mirror v2 to a mirror registry for Red Hat OpenShift).

## How reproducible

Always (observed once end to end; the cause is in how the install-config is generated).

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
- Before filing, check whether IPI on another platform keeps the annotation in `cluster-config-v1`, to confirm this is specific to the Agent-based Installer. Not tested here.
