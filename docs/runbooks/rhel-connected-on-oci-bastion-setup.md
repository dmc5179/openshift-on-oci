# RHEL 9 Bastion Setup on OCI — Terraform, OCI CLI, and Oracle Providers

**Date:** 2026-08-06
**Scope:** Setting up an internet-connected RHEL 9 bastion VM on OCI with Terraform, the OCI CLI, and the Oracle Terraform providers/stacks needed to deploy OpenShift on OCI

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Subscribe and Register RHEL](#2-subscribe-and-register-rhel)
3. [Install the OCI CLI](#3-install-the-oci-cli)
4. [Configure OCI CLI Authentication](#4-configure-oci-cli-authentication)
5. [Install Terraform](#5-install-terraform)
6. [Install Oracle Terraform Providers](#6-install-oracle-terraform-providers)
7. [Download the OCI OpenShift Terraform Stacks](#7-download-the-oci-openshift-terraform-stacks)
8. [Verify the Setup](#8-verify-the-setup)
9. [Next Steps](#9-next-steps)

---

## 1. Prerequisites

- A RHEL 9 VM running on OCI with internet access (see [OCI Marketplace RHEL images](https://docs.oracle.com/en-us/iaas/Content/Compute/References/images.htm) or the [KVM guest image import process](./openshift-on-oci-disconnected-prep.md))
- SSH access to the VM (default user `opc` for Marketplace images, `cloud-user` for imported KVM guest images)
- An OCI tenancy with a compartment for your OpenShift cluster
- An OCI user with API key authentication or instance principal access

---

## 2. Subscribe and Register RHEL

If you launched from the OCI Marketplace RHEL image (BYOS), register and attach your Red Hat subscription:

```bash
sudo subscription-manager register --username <rhn_username> --password <rhn_password>
sudo subscription-manager attach --auto
```

Enable the base and AppStream repos:

```bash
sudo subscription-manager repos \
  --enable=rhel-9-for-x86_64-baseos-rpms \
  --enable=rhel-9-for-x86_64-appstream-rpms
```

Install common utilities:

```bash
sudo dnf install -y unzip wget git jq bind-utils tar
```

---

## 3. Install the OCI CLI

Oracle provides an installer script for the OCI CLI. It installs into your home directory and does not require root:

```bash
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)" -- \
  --accept-all-defaults
```

Reload your shell profile so the `oci` command is on your `PATH`:

```bash
source ~/.bashrc
```

Verify the installation:

```bash
oci --version
```

---

## 4. Configure OCI CLI Authentication

### Option A: API Key Authentication

Run the guided setup:

```bash
oci setup config
```

This prompts for your tenancy OCID, user OCID, region, and generates an API signing key pair at `~/.oci/`. Upload the **public** key to your OCI user profile:

**OCI Console → Identity & Security → Users → your user → API Keys → Add API Key → Paste Public Key**

Verify connectivity:

```bash
oci iam region list --output table
```

### Option B: Instance Principal Authentication

If the bastion VM's dynamic group has the necessary IAM policies, you can skip API key setup and use instance principals. Set the auth mode in your OCI CLI config or export the environment variable:

```bash
export OCI_CLI_AUTH=instance_principal
```

Verify:

```bash
oci iam region list --auth instance_principal --output table
```

Instance principal auth is also used by Terraform — see the `auth` variable in the OCI provider block.

---

## 5. Install Terraform

### Option A: Install from HashiCorp RPM Repository (recommended)

Add the HashiCorp repo and install via `dnf`:

```bash
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
sudo dnf install -y terraform
```

### Option B: Install from Binary Download

Download a specific version (the OCI OpenShift stacks require >= 1.0; the offline script defaults to 1.9.8):

```bash
TERRAFORM_VERSION="1.9.8"

wget "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
unzip "terraform_${TERRAFORM_VERSION}_linux_amd64.zip" -d /tmp
sudo install -m 0755 /tmp/terraform /usr/local/bin/terraform
rm -f "terraform_${TERRAFORM_VERSION}_linux_amd64.zip" /tmp/terraform
```

Verify:

```bash
terraform version
```

---

## 6. Install Oracle Terraform Providers

On an internet-connected system, `terraform init` downloads providers automatically from `registry.terraform.io`. The OCI OpenShift stacks declare these providers:

| Provider | Registry Source | Version Constraint |
|----------|----------------|-------------------|
| `oracle/oci` | `registry.terraform.io/oracle/oci` | `>= 6.12.0` |
| `hashicorp/time` | `registry.terraform.io/hashicorp/time` | `>= 0.12.1` |
| `hashicorp/external` | `registry.terraform.io/hashicorp/external` | `~> 2.3` |

### Automatic Installation (connected)

When connected to the internet, simply running `terraform init` inside a stack directory downloads and caches all required providers. No manual provider installation is needed. Skip to [Section 7](#7-download-the-oci-openshift-terraform-stacks).

### Manual Pre-download (optional — useful if preparing for later disconnected use)

If you want to create a local provider mirror for later transfer to an air-gapped environment, use the included `oci-terraform-offline.sh` script from this repo:

```bash
./oci-terraform-offline.sh --output-dir ./oci-terraform-offline
```

Or manually download and set up a filesystem mirror:

```bash
OCI_PROVIDER_VERSION="6.30.0"
TIME_PROVIDER_VERSION="0.12.1"
EXTERNAL_PROVIDER_VERSION="2.3.4"

mkdir -p ~/.terraform.d/plugins/registry.terraform.io/oracle/oci/${OCI_PROVIDER_VERSION}/linux_amd64
mkdir -p ~/.terraform.d/plugins/registry.terraform.io/hashicorp/time/${TIME_PROVIDER_VERSION}/linux_amd64
mkdir -p ~/.terraform.d/plugins/registry.terraform.io/hashicorp/external/${EXTERNAL_PROVIDER_VERSION}/linux_amd64

# Download OCI provider
wget "https://releases.hashicorp.com/terraform-provider-oci/${OCI_PROVIDER_VERSION}/terraform-provider-oci_${OCI_PROVIDER_VERSION}_linux_amd64.zip" \
  -O /tmp/oci-provider.zip
unzip /tmp/oci-provider.zip -d ~/.terraform.d/plugins/registry.terraform.io/oracle/oci/${OCI_PROVIDER_VERSION}/linux_amd64/

# Download time provider
wget "https://releases.hashicorp.com/terraform-provider-time/${TIME_PROVIDER_VERSION}/terraform-provider-time_${TIME_PROVIDER_VERSION}_linux_amd64.zip" \
  -O /tmp/time-provider.zip
unzip /tmp/time-provider.zip -d ~/.terraform.d/plugins/registry.terraform.io/hashicorp/time/${TIME_PROVIDER_VERSION}/linux_amd64/

# Download external provider
wget "https://releases.hashicorp.com/terraform-provider-external/${EXTERNAL_PROVIDER_VERSION}/terraform-provider-external_${EXTERNAL_PROVIDER_VERSION}_linux_amd64.zip" \
  -O /tmp/external-provider.zip
unzip /tmp/external-provider.zip -d ~/.terraform.d/plugins/registry.terraform.io/hashicorp/external/${EXTERNAL_PROVIDER_VERSION}/linux_amd64/

rm -f /tmp/oci-provider.zip /tmp/time-provider.zip /tmp/external-provider.zip
```

To use the filesystem mirror, create `~/.terraformrc`:

```hcl
provider_installation {
  filesystem_mirror {
    path    = "/home/<user>/.terraform.d/plugins"
    include = ["registry.terraform.io/*/*"]
  }
  direct {
    exclude = ["registry.terraform.io/*/*"]
  }
}
```

---

## 7. Download the OCI OpenShift Terraform Stacks

Clone the `oracle-quickstart/oci-openshift` repository, which contains the Terraform stacks and custom manifests for CCM/CSI:

```bash
git clone https://github.com/oracle-quickstart/oci-openshift.git
cd oci-openshift
```

!!!!!!!!!!!!!!!!!!!!!!Or download specific stack zip files from the [releases page](https://github.com/oracle-quickstart/oci-openshift/releases):

```bash
OCI_OPENSHIFT_RELEASE="v1.6.0"  # check for the latest release

wget "https://github.com/oracle-quickstart/oci-openshift/releases/download/${OCI_OPENSHIFT_RELEASE}/create-resource-attribution-tags.zip"
wget "https://github.com/oracle-quickstart/oci-openshift/releases/download/${OCI_OPENSHIFT_RELEASE}/create-instance-role-tags.zip"
wget "https://github.com/oracle-quickstart/oci-openshift/releases/download/${OCI_OPENSHIFT_RELEASE}/create-cluster.zip"
wget "https://github.com/oracle-quickstart/oci-openshift/releases/download/${OCI_OPENSHIFT_RELEASE}/add-nodes.zip"
```

### Central location for terraform modules and providers

- bashrc
export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"
 mkdir -p "$HOME/.terraform.d/plugin-cache"

### Run the prerequisite tag stacks

The resource attribution tags **must** be created before deploying the cluster:

```bash
unzip create-resource-attribution-tags.zip -d create-resource-attribution-tags
cd create-resource-attribution-tags

terraform init
terraform apply -var="tenancy_ocid=<your_tenancy_ocid>" \
                -var="compartment_ocid=<your_compartment_ocid>" \
                -var="region=<your_region>"
cd ..
```

Then create the instance role tags:

```bash
unzip create-instance-role-tags.zip -d create-instance-role-tags
cd create-instance-role-tags

terraform init
terraform apply -var="tenancy_ocid=<your_tenancy_ocid>" \
                -var="compartment_ocid=<your_compartment_ocid>" \
                -var="region=<your_region>" \
                -var="cluster_name=<your_cluster_name>"
cd ..
```

---

## 8. Verify the Setup

Run these checks to confirm everything is in place:

```bash
# OCI CLI
oci --version
oci iam region list --output table

# Terraform
terraform version

# Terraform providers (from inside any stack directory)
cd create-resource-attribution-tags
terraform providers
cd ..

# Git repo
ls oci-openshift/
```

Expected output: OCI CLI returns your tenancy's regions, Terraform reports version >= 1.0, and the provider list includes `oracle/oci`, `hashicorp/time`, and `hashicorp/external`.

---

## 9. Next Steps

With the bastion set up, you can proceed with:

1. **Generate the agent ISO** — Use `openshift-install agent create image` (see [disconnected prep](./openshift-on-oci-disconnected-prep.md) Section 4)
2. **Upload the ISO to OCI Object Storage** and create a Pre-Authenticated Request (PAR)
3. **Configure `terraform.tfvars`** — Copy the template and fill in your values (see [Terraform variables reference](./ocp-on-oci-terraform-quickstart.md))
4. **Run the `create-cluster` stack** — `terraform init && terraform plan && terraform apply`

---

## Sources

- [HashiCorp Terraform Downloads](https://releases.hashicorp.com/terraform/)
- [OCI CLI Installation Guide (Oracle)](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm)
- [oracle-quickstart/oci-openshift (GitHub)](https://github.com/oracle-quickstart/oci-openshift)
- [OCI Terraform Provider Documentation](https://registry.terraform.io/providers/oracle/oci/latest/docs)
- [OpenShift on OCI — Disconnected Prep](./openshift-on-oci-disconnected-prep.md)
- [OpenShift on OCI — Terraform Variables Reference](./ocp-on-oci-terraform-quickstart.md)
