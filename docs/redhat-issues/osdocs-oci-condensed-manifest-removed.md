# Draft docs bug: Agent-based OCI install points to condensed-manifest.yml, which no longer exists

**Status:** draft for Dan to file (2026-11-10). Suggested project: OSDOCS. Related docs
epic: OSDOCS-23407 (OCPSTRAT-3871). Sibling drafts:
[firewall table](osdocs-oci-firewall-table-errors.md),
[disconnected vs. proxy](osdocs-oci-disconnected-requires-egress.md).

---

## Summary

The Agent-based Installer procedure for Oracle Distributed Cloud tells users who did not use
the Oracle stack to copy `condensed-manifest.yml` from Oracle's GitHub repository. That file
was removed from the repository in Oracle's v1.4.1 release and is not published as a release
asset, so the step cannot be followed as written.

## Where

- OpenShift Container Platform 4.22, *Installing on Oracle Distributed Cloud*, section 2.5
  "Creating configuration files for installing a cluster on Oracle Distributed Cloud":
  https://access.redhat.com/documentation/en-us/openshift_container_platform/4.22/html-single/installing_on_oracle_distributed_cloud/index#creating-config-files-cluster-install-oci_installing-oci-agent-based-installer
- The same text is in 4.21, section 2.5.

The step, under "If you did not use a stack to provision OCI infrastructure resources":

> Go to Configuration Files (Oracle documentation) and follow the link to the custom manifests
> directory on GitHub. Copy the contents of the `condensed-manifest.yml` file and save it
> locally to a file in the `openshift` directory. In the `condensed-manifest.yml` file, update
> the sections marked with TODO ...

## What is wrong

- `custom_manifests/condensed-manifest.yml` was deleted from
  `oracle-quickstart/oci-openshift` in commit `1b1e986` ("Release v1.4.1 (#76)"). It is not in
  the repository on `main` (v1.6.2).
- It is not a release asset. The v1.6.2 release assets are the stack zips
  (`create-cluster.zip`, `add-nodes.zip`, `create-autoscaler-operator.zip`,
  `create-instance-role-tags.zip`, `create-resource-attribution-tags.zip`, each also with a
  versioned name) and `iscsi.sh`.
- The file is now produced only by the repository's `Makefile`
  (`cat ./custom_manifests/manifests/* > custom_manifests/condensed-manifest.yml`), which a
  user following the docs would not know to run.

## Secondary issues if a user regenerates the file

Worth considering while fixing the step:

- The concatenation includes every file in `custom_manifests/manifests/`, so it also installs
  the Oracle Cloud Agent (`06-oci-oca.yml`) and the autoscaling operator (`08-`, `09-`,
  `10-autoscaling-operator*.yml`), which are optional.
- `10-autoscaling-operator-configs.yml` contains unexpanded placeholders such as
  `$CAPI_VERSION`, `$CAPOCI_VERSION` and `$IMAGE_ID`, which would be created as literal values.
- The TODO list in the docs (compartment, VCN, load balancer subnet and security list OCIDs)
  matches `01-oci-driver-configs.yml`; the other files need no edits.

## Suggested fix

Either:

1. Point users to the individual manifests in `custom_manifests/manifests/` and name the
   required ones (`01-oci-ccm.yml`, `01-oci-csi.yml`, `01-oci-driver-configs.yml` with its
   TODOs filled in, `02-machineconfig-ccm.yml`, `02-machineconfig-csi.yml`,
   `03-machineconfig-consistent-device-path.yml`, `04-cluster-network.yml`,
   `05-oci-eval-user-data.yml`), with OCA and the autoscaler called out as optional; or
2. Ask Oracle to publish `condensed-manifest.yml` again as a release asset, and link to the
   asset rather than the repository directory.

For the stack path, the existing instruction (save the stack's `dynamic_custom_manifest`
output as `manifest.yaml` in `openshift/`) is correct: verified 2026-11-10 with the 4.22.18
installer, which split the single file into 28 separate manifests in the agent ISO. Users
copying the output from the Terraform CLI must use `terraform output -raw`; without `-raw` the
file is wrapped in heredoc markers and the installer fails with `could not decode YAML ...
Error reading multiple YAMLs`. A one-line note to that effect would prevent a misleading
failure.

## Verification

- `git log --all -- custom_manifests/condensed-manifest.yml` in `oracle-quickstart/oci-openshift`
  shows the file last present in v1.4.1 and deleted by `1b1e986`.
- `gh release view v1.6.2 --repo oracle-quickstart/oci-openshift` lists the assets above.
