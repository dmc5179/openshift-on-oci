# Fork change inventory

Every change made to `dmc5179/oci-openshift` since forking from
`oracle-quickstart/oci-openshift`, classified by concern so the work can be
submitted upstream as small, scoped PRs.

- **Fork point:** `008a531` (upstream Release v1.6.0, 2026-07-30)
- **Upstream baseline merged into `disconnected`:** `4944984` (v1.6.1), merged
  2026-10-14, tagged `upstream-merge/v1.6.1`
- **Latest upstream:** `8bed062` (v1.6.2, 2026-10-22), merged into
  `disconnected` as `0397ff0` on 2026-11-07; see [v1.6.2](#upstream-v162) below.
- **Working branch:** `disconnected`
- **Frozen:** `oc3-support` at `40c6221`, tagged `archive/oc3-support-pr88` —
  the state submitted as PR #88, now closed

Entries 1–33 exist under two SHAs because `oc3-support` was rebased from
`disconnected`. Both are listed; `disconnected` is authoritative.

Last refreshed 2026-10-30.

## Categories

| Tag | Meaning | Upstream? |
|---|---|---|
| `airgap` | Disconnected / mirroring. Realm-agnostic. | Yes |
| `realm` | Any non-commercial realm — OC3, OC6 and others. | Yes |
| `oc3` | Gov Cloud specific. | Yes |
| `oc6` | Isolated realm specific. | Yes |
| `upstream-fix` | Plain bug or gap in Oracle's code, nothing to do with realms. | Yes — submit first |
| `tooling` | Scripts and docs that support the disconnected workflow: bundling, testing, checklists. Kept in the fork until the code they describe is upstream. | Yes, later |
| `local` | Specific to our environment or our debugging. | No |

`tooling` was split out of `local` on 2026-10-30. The fork is meant to be
self-contained and flow upstream, so docs and scripts that would help anyone
deploying disconnected are no longer assumed to stay here.

## Inventory

| # | Change | disconnected | oc3-support | Category | Upstream status |
|---|---|---|---|---|---|
| 1 | Collapse webserver and bastion into one host | `d8385d4` | `8865e3b` | `airgap` | Plan PR 7, not submitted (waits on #95) |
| 2 | Enable FIPS on the cluster | `3dfc4ad` | `a3713af` | `upstream-fix` | [#98](https://github.com/oracle-quickstart/oci-openshift/pull/98) |
| 3 | Bastion preflight validation script | `4695a71` | — | `tooling` | not submitted |
| 4 | imageDigestSources + additionalTrustBundle | `e90e745` | `5a3656e` | `airgap` | [#94](https://github.com/oracle-quickstart/oci-openshift/pull/94) |
| 5 | Remove webserver references (PXE concept, invalid on OCI) | `cf266d9` | `ba41d91` | `upstream-fix` | Plan PR 7, not submitted (waits on #95) |
| 6 | Output manifests individually, not one multi-doc YAML | `03b67b2` | `4a9ace6` | `upstream-fix` | [#91](https://github.com/oracle-quickstart/oci-openshift/pull/91) **closed 2026-11-10**: premise false, see note below |
| 7 | Ignore terraform state files | `6590951` | `dca3b82` | `local` | n/a |
| 8 | Disable OCA by default in Gov Cloud (no marketplace) | `010308c` | `abe509e` | `oc3` | Reworked as [#100](https://github.com/oracle-quickstart/oci-openshift/pull/100) |
| 9 | Example `imageset-config.yaml` for oc-mirror | `d93fe86` | `536e71a` | `airgap` | [#99](https://github.com/oracle-quickstart/oci-openshift/pull/99) |
| 10 | Deployment container image (Containerfile, build script) | `34af3e5` `77e45f9` `f14950d` `433e2e2` `d323573` `302079f` `13cb4a3` `c403c60` | — | `local` | **Removed** in `881ca27` |
| 11 | Secrets operator / OCI Vault integration | `c85cbf4` | `8695f8d` | `upstream-fix` | Split: imageset part in #99; Vault part parked (12b) |
| 12 | Non-commercial realm support — templatize CCM, realm endpoints, OCIR domain | `db3b2ca` | `d53e4d7` | `realm` | [#96](https://github.com/oracle-quickstart/oci-openshift/pull/96) |
| 13 | Host rootfs in Object Storage for minimal ISO | `b6f3599` | `b28b4a5` | `airgap` | [#95](https://github.com/oracle-quickstart/oci-openshift/pull/95) |
| 14 | Follow-up to rootfs hosting | `fcecaad` | `c6cac0a` | `airgap` | [#95](https://github.com/oracle-quickstart/oci-openshift/pull/95) |
| 15 | Helper scripts + tfvars gitignore | `46999f0` | `7bef4d9` `35ec7b0` | `tooling` | not submitted |
| 16 | OC6 quickstart doc | `dc6be10` | — | `oc6` | not submitted |
| 17 | Rename `rootfs_storage` → `boot_artifacts`, add ISO upload | `bc74c01` | `51351d3` | `airgap` | [#95](https://github.com/oracle-quickstart/oci-openshift/pull/95) |
| 18 | Docs for terraform-managed ISO upload | `af06e0d` | — | `tooling` | not submitted |
| 19 | Use IMDS `realmDomainComponent` as primary realm source | `0c3ae6f` | `59628ff` | `realm` | Largely obsoleted by #34; not submitted |
| 20 | Remove hardcoded realm domain map | `4eb103b` | `9366189` | `realm` | Largely obsoleted by #34; not submitted |
| 21 | CCM image source + `imageTagSources` | `4f54f3e` | `d1fedb5` | `airgap` | superseded by #24 |
| 22 | CCM image in static v1.34.0 manifest → official Oracle source | `9cb8b0c` | `8f1486d` | *reverted* | **REVERTED** by `6b71526` — see below |
| 23 | `additionalNTPSources` via agent-config (IMDS as NTP) | `a469082` | `7244c31` | `upstream-fix` | [#93](https://github.com/oracle-quickstart/oci-openshift/pull/93) |
| 24 | Generate `ImageTagMirrorSet` manifest | `40f0fb0` | `0f10990` | `airgap` | [#94](https://github.com/oracle-quickstart/oci-openshift/pull/94) |
| 25 | Align origin-cli to 4.22 | `c976eb2` | `2b7907b` | `upstream-fix` | [#92](https://github.com/oracle-quickstart/oci-openshift/pull/92) |
| 26 | Fix `additionalTrustBundle` indentation (invalid YAML) | `707b100` | `f26a276` | `upstream-fix` | Folded into #94 |
| 27 | Order boot artifact PARs after their object uploads | `164e81b` | `1b8aff2` | `upstream-fix` | Folded into #95 |
| 28 | origin-cli 4.22 in container-deployer doc | `d31af1b` | — | `local` | **Removed** with #10 |
| 29 | Document two-pass workflow in tfvars template | `d6d290d` | `4f3fe65` | `tooling` | not submitted |
| 30 | Boot artifact URLs instead of local paths (Resource Manager) | `d0491db` | `4427d80` | `airgap` | [#95](https://github.com/oracle-quickstart/oci-openshift/pull/95) |
| 31 | `upload-rootfs.sh` debugging helper | `b31c551` | — | `local` | n/a |
| 32 | Fail loudly on incomplete manifest extraction | `c947d16` | `40c6221` | `tooling` | not submitted |
| 33 | Mount additional_trust_bundle into the CCM and CSI pods | `99c5feb` | — | `upstream-fix` | [#97](https://github.com/oracle-quickstart/oci-openshift/pull/97) |
| 34 | Use the provider's `full_path` for PAR URLs | `7f1753c` | — | `airgap` | In [#95](https://github.com/oracle-quickstart/oci-openshift/pull/95); autoscaler half goes with PR 9 |
| 35 | Autoscaler air-gap: artifacts in Object Storage behind a PAR, parameterised fetches, ITMS for its images, bucket listing denied | `ac6c574` `b003540` `dfb4b0e` `a06d6ef` | — | `airgap` | Plan PR 9, **blocked on Oracle** |
| 36 | Doc: running terraform on a disconnected bastion | `775fae7` | — | `tooling` | not submitted |
| 37 | Offline terraform test in a UBI9 container | `e9bc42f` | — | `tooling` | not submitted |
| 38 | Offline bundle build and install scripts; test drives them | `9ea051a` | — | `tooling` | not submitted |
| 39 | Docs from the notes repo: imageset merge, enclave checklist, bastion setup, `private_registry` rule | `b202a36` | — | `tooling` | not submitted |
| 40 | Remove the deployer container; add the image mirror test; region metadata docs | `881ca27` | — | `tooling` | not submitted |
| — | Remove bastion doc from PR scope | — | `66129d6` | *drop* | PR housekeeping, obsolete |

## Notes on specific entries

**#6 / PR #91 rested on a wrong premise and was withdrawn on 2026-11-10.** The
Agent-based Installer does accept one multi-document file in `openshift/`:
tested with `openshift-install agent create image` 4.22.18, the stack's
`dynamic_custom_manifest` written to a single file with `terraform output
-raw` was split into 28 separate manifests in the agent ISO. Written
*without* `-raw`, Terraform wraps it in `<<EOT ... EOT` and the installer
fails with `could not decode YAML ... Error reading multiple YAMLs`, which is
the likely origin of the August finding in `03b67b2`. Red Hat's 4.21/4.22
docs also tell users to save that output as a single `manifest.yaml`. The
per-file outputs stay in the fork as a convenience; the fork docs that say
the installer needs one manifest per file are still to be corrected.


**#22 was reverted on 2026-10-14.** Oracle engineering confirmed the official
`ghcr.io/oracle/cloud-provider-oci:v1.34.0` is missing a required fix, and that
`ghcr.io/nikhisin3001/cloud-provider-oci:v1.34.0` must be used until a corrected
release ships. Commit `6b71526` restores the developer image across the
terraform image map, the static reference manifests and both example imagesets.

**Open question from v1.6.2 (found 2026-10-30).** Upstream v1.6.2 dropped the
developer image and maps `v1.34.0` to the official
`ghcr.io/oracle/cloud-provider-oci:v1.34.0` again. That tag has not been
re-published: it is still the image created 2026-03-23, while the developer
build is from 2026-04-01. So on v1.6.2, anyone who sets
`oci_driver_version = "v1.34.0"` gets the image Oracle said lacks the fix. The
new default, v1.36.0, presumably includes it. Worth asking Oracle whether the
`v1.34.0` mapping is intended, before merging v1.6.2 into `disconnected`.

**#21 is superseded.** `imageTagSources` is not a valid InstallConfig field.
The CCM image source part of that commit still stands; the mirror mechanism was
replaced by #24.

**#2, #11, #23 apply to every OCI region.** FIPS, OCI Vault integration and the
NTP change each surfaced during Gov Cloud or OC6 work, but all three are useful
on commercial OCI, OC3 and OC6 alike.

**#33 is not OC6-specific, despite surfacing there.** It applies to any
OpenShift on OCI deployment where something the Oracle containers talk to is
fronted by a non-commercial CA — isolated realms, Gov Cloud, and on-premise
Compute Cloud@Customer or Private Cloud Appliance. `additionalTrustBundlePolicy:
Always` puts the CA on the node, which is why image pulls from a private
registry succeed, but CRI-O does not mount the host trust store into pods and
Oracle's manifests mount no CA bundle, so the CCM fails x509, nodes keep the
uninitialized taint, CNI never starts and the cluster cannot converge. Gated on
`additional_trust_bundle`, so connected installs are unaffected.

**#10 and #28 were removed on 2026-10-30.** Packaging the stack as a container
and running it from inside one did not work well. The offline bundle scripts
(#38) and the two tests (#37, #40) replace it.

**`tooling` entries depend on the code they describe.** The offline bundle,
the tests and the disconnected docs reference `private_registry`,
`additional_trust_bundle`, the boot artifacts module and so on. They can only
go upstream once #94, #95 and #97 have landed, and should go as one
docs-and-tooling PR rather than piecemeal.

## Upstream v1.6.2

`8bed062`, released 2026-10-22, merged into `disconnected` as `0397ff0` on
2026-11-07. Conflicts were in `custom_manifests/manifests/01-oci-{ccm,csi}.yml`,
`docs/STORAGE.md` and `shared_modules/manifest/locals.tf`, all from upstream
moving every driver version to `ghcr.io/oracle` images.

**Driver version: `disconnected` now uses v1.35.0**, not the developer
v1.34.0 build and not the stack default v1.36.0. Upstream's README maps
OpenShift 4.22 (Kubernetes 1.35; the OC3 cluster reports v1.35.6) to v1.35.0
and lists v1.36.0 against OpenShift 5.0 as a planned target. The v1.35.0
image (2026-06-17) is newer than the 2026-04-01 developer build that carried
the fix the official v1.34.0 lacks. The tfvars template sets it and the
imageset mirrors it. The open question to Oracle about v1.6.2 mapping
v1.34.0 to the unfixed image (Google Doc item 1) no longer blocks us.

Follow-on: v1.6.2 removed `07-configure-bm-vlan-mtu.yml`, so the
`manifest_machineconfig_bm_vlan_mtu` outputs and the required-manifest entry
in `generate-ocp-artifacts.sh` were removed in the merge. `a4f8280` then
brought the proxy rendering fix from #98, which `disconnected` lacked.
Both test scripts pass on the merged branch.

## Submission plan

Grouped into reviewable PRs and ordered so each lands before anything
depending on it. Upstream had no `imageDigestSources`, no
`additionalTrustBundle` and no PAR or boot-artifact handling at all; PR 1 is the
fix for that.

| # | PR | Why air-gap needs it | Entries | Depends on | Size | Status |
|---|---|---|---|---|---|---|
| 1 | Emit mirror config in install-config | Nothing pulls from a mirror without it | 4, 24 (26 folded in) | — | Medium | [#94](https://github.com/oracle-quickstart/oci-openshift/pull/94) |
| 2 | Host boot artifacts in Object Storage | A disconnected cluster cannot fetch the rootfs from the internet | 13, 14, 17, 30, 34 (27 folded in) | — | Medium | [#95](https://github.com/oracle-quickstart/oci-openshift/pull/95) |
| 3 | Mount the trust bundle into the CCM and CSI pods | Without it the CCM fails x509 behind a private CA | 33 | PR 1, PR 8 | Small | [#97](https://github.com/oracle-quickstart/oci-openshift/pull/97), stacked on #94 and #96 |
| 4 | Output manifests individually | — | 6 | — | Small | [#91](https://github.com/oracle-quickstart/oci-openshift/pull/91) **closed 2026-11-10**: the agent installer does take a combined file |
| 5 | NTP via additionalNTPSources | No public NTP in an enclave; clock skew breaks TLS | 23 | — | Small | [#93](https://github.com/oracle-quickstart/oci-openshift/pull/93) |
| 6 | origin-cli 4.20 → 4.22 | Mismatched tag 404s against a mirror | 25 | — | Trivial | [#92](https://github.com/oracle-quickstart/oci-openshift/pull/92) |
| 7 | Remove the webserver module | PXE concept that cannot work on OCI | 1, 5 | PR 2 | Small | Not submitted; waits on #95 |
| 8 | Non-commercial realm support | OC3/OC6 API endpoints differ | 12 | — | Medium | [#96](https://github.com/oracle-quickstart/oci-openshift/pull/96) |
| 9 | Autoscaler air-gap | Four runtime fetches from github.com | 35 | PR 2 | Large | **Blocked on Oracle**: clarifying questions delivered 2026-10-14, no answer |
| 10 | Fail clearly when the OCA image cannot be found | With OCA on, the stack renders a DaemonSet for a nonexistent image; in OC3 that is the normal outcome | 8 | — | Small | [#100](https://github.com/oracle-quickstart/oci-openshift/pull/100), from main. Reframed 2026-11-06: OCA is already off by default upstream and the OC3 lookup returns empty rather than failing, so the real bug is the `no-image-found` guard that never matches. Whether OCA will be published to the OC3 Marketplace is still open with Oracle (Google Doc item 4). |
| 11 | FIPS support | Commonly required alongside air-gap | 2 | — | Small | [#98](https://github.com/oracle-quickstart/oci-openshift/pull/98), with the proxy rendering fix |
| 12a | Example ImageSetConfiguration | Users have no list of what to mirror | 9, part of 11 | — | Small | [#99](https://github.com/oracle-quickstart/oci-openshift/pull/99), rebased on v1.6.2 |
| 12b | OCI Vault secrets operator | No air-gap justification | part of 11 | — | Small | **Parked** — see below |
| 13 | Disconnected docs and tooling | Bundle, tests, enclave checklist, bastion setup | 3, 15, 16, 18, 29, 32, 36–40 | PRs 1, 2, 3 | Medium | Not submitted; waits on the code it documents |

As of 2026-10-30 none of #91–#99 has had a human review; each carries `OCA
Required` and only the Oracle Contributor Agreement bot has commented. Issue
[#90](https://github.com/oracle-quickstart/oci-openshift/issues/90) (provider
pinning) has no replies.

### Why 12b (OCI Vault) is parked

Entry 11 was a single 6-line `operators:` stanza in `docs/imageset-config.yaml`.
On its own it is not usable:

- Red Hat's `secrets-store-csi-driver-operator` ships the CSI driver, not
  third-party providers. OCI Vault needs Oracle's separate provider DaemonSet,
  `ghcr.io/oracle/oci-secrets-store-csi-driver-provider:v0.5.1`. KCS 7146818
  documents users hitting exactly this with Azure.
- The provider's Helm chart is served from `oracle.github.io` — a runtime
  internet fetch, the same class of problem as the autoscaler in PR 9.
- The chart defaults to `secrets-store-csi-driver.install: true`, which would
  install the upstream sigs driver alongside the Red Hat operator.

Pick it back up as a complete change (operator + provider + chart handling) or
drop it.

### Found while testing, fixed in #98

`shared_modules/manifest/locals.tf` — the proxy heredoc is interpolated at the
end of the `cloudControllerManager` line and its body starts directly with
`proxy:`, so with `set_proxy = true` the two run together and the rendered
install-config does not parse. Pre-existing on upstream `main`. Folded into #98
as a second commit.

### Notes on grouping

Entries 26 (the `indent()` YAML bug) and 27 (PAR `depends_on`) fix code we
wrote, and upstream does not have that code, so they are folded into PRs 1
and 2.

Entries 19 and 20 (IMDS realm detection, removing the hardcoded realm map) are
largely obsoleted by #34. The provider's `full_path` is realm-correct on its
own, so most of that machinery should never reach upstream.
