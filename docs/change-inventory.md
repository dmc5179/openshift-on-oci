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

**#32 is classified `local` but was in PR #88.** The helper scripts are our
tooling; whether Oracle wants them upstream is their call, not an assumption we
should bake in.

## Not yet in the inventory

Work identified but not implemented, so no commits exist yet:

- **CA injection for CCM and CSI pods** (`oc6`) — the OC6 non-commercial CA does
  not reach the Oracle-image containers, which fail with x509 against the OCI
  API. Tracked in the `ca-injection-ccm-csi` work state.
- **Autoscaler disconnected support** (`airgap`) — four runtime dependencies on
  public endpoints. Oracle has proposed a design; see
  `oracle-issues/oracle-issue-autoscaler-disconnected-oracle-response.txt` and
  the drafted clarifying questions alongside it.

## Suggested submission order

1. **`upstream-fix`** — #26, #27, #25, #6, #5. Small, uncontroversial, realm-agnostic, independently useful. Best first PR to rebuild review momentum.
2. **`realm`** — #12, #19, #20. Coherent story: support non-commercial realms. (#22 is no longer part of this group; it was reverted.)
3. **`airgap`** — #4, #9, #13, #14, #17, #21, #24, #29, #30, #1. The largest group; may need splitting again.
4. **`oc3` / `oc6`** — #8, #16, plus the CA injection work once done.

`local` entries stay in the fork.
