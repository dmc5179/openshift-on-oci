# OpenShift 4.22 on Oracle Distributed Cloud — Disconnected Environment Preparation

**Date:** 2026-07-28
**Source:** Red Hat documentation "Installing on Oracle Distributed Cloud — installing-oci-agent-based-installer" (OCP 4.22)
**Scope:** Everything that must be brought into an air-gapped/disconnected enclave to deploy OpenShift 4.22 on OCI using the Agent-based Installer

---

## Table of Contents

1. [CLI Tools & Binaries](#1-cli-tools--binaries)
2. [Mirror Registry](#2-mirror-registry)
3. [OpenShift Release Images](#3-openshift-release-images)
4. [RHCOS / Agent ISO](#4-rhcos--agent-iso)
5. [Operator Catalog Images](#5-operator-catalog-images)
6. [Oracle CCM & CSI Container Images](#6-oracle-ccm--csi-container-images)
7. [Terraform & Infrastructure-as-Code Artifacts](#7-terraform--infrastructure-as-code-artifacts)
8. [Git Repositories](#8-git-repositories)
9. [Configuration Files & Custom Manifests](#9-configuration-files--custom-manifests)
10. [Certificates & Authentication](#10-certificates--authentication)
11. [OCI Infrastructure Prerequisites](#11-oci-infrastructure-prerequisites)
12. [Web Server for rootfs (Disconnected-Specific)](#12-web-server-for-rootfs-disconnected-specific)
13. [Example oc-mirror ImageSetConfiguration](#13-example-oc-mirror-imagesetconfiguration)
14. [Summary Checklist](#14-summary-checklist)

---

## 1. CLI Tools & Binaries

Download from [mirror.openshift.com/pub/openshift-v4/clients/ocp/](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/) on a connected system, then transfer into the enclave.

| Tool | Purpose | Download Source |
|------|---------|----------------|
| `openshift-install` | Agent-based installer binary — generates agent ISO, monitors install | `mirror.openshift.com/pub/openshift-v4/clients/ocp/<version>/` |
| `oc` | OpenShift CLI — `oc adm release info`, `oc adm release extract`, post-install ops | Same as above |
| `oc-mirror` (v2) | Mirrors all container images (release, operators, additional) into archive for transfer | Same as above |
| `terraform` (>= 1.0) | Provisions OCI infrastructure via Terraform stacks | [releases.hashicorp.com/terraform/](https://releases.hashicorp.com/terraform/) |

**Important:** Verify your `openshift-install` binary points to the mirror registry, not a shared registry:
```bash
./openshift-install version
# release image should reference your mirror, not registry.ci.openshift.org
```

---

## 2. Mirror Registry

A Docker v2-compatible container image registry must be running inside the enclave **before** mirroring images.

Options:
- **mirror-registry for Red Hat OpenShift** (simplest — single-binary install)
- **Red Hat Quay** (full-featured)
- Any registry supporting Docker v2 API (Harbor, Nexus, etc.)

Required:
- TLS certificate and CA bundle (all nodes must trust the registry CA)
- Registry credentials (username/password or token)
- Merged pull secret: combine your Red Hat pull secret (from console.redhat.com) with the enclave registry credentials

---

## 3. OpenShift Release Images

Mirror using `oc-mirror` v2 on a connected system, create an archive, then transport and publish into the enclave registry.

| Image Source | Description |
|--------------|-------------|
| `quay.io/openshift-release-dev/ocp-release` | OCP release metadata image for 4.22.x |
| `quay.io/openshift-release-dev/ocp-v4.0-art-dev` | All individual operator and component images referenced by the release |

These are configured in the `ImageSetConfiguration` (see [Section 13](#13-example-oc-mirror-imagesetconfiguration)).

`oc-mirror` also generates:
- `ImageDigestMirrorSet` (IDMS) CRs — telling the cluster to pull from the mirror
- `CatalogSource` CRs — for mirrored operator catalogs

---

## 4. RHCOS / Agent ISO

In a disconnected environment, the RHCOS base ISO is **embedded in the release payload**. The `openshift-install agent create image` command extracts it from the mirrored release images.

**Workflow:**
1. `openshift-install agent create image` generates a **minimal ISO** (< 150 MB) and a **rootfs** image
2. The rootfs image must be uploaded to a **web server accessible by OCI instances** (see [Section 12](#12-web-server-for-rootfs-disconnected-specific))
3. The minimal ISO is uploaded to OCI Object Storage
4. A custom compute image is created from the ISO (QCOW2 format, UEFI_64 enabled, BIOS disabled)

**No separate RHCOS download is needed** if the release images are properly mirrored — the installer pulls the RHCOS ISO from `imageContentSources` / `imageDigestMirrorSet` in `install-config.yaml`.

---

## 5. Operator Catalog Images

Mirror the operator catalogs you need. At minimum for OCI:

| Catalog | Image |
|---------|-------|
| Red Hat Operators | `registry.redhat.io/redhat/redhat-operator-index:v4.22` |
| Certified Operators (optional) | `registry.redhat.io/redhat/certified-operator-index:v4.22` |
| Community Operators (optional) | `registry.redhat.io/redhat/community-operator-index:v4.22` |

Include specific operators you plan to install (e.g., OpenShift Data Foundation, Logging, etc.) in the `ImageSetConfiguration`.

---

## 6. Oracle CCM & CSI Container Images

The Oracle Cloud Controller Manager and CSI driver are deployed as DaemonSets via custom manifests post-install. These images must be mirrored into the enclave registry.

Per the OCI firewall requirements doc and the `oracle-quickstart/oci-openshift` v1.34.0 manifests:

### CCM Image
| Image | Source |
|-------|--------|
| `ghcr.io/oracle/cloud-provider-oci:v1.34.0` | GitHub Container Registry (Oracle) |

### CSI Sidecar Images (from `registry.k8s.io`)
| Image | Purpose |
|-------|---------|
| `registry.k8s.io/sig-storage/csi-attacher:v4.6.1` | CSI attacher |
| `registry.k8s.io/sig-storage/csi-provisioner:v5.0.1` | CSI provisioner |
| `registry.k8s.io/sig-storage/csi-resizer:v1.11.1` | CSI resizer |
| `registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.12.0` | CSI node driver registrar |
| `registry.k8s.io/sig-storage/csi-snapshotter:v6.3.0` | CSI snapshotter |
| `registry.k8s.io/sig-storage/snapshot-controller:v6.3.0` | Snapshot controller |

### Additional Images (from manifests/ directory)
| Image | Purpose |
|-------|---------|
| `quay.io/openshift/origin-cli:4.20` | Used by autoscaling operator manifests |
| `ghcr.io/yutpeng/openshift-oracle-capi-autoscaling-dev-preview:v1.19` | Autoscaling dev preview (if needed) |

**After mirroring**, update the image references in the custom manifests to point to your enclave mirror registry.

---

## 7. Terraform & Infrastructure-as-Code Artifacts

### Terraform Binary
- Download from [releases.hashicorp.com/terraform/](https://releases.hashicorp.com/terraform/)
- Required version: `>= 1.0`

### Terraform Providers (for offline/air-gapped use)
Create a local provider mirror. The stacks require these providers:

| Provider | Source | Version Constraint |
|----------|--------|-------------------|
| `oracle/oci` | `registry.terraform.io/oracle/oci` | `>= 6.12.0` |
| `hashicorp/time` | `registry.terraform.io/hashicorp/time` | `>= 0.12.1` |
| `hashicorp/external` | `registry.terraform.io/hashicorp/external` | `~> 2.3` |

Use the script `oci-terraform-offline.sh` (included in this repo) to download providers and stacks.

### Terraform Stacks (from oracle-quickstart/oci-openshift)
Download from [GitHub releases](https://github.com/oracle-quickstart/oci-openshift/releases):

| Stack | Purpose | Required |
|-------|---------|----------|
| `create-resource-attribution-tags.zip` | Creates mandatory OpenShift resource attribution tags — **must run first** | Yes |
| `create-instance-role-tags.zip` | Creates instance role tags (control_plane, compute, boot-volume-type) | Yes |
| `create-cluster.zip` | Provisions all OCI infrastructure (VCN, subnets, LBs, DNS, compute, etc.) | Yes (connected) / Reference (disconnected manual) |
| `add-nodes.zip` | Adds worker nodes to an existing cluster | Optional |

---

## 8. Git Repositories

Clone these on a connected system and transfer into the enclave:

| Repository | Purpose |
|------------|---------|
| `github.com/oracle-quickstart/oci-openshift` | Terraform stacks, custom manifests (CCM/CSI), and configuration files |
| `github.com/oracle/oci-cloud-controller-manager` | Oracle CCM source (reference for manifest customization) |

Use the script `oci-github-offline.sh` (included in this repo) to clone repositories.

---

## 9. Configuration Files & Custom Manifests

### Agent-based Installer Config Files

Create on a connected or disconnected workstation:

```
<install_directory>/
├── install-config.yaml
├── agent-config.yaml
└── openshift/
    └── manifest.yaml        # or condensed-manifest.yml from oracle-quickstart
```

**install-config.yaml** — key disconnected fields:
```yaml
apiVersion: v1
baseDomain: <base_domain>
platform:
  external:
    platformName: oci
    cloudControllerManager: External
# Disconnected: point to enclave mirror registry
imageDigestSources:            # generated by oc-mirror v2
- mirrors:
  - <mirror_registry>:<port>/openshift/release-images
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - <mirror_registry>:<port>/openshift/release
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
additionalTrustBundle: |
  -----BEGIN CERTIFICATE-----
  <mirror_registry_CA_cert>
  -----END CERTIFICATE-----
pullSecret: '<merged_pull_secret>'
sshKey: '<public_ssh_key>'
# ...
```

**agent-config.yaml** — key disconnected field:
```yaml
apiVersion: v1beta1
metadata:
  name: <cluster_name>
rendezvousIP: <ip_address>
bootArtifactsBaseURL: <web_server_URL>   # REQUIRED for disconnected — URL where rootfs is hosted
```

### Custom Manifests (from oracle-quickstart/oci-openshift)

Place in the `openshift/` subdirectory:

| Manifest | Purpose |
|----------|---------|
| `01-oci-ccm.yml` | OCI Cloud Controller Manager DaemonSet and cluster resources |
| `01-oci-csi.yml` | OCI CSI driver DaemonSet and cluster resources |
| `01-oci-driver-configs.yml` | ConfigMaps/Secrets for CCM and CSI (contains TODO placeholders for compartment OCID, VCN OCID, subnet OCID, security list OCID) |
| `02-machineconfig-ccm.yml` | MachineConfig for kubelet provider ID |
| `02-machineconfig-csi.yml` | MachineConfig enabling iscsid.service |
| `03-machineconfig-consistent-device-path.yml` | MachineConfig for consistent device paths |
| `04-cluster-network.yml` | Network configuration (OCP 4.17+) |
| `05-oci-eval-user-data.yml` | MachineConfig for bare metal userdata scripts |

**For disconnected environments:** Update all `image:` references in `01-oci-ccm.yml` and `01-oci-csi.yml` to point to your enclave mirror registry instead of `ghcr.io` and `registry.k8s.io`.

### oc-mirror Generated Manifests

After mirroring, `oc-mirror` generates:
- `ImageDigestMirrorSet` (IDMS) CRs
- `CatalogSource` CRs
- These must be placed in the `openshift/` directory or applied post-install

---

## 10. Certificates & Authentication

| Item | Purpose |
|------|---------|
| Red Hat pull secret | From [console.redhat.com](https://console.redhat.com/openshift/install/pull-secret) — authenticate to Red Hat registries during mirroring |
| Mirror registry TLS CA certificate | Nodes and installer must trust the enclave registry's CA |
| Merged pull secret | Combine Red Hat pull secret + enclave registry credentials |
| SSH key pair | For cluster node access |
| OCI API credentials | For Terraform and CCM (API key or instance principal auth) |
| Custom CA bundle (if applicable) | If OCI API endpoints use an internal PKI in the isolated region |

For isolated OCI regions with internal certificate authorities:
```bash
export OCI_DEFAULT_CERTS_PATH="/path/to/custom-ca-bundle.pem"
```

---

## 11. OCI Infrastructure Prerequisites

These are configured **within OCI** (not mirrored, but must be provisioned before installation):

| Resource | Details |
|----------|---------|
| Compartment | Dedicated compartment for cluster resources |
| VCN + Subnets | Virtual Cloud Network with public and private subnets |
| Internet/NAT Gateways | As needed for network topology |
| Load Balancers (3) | **Internal** (ports 6443, 22623, 22624), **API** (port 6443, 22624), **Apps** (ports 80, 443) |
| DNS Zone | A records: `api.<cluster>.<domain>`, `api-int.<cluster>.<domain>`, `*.apps.<cluster>.<domain>` |
| Resource Attribution Tags | Tag namespace `openshift-tags` with tag `openshift-resource` — **must exist before install** |
| Instance Role Tags | Tag namespace `openshift-{cluster_name}` with tags `instance-role` and `boot-volume-type` |
| Dynamic Group | For control plane nodes matching the compartment and instance-role tag |
| IAM Policies | Manage volume-family, instance-family, security-lists, virtual-network-family, load-balancers, objects, tag-namespaces |
| Object Storage Bucket | For uploading the agent ISO image |
| Custom Compute Image | Created from the uploaded agent ISO (QCOW2, UEFI_64 enabled, BIOS disabled) |

---

## 12. Web Server for rootfs (Disconnected-Specific)

Per the Red Hat 4.22 documentation, disconnected environments require:

1. A **web server accessible by OCI instances** inside the enclave (e.g., httpd, nginx)
2. The `bootArtifactsBaseURL` parameter in `agent-config.yaml` points to this server
3. After running `openshift-install agent create image`, upload the rootfs image from `./<install_dir>/boot-artifacts/` to the web server
4. The agent ISO's boot process downloads the rootfs from `<bootArtifactsBaseURL>/agent.x86_64-rootfs.img`

The **minimal ISO** (< 150 MB) is uploaded to OCI Object Storage. The **rootfs** (> 1 GB) is served by the web server.

---

## 13. Example oc-mirror ImageSetConfiguration

This `ImageSetConfiguration` mirrors OpenShift 4.22 release images plus the Oracle CCM/CSI images needed for OCI:

```yaml
# imageset-config.yaml
# oc-mirror v2 ImageSetConfiguration for OpenShift 4.22 on OCI (disconnected)
apiVersion: mirror.openshift.io/v2alpha1
kind: ImageSetConfiguration
mirror:
  platform:
    channels:
      - name: stable-4.22
        minVersion: "4.22.0"
        maxVersion: "4.22.0"
        type: ocp
    graph: true

  operators:
    - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.22
      packages: []
      # Uncomment and add specific operator packages as needed:
      # - name: odf-operator
      # - name: cluster-logging
      # - name: local-storage-operator

  additionalImages:
    # --- Red Hat Offline Knowledge Portal ---
    - name: registry.redhat.io/offline-knowledge-portal/rhokp-rhel9:latest
    # --- Oracle Cloud Controller Manager ---
    - name: ghcr.io/oracle/cloud-provider-oci:v1.34.0

    # --- OCI CSI Driver Sidecars ---
    - name: registry.k8s.io/sig-storage/csi-attacher:v4.6.1
    - name: registry.k8s.io/sig-storage/csi-provisioner:v5.0.1
    - name: registry.k8s.io/sig-storage/csi-resizer:v1.11.1
    - name: registry.k8s.io/sig-storage/csi-node-driver-registrar:v2.12.0
    - name: registry.k8s.io/sig-storage/csi-snapshotter:v6.3.0
    - name: registry.k8s.io/sig-storage/snapshot-controller:v6.3.0

    # --- Supporting images from OCI manifests ---
    - name: quay.io/openshift/origin-cli:4.20
```

### Usage

**Step 1: Mirror to disk (on connected system)**
```bash
oc-mirror --v2 --config imageset-config.yaml file:///path/to/output-dir
```

**Step 2: Transfer the archive to the enclave** (USB, physical media, data diode, etc.)

**Step 3: Mirror from disk to enclave registry**
```bash
oc-mirror --v2 --config imageset-config.yaml --from file:///path/to/output-dir \
  docker://<mirror_registry>:<port>
```

**Step 4: Apply generated manifests**
```bash
# oc-mirror generates IDMS and CatalogSource CRs in the results directory
# Place them in the openshift/ directory before creating the agent ISO,
# or apply post-install:
oc apply -f /path/to/oc-mirror-workspace/results-*/
```

---

## 14. Summary Checklist

| Category | Items | Transfer Method |
|----------|-------|-----------------|
| **CLI tools** | `openshift-install`, `oc`, `oc-mirror`, `terraform` | Binary download → media transfer |
| **Release images** | OCP 4.22 release + component images | `oc-mirror` archive → media transfer |
| **Operator catalogs** | Red Hat operator index + selected operator bundles | `oc-mirror` archive (same as above) |
| **Oracle CCM/CSI images** | 8 container images from `ghcr.io` and `registry.k8s.io` | `oc-mirror` additionalImages → same archive |
| **Mirror registry** | Registry software + TLS certs + credentials | Binary/RPM → media transfer |
| **Terraform providers** | `oracle/oci`, `hashicorp/time`, `hashicorp/external` | Provider mirror → media transfer |
| **Terraform stacks** | `create-resource-attribution-tags`, `create-instance-role-tags`, `create-cluster`, `add-nodes` | Zip downloads → media transfer |
| **Git repos** | `oracle-quickstart/oci-openshift` (manifests + terraform) | `git clone --mirror` → media transfer |
| **Config files** | `install-config.yaml`, `agent-config.yaml`, custom manifests, merged pull secret | Authored on workstation |
| **Certificates** | Mirror registry CA, OCI internal CA (if applicable) | Generated/exported |
| **Web server** | httpd/nginx for rootfs hosting inside enclave | RPM/binary → media transfer |
| **OCI region config** | `regions-config.json` or `OCI_REGION_METADATA` (if isolated OCI region not in SDK) | Authored manually |

---

## Scripts

### Deployment Helper Scripts

These scripts automate the two-pass terraform workflow. Copy them to the bastion and configure the environment variables before use.

| Script | Purpose | When to Run |
|--------|---------|-------------|
| `generate-ocp-artifacts.sh` | Extracts `agent-config.yaml`, `install-config.yaml`, and all OCI day-0 manifests (CCM, CSI, MachineConfigs, network) from terraform outputs into the agent-based installer directory | After terraform pass 1, before `openshift-install agent create image` |
| `add-bastion-peering-route.sh` | Adds the bastion VCN peering route to the cluster's private route table (terraform recreates the route table each apply) | After terraform pass 2 |
| `oci-list-vms.sh` | Lists all running OCI instances in a compartment with name, private IP, and OCID | Anytime, for verification |
| `oci-bastion-preflight.sh` | Verifies bastion has required tools and FIPS/SELinux settings | Before starting the deployment |

> **Critical:** `generate-ocp-artifacts.sh` must run between terraform pass 1 and ISO creation. Without it, the OCI CCM/CSI manifests are not baked into the ISO, and the cluster will fail to bootstrap — the cloud controller manager won't deploy, nodes will be stuck with an `uninitialized` taint, and no pods can schedule.

### Offline Preparation Scripts

| Script | Purpose |
|--------|---------|
| `oci-terraform-offline.sh` | Downloads Terraform binary, providers, and OCI Terraform stacks for offline use |
| `oci-github-offline.sh` | Clones required Git repositories for offline use |
