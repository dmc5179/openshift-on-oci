# Upstream issue draft — OCI provider version is effectively unpinned

**Repository:** `oracle-quickstart/oci-openshift`
**Type:** GitHub issue (not yet filed)
**Verified against:** `upstream/main` at `4944984` (release v1.6.1, 2026-08-12)

Status: **drafted, not yet filed.**

---

## Title

Provider version constraints are unbounded and the lock file is gitignored, so `terraform init` is not reproducible

## Body

### Summary

Every stack declares `version = ">= 6.12.0"` for `oracle/oci` with no upper bound, and `.terraform.lock.hcl` is listed in `.gitignore`. Together these mean nothing pins the provider: two people running `terraform init` on the same commit, days apart, can get different major versions, and neither gets what the maintainers tested against.

The current published provider is **9.10.0** — three major versions above the declared floor.

### Detail

Twenty `.tf` files declare the provider. Nineteen use `>= 6.12.0`; one,
`terraform-stacks/shared_modules/webserver/main.tf`, uses `>= 5.38.0`. Terraform
resolves the highest constraint across the configuration, so the lower floor has
no practical effect today — but it indicates the constraints are not maintained
as a set.

`.gitignore:26` ignores `.terraform.lock.hcl`. The dependency lock file is
designed to be committed precisely so provider selection is reproducible across
machines and over time; ignoring it discards that guarantee.

### Why this matters in practice

We hit this deploying into disconnected OCI realms. Running `terraform init` on an
unmodified checkout resolved **9.9.0**, and by the time we revisited it a few days
later the registry had moved to **9.10.0**. A colleague initialising from the same
commit would therefore be running a different provider from us, with no signal that
anything had changed.

This is worse in air-gapped environments. Provider binaries are mirrored ahead of
time; an unbounded constraint makes it unclear which version to mirror, and a
version resolved at init time may simply not be present in the mirror.

Major version bumps also carry breaking changes by definition. A constraint of
`>= 6.12.0` asserts that every future major release is compatible, which is not a
claim the project can realistically stand behind.

### Suggested resolution

1. **Commit `.terraform.lock.hcl`** and drop it from `.gitignore`. This is the
   mechanism Terraform provides for exactly this problem, and it records the
   hashes needed for verification in mirrored environments.
2. **Bound the constraint**, for example `~> 6.12` to stay on 6.x, or an explicit
   range such as `>= 6.12.0, < 10.0.0` if the newer majors are known good. Either
   is more honest than an open upper bound.
3. **Make the constraints consistent** across all twenty files, including
   `shared_modules/webserver/main.tf`.
4. Optionally, **state the tested provider version** in the release notes, so
   consumers mirroring binaries know what to pull.

### Reproduction

```console
$ git clone https://github.com/oracle-quickstart/oci-openshift
$ cd oci-openshift/terraform-stacks/create-cluster
$ terraform init -backend=false
$ grep -A1 'oracle/oci' .terraform.lock.hcl
```

The resolved version depends on the date, not the commit.

---

## Notes for us (strip before filing)

- Both decisions are upstream's, not ours: `>= 6.12.0` is in `upstream/main`, and
  the lock-file ignore came in via upstream commit `3d04bc7`
  ("implement some vc best practices (#23)") — worth noting the irony gently, or
  not at all.
- Our fork inherits both. Committing a lock file locally would protect us
  regardless of whether upstream acts.
- Our `terraform validate` runs during the CA and autoscaler work executed against
  9.9.0. Anything we claim to have validated carries that caveat.
- File this separately from the Google Doc items — it is a plain repository-hygiene
  issue, unrelated to the realm and air-gap work, and should not be bundled with
  those.
