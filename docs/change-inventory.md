# Fork change inventory

Every change made to `dmc5179/oci-openshift` since forking from
`oracle-quickstart/oci-openshift`, classified by concern so the work can be
re-submitted upstream as small, scoped PRs.

- **Fork point:** `008a531` (upstream Release v1.6.0, 2026-07-30)
- **Current upstream baseline:** `4944984` (v1.6.1), merged 2026-10-14, tagged `upstream-merge/v1.6.1`
- **Working branch:** `disconnected`
- **Frozen:** `oc3-support` at `40c6221`, tagged `archive/oc3-support-pr88` — the state submitted as PR #88, now closed

Most changes exist under two SHAs because `oc3-support` was rebased from
`disconnected`. Both are listed; `disconnected` is authoritative.

## Categories

| Tag | Meaning | Upstream? |
|---|---|---|
| `airgap` | Disconnected / mirroring. Realm-agnostic. | Yes |
| `realm` | Any non-commercial realm — OC3, OC6 and others. | Yes |
| `oc3` | Gov Cloud specific. | Yes |
| `oc6` | Isolated realm specific. | Yes |
| `upstream-fix` | Plain bug or gap in Oracle's code, nothing to do with realms. | Yes — submit first |
| `local` | Our tooling and docs. Never upstream. | No |

## Inventory

| # | Change | disconnected | oc3-support | Category | Upstream status |
|---|---|---|---|---|---|
| 1 | Collapse webserver and bastion into one host | `d8385d4` | `8865e3b` | `airgap` | not submitted |
| 2 | Enable FIPS on the cluster | `3dfc4ad` | `a3713af` | `upstream-fix` | not submitted |
| 3 | Bastion preflight validation script | `4695a71` | — | `local` | n/a |
| 4 | imageDigestSources + additionalTrustBundle | `e90e745` | `5a3656e` | `airgap` | not submitted |
| 5 | Remove webserver references (PXE concept, invalid on OCI) | `cf266d9` | `ba41d91` | `upstream-fix` | not submitted |
| 6 | Output manifests individually, not one multi-doc YAML | `03b67b2` | `4a9ace6` | `upstream-fix` | not submitted |
| 7 | Ignore terraform state files | `6590951` | `dca3b82` | `local` | n/a |
| 8 | Disable OCA by default in Gov Cloud (no marketplace) | `010308c` | `abe509e` | `oc3` | not submitted |
| 9 | Example `imageset-config.yaml` for oc-mirror | `d93fe86` | `536e71a` | `airgap` | not submitted |
| 10 | Deployment container image (Containerfile, build script) | `34af3e5` `77e45f9` `f14950d` `433e2e2` `d323573` `302079f` `13cb4a3` `c403c60` | — | `local` | n/a |
| 11 | Secrets operator / OCI Vault integration | `c85cbf4` | `8695f8d` | `upstream-fix` | not submitted |
| 12 | Non-commercial realm support — templatize CCM, realm endpoints, OCIR domain | `db3b2ca` | `d53e4d7` | `realm` | not submitted |
| 13 | Host rootfs in Object Storage for minimal ISO | `b6f3599` | `b28b4a5` | `airgap` | not submitted |
| 14 | Follow-up to rootfs hosting | `fcecaad` | `c6cac0a` | `airgap` | not submitted |
| 15 | Helper scripts + tfvars gitignore | `46999f0` | `7bef4d9` `35ec7b0` | `local` | n/a |
| 16 | OC6 quickstart doc | `dc6be10` | — | `oc6` | not submitted |
| 17 | Rename `rootfs_storage` → `boot_artifacts`, add ISO upload | `bc74c01` | `51351d3` | `airgap` | not submitted |
| 18 | Docs for terraform-managed ISO upload | `af06e0d` | — | `airgap` | not submitted |
| 19 | Use IMDS `realmDomainComponent` as primary realm source | `0c3ae6f` | `59628ff` | `realm` | not submitted |
| 20 | Remove hardcoded realm domain map | `4eb103b` | `9366189` | `realm` | not submitted |
| 21 | CCM image source + `imageTagSources` | `4f54f3e` | `d1fedb5` | `airgap` | superseded by #24 |
| 22 | CCM image in static v1.34.0 manifest → official Oracle source | `9cb8b0c` | `8f1486d` | *reverted* | **REVERTED** by `6b71526` — see below |
| 23 | `additionalNTPSources` via agent-config (IMDS as NTP) | `a469082` | `7244c31` | `upstream-fix` | not submitted |
| 24 | Generate `ImageTagMirrorSet` manifest | `40f0fb0` | `0f10990` | `airgap` | not submitted |
| 25 | Align origin-cli to 4.22 | `c976eb2` | `2b7907b` | `upstream-fix` | not submitted |
| 26 | Fix `additionalTrustBundle` indentation (invalid YAML) | `707b100` | `f26a276` | `upstream-fix` | not submitted |
| 27 | Order boot artifact PARs after their object uploads | `164e81b` | `1b8aff2` | `upstream-fix` | not submitted |
| 28 | origin-cli 4.22 in container-deployer doc | `d31af1b` | — | `local` | n/a |
| 29 | Document two-pass workflow in tfvars template | `d6d290d` | `4f3fe65` | `airgap` | not submitted |
| 30 | Boot artifact URLs instead of local paths (Resource Manager) | `d0491db` | `4427d80` | `airgap` | not submitted |
| 31 | `upload-rootfs.sh` debugging helper | `b31c551` | — | `local` | n/a |
| 32 | Fail loudly on incomplete manifest extraction | `c947d16` | `40c6221` | `local` | n/a |
| 33 | Mount additional_trust_bundle into the CCM and CSI pods | `99c5feb` | — | `upstream-fix` | not submitted |
| — | Remove bastion doc from PR scope | — | `66129d6` | *drop* | PR housekeeping, obsolete |

## Notes on specific entries

**#22 was reverted on 2026-10-14.** Oracle engineering confirmed the official
`ghcr.io/oracle/cloud-provider-oci:v1.34.0` is missing a required fix, and that
`ghcr.io/nikhisin3001/cloud-provider-oci:v1.34.0` must be used until a corrected
release ships. Commit `6b71526` restores the developer image across the
terraform image map, the static reference manifests and both example imagesets.
Not upstreamable in either direction until Oracle publishes the fix under an
Oracle-owned namespace — tracked as an open item for Oracle engineering.

**#21 is superseded.** `imageTagSources` is not a valid InstallConfig field.
The CCM image source part of that commit still stands; the mirror mechanism was
replaced by #24.

**#2, #11, #23 apply to every OCI region.** FIPS, OCI Vault integration and the
NTP change each surfaced during Gov Cloud or OC6 work, but all three are useful
on commercial OCI, OC3 and OC6 alike. Confirmed 2026-10-14; classified
`upstream-fix` and upstreamable on their own merits.

**#33 is not OC6-specific, despite surfacing there.** It applies to any
OpenShift on OCI deployment where something the Oracle containers talk to is
fronted by a non-commercial CA — isolated realms, Gov Cloud, and on-premise
Compute Cloud@Customer or Private Cloud Appliance, where customer-supplied
certificates are the norm rather than the exception. The failure is not
realm-specific either: `additionalTrustBundlePolicy: Always` puts the CA on the
node, which is why image pulls from a private registry succeed, but CRI-O does
not mount the host trust store into pods and Oracle's manifests mount no CA
bundle, so the CCM fails x509, nodes keep the uninitialized taint, CNI never
starts and the cluster cannot converge. Classified `upstream-fix` rather than
`realm` on that basis — it is a gap in Oracle's manifests that anyone with a
private CA will hit. Gated on `additional_trust_bundle`, so connected installs
are unaffected.

**#32 is classified `local` but was in PR #88.** The helper scripts are our
tooling; whether Oracle wants them upstream is their call, not an assumption we
should bake in.

## Not yet in the inventory

Work identified but not implemented, so no commits exist yet:

- **Autoscaler disconnected support** (`airgap`) — four runtime dependencies on
  public endpoints. Oracle has proposed a design; see
  `oracle-issues/oracle-issue-autoscaler-disconnected-oracle-response.txt` and
  the drafted clarifying questions alongside it.

## Submission plan

Supersedes the earlier four-bucket ordering. Grouped into reviewable PRs and
ordered so each lands before anything depending on it.

Upstream has **no** `imageDigestSources`, **no** `additionalTrustBundle` and no
PAR or boot-artifact handling at all. Air-gap was not partially supported — the
mirror configuration was never emitted. PR 1 is the fix for that.

| # | PR | Why air-gap needs it | Entries | Depends on | Size | Status |
|---|---|---|---|---|---|---|
| 1 | Emit mirror config in install-config — imageDigestSources, additionalTrustBundle(+Policy), generated ImageTagMirrorSet, example imageset | Nothing pulls from a mirror without it | 4, 9, 21, 24 (26, 27 folded in) | — | Medium |
| 2 | Host boot artifacts in Object Storage — boot_artifacts module, rootfs + ISO upload, PARs via full_path, RM-compatible URL inputs | A disconnected cluster cannot fetch the rootfs from the internet | 13, 14, 17, 30, `7f1753c`, `a06d6ef` | PR 1 | Medium |
| 3 | Mount the trust bundle into the CCM and CSI pods | Without it the CCM fails x509, nodes stay tainted, CNI never starts. Validated on a live OC6 cluster | 33 | PR 1 | Small | [#97](https://github.com/oracle-quickstart/oci-openshift/pull/97) stacked on #94, #96 |
| 4 | Output manifests individually, not one multi-doc YAML | The agent installer cannot consume `dynamic_custom_manifest` | 6 | — | Small |
| 5 | NTP via additionalNTPSources | No public NTP in an enclave; clock skew breaks TLS | 23 | — | Small |
| 6 | origin-cli 4.20 → 4.22 | Genuine upstream pin; mismatched tag 404s against a mirror | 25 | — | Trivial |
| 7 | Remove the webserver module | PXE concept that cannot work on OCI; misleading for air-gap | 1, 5 | — | Small |
| 8 | Non-commercial realm support — templatized CCM, realm endpoints, OCIR domain | OC3/OC6 API endpoints differ | 12 | — | Medium |
| 9 | Autoscaler air-gap — configurable artifact sources, Object Storage hosting | Four runtime fetches from github.com | `ac6c574`, `dfb4b0e`, `b003540` | PR 2; blocked on Oracle | Large |
| 10 | Disable OCA in Gov Cloud | No marketplace in OC3/OC6 | 8 | **blocked on Oracle** | Trivial | Waiting on Oracle to confirm whether a marketplace exists in OC3/OC6 at all, or whether the commercial OCA image can be pulled into those realms. The fix depends on the answer. |
| 11 | FIPS support | Not air-gap, but commonly required alongside | 2 | — | Small | [#98](https://github.com/oracle-quickstart/oci-openshift/pull/98) branched from main |
| 12 | OCI Vault secrets operator | Independent feature | 11 | — | Small |

### Order of submission

**4, 6, 5** first — trivial, uncontroversial, and they rebuild review momentum
after #88 was closed as too large. Then **1**, then **2 and 3** together since 3
is useless without 1. Then **7, 8, 10**. Hold **9** until Oracle answers the
outstanding questions.

### Submitted so far

| Plan # | PR | Scope | Note |
|---|---|---|---|
| 4 | [#91](https://github.com/oracle-quickstart/oci-openshift/pull/91) | +117/−0 | Individual manifest outputs |
| 6 | [#92](https://github.com/oracle-quickstart/oci-openshift/pull/92) | +3/−3 | origin-cli 4.22 |
| 5 | [#93](https://github.com/oracle-quickstart/oci-openshift/pull/93) | +24/−11 | NTP via additionalNTPSources |
| 1 | [#94](https://github.com/oracle-quickstart/oci-openshift/pull/94) | +90/−1 | Mirror config + ITMS |
| 2 | [#95](https://github.com/oracle-quickstart/oci-openshift/pull/95) | +185/−13 | Boot artifacts in Object Storage |
| 8 | [#96](https://github.com/oracle-quickstart/oci-openshift/pull/96) | +306/−8 | CCM template + realm endpoints |
| 3 | [#97](https://github.com/oracle-quickstart/oci-openshift/pull/97) | +78/−0 | CA mount — stacked on #94 and #96 |
| 11 | [#98](https://github.com/oracle-quickstart/oci-openshift/pull/98) | +26/−2 | FIPS + proxy rendering fix — branched from main |

Remaining: **7** (waiting on #95 to land), **12** (ready), **9** and **10**
(blocked on Oracle).

### Found while testing, fixed in #98

`shared_modules/manifest/locals.tf:343` — the proxy heredoc is interpolated at
the end of the `cloudControllerManager` line and its body starts directly with
`proxy:`, so with `set_proxy = true` the two run together and the rendered
install-config does not parse (`mapping values are not allowed here`).
Pre-existing on `main`, unrelated to anything we added. Folded into #98 as a
second commit rather than filed separately: same expression, same four-way test
matrix, and it would have been odd to add a flag whose matrix includes a
combination documented as broken.

### Two notes on grouping

Entries 26 (the `indent()` YAML bug) and 27 (PAR `depends_on`) fix code we wrote,
and upstream does not have that code. They are folded into PRs 1 and 2 rather
than submitted separately — the right move is to write it correctly the first
time.

Entries 19 and 20 (IMDS realm detection, removing the hardcoded realm map) are
largely obsoleted by `7f1753c`. The provider's `full_path` is realm-correct on
its own, so most of that machinery should never reach upstream.

`local` entries stay in the fork.
