#!/usr/bin/env bash
# oci-github-offline.sh
#
# Clones Git repositories and downloads release artifacts needed for deploying
# OpenShift 4.22 on Oracle Distributed Cloud in a disconnected environment.
#
# Run this script on a connected system, then transfer the output directory
# into the enclave.
#
# Usage:
#   ./oci-github-offline.sh [--output-dir /path/to/output]

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
OUTPUT_DIR="${OUTPUT_DIR:-./oci-github-offline}"
OCP_VERSION="${OCP_VERSION:-4.22}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-dir)   OUTPUT_DIR="$2"; shift 2 ;;
        --ocp-version)  OCP_VERSION="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: $0 [--output-dir DIR] [--ocp-version VER]"
            echo ""
            echo "Options:"
            echo "  --output-dir DIR     Output directory (default: ./oci-github-offline)"
            echo "  --ocp-version VER    OpenShift version (default: 4.22)"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

REPOS_DIR="${OUTPUT_DIR}/repos"
RELEASES_DIR="${OUTPUT_DIR}/releases"
MANIFESTS_DIR="${OUTPUT_DIR}/custom-manifests"

mkdir -p "${REPOS_DIR}" "${RELEASES_DIR}" "${MANIFESTS_DIR}"

echo "============================================================"
echo "OCI GitHub Offline Package Builder"
echo "============================================================"
echo "Output directory: ${OUTPUT_DIR}"
echo "OCP version:      ${OCP_VERSION}"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# 1. Clone Git repositories (bare mirrors for maximum portability)
# ---------------------------------------------------------------------------
echo "[1/4] Cloning Git repositories..."

clone_repo() {
    local url="$1"
    local name="$2"
    local dest="${REPOS_DIR}/${name}.git"

    if [[ -d "${dest}" ]]; then
        echo "  Updating existing mirror: ${name}"
        git -C "${dest}" remote update 2>/dev/null || true
    else
        echo "  Cloning: ${url}"
        git clone --mirror "${url}" "${dest}"
    fi
    echo "    Saved: ${dest}"
}

# Primary repository — Terraform stacks + custom manifests
clone_repo "https://github.com/oracle-quickstart/oci-openshift.git" "oci-openshift"

# Oracle Cloud Controller Manager — CCM + CSI driver source code and manifests
clone_repo "https://github.com/oracle/oci-cloud-controller-manager.git" "oci-cloud-controller-manager"

# Cluster API Provider OCI — CAPI infrastructure provider (reference/future use)
clone_repo "https://github.com/oracle/cluster-api-provider-oci.git" "cluster-api-provider-oci"

# Oracle OCI Go SDK — reference for custom region configuration
clone_repo "https://github.com/oracle/oci-go-sdk.git" "oci-go-sdk"

echo ""

# ---------------------------------------------------------------------------
# 2. Download oracle-quickstart/oci-openshift release artifacts
# ---------------------------------------------------------------------------
echo "[2/4] Downloading oci-openshift release artifacts..."

# Get the latest release tag
LATEST_TAG=$(curl -fsSL "https://api.github.com/repos/oracle-quickstart/oci-openshift/releases/latest" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])" 2>/dev/null || echo "v1.5.1")

echo "  Latest release: ${LATEST_TAG}"

RELEASE_ASSETS=(
    "create-resource-attribution-tags.zip"
    "create-instance-role-tags.zip"
    "create-cluster.zip"
    "add-nodes.zip"
)

# Also download the versioned copies
VERSIONED_ASSETS=(
    "create-resource-attribution-tags-${LATEST_TAG}.zip"
    "create-instance-role-tags-${LATEST_TAG}.zip"
    "create-cluster-${LATEST_TAG}.zip"
    "add-nodes-${LATEST_TAG}.zip"
)

RELEASE_BASE_URL="https://github.com/oracle-quickstart/oci-openshift/releases/download/${LATEST_TAG}"

for asset in "${RELEASE_ASSETS[@]}" "${VERSIONED_ASSETS[@]}"; do
    dest="${RELEASES_DIR}/${asset}"
    if [[ -f "${dest}" ]]; then
        echo "  Already downloaded: ${asset}"
    else
        echo "  Downloading: ${asset}"
        if curl -fSL -o "${dest}" "${RELEASE_BASE_URL}/${asset}" 2>/dev/null; then
            echo "    Saved: ${dest}"
        else
            echo "    WARN: ${asset} not found in release (may not exist for this version)"
            rm -f "${dest}"
        fi
    fi
done

# Download source code archive
SOURCE_ARCHIVE="${RELEASES_DIR}/oci-openshift-${LATEST_TAG}.tar.gz"
if [[ ! -f "${SOURCE_ARCHIVE}" ]]; then
    echo "  Downloading source archive..."
    curl -fSL -o "${SOURCE_ARCHIVE}" \
        "https://github.com/oracle-quickstart/oci-openshift/archive/refs/tags/${LATEST_TAG}.tar.gz"
    echo "    Saved: ${SOURCE_ARCHIVE}"
fi

echo ""

# ---------------------------------------------------------------------------
# 3. Extract custom manifests for easy access
# ---------------------------------------------------------------------------
echo "[3/4] Extracting custom manifests..."

# Create a working copy from the mirror
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "${TEMP_DIR}"' EXIT

git clone "${REPOS_DIR}/oci-openshift.git" "${TEMP_DIR}/oci-openshift" --depth 1 2>/dev/null

# Copy custom manifests
if [[ -d "${TEMP_DIR}/oci-openshift/custom_manifests" ]]; then
    cp -r "${TEMP_DIR}/oci-openshift/custom_manifests/"* "${MANIFESTS_DIR}/"
    echo "  Extracted custom manifests to: ${MANIFESTS_DIR}/"

    echo ""
    echo "  Available CCM/CSI driver versions:"
    ls -1 "${MANIFESTS_DIR}/oci-ccm-csi-drivers/" 2>/dev/null | sed 's/^/    /'

    echo ""
    echo "  Container images referenced in latest manifests:"
    grep -rh 'image:' "${MANIFESTS_DIR}/oci-ccm-csi-drivers/" 2>/dev/null \
        | sed 's/.*image:[[:space:]]*/    /' | sort -u
else
    echo "  WARN: custom_manifests directory not found"
fi

echo ""

# ---------------------------------------------------------------------------
# 4. Download OpenShift CLI tools
# ---------------------------------------------------------------------------
echo "[4/4] Downloading OpenShift CLI tools..."

CLI_DIR="${OUTPUT_DIR}/openshift-clients"
mkdir -p "${CLI_DIR}"

MIRROR_BASE="https://mirror.openshift.com/pub/openshift-v4/clients/ocp"

# Get latest 4.22 stable version
STABLE_VERSION=$(curl -fsSL "${MIRROR_BASE}/stable-${OCP_VERSION}/release.txt" 2>/dev/null \
    | grep "^Name:" | awk '{print $2}' || echo "")

if [[ -z "${STABLE_VERSION}" ]]; then
    echo "  WARN: Could not determine latest stable ${OCP_VERSION} version."
    echo "  Trying latest-${OCP_VERSION}..."
    STABLE_VERSION=$(curl -fsSL "${MIRROR_BASE}/latest-${OCP_VERSION}/release.txt" 2>/dev/null \
        | grep "^Name:" | awk '{print $2}' || echo "")
fi

if [[ -n "${STABLE_VERSION}" ]]; then
    echo "  OpenShift version: ${STABLE_VERSION}"
    CLIENT_BASE="${MIRROR_BASE}/${STABLE_VERSION}"

    TOOLS=(
        "openshift-install-linux.tar.gz"
        "openshift-client-linux.tar.gz"
        "oc-mirror.tar.gz"
    )

    for tool in "${TOOLS[@]}"; do
        dest="${CLI_DIR}/${tool}"
        if [[ -f "${dest}" ]]; then
            echo "  Already downloaded: ${tool}"
        else
            echo "  Downloading: ${tool}"
            if curl -fSL -o "${dest}" "${CLIENT_BASE}/${tool}" 2>/dev/null; then
                echo "    Saved: ${dest}"
            else
                echo "    WARN: Could not download ${tool}"
                rm -f "${dest}"
            fi
        fi
    done

    # Download SHA256 checksums
    curl -fsSL -o "${CLI_DIR}/sha256sum.txt" "${CLIENT_BASE}/sha256sum.txt" 2>/dev/null || true
else
    echo "  ERROR: Could not determine OpenShift ${OCP_VERSION} version."
    echo "  Manually download CLI tools from: ${MIRROR_BASE}/"
fi

echo ""
echo "============================================================"
echo "Download complete!"
echo ""
echo "Contents of ${OUTPUT_DIR}/:"
echo ""
echo "  repos/                        Bare Git mirrors"
echo "    oci-openshift.git             Terraform stacks + manifests"
echo "    oci-cloud-controller-manager.git  CCM/CSI source"
echo "    cluster-api-provider-oci.git  CAPI provider (reference)"
echo "    oci-go-sdk.git                OCI Go SDK (reference)"
echo ""
echo "  releases/                     GitHub release zip artifacts"
echo "    create-resource-attribution-tags.zip"
echo "    create-instance-role-tags.zip"
echo "    create-cluster.zip"
echo "    add-nodes.zip"
echo ""
echo "  custom-manifests/             Extracted OCI custom manifests"
echo "    manifests/                    CCM, CSI, MachineConfig YAMLs"
echo "    oci-ccm-csi-drivers/          Per-version CCM/CSI manifests"
echo ""
echo "  openshift-clients/            OpenShift CLI tools"
echo "    openshift-install-linux.tar.gz"
echo "    openshift-client-linux.tar.gz"
echo "    oc-mirror.tar.gz"
echo ""
echo "Transfer the entire ${OUTPUT_DIR}/ directory into the enclave."
echo ""
echo "In the enclave, restore a Git repo from a bare mirror:"
echo "  git clone repos/oci-openshift.git oci-openshift"
echo "============================================================"
