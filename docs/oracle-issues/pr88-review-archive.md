# PR #88 review archive

**Add support for OCI Gov Cloud (OC3) and disconnected installations**

- URL: https://github.com/oracle-quickstart/oci-openshift/pull/88
- Opened: 2026-10-02 by dmc5179
- Head: 40c6221 (`oc3-support`) → base `main`
- Size: 28 commits, 33 files, +1664/-508

Captured 2026-10-14 before closing the PR. Preserved here because the
review feedback outlived the PR and several items are still open.

## Review threads

### custom_manifests/oci-ccm-csi-drivers/v1.34.0/01-oci-ccm.yml:241

**yutpeng** (2026-10-05):

We'll have to keep ghcr.io/nikhisin3001/cloud-provider-oci:v1.34.0 until ccm team release the one that contains the fix 

---

**dmc5179** (2026-10-12):

Thanks — and this is honestly outside my ability to decide.

Which image is correct here is a call for Oracle and Red Hat engineering to make together. I changed it to `ghcr.io/oracle/cloud-provider-oci:v1.34.0` on the assumption that the official build was the right target; if the fix you mention isn't in an official release yet, then `ghcr.io/nikhisin3001/cloud-provider-oci:v1.34.0` may genuinely be required and I'd defer to you. Please feel free to modify the PR directly if so.

Two bits of context that may be useful to that decision rather than arguments against it. We'd already mirrored and deployed the official image in a disconnected environment, so if it's missing something load-bearing we'd want to know what, to assess whether we're exposed. And in a government tenancy, images from a personal namespace are harder to carry — they have to be mirrored by name and justified in review — so if the fork is needed for now, knowing what the fix addresses and whether there's a tracking issue would help us document it.

---

### terraform-stacks/shared_modules/manifest/locals.tf:360

**yutpeng** (2026-10-05):

I think indent() does not indent the first line, so the certificate header is emitted at column 0 and produces invalid YAML.

---

**dmc5179** (2026-10-08):

Good catch — confirmed and fixed in f26a276.

You're right that `indent()` skips the first line, so the certificate header landed at column 0. Being less indented than the key, it terminated the block scalar and made `install-config.yaml` unparseable for any disconnected install supplying a private registry CA.

The fix indents the first line explicitly and trims surrounding whitespace so the block can't open with a blank line:

```hcl
"additionalTrustBundle: |\n  ${indent(2, trimspace(var.additional_trust_bundle))}"
```

Verified by rendering the old and new forms against a YAML parser — the old one raises a scanner error, the new one parses with the certificate round-tripping intact.

---

### terraform-stacks/shared_modules/boot_artifacts/outputs.tf:13

**yutpeng** (2026-10-05):

Do we need to add an explicit dependency on oci_objectstorage_object.iso?

---

**dmc5179** (2026-10-08):

Yes — needed, and added in 1b8aff2.

Neither PAR referenced the object it points at, only the bucket, so nothing in the graph ordered the upload ahead of consumers of the PAR URL. The compute image import could start against an ISO that was still uploading.

I put `depends_on` on the PAR resources rather than on the output, since a PAR shouldn't be minted before its object exists, and because the output reads the PAR's `access_uri` the ordering carries through to consumers transitively. Applied to the rootfs PAR as well — it had the same gap.

Pass 1 is unaffected: with `iso_file_path`/`rootfs_file_path` empty the object resources have `count = 0` and the dependency is a no-op.

---

### terraform-stacks/create-cluster/main.tf:83

**yutpeng** (2026-10-05):

Does disconnected flow support OCI Resource Manager? 
iso_file_path and rootfs_file_path refer to files local to Terraform. How are those artifacts delivered to the RM job?

---

**dmc5179** (2026-10-12):

Good catch, and it turned out to be a different problem than missing inputs — `openshift_image_source_uri` was already the right shape for Resource Manager, but `main.tf:83` discarded it whenever `is_disconnected_installation` was set, substituting a PAR minted by the `boot_artifacts` module. In an RM job `iso_file_path` is necessarily empty, so that PAR pointed at an object nobody had uploaded and the image import failed regardless of what the user supplied. The rootfs had no override at all.

Fixed in 4427d80. `openshift_image_source_uri` is now honoured when `iso_file_path` is unset, and `boot_artifacts_base_url` is added as the rootfs equivalent, surfaced in the Resource Manager schema since it is a URL rather than a local path.

Local file paths are deliberately *not* exposed in the schema — they would reference a filesystem the RM job cannot see. The bastion workflow is unchanged: set the file paths and Terraform still does the upload and PAR creation itself.

---

### openshift-on-oci.tfvars.template:230

**yutpeng** (2026-10-05):

The example enables instance creation while instructing users to leave artifact paths empty during pass 1. 
When to set create_openshift_instances to false/true?
Would be great to add some instructions, including mirror preparation, manifest generation, ISO creation, and upload/import verification steps

---

**dmc5179** (2026-10-12):

Agreed, the file contradicted itself — line 57 set `create_openshift_instances = true` with no mention of the two-pass flow, while a comment 170 lines later said to leave the artifact paths empty "during pass 1."

Rewritten in 4f3fe65. The header now spells out the sequence once: mirror prep, pass 1, manifest extraction, ISO build, pass 2, upload verification. It also answers the specific question you raised — the values in the file are the pass 2 values, and pass 1 overrides `create_openshift_instances` on the command line, so there is no editing between passes. The artifact paths are documented as staying commented out, since they do not exist until the ISO is built.

Related, and in the same spirit: 40c6221 hardens `scripts/generate-ocp-artifacts.sh`, which performs the manifest extraction in step 2 of that sequence. It previously relied on `set -e`, so one failed `terraform output` aborted the run partway and left a partial manifest set — and because a redirect creates its target before the command runs, the failing manifest was left as a zero-byte file. The ISO build then consumed whatever was present without complaint, and the problem surfaced much later as control plane nodes stuck NotReady with no CNI. It now validates each output before moving it into place, reports every missing manifest in one run, and refuses to exit zero on a partial set. We lost a cluster to this, so it seemed worth making loud.

---

### terraform-stacks/shared_modules/manifest/locals.tf:369

**yutpeng** (2026-10-05):

I think imageTagSources is not supported by the InstallConfig schema. 

---

**dmc5179** (2026-10-07):

@yutpeng correct, InstallConfig does not directly support imageTagSources which is why we have to have the terraform inject it into the openshift manifests directory before the command that generates the agent ISO. The manifest is picked up and used by the cluster. I can submit an RFE to the installer team to add support for imageTagSources in the install config directly but it is not a blocker

---

**dmc5179** (2026-10-08):

Confirmed — `imageTagSources` isn't in the InstallConfig schema and the installer rejects it. That's fixed as of 0f10990, which is in the current head (7bef4d9).

The terraform no longer writes that field into `install-config.yaml`. It now generates an `ImageTagMirrorSet` CR through a new `manifest_image_tag_mirror_set` output, written to `openshift/99-image-tag-mirror-set.yml` before `openshift-install agent create image` runs, so the agent installer picks it up as a day-0 manifest. It's gated on `private_registry`, so connected installs are unaffected.

One note for re-review: the invalid field was added in d1fedb5 and removed later in 0f10990, so reading commit-by-commit shows it appear and then go away — the final diff is clean.

I'll file a separate RFE with the installer team about supporting tag-based mirrors in `install-config.yaml` directly, but that isn't a blocker here.

---

## Issue comments

**oracle-contributor-agreement[bot]** (2026-10-02):

Thank you for your pull request and welcome to our community! To contribute, please sign the Oracle Contributor Agreement (OCA).
The following contributors of this PR have not signed the OCA:

- PR author: danielmclark@gmail.com (@dmc5179)
- danclark@redhat.com (@dmc5179)

To sign the OCA, please [create an Oracle account](https://profile.oracle.com/myprofile/account/create-account.jspx) and sign the OCA in [Oracle's Contributor Agreement Application](https://oca.opensource.oracle.com/).

When signing the OCA, please provide your GitHub username. After signing the OCA and getting an OCA approval from Oracle, this PR will be automatically updated.

*If you are an Oracle employee, please make sure that you are a member of the main [Oracle GitHub organization](https://github.com/oracle), and your [membership in this organization is public](https://docs.github.com/en/account-and-profile/setting-up-and-managing-your-personal-account-on-github/managing-your-membership-in-organizations/publicizing-or-hiding-organization-membership).*


---

**dmc5179** (2026-10-12):

A note on where this PR stands overall.

It has grown considerably since it was opened on 2 October — 28 commits, 33 files, +1664/-508. Much of that came from working through the review feedback, and some from fixes we found while actively deploying into OC3 and OC6.

Five of the six review threads are now answered with fixes pushed. The remaining one is the CCM image question, which needs an Oracle/Red Hat decision rather than a code change from me.

We're still testing in a disconnected government realm and expect to find more. Rather than keep growing this PR — every addition restarts review — it may be more practical to accept some or all of what's here, so we can rebase onto main and continue in smaller, more reviewable pieces. I'm happy to split it if that would help: the OC3/Gov Cloud realm support, the disconnected install path, and the operator tooling are reasonably separable.

Equally happy to keep iterating here if you'd prefer it land as one change.

---

