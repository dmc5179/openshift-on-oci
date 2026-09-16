# OpenShift on OCI — Terraform Variables Reference

This directory contains a `terraform.tfvars.template` for deploying OpenShift Container Platform on Oracle Cloud Infrastructure (OCI) using the **Agent-based Installer** and Terraform. The variables come from the [oracle-quickstart/oci-openshift](https://github.com/oracle-quickstart/oci-openshift) `create-cluster` Terraform stack, which is the method documented by Red Hat for OCI deployments.

## Quick Start

The deployment uses a **two-pass terraform workflow**:

- **Pass 1** (`create_openshift_instances=false`) — creates infrastructure, networking, load balancers, Object Storage bucket, and PARs for the rootfs and ISO. Produces terraform outputs consumed by the helper scripts.
- **Pass 2** (`create_openshift_instances=true`) — uploads rootfs and ISO to Object Storage, imports the ISO as a custom compute image, and launches all cluster instances.

Between the two passes, you extract manifests and create the agent ISO.

```bash
# 1. Copy the template and fill in your values
cp terraform.tfvars.template terraform.tfvars
$EDITOR terraform.tfvars

# 2. Terraform pass 1 — infrastructure only
cd <terraform-stack>/terraform-stacks/create-cluster
terraform init
terraform apply -var-file=../../terraform.tfvars -var='create_openshift_instances=false'

# 3. Extract manifests from terraform outputs (CRITICAL — do not skip)
../../scripts/generate-ocp-artifacts.sh

# 4. Create the agent ISO (bakes OCI CCM/CSI/network manifests into the image)
cd ~/ocp-deployment-agentBasedInstallation
openshift-install agent create image --dir=.

# 5. Terraform pass 2 — uploads ISO + rootfs and creates instances
cd <terraform-stack>/terraform-stacks/create-cluster
terraform apply -var-file=../../terraform.tfvars \
  -var='create_openshift_instances=true' \
  -var='iso_file_path=~/ocp-deployment-agentBasedInstallation/agent.x86_64.iso' \
  -var='rootfs_file_path=~/ocp-deployment-agentBasedInstallation/boot-artifacts/agent.x86_64-rootfs.img'

# 6. If using a bastion with VCN peering, re-add the peering route
../../scripts/add-bastion-peering-route.sh

# 7. Monitor installation (~30-45 min)
export KUBECONFIG=~/ocp-deployment-agentBasedInstallation/auth/kubeconfig
oc get clusterversion
oc get nodes
oc get co
```

> **Warning:** Step 3 (`generate-ocp-artifacts.sh`) must run before `openshift-install agent create image`. If the OCI manifests (CCM, CSI, network config) are not in the `openshift/` directory when the ISO is created, the cluster will fail to bootstrap — the cloud controller manager won't deploy, nodes will be stuck with `node.cloudprovider.kubernetes.io/uninitialized` taints, and no pods can schedule.

## Prerequisites

Before running the stack you must:

1. **Create resource attribution tags** — Run the `create-resource-attribution-tags` stack first. These tags are mandatory for OpenShift on OCI.
2. **Create a compartment** — Decide on (or create) the OCI compartment where cluster resources will live.
3. **Prepare a bastion** (disconnected environments) — A RHEL instance with `openshift-install`, `oc`, `terraform`, and OCI CLI installed.

## Variable Reference

### Required Variables

These **must** be provided — the stack has no usable defaults for them.

| Variable | Description |
|----------|-------------|
| `tenancy_ocid` | OCID of your OCI tenancy. Found under Tenancy Details in the OCI console. |
| `compartment_ocid` | OCID of the compartment where all cluster resources will be created. |
| `region` | OCI region identifier (e.g. `us-sanjose-1`, `eu-frankfurt-1`). |
| `cluster_name` | DNS-compatible cluster name. Lowercase alphanumeric and hyphens, 1–54 characters. Becomes part of the cluster FQDN. |
| `zone_dns` | Base DNS domain for the cluster (e.g. `example.com`). Must match the base domain in your `install-config.yaml`. |
| `openshift_image_source_uri` | PAR URL pointing to the agent ISO image in OCI Object Storage. Not needed for disconnected installs — set `iso_file_path` instead and terraform creates the PAR automatically. |
| `tag_namespace_compartment_ocid_resource_tagging` | OCID of the compartment containing the OpenShift resource attribution tag namespace. |
| `rendezvous_ip` | IP assigned to the bootstrap node that orchestrates the Agent-based installation. Must be within the `private_cidr_ocp` subnet and must match the `rendezvousIP` in your `agent-config.yaml`. Default: `10.0.16.20`. |

### Installation Method

| Variable | Default | Description |
|----------|---------|-------------|
| `installation_method` | `"Agent-based"` | Set to `"Agent-based"` for Agent-based Installer deployments. The alternative is `"Assisted"` for the Assisted Installer. |
| `create_openshift_instances` | `true` | Whether Terraform should create compute instances. Set to `false` if provisioning instances separately. |

### Control Plane Nodes

| Variable | Default | Description |
|----------|---------|-------------|
| `control_plane_shape` | `VM.Standard.E5.Flex` | OCI compute shape for control plane nodes. |
| `control_plane_count` | `3` | Number of control plane nodes. |
| `control_plane_ocpu` | `4` | OCPUs per control plane node (1–144). |
| `control_plane_memory` | `24` | Memory in GB per control plane node (1–1760). |
| `control_plane_boot_size` | `1024` | Boot volume size in GB (50–32768). |
| `control_plane_boot_volume_vpus_per_gb` | `100` | Boot volume performance in VPUs/GB (10–120, multiples of 10). |
| `distribute_cp_instances_across_ads` | `true` | Round-robin distribution across Availability Domains. |
| `distribute_cp_instances_across_fds` | `true` | Distribution across Fault Domains. |
| `starting_ad_name_cp` | `null` | (Optional) Specific AD to start placement from. |
| `starting_fd_name_cp` | `null` | (Optional) Specific Fault Domain to start from. |
| `control_plane_capacity_reservation` | `null` | (Optional) Capacity Reservation OCID. |

### Compute (Worker) Nodes

| Variable | Default | Description |
|----------|---------|-------------|
| `compute_shape` | `VM.Standard.E5.Flex` | OCI compute shape for worker nodes. |
| `compute_count` | `3` | Number of worker nodes. |
| `compute_ocpu` | `6` | OCPUs per worker node (1–144). |
| `compute_memory` | `32` | Memory in GB per worker node (1–1760). |
| `compute_boot_size` | `300` | Boot volume size in GB (50–32768). |
| `compute_boot_volume_vpus_per_gb` | `30` | Boot volume performance in VPUs/GB (10–120, multiples of 10). |
| `distribute_compute_instances_across_ads` | `true` | Round-robin distribution across Availability Domains. |
| `distribute_compute_instances_across_fds` | `true` | Distribution across Fault Domains. |
| `starting_ad_name_compute` | `null` | (Optional) Specific AD to start placement from. |
| `starting_fd_name_compute` | `null` | (Optional) Specific Fault Domain to start from. |
| `compute_capacity_reservation` | `null` | (Optional) Capacity Reservation OCID. |

### Networking

| Variable | Default | Description |
|----------|---------|-------------|
| `create_public_dns` | `true` | Create a public DNS zone with the base domain. |
| `create_private_dns` | `false` | Create a private DNS zone with the base domain. |
| `enable_public_api_lb` | `false` | Expose the Kubernetes API load balancer on a public IP. |
| `enable_public_apps_lb` | `true` | Expose the Apps/Ingress load balancer on a public IP. |
| `use_existing_network` | `false` | Use an existing VCN instead of creating one. |
| `vcn_dns_label` | `openshiftvcn` | DNS label for the VCN (1–15 chars). |
| `vcn_cidr` | `10.0.0.0/16` | CIDR block for the VCN. |
| `public_cidr` | `10.0.0.0/20` | CIDR for the public subnet (LBs, bastion). |
| `private_cidr_ocp` | `10.0.16.0/20` | CIDR for the private OCP node subnet. |
| `private_cidr_bare_metal` | `10.0.32.0/20` | CIDR for the private bare metal subnet. |
| `load_balancer_shape_details_minimum_bandwidth_in_mbps` | `10` | LB minimum bandwidth in Mbps (10–8000). |
| `load_balancer_shape_details_maximum_bandwidth_in_mbps` | `500` | LB maximum bandwidth in Mbps (10–8000). |

When `use_existing_network = true`, also provide:

| Variable | Description |
|----------|-------------|
| `vcn_compartment_ocid` | Compartment OCID where the existing VCN is located. |
| `existing_vcn_id` | OCID of the existing VCN. |
| `subnet_compartment_ocid` | Compartment OCID where existing subnets are located. |
| `existing_private_ocp_subnet_id` | OCID of the existing private subnet for OCP nodes. |
| `existing_private_bare_metal_subnet_id` | OCID of the existing private bare metal subnet. |
| `existing_public_subnet_id` | OCID of the existing public subnet. |

### Disconnected / Air-Gapped Installation

These variables apply when `is_disconnected_installation = true` (available only with the Agent-based Installer).

| Variable | Default | Description |
|----------|---------|-------------|
| `is_disconnected_installation` | `false` | Enable disconnected installation mode. |
| `iso_file_path` | `""` | Local path to `agent.x86_64.iso`. Terraform uploads it to Object Storage and creates a PAR automatically. Leave empty during pass 1. |
| `rootfs_file_path` | `""` | Local path to `boot-artifacts/agent.x86_64-rootfs.img`. Terraform uploads it to Object Storage. Leave empty during pass 1. |
| `rootfs_par_expiry_hours` | `168` | Hours until the boot artifact PARs expire (default: 7 days). |
| `public_ssh_key` | `""` | SSH public key for instance access. |
| `redhat_pull_secret` | `""` | Red Hat pull secret JSON from console.redhat.com. |
| `object_storage_namespace` | `""` | OCI Object Storage namespace for the tenancy. |
| `object_storage_bucket` | `""` | Bucket name for OpenShift installation files. |
| `webserver_private_ip` | `10.0.0.200` | Private IP for the content webserver. |
| `webserver_shape` | `VM.Standard.E5.Flex` | Compute shape for the webserver instance. |
| `webserver_image_source_id` | *(OEL 9 image)* | OCID of the Oracle Enterprise Linux image for the webserver. |
| `webserver_ocpus` | `2` | OCPUs for the webserver. |
| `webserver_memory_in_gbs` | `8` | Memory in GB for the webserver. |

### Proxy Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `set_proxy` | `false` | Enable proxy settings for instances behind a firewall. |
| `http_proxy` | `""` | HTTP proxy URL. |
| `https_proxy` | `""` | HTTPS proxy URL. |
| `no_proxy` | `""` | Comma-separated list of domains/CIDRs to bypass the proxy. |

### Autoscaling

| Variable | Default | Description |
|----------|---------|-------------|
| `use_autoscaling_operator` | `false` | Enable the Oracle Cloud Autoscaler Operator. |
| `autoscaler_node_shape` | `VM.Standard.E5.Flex` | Compute shape for autoscaled nodes. |
| `autoscaler_node_ocpus` | `4` | OCPUs per autoscaled node. |
| `autoscaler_node_memory` | `24` | Memory in GB per autoscaled node. |
| `autoscaler_node_minimum_count` | `0` | Minimum number of autoscaled nodes. |
| `autoscaler_node_maximum_count` | `5` | Maximum number of autoscaled nodes. |
| `autoscaler_pool_identifier` | `""` | Lowercase identifier for the pool (max 5 chars). |
| `autoscaler_node_image_source_uri` | `""` | PAR URL for the autoscaler node image. |
| `cluster_network_cidr_block` | `10.128.0.0/14` | OpenShift cluster network CIDR. |
| `service_network_cidr_block` | `172.30.0.0/16` | OpenShift service network CIDR. |

### Version & Driver Overrides

| Variable | Default | Description |
|----------|---------|-------------|
| `set_openshift_installer_version` | `false` | Pin a specific openshift-installer version. |
| `openshift_installer_version` | `latest` | Version string (used when override is enabled). |
| `oci_driver_version` | `v1.34.0` | OCI Cloud Controller Manager and CSI driver version. |

### Instance Role Tags

| Variable | Default | Description |
|----------|---------|-------------|
| `use_existing_tags` | `false` | Reuse an existing instance role tag namespace. |
| `tag_namespace_name` | `""` | Name of the tag namespace (must start with `openshift-`). |
| `tag_namespace_compartment_ocid` | `""` | Compartment OCID containing the tag namespace. |

### Oracle Cloud Agent

| Variable | Default | Description |
|----------|---------|-------------|
| `use_oracle_cloud_agent` | `false` | Enable Oracle Cloud Agent in the cluster. |
| `oracle_cloud_agent_repo_name` | `openshift-oca` | Repository containing the OCA container image. |

## What Terraform Creates

When all defaults are accepted, the `create-cluster` stack provisions:

- **VCN** with public and private subnets, route tables, security lists, and internet/NAT/service gateways
- **Load Balancers** for the Kubernetes API (port 6443/22623) and Apps/Ingress (port 80/443)
- **Compute Instances** for control plane and worker nodes using the uploaded RHCOS image
- **DNS Zone** and records for `api.<cluster_name>.<zone_dns>` and `*.apps.<cluster_name>.<zone_dns>`
- **IAM Dynamic Groups and Policies** for OpenShift components to manage OCI resources (CCM, CSI)
- **Network Security Groups (NSGs)** with rules for cluster communication
- **Instance role tags** for identifying control plane vs. compute nodes

## Sources

- [Installing OpenShift on OCI (Red Hat documentation)](https://access.redhat.com/documentation/en-us/openshift_container_platform/4.19/html-single/installing_on_oci/index)
- [oracle-quickstart/oci-openshift (GitHub)](https://github.com/oracle-quickstart/oci-openshift)
- [Verifying OCP 4 Installation on OCI (Red Hat KB)](https://access.redhat.com/solutions/7132057)
