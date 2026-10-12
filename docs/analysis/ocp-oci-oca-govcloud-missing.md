# Oracle Cloud Agent (OCA) Unavailable in OCI Gov Cloud

## Summary

The OCI Marketplace Listing API is **not available** in OCI Gov Cloud (realm `oc3`, region `us-gov-ashburn-1`). This means the Oracle Cloud Agent (OCA) container image cannot be resolved via the Marketplace, and the upstream `oracle-quickstart/oci-openshift` terraform will fail during `terraform apply` if the OCA module is not gated.

## What is OCA?

Oracle Cloud Agent is a **privileged DaemonSet** deployed onto OpenShift nodes. It provides:

- iSCSI volume management (attach/detach/mount block volumes)
- OS Management (patching, compliance reporting)
- Monitoring and metrics collection

OCA runs as a **container** pulled from OCI Container Registry (OCIR). The terraform stack uses the Marketplace API to discover the correct OCA image version, then constructs an OCIR pull URL for the DaemonSet manifest (`custom_manifests/manifests/06-oci-oca.yml`).

## The Problem

The upstream terraform stack (`shared_modules/ocir/main.tf`) calls `oci_marketplace_listing_packages` with a **hardcoded commercial-realm listing OCID**:

```
ocid1.mktpublishing.oc1.phx.amaaaaaabg7vt6ia6vyockkduxg2jvwmxzef7nliwilshjavyjrybs66g57q
```

This OCID is scoped to the commercial realm (`oc1`). In Gov Cloud (`oc3`), this call fails because:

1. Marketplace listing OCIDs are **realm-scoped** and not cross-realm portable
2. The Gov Cloud Marketplace API endpoint itself returns **404 NotAuthorizedOrNotFound**

## Evidence

Tested from the bastion in Gov Cloud on 2025-08-11:

```bash
oci marketplace listing list \
  --name "Oracle Cloud Agent" \
  --region us-gov-ashburn-1 \
  --debug
```

Response:

```
GET https://marketplace.us-gov-ashburn-1.oci.oraclegovcloud.com/20181001/listings
→ 404 NotAuthorizedOrNotFound
```

The entire Marketplace Listing API returned 404 — not just the OCA listing. A name-based lookup (`oci_marketplace_listings` data source) would also fail because the underlying API endpoint does not respond.

## Terraform Error

Without the fix, `terraform apply` fails with:

```
Error: 404-NotAuthorizedOrNotFound, Authorization failed or requested resource not found.
│ Suggestion: Either the resource has been deleted or service Marketplace Listing Package need policy to access this resource.
│
│   with module.ocir.data.oci_marketplace_listing_packages.marketplace_listing_packages
```

This error was previously masked because the `module "ocir"` ran unconditionally but its output was only consumed when `use_oracle_cloud_agent = true`. The timing of the failure depended on terraform's execution order, which is why it did not surface on every run.

## Fix Applied (fork: oci-openshift-mine)

Four changes gate the OCA module so it only runs when explicitly enabled:

### 1. `create-cluster/main.tf` — Conditional module instantiation

```hcl
module "ocir" {
  source = "./shared_modules/ocir"
  count  = var.use_oracle_cloud_agent ? 1 : 0
  # ...
  oca_marketplace_listing_id = var.oca_marketplace_listing_id
}
```

And the downstream reference:

```hcl
oca_image_pull_link = var.use_oracle_cloud_agent ? module.ocir[0].image_pull_command : ""
```

### 2. `create-cluster/variables.tf` — New variable for listing OCID

```hcl
variable "oca_marketplace_listing_id" {
  description = "OCI Marketplace listing OCID for the Oracle Cloud Agent. Default is commercial (oc1). Gov Cloud (oc3) requires the listing OCID from its own marketplace."
  type        = string
  default     = "ocid1.mktpublishing.oc1.phx.amaaaaaabg7vt6ia6vyockkduxg2jvwmxzef7nliwilshjavyjrybs66g57q"
}
```

### 3. `shared_modules/ocir/variables.tf` — Accept listing OCID as input

```hcl
variable "oca_marketplace_listing_id" {
  type = string
}
```

### 4. `shared_modules/ocir/main.tf` — Use variable instead of hardcoded OCID

```hcl
data "oci_marketplace_listing_packages" "marketplace_listing_packages" {
  listing_id = var.oca_marketplace_listing_id
}
```

## Impact

With `use_oracle_cloud_agent = false` (the default), the Marketplace API is never called and the terraform stack deploys successfully in Gov Cloud. OCA is not deployed as a DaemonSet — iSCSI management, OS management, and OCI monitoring features provided by OCA are unavailable.

For Gov Cloud deployments using paravirtualized (non-iSCSI) storage, OCA is not required. If OCA becomes available in Gov Cloud in the future, the `oca_marketplace_listing_id` variable can be set to the Gov Cloud listing OCID.

## Upstream Consideration

The `count` gate and parameterized listing OCID would be a reasonable upstream contribution to `oracle-quickstart/oci-openshift` to support multi-realm deployments without hardcoding commercial-only assumptions.
