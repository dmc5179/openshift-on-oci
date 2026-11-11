# Draft docs bug: OCI firewall allowlist table lists "port" instead of 443 and an obsolete registry

**Status:** draft for Dan to file (2026-11-10). Suggested project: OSDOCS. Related docs
epic: OSDOCS-23407 (OCPSTRAT-3871). Sibling drafts:
[condensed-manifest](osdocs-oci-condensed-manifest-removed.md),
[disconnected vs. proxy](osdocs-oci-disconnected-requires-egress.md).

---

## Summary

In *Installing on Oracle Distributed Cloud*, the last table of section 2.6 has the literal
word "port" in the Port column for three registries, where it should say 443. It also still
lists `k8s.gcr.io`, a registry the same table describes as replaced, and which the Oracle
manifests do not use.

## Where

- OpenShift Container Platform 4.22, *Installing on Oracle Distributed Cloud*, section 2.6
  "Configuring your firewall for OpenShift Container Platform", the table introduced by "Set
  your firewall's allowlist to include the following external URLs":
  https://access.redhat.com/documentation/en-us/openshift_container_platform/4.22/html-single/installing_on_oracle_distributed_cloud/index#configuring-firewall-module_installing-oci-agent-based-installer
- The same table, with the same errors, is in 4.21.

## What is wrong

Current rows:

| URL | Port | Function (abridged) |
|---|---|---|
| `k8s.gcr.io` | port | A Kubernetes registry ... hosted on a custom Google Container Registry (GCR) domain. |
| `ghcr.io` | port | A GitHub image registry ... Requires an access token to publish, install, and delete private, internal, and public packages. |
| `storage.googleapis.com` | 443 | A source of release image signatures ... |
| `registry.k8s.io` | port | Replaces the `k8s.gcr.io` image registry ... |

1. **The Port column says "port" for `k8s.gcr.io`, `ghcr.io` and `registry.k8s.io`.** It
   looks like an unfilled placeholder. All three are HTTPS registries on 443, as every other
   row in section 2.6 says. Oracle's own allowlist for the same registries gives 443
   ("Firewall Configuration" in
   https://docs.oracle.com/en-us/iaas/Content/openshift-on-oci/agent-prereq.htm).
2. **`k8s.gcr.io` is obsolete and not used.** The table's own `registry.k8s.io` row says it
   replaces `k8s.gcr.io`. The Kubernetes project froze `k8s.gcr.io` in 2023. The Oracle
   manifests the guide installs (`oracle-quickstart/oci-openshift`, v1.6.2,
   `custom_manifests/manifests/`) pull their Kubernetes images, the CSI sidecars, from
   `registry.k8s.io` and do not reference `k8s.gcr.io`. Oracle's allowlist lists only
   `ghcr.io` and `registry.k8s.io`.

## Suggested fix

- Set the Port column to 443 for `ghcr.io` and `registry.k8s.io`.
- Remove the `k8s.gcr.io` row, and drop "Replaces the `k8s.gcr.io` image registry ..." from the
  `registry.k8s.io` description.
- Optional, while editing the table: say what each registry is for on OCI, as Oracle's table
  does. `ghcr.io` hosts the Oracle Cloud Controller Manager and CSI driver images, and
  `registry.k8s.io` hosts the Kubernetes CSI sidecar images. The current `ghcr.io` text about
  needing an access token to publish or delete packages doesn't matter here, because the
  cluster only pulls public images.

## Verification

- Section 2.6 of the 4.21 and 4.22 html-single guides, checked 2026-11-10.
- `grep -rhoE '(k8s\.gcr\.io|registry\.k8s\.io|ghcr\.io)/[^"[:space:]]+' custom_manifests/manifests/`
  on `oracle-quickstart/oci-openshift` v1.6.2 finds no `k8s.gcr.io` references.
