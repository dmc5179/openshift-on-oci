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

## Migrated to the fork

| Was here | Now in the fork |
|---|---|
| `oci-terraform-offline.sh`, `oci-github-offline.sh` | `scripts/build-offline-bundle.sh`, `scripts/install-offline-bundle.sh`, tested by `scripts/test-offline-terraform-init.sh`. See `docs/terraform-offline-init.md`. |
| `imageset-config.yaml` | Merged into `docs/imageset-config.yaml` |
| `docs/runbooks/openshift-on-oci-disconnected-prep.md` | Rewritten as `docs/disconnected-prerequisites.md` |
| `docs/runbooks/rhel-connected-on-oci-bastion-setup.md`, `rhel-on-oci-cloud-init.yaml` | `docs/bastion-setup.md` |
| `docs/runbooks/ocp-on-oci-terraform-quickstart.md` | Not carried over. Its variable table had drifted badly; `openshift-on-oci.tfvars.template`, `variables.tf` and `schema.yaml` describe every variable. |
| `terraform.tfvars.template` | Not carried over. An older copy of `openshift-on-oci.tfvars.template`. |
