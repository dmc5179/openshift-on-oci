# Draft docs bug: OCI "disconnected" Agent-based install actually requires internet egress (firewall allowlist or proxy)

**Status:** filed 2026-11-10 as [OSDOCS-24411](https://redhat.atlassian.net/browse/OSDOCS-24411), linked "relates to" OSDOCS-23407
(OCPSTRAT-3871). Sibling drafts:
[condensed-manifest](osdocs-oci-condensed-manifest-removed.md),
[firewall table](osdocs-oci-firewall-table-errors.md).

---

## Summary

*Installing on Oracle Distributed Cloud* describes a disconnected Agent-based installation.
But both the guide and the Oracle documentation it links to require outbound access from the
cluster to public registries, through a firewall allowlist or a proxy. So what the guide calls
disconnected is really a restricted-network install. A user in an environment with no internet
egress cannot complete it from the documentation. Oracle's own overview says fully air-gapped
installs need "additional manual setup and configuration", which neither Red Hat nor Oracle
documents.

This matters most for the regions the guide lists as Technology Preview: US Government Cloud
and Isolated Region. Those are the environments where an air-gapped install is the norm.

## Where

OpenShift Container Platform 4.22, *Installing on Oracle Distributed Cloud*, chapter 2 (same
text in 4.21):

- Section 2.2, Figure 2.2, "Workflow for using the Agent-based installer in a disconnected
  environment".
- Section 2.4 "Creating OCI infrastructure resources and services":
  https://access.redhat.com/documentation/en-us/openshift_container_platform/4.22/html-single/installing_on_oracle_distributed_cloud/index#abi-oci-resources-services_installing-oci-agent-based-installer
- Section 2.6 "Configuring your firewall for OpenShift Container Platform":
  https://access.redhat.com/documentation/en-us/openshift_container_platform/4.22/html-single/installing_on_oracle_distributed_cloud/index#configuring-firewall-module_installing-oci-agent-based-installer

## What is wrong

1. **Section 2.6 contradicts itself.** It says: *"For a disconnected environment, you must
   mirror content from both Red Hat and Oracle. This environment requires that you create
   firewall rules to expose your firewall to specific ports and registries."* It then lists
   public endpoints that must be allowlisted, including `registry.redhat.io`, `quay.io`,
   `api.openshift.com`, `ghcr.io` and `registry.k8s.io`. If all content is mirrored, the
   cluster should not need rules to reach public registries. If it does need them, the
   environment isn't disconnected. The section doesn't say which it means. It also doesn't say
   which Oracle content to mirror.

2. **The disconnected link in section 2.4 goes to Oracle's manual provisioning page, which
   needs internet access.** The link text is "Provisioning OCI Resources for the Agent-based
   Installer in Disconnected Environments (Oracle documentation)". Its target,
   https://docs.oracle.com/iaas/Content/openshift-on-oci/agent-prereq.htm, is now titled "OCI
   Resources for the Agent-based Installer for Manual Installation". It contains nothing
   specific to disconnected environments. Its "Firewall Configuration" section tells the user to
   allowlist `ghcr.io` (443, the Oracle CCM and CSI images) and `registry.k8s.io` (443, the
   Kubernetes images for CCM and CSI).

3. **Oracle says a full air gap needs steps that nobody documents.** Oracle's Agent-based
   Installer overview (https://docs.oracle.com/en-us/iaas/Content/openshift-on-oci/agent-installer.htm)
   says: *"For fully disconnected (air-gapped) environments, those requiring firewall changes,
   mirror servers, and internal content or container image repositories, additional manual
   setup and configuration is required."* Neither Oracle's documentation nor Red Hat's
   describes those steps.

4. **Oracle's Terraform option does not cover image content.** Oracle's stack has an "Is
   Disconnected Agent-based Installation" option
   (https://docs.oracle.com/en-us/iaas/Content/openshift-on-oci/agent-installer-using-stack.htm).
   It only creates a web server to host the rootfs image. It does nothing about the Oracle
   container images, and the same page offers HTTP and HTTPS proxy settings "if hosts are behind
   a firewall that requires the use of a proxy".

## What a truly disconnected install needs that the guide does not say

Found while installing in a disconnected OC3 environment with OpenShift 4.22:

- **Which Oracle images to mirror.** The Oracle manifests (`oracle-quickstart/oci-openshift`
  v1.6.2) pull the CCM and CSI driver from `ghcr.io/oracle/cloud-provider-oci`, and the CSI
  sidecars (`csi-attacher`, `csi-provisioner`, `csi-resizer`, `csi-snapshotter`,
  `csi-node-driver-registrar`, `snapshot-controller`) from `registry.k8s.io/sig-storage`. The
  optional autoscaler image comes from `ghcr.io/oracle-samples`.
- **An `ImageTagMirrorSet`.** Those manifests reference images by tag, not digest. The
  `imageDigestSources` that the guide's mirror-registry flow configures applies only to
  pulls by digest. Without an ITMS, the CCM and CSI pods still try the public registries. The
  CCM then never starts, nodes keep the `node.cloudprovider.kubernetes.io/uninitialized` taint,
  and the install does not converge. (`oc-mirror` v2 generates an ITMS for tag-referenced
  images, but the guide does not mention it.)
- **The cluster autoscaler is not air-gap capable.** In testing, the autoscaling operator
  fetched Cluster API release artifacts from github.com at runtime.

## Suggested fix

Make the guide pick one meaning of "disconnected" for OCI:

1. **Restricted network.** State plainly that the cluster needs outbound access to the
   endpoints in section 2.6, directly or through a cluster-wide proxy, and link to the
   `proxy` settings in `install-config.yaml`. Present mirroring as covering the OpenShift
   release only, and stop implying that no egress is needed. Or:
2. **Fully disconnected.** State that the section 2.6 allowlist does not apply. List the
   Oracle images to mirror, say an `ImageTagMirrorSet` is required for them, and mark the
   cluster autoscaler as not supported without egress.

Whichever is chosen, fix the section 2.4 link. Either retitle it to match the Oracle page it
targets ("OCI Resources for the Agent-based Installer for Manual Installation"), or point it to
an Oracle page that actually covers disconnected provisioning, if Oracle publishes one.

Until then, the Technology Preview entries for US Government Cloud and Isolated Region could
carry a note that installs there currently need egress to the listed endpoints.

OCPSTRAT-3871 / OSDOCS-23407 will add full disconnected content for the OC3 and OC6 regions.
This bug is about the text published now, which applies to every region.

## Verification

- Section 2.4 and 2.6 text and the link target checked in the 4.21 and 4.22 html-single guides
  on 2026-11-10.
- The three Oracle pages above were fetched on 2026-11-10.
- Image references: `git grep` for registry hostnames over `custom_manifests/manifests/` at
  `oracle-quickstart/oci-openshift` v1.6.2 (`8bed062`).
