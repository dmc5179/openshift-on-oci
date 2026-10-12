# Autoscaler in disconnected environments — clarifying questions for Oracle

Follow-up to Oracle's response (`oracle-issue-autoscaler-disconnected-oracle-response.txt`),
which proposes `provider_artifacts_base_url`, `cluster_autoscaler_repository_url` and
`provider_installer_image` as module inputs, with the three provider manifests and the Helm
chart/index pre-staged on an internal webserver.

Status: **drafted, not yet sent.**

---

Thanks — this is exactly what we needed, particularly making `repositoryURL` configurable.
That was the one dependency we had found no override for, and it was the reason we had written
off the autoscaler as unusable in an enclave.

Four things before we act on it.

## 1. Who implements this?

Is this landing in `oracle-quickstart/oci-openshift` upstream, or is it a pattern you would
like us to implement and contribute? We are happy to do the work, but we do not want to
duplicate yours or raise a conflicting PR. If it is ours, we would submit it as a separate PR
rather than folding it into #88.

## 2. `provider_installer_image` default

Your snippet defaults to `quay.io/openshift/origin-cli:4.20`. We recently moved every
origin-cli reference in our fork to `4.22` to match the OCP 4.22 release being mirrored —
mirroring 4.22 while the manifests still requested 4.20 produced a pull failure in a
disconnected cluster, because the tag was simply absent from the mirror.

Should this default track the cluster version rather than being pinned to a specific tag?

## 3. Image redirection — rewrite the manifests, or use mirror sets?

You mention rewriting the manifests and chart to use private registry digest references.

We already generate an `ImageTagMirrorSet` covering the OCI CCM and CSI images. Extending it
to cover cert-manager, `cluster-api-controller` and `cluster-api-oci-controller` would redirect
those pulls without editing the YAML at all, which avoids re-applying edits on every component
bump.

Is there a reason you rewrite instead — digest pinning for provenance, or something an ITMS
cannot cover — or would an ITMS-based approach be acceptable upstream?

## 4. Chart and image versions

Your example serves `cluster-autoscaler-9.40.0.tgz`. Is that chart version pinned anywhere in
the stack, or selected by the operator at install time?

We need to know which chart version to stage and which `cluster-autoscaler` image it renders,
so we can add it to our `oc-mirror` imageset. More generally: a definitive list of every image
pulled by the four artifacts at the pinned component versions would save us reverse-engineering
it. For reference, we extracted the following from the three manifests ourselves:

```
quay.io/jetstack/cert-manager-controller:v1.16.3
quay.io/jetstack/cert-manager-cainjector:v1.16.3
quay.io/jetstack/cert-manager-webhook:v1.16.3
registry.k8s.io/cluster-api/cluster-api-controller:v1.14.0
ghcr.io/oracle/cluster-api-oci-controller:v0.24.0
```

That list does not include whatever the Helm chart renders, which is the gap in question 4.

---

For context, we wrote up the disconnected gap as we originally found it — happy to share if it
is useful for tracking.

## Notes for us (not for Oracle)

- Question 1 gates everything else. Worth sending alone if the rest is trimmed.
- `capi_version` currently differs between our branches: `oc3-support` is on `v1.14.0`
  (matching upstream and Oracle's example filename `cluster-api-v1.14.0.yaml`), `disconnected`
  is still on `v1.12.3`. Whatever we stage on the webserver must match the variable or the
  fetch 404s. Reconcile before implementing.
- Implementation, if it falls to us, should land on `disconnected` first where it can be
  tested against a real enclave — not on `oc3-support`, which is PR #88 and already awaiting
  review.
