# Autoscaler operator cannot be installed in disconnected environments

**Repository:** `oracle-quickstart/oci-openshift`
**Affected ref:** `main` (verified against `upstream/main` as of 2026-10-06)
**Severity:** Blocker for disconnected / air-gapped installs that enable the autoscaler
**Scope:** Only when `use_autoscaling_operator = true`, or when the
`create-autoscaler-operator` stack is used. Clusters without the autoscaler are
unaffected.

## Summary

The autoscaler operator's provider-installer Job downloads three component
manifests from `github.com` at runtime, from inside the cluster. In an
air-gapped environment these downloads fail and the Job exhausts its
`backoffLimit`, so the autoscaler can never be installed. A fourth dependency
— a public Helm repository — is configured in the `OCIClusterAutoscaler` CR
and is subject to the same constraint.

This cannot be worked around with registry mirroring. `ImageDigestMirrorSet`
and `ImageTagMirrorSet` only rewrite *image references*; they have no effect on
arbitrary HTTPS requests. The Job fails at the first `oc apply -f https://...`
before any image pull is attempted.

## Root cause

Two live code paths contain the same installer script, and both are affected:

| Stack | File | Lines |
|---|---|---|
| `create-cluster` | `terraform-stacks/shared_modules/manifest/locals.tf` | 115, 122, 168 |
| `create-autoscaler-operator` | `terraform-stacks/shared_modules/manifest/autoscaling/main.tf` | 104, 111, 157 |

The three external dependencies:

```sh
oc apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"
curl -LfsS "https://github.com/kubernetes-sigs/cluster-api/releases/download/${CAPI_VERSION}/core-components.yaml" -o /tmp/capi-core-components.yaml
curl -LfsS "https://github.com/oracle/cluster-api-provider-oci/releases/download/${CAPOCI_VERSION}/infrastructure-components.yaml" -o /tmp/capoci-infrastructure-components.yaml
```

Version pins at the time of writing:

| Component | Variable | Default |
|---|---|---|
| cert-manager | `local.cert_manager_version` (`locals.tf:4`) | `v1.16.3` |
| Cluster API | `var.capi_version` | `v1.14.0` |
| CAPI Provider OCI | `var.capoci_version` | `v0.24.0` |

### Fourth dependency: public Helm repository

The generated `OCIClusterAutoscaler` custom resource points the operator at a
public Helm repository to install the cluster-autoscaler chart:

```yaml
clusterAutoscaler:
  repositoryURL: https://kubernetes.github.io/autoscaler
  name: oci-cluster-autoscaler
```

`terraform-stacks/shared_modules/manifest/locals.tf:82` and
`terraform-stacks/shared_modules/manifest/autoscaling/main.tf:71`.

This is a Helm repository index plus a chart tarball rather than a plain YAML
manifest, so it is a third class of artifact again, and the chart in turn
deploys a cluster-autoscaler image that also needs mirroring. Resolving only
the three `github.com` manifest fetches would therefore still leave the
autoscaler unable to install. There is no configuration surface to redirect
this URL today.

### Other hosts

Every other external reference in the install path is either a documentation
link in a variable description, or the OCI instance metadata service at
`169.254.169.254`, which is reachable in a disconnected VCN. One unrelated
item worth separating out: the optional webserver module fetches
`openshift-install` and `oc` from `mirror.openshift.com`
(`terraform-stacks/shared_modules/webserver/userdata/setup-webserver.sh.tpl:37,41`),
which is a distinct disconnected concern and not part of this report.

## Second, separate problem: component images are not documented for mirroring

Even once the manifests are available locally, the images they reference are
not listed anywhere in the project's disconnected documentation, so operators
have no way to know what to mirror. Extracted directly from the three manifests
at the pinned versions:

```
quay.io/jetstack/cert-manager-controller:v1.16.3
quay.io/jetstack/cert-manager-cainjector:v1.16.3
quay.io/jetstack/cert-manager-webhook:v1.16.3
registry.k8s.io/cluster-api/cluster-api-controller:v1.14.0
ghcr.io/oracle/cluster-api-oci-controller:v0.24.0
```

Repository paths are stable across releases; only the tag tracks the configured
version. Note there is no `cert-manager-startupapicheck` image — that component
is Helm-only and absent from the static `cert-manager.yaml`.

All five are referenced **by tag, not digest**. Mirroring them is therefore not
sufficient on its own: a disconnected cluster also needs an
`ImageTagMirrorSet` CR, because `imageDigestSources` in `install-config.yaml`
only redirects digest-based pulls. (Related: `imageTagSources` is not a valid
`install-config.yaml` field — the installer rejects it. Tag redirection has to
be delivered as an `ImageTagMirrorSet` manifest in the `openshift/` directory.)

## Why the obvious fix does not work

Serving the three manifests from ConfigMaps is not viable for two of them. The
ConfigMap / etcd object limit is 1 MiB:

| Manifest | Size | Fits in a ConfigMap? |
|---|---|---|
| `cert-manager.yaml` | 986,843 B (0.94 MiB) | Marginal |
| `core-components.yaml` | 1,174,593 B (1.12 MiB) | **No** |
| `infrastructure-components.yaml` | 1,157,483 B (1.10 MiB) | **No** |

Gzip + base64 into a ConfigMap would fit but adds decompression steps to the
installer script and remains close to the limit as upstream components grow.

## Suggested remediation

Listed roughly in order of robustness. Note that the manifest fetches and the
Helm repository are separate problems — a complete fix has to address both.

1. **Bake the manifests into the operator image.** The Job already runs
   `ghcr.io/oracle-samples/openshift-oracle-capi-autoscaling`, which operators
   must mirror anyway. Shipping the three YAMLs inside that image and applying
   them from local disk removes the `github.com` dependency with no new
   configuration surface and no size limit. Version pinning becomes a property
   of the image tag, which is arguably more correct than the current runtime
   variables. This does **not** address the Helm repository — see item 4.

2. **Make the source location configurable.** Add something like
   `component_manifest_base_url`, defaulting to the current GitHub release URLs,
   so disconnected operators can point at an internal web server or an OCI
   Object Storage PAR. Smallest change, preserves current behaviour by default,
   but leaves operators responsible for staging the files.

3. **Publish the component manifests as OCI artifacts** in the same registry
   namespace as the operator image, so a single `oc-mirror` pass covers both
   images and manifests.

4. **Make `repositoryURL` configurable, or vendor the chart.** The
   `OCIClusterAutoscaler` CR currently hardcodes
   `https://kubernetes.github.io/autoscaler`. Either expose it as a terraform
   variable so operators can point at an internal chart repository, or ship
   the cluster-autoscaler chart with the operator so no Helm repository is
   contacted at all.

Independently of which options are chosen, the project's disconnected-install
documentation should list the five images above plus the cluster-autoscaler
image pulled in by the Helm chart, with a note that these are tag-referenced
and therefore require an `ImageTagMirrorSet` rather than `imageDigestSources`.

## Interim workaround for consumers

Until this is fixed, disconnected deployments must leave the autoscaler
disabled. Patching the installer script to read the three manifests from an
internal source is not sufficient on its own, because the Helm repository
reference in the `OCIClusterAutoscaler` CR has no override. Either way this is
a fork-and-maintain burden that this report is intended to remove.

## Reproduction

1. Deploy to a disconnected OCI tenancy (observed in OC6; applies to any
   air-gapped realm) with `is_disconnected_installation = true`.
2. Set `use_autoscaling_operator = true`.
3. Complete the install and inspect the provider-installer Job in namespace
   `oci-openshift-autoscaling-operator`.
4. The Job fails at the first `oc apply`, unable to resolve or reach
   `github.com`, and retries until `backoffLimit` is exhausted.
