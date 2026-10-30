# openshift-on-oci

Working notes for deploying OpenShift on Oracle Cloud Infrastructure,
including disconnected installs and non-commercial realms (OC3, OC6).

## Which repo is for what

| Repo | Purpose |
|---|---|
| [dmc5179/oci-openshift](https://github.com/dmc5179/oci-openshift) | Fork of [oracle-quickstart/oci-openshift](https://github.com/oracle-quickstart/oci-openshift). **Everything you run or follow to deploy lives here**: terraform, scripts, deployment docs, example configs. Work flows from here upstream as focused PRs. Checked out locally as `oci-openshift-mine/`. |
| dmc5179/openshift-on-oci (this repo) | Material that is not meant to go upstream: correspondence and issue drafts for Oracle, analysis, diagnostics from specific clusters, and the inventory tracking what has been submitted upstream. |

The rule: **no deployment doc or script exists in both repos.** If something
here would help someone deploy, it moves to the fork and is deleted here.

## Contents

| Path | What it is |
|---|---|
| `docs/change-inventory.md` | Every change made in the fork, its category, and its upstream PR status |
| `docs/oracle-issues/` | Issue drafts, Oracle's responses, PR review archives |
| `docs/analysis/` | Investigations: new-region support, CCM enhancements, Gov Cloud OCA |
| `docs/diagnostics/` | Notes from debugging specific clusters |

## Still to migrate to the fork

| Path | Plan |
|---|---|
| `imageset-config.yaml` | Has 10 images the fork's `docs/imageset-config.yaml` lacks: the autoscaler runtime images (cert-manager x3, cluster-api, cluster-api-provider-oci, cluster-autoscaler), the deployer image, UBI, support-tools and must-gather. Fold them in, then delete. |
| `docs/runbooks/ocp-on-oci-terraform-quickstart.md` | Overlaps the fork's `docs/oc6-quickstart.md` and tfvars template. Merge, then delete. |
| `docs/runbooks/openshift-on-oci-disconnected-prep.md` | Overlaps the fork's `docs/disconnected-bastion-setup.md` and `docs/terraform-offline-init.md`. Merge, then delete. |
| `docs/runbooks/rhel-connected-on-oci-bastion-setup.md` | RHEL bastion setup. No equivalent in the fork yet. Move it. |
| `terraform.tfvars.template` | Every variable in it is already in the fork's `openshift-on-oci.tfvars.template`. Delete. |
| `rhel-on-oci-cloud-init.yaml` | Seven-line cloud-init for a RHEL bastion. Move with the bastion setup runbook. |

## Done

| Was here | Now in the fork |
|---|---|
| `oci-terraform-offline.sh`, `oci-github-offline.sh` | `scripts/build-offline-bundle.sh`, `scripts/install-offline-bundle.sh`, tested by `scripts/test-offline-terraform-init.sh`. See `docs/terraform-offline-init.md`. |
