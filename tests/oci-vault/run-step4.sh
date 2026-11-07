#!/bin/bash
set -uo pipefail

# Steps 4, 5 and 7 of the OCI Vault on OpenShift test plan, run against the
# OC3 cluster once the tenancy owners have created the test vault (see
# docs/analysis/oci-vault-openshift-test.md for steps 2-3 and the setup this
# relies on). Run on the bastion, logged in to the cluster.
#
# Usage:
#   run-step4.sh VAULT_OCID check       mount both secrets; confirm a missing
#                                       secret and a wrong vault fail clearly
#   run-step4.sh VAULT_OCID rotation    after the owners update secret 2, wait
#                                       for the new value to reach the pod
#   run-step4.sh VAULT_OCID cleanup     delete the test namespace
#   run-step4.sh VAULT_OCID dry-run     validate the manifests server-side only
#
# Secret names and values must match what the access request asked for.

VAULT="${1:-}"; MODE="${2:-}"
NS=oci-vault-step4
SECRET1=ocp-test-secret-1; VALUE1=openshift-secrets-store-test-value-1
SECRET2=ocp-test-secret-2; VALUE2=openshift-secrets-store-test-value-2
VALUE2_ROTATED=openshift-secrets-store-test-value-2-rotated
# Well-formed but nonexistent, so OCI answers 404 rather than 400.
WRONG_VAULT=ocid1.vault.oc3.iad.bbpbtzmyaaeuk.abuwcljr2wmcl6dsd7mfuopbbttgbt4fljrggnqw7flovyfq2xszjcncqxdq

[[ "$VAULT" == ocid1.vault.* && -n "$MODE" ]] || { sed -n '3,19p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

FAILS=0
pass() { echo "  PASS  $*"; }
fail() { echo "  FAIL  $*"; FAILS=$((FAILS + 1)); }

manifests() {
# The dry run validates against an existing namespace, so it skips this one.
[[ "$MODE" == dry-run ]] || cat <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: $NS
  labels: {oci-vault-test: "12b"}
EOF
  for spc in main:"$VAULT":"$SECRET1 $SECRET2" missing:"$VAULT":"ocp-test-secret-does-not-exist" wrongvault:"$WRONG_VAULT":"$SECRET1"; do
    name="${spc%%:*}"; rest="${spc#*:}"; vault="${rest%%:*}"; secrets="${rest#*:}"
    cat <<EOF
---
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: $name
  namespace: $NS
  labels: {oci-vault-test: "12b"}
spec:
  provider: oci
  parameters:
    authType: instance
    vaultId: $vault
    secrets: |
EOF
    for s in $secrets; do printf '      - name: %s\n        fileName: %s\n' "$s" "$s"; done
    cat <<EOF
---
apiVersion: v1
kind: Pod
metadata:
  name: $name
  namespace: $NS
  labels: {oci-vault-test: "12b"}
spec:
  securityContext: {runAsNonRoot: true, seccompProfile: {type: RuntimeDefault}}
  containers:
  - name: c
    image: registry.access.redhat.com/ubi9/ubi-minimal:latest
    command: ["sleep", "infinity"]
    securityContext: {allowPrivilegeEscalation: false, capabilities: {drop: ["ALL"]}}
    volumeMounts: [{name: vault, mountPath: /mnt/vault, readOnly: true}]
  volumes:
  - name: vault
    csi: {driver: secrets-store.csi.k8s.io, readOnly: true, volumeAttributes: {secretProviderClass: $name}}
EOF
  done
}

mount_error() {  # latest FailedMount message for a pod
  oc get events -n "$NS" --field-selector "involvedObject.name=$1,reason=FailedMount" \
    -o jsonpath='{range .items[*]}{.message}{"\n"}{end}' 2>/dev/null | tail -1
}

case "$MODE" in
  dry-run)
    # A server dry run never creates the namespace, so validate the namespaced
    # objects against an existing one instead.
    NS=default
    if out=$(manifests | oc apply --dry-run=server -f - 2>&1); then
      echo "$out" | sed 's/^/  /'; pass "manifests accepted by the API server (nothing created)"
    else
      echo "$out" | sed 's/^/  /'; fail "manifests rejected"
    fi ;;

  check)
    manifests | oc apply -f - >/dev/null || { fail "apply failed"; exit 1; }
    echo "--- Step 4: both secrets mount with the right contents ---"
    oc wait -n "$NS" pod/main --for=condition=Ready --timeout=180s >/dev/null 2>&1 \
      && pass "pod 'main' is Ready" || { fail "pod 'main' not Ready: $(mount_error main | cut -c1-300)"; }
    for pair in "$SECRET1=$VALUE1" "$SECRET2=$VALUE2"; do
      f="${pair%%=*}"; want="${pair#*=}"
      got=$(oc exec -n "$NS" main -- cat "/mnt/vault/$f" 2>/dev/null)
      [[ "$got" == "$want" ]] && pass "$f contains the expected value" || fail "$f: got '${got:-nothing}', expected '$want'"
    done
    echo "--- Step 5: failures are clear ---"
    sleep 60   # let both negative pods attempt their mounts
    for p in missing wrongvault; do
      phase=$(oc get pod -n "$NS" "$p" -o jsonpath='{.status.phase}')
      err=$(mount_error "$p")
      if [[ "$phase" != Running && "$err" == *"unable to retrieve secret"* ]]; then
        pass "'$p' did not start, with a mount error"
      else
        fail "'$p': phase=$phase, error='${err:0:200}'"
      fi
    done
    echo "  Provider-side OCI responses for the negative cases:"
    for p in $(oc get pods -n openshift-cluster-csi-drivers -o name | grep oci-secrets); do
      oc logs -n openshift-cluster-csi-drivers "$p" --since=5m 2>/dev/null | sed -E 's/\x1b\[[0-9;]*m//g' \
        | grep -oE 'Http Status Code: [0-9]+\. Error Code: [A-Za-z]+' | sort | uniq -c | sed 's/^/    /'
    done
    # The negative pods would keep retrying their mounts against the OCI API.
    oc delete pod -n "$NS" missing wrongvault --wait=false >/dev/null 2>&1
    echo "  (deleted the negative-case pods so they stop retrying against the OCI API)" ;;

  rotation)
    echo "--- Step 7: a secret changed in Vault reaches the pod ---"
    echo "  rotation poll interval: $(oc get ds -n openshift-cluster-csi-drivers secrets-store-csi-driver-node \
      -o jsonpath='{.spec.template.spec.containers[?(@.name=="csi-driver")].args}' | grep -oE 'rotation-poll-interval=[^"]+' || echo unknown)"
    for i in $(seq 1 30); do
      got=$(oc exec -n "$NS" main -- cat "/mnt/vault/$SECRET2" 2>/dev/null)
      [[ "$got" == "$VALUE2_ROTATED" ]] && break; sleep 20
    done
    [[ "$got" == "$VALUE2_ROTATED" ]] && pass "$SECRET2 updated in the pod after ~$((i * 20))s" \
      || fail "$SECRET2 still '${got:-nothing}' after 10 minutes" ;;

  cleanup)
    oc delete namespace "$NS" --ignore-not-found && pass "test namespace removed" ;;

  *) echo "unknown mode: $MODE" >&2; exit 2 ;;
esac

echo; [[ "$FAILS" -eq 0 ]] && echo "RESULT: PASS" || echo "RESULT: FAIL ($FAILS)"
exit "$FAILS"
