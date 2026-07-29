#!/usr/bin/env bash
# oci-terraform-offline.sh
#
# Downloads Terraform binary, required providers, and OCI OpenShift Terraform
# stacks for use in a disconnected/air-gapped environment.
#
# Run this script on a connected system, then transfer the output directory
# into the enclave.
#
# Usage:
#   ./oci-terraform-offline.sh [--output-dir /path/to/output] [--terraform-version 1.9.8]

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — override via CLI flags or environment variables
# ---------------------------------------------------------------------------
OUTPUT_DIR="${OUTPUT_DIR:-./oci-terraform-offline}"
TERRAFORM_VERSION="${TERRAFORM_VERSION:-1.9.8}"
PLATFORM="${PLATFORM:-linux_amd64}"

# Terraform provider versions (match oracle-quickstart/oci-openshift requirements)
OCI_PROVIDER_VERSION="${OCI_PROVIDER_VERSION:-6.30.0}"          # >= 6.12.0
TIME_PROVIDER_VERSION="${TIME_PROVIDER_VERSION:-0.12.1}"        # >= 0.12.1
EXTERNAL_PROVIDER_VERSION="${EXTERNAL_PROVIDER_VERSION:-2.3.4}" # ~> 2.3

# OCI OpenShift Terraform stacks release
OCI_OPENSHIFT_RELEASE="${OCI_OPENSHIFT_RELEASE:-latest}"
OCI_OPENSHIFT_REPO="https://github.com/oracle-quickstart/oci-openshift"

# ---------------------------------------------------------------------------
# Parse CLI arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-dir)   OUTPUT_DIR="$2"; shift 2 ;;
        --terraform-version) TERRAFORM_VERSION="$2"; shift 2 ;;
        --platform)     PLATFORM="$2"; shift 2 ;;
        --oci-provider-version) OCI_PROVIDER_VERSION="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--output-dir DIR] [--terraform-version VER] [--platform PLAT]"
            echo ""
            echo "Options:"
            echo "  --output-dir DIR          Output directory (default: ./oci-terraform-offline)"
            echo "  --terraform-version VER   Terraform version (default: ${TERRAFORM_VERSION})"
            echo "  --platform PLAT           Platform string (default: ${PLATFORM})"
            echo "  --oci-provider-version V  OCI provider version (default: ${OCI_PROVIDER_VERSION})"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Derived paths
# ---------------------------------------------------------------------------
PROVIDERS_DIR="${OUTPUT_DIR}/terraform-providers"
STACKS_DIR="${OUTPUT_DIR}/terraform-stacks"
BIN_DIR="${OUTPUT_DIR}/bin"

mkdir -p "${BIN_DIR}" "${PROVIDERS_DIR}" "${STACKS_DIR}"

echo "============================================================"
echo "OCI Terraform Offline Package Builder"
echo "============================================================"
echo "Output directory:     ${OUTPUT_DIR}"
echo "Terraform version:    ${TERRAFORM_VERSION}"
echo "Platform:             ${PLATFORM}"
echo "OCI provider:         oracle/oci ${OCI_PROVIDER_VERSION}"
echo "Time provider:        hashicorp/time ${TIME_PROVIDER_VERSION}"
echo "External provider:    hashicorp/external ${EXTERNAL_PROVIDER_VERSION}"
echo "OCI OpenShift release: ${OCI_OPENSHIFT_RELEASE}"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# 1. Download Terraform binary
# ---------------------------------------------------------------------------
echo "[1/3] Downloading Terraform ${TERRAFORM_VERSION} for ${PLATFORM}..."
TERRAFORM_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_${PLATFORM}.zip"
TERRAFORM_ZIP="${BIN_DIR}/terraform_${TERRAFORM_VERSION}_${PLATFORM}.zip"

if [[ -f "${TERRAFORM_ZIP}" ]]; then
    echo "  Already downloaded: ${TERRAFORM_ZIP}"
else
    curl -fSL -o "${TERRAFORM_ZIP}" "${TERRAFORM_URL}"
    echo "  Downloaded: ${TERRAFORM_ZIP}"
fi

# Also download the SHA256 checksum for verification
TERRAFORM_SHA_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS"
curl -fsSL -o "${BIN_DIR}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" "${TERRAFORM_SHA_URL}" 2>/dev/null || true

echo ""

# ---------------------------------------------------------------------------
# 2. Download Terraform providers
# ---------------------------------------------------------------------------
echo "[2/3] Downloading Terraform providers..."

download_provider() {
    local namespace="$1"
    local name="$2"
    local version="$3"
    local provider_dir="${PROVIDERS_DIR}/registry.terraform.io/${namespace}/${name}/${version}/${PLATFORM}"

    mkdir -p "${provider_dir}"

    local zip_name="terraform-provider-${name}_${version}_${PLATFORM}.zip"
    local zip_path="${provider_dir}/${zip_name}"

    if [[ -f "${zip_path}" ]]; then
        echo "  Already downloaded: ${namespace}/${name} v${version}"
        return 0
    fi

    local download_url="https://releases.hashicorp.com/terraform-provider-${name}/${version}/${zip_name}"

    # Oracle provider uses a different URL pattern
    if [[ "${namespace}" == "oracle" ]]; then
        download_url="https://releases.hashicorp.com/terraform-provider-${name}/${version}/${zip_name}"
    fi

    echo "  Downloading ${namespace}/${name} v${version}..."
    if curl -fSL -o "${zip_path}" "${download_url}" 2>/dev/null; then
        echo "    Saved: ${zip_path}"
    else
        echo "    WARN: Failed to download from HashiCorp releases. Trying Terraform registry..."
        # Fallback: query registry for download URL
        local registry_url="https://registry.terraform.io/v1/providers/${namespace}/${name}/${version}/download/${PLATFORM}"
        local actual_url
        actual_url=$(curl -fsSL "${registry_url}" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['download_url'])" 2>/dev/null || echo "")
        if [[ -n "${actual_url}" ]]; then
            curl -fSL -o "${zip_path}" "${actual_url}"
            echo "    Saved: ${zip_path}"
        else
            echo "    ERROR: Could not download ${namespace}/${name} v${version}"
            return 1
        fi
    fi
}

download_provider "oracle"    "oci"      "${OCI_PROVIDER_VERSION}"
download_provider "hashicorp" "time"     "${TIME_PROVIDER_VERSION}"
download_provider "hashicorp" "external" "${EXTERNAL_PROVIDER_VERSION}"

echo ""

# ---------------------------------------------------------------------------
# 3. Download OCI OpenShift Terraform stacks
# ---------------------------------------------------------------------------
echo "[3/3] Downloading OCI OpenShift Terraform stacks..."

STACKS=(
    "create-resource-attribution-tags"
    "create-instance-role-tags"
    "create-cluster"
    "add-nodes"
)

if [[ "${OCI_OPENSHIFT_RELEASE}" == "latest" ]]; then
    BASE_URL="${OCI_OPENSHIFT_REPO}/releases/latest/download"
else
    BASE_URL="${OCI_OPENSHIFT_REPO}/releases/download/${OCI_OPENSHIFT_RELEASE}"
fi

for stack in "${STACKS[@]}"; do
    local_path="${STACKS_DIR}/${stack}.zip"
    if [[ -f "${local_path}" ]]; then
        echo "  Already downloaded: ${stack}.zip"
    else
        echo "  Downloading ${stack}.zip..."
        curl -fSL -o "${local_path}" "${BASE_URL}/${stack}.zip"
        echo "    Saved: ${local_path}"
    fi
done

echo ""

# ---------------------------------------------------------------------------
# Generate filesystem mirror configuration
# ---------------------------------------------------------------------------
cat > "${OUTPUT_DIR}/terraform-mirror.tfrc" <<'TFRC'
# Terraform CLI configuration for air-gapped provider mirror.
#
# Usage:
#   export TF_CLI_CONFIG_FILE=/path/to/oci-terraform-offline/terraform-mirror.tfrc
#
# Then run terraform init as normal — it will resolve providers from the
# local filesystem mirror instead of the internet.

provider_installation {
  filesystem_mirror {
    path    = "./terraform-providers"
    include = ["registry.terraform.io/*/*"]
  }
  direct {
    exclude = ["registry.terraform.io/*/*"]
  }
}
TFRC

echo "============================================================"
echo "Download complete!"
echo ""
echo "Contents of ${OUTPUT_DIR}/:"
echo ""
echo "  bin/                          Terraform binary (zipped)"
echo "  terraform-providers/          Provider plugin mirror"
echo "  terraform-stacks/             OCI OpenShift Terraform stacks"
echo "  terraform-mirror.tfrc         Terraform CLI config for offline use"
echo ""
echo "Transfer the entire ${OUTPUT_DIR}/ directory into the enclave."
echo ""
echo "In the enclave:"
echo "  1. Unzip and install the terraform binary:"
echo "     unzip bin/terraform_${TERRAFORM_VERSION}_${PLATFORM}.zip -d /usr/local/bin/"
echo ""
echo "  2. Configure Terraform to use the local provider mirror:"
echo "     export TF_CLI_CONFIG_FILE=\$(pwd)/terraform-mirror.tfrc"
echo ""
echo "  3. Unzip and run the stacks:"
echo "     unzip terraform-stacks/create-resource-attribution-tags.zip -d create-resource-attribution-tags/"
echo "     cd create-resource-attribution-tags/"
echo "     terraform init"
echo "     terraform apply"
echo "============================================================"
