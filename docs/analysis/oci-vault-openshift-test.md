# OCI Vault via the Secrets Store CSI driver on OpenShift — test results

Tested 2026-11-07 on the OC3 `ocp-deployment` cluster (OpenShift 4.22.9,
3 workers + 3 control plane, `us-gov-ashburn-1`), from `ocibastion`.
Plan steps 2–3 and the instance principal auth test from the 12b test plan.

## Result

**Instance principals work for Oracle's provider on OpenShift on OCI, provided
the provider runs on the host network.** Oracle's documentation says instance
principals "would work only on OKE"; the real constraint is that OpenShift's
pod network cannot reach the instance metadata endpoint.

Evidence: with the provider host-networked, a `SecretProviderClass` using
`authType: instance` and a well-formed but nonexistent vault OCID got
`404 NotAuthorizedOrNotFound` from
`secrets.vaults.us-gov-ashburn-1.oci.oraclegovcloud.com` — an authenticated
response. Before that change, the same request failed in the SDK with
`dial tcp 169.254.169.254:80: connect: connection refused` and "Instance
principals authentication can only be used on OCI compute instances".

Reading a real secret (plan step 4) is still to do; it needs a vault, which our
accounts cannot create in this tenancy. A request to the tenancy owners is in
`oc3-oci-vault-access-request.md` (untracked; it holds tenancy OCIDs and this
repo is public).

## What it took

### Red Hat operator and driver (no surprises)

- `openshift-cluster-csi-drivers` had no OperatorGroup. The operator only
  supports `AllNamespaces`, so: an OperatorGroup with `spec: {}`, then a
  Subscription to `secrets-store-csi-driver-operator`, channel `stable`, source
  `redhat-operators`. CSV `secrets-store-csi-driver-operator.v4.22.0-202611031655`.
- `ClusterCSIDriver` `secrets-store.csi.k8s.io` with `managementState: Managed`.
  The `secrets-store-csi-driver-node` DaemonSet ran on all 6 nodes.
- **The driver watches both provider directories**:
  `--provider-volume=/var/run/secrets-store-csi-providers` and
  `--additional-provider-volume-paths=/etc/kubernetes/secrets-store-csi-providers`.
  So Oracle's chart default (`/var/run/...`) is fine. An earlier assumption,
  from Red Hat's older AWS provider example, that it needed changing was wrong.

### Oracle's provider (chart 0.5.1, image `ghcr.io/oracle/oci-secrets-store-csi-driver-provider:v0.5.1`)

Rendered with `helm template` on a connected host:

```
--set secrets-store-csi-driver.install=false
--set provider.oci.auth.types.workload.enabled=false
--set provider.enableProfile=false    # added 2026-11-11, see Security notes
```

Then four OpenShift problems, each found by deploying and reading the failure:

| Symptom | Cause | Fix |
|---|---|---|
| `FailedCreate`: no SCC validates the pod | `restricted-v2` forbids `hostPath` and UID 0 | Needs an SCC grant |
| Still rejected with `hostmount-anyuid` granted | `oc adm policy scc-review` showed the only blocker is the pod's `seccompProfile: RuntimeDefault`; `hostmount-anyuid` allows no seccomp profiles | Custom SCC (below) |
| `CrashLoopBackOff`: `listen unix /opt/provider/sockets/oci.sock: bind: permission denied` | SELinux AVC: `container_t` denied `write` on the host dir labelled `container_var_run_t` | `seLinuxOptions: {type: spc_t}` on the container |
| Mount hangs, then provider logs `failed to get the region name from http://169.254.169.254/...: connection refused` | Pods on the OpenShift pod network cannot reach instance metadata. Host network can (`200`). OC3 auth and Vault endpoints were reachable from the pod network (`405`, `404`). | `hostNetwork: true`, `dnsPolicy: ClusterFirstWithHostNet` |

The provider's health (8098) and metrics (8198) ports were free on the
workers, so host networking caused no port clash. The chart has no
tolerations, so the provider runs on workers only — matching the IAM, which
should grant the worker dynamic group (`ocp-deployment_compute_nodes`).

### The SCC that works

A copy of `hostmount-anyuid` with three changes. Narrower than `privileged`:
no host devices, no added capabilities (the chart drops ALL), no host PID/IPC.

```yaml
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: oci-secrets-store-provider
# ...all other fields as hostmount-anyuid (hostPath allowed, runAsUser RunAsAny)...
seccompProfiles: ["runtime/default"]   # hostmount-anyuid has none
seLinuxContext: {type: RunAsAny}        # to allow spc_t; hostmount-anyuid is MustRunAs
allowHostNetwork: true                  # hostmount-anyuid is false
allowHostPorts: true
users: []
groups: []
```

Granted with `oc adm policy add-scc-to-user oci-secrets-store-provider
-z oci-secrets-store-csi-driver-provider-sa -n openshift-cluster-csi-drivers`.

### DaemonSet changes on top of the rendered chart

```yaml
spec:
  template:
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      containers:
      - name: oci-secrets-store-csi-driver-provider
        securityContext:
          seLinuxOptions: {type: spc_t}   # plus the chart's own settings
```

## Security notes

- **Turn pprof off.** Oracle's chart (`provider.enableProfile: true`) and the
  provider binary (`-enable-pprof`, default `true`) both enable Go pprof on
  port 6060, bound to all interfaces. With `hostNetwork: true` that is
  `*:6060` on every worker: checked on the cluster on 2026-11-11 with
  `ss -ltnp`, and `/debug/pprof/` answered 200 locally. It was not reachable
  from the bastion, but anything that can reach a worker's node IP could pull
  heap dumps from the process that handles the secrets. Render with
  `--set provider.enableProfile=false` (the manifests in
  `tests/oci-vault/manifests/` do). The health (8098) and metrics (8198)
  ports are bound to all interfaces as well.

- `spc_t` and host networking together are a meaningful grant. They are what
  the CCM and CSI driver already need for the same reasons (instance
  metadata, host sockets), and Red Hat's own secrets-store driver pods run
  fully privileged.
- With instance principals, the worker node's identity reads the secrets. Any
  pod on a worker can mount any secret the policy allows, given a
  `SecretProviderClass` in its namespace. Scope the policy with
  `where target.vault.id = '...'`, and keep the vault dedicated to the
  cluster's workloads.

## Removed from the cluster

Everything from the test was removed on 2026-11-11 with the cleanup above:
the operator, its CSV and CRDs, the `ClusterCSIDriver`, the SCC and its RBAC,
the provider DaemonSet, ServiceAccount and RBAC, and the empty directories on
all six nodes. All nodes Ready and all cluster operators healthy afterwards.
Reinstall from `tests/oci-vault/manifests/` before running step 4.
