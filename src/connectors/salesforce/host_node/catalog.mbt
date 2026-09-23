///|
pub(all) suberror SalesforceCatalogBridgeIssue {
  Listing(@catalog.ListingIssue)
  Sync(@catalog.CatalogSyncIssue)
  InvalidResource
}

///|
#export_name("salesforceProjectListing")
pub fn salesforce_project_listing(
  bytes : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_resources : Int,
  max_selected : Int,
  max_name_units : Int,
) -> @catalog.ResourceListing raise SalesforceCatalogBridgeIssue {
  match
    @catalog.project_resource_listing(bytes, {
      max_bytes,
      max_nodes,
      max_depth,
      max_resources,
      max_selected,
      max_name_units,
    }) {
    Ok(value) => value
    Err(issue) => raise Listing(issue)
  }
}

///|
#export_name("salesforceCatalogBegin")
pub fn salesforce_catalog_begin(
  listing : @catalog.ResourceListing,
) -> @catalog.CatalogSync {
  @catalog.begin_catalog_sync(listing)
}

///|
#export_name("salesforceCatalogNext")
pub fn salesforce_catalog_next(sync : @catalog.CatalogSync) -> String? {
  @catalog.catalog_sync_next(sync)
}

///|
#export_name("salesforceCatalogDescribe")
pub fn salesforce_catalog_describe(
  sync : @catalog.CatalogSync,
  name : String,
  bytes : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_fields : Int,
  max_name_units : Int,
) -> Bool raise SalesforceCatalogBridgeIssue {
  match
    @catalog.catalog_sync_describe(sync, name, bytes, {
      max_bytes,
      max_nodes,
      max_depth,
      max_fields,
      max_name_units,
    }) {
    Ok(_) => true
    Err(Describe(_)) => false
    Err(issue) => raise Sync(issue)
  }
}

///|
#export_name("salesforceCatalogUnavailable")
pub fn salesforce_catalog_unavailable(
  sync : @catalog.CatalogSync,
  name : String,
  reason : Int,
) -> Bool raise SalesforceCatalogBridgeIssue {
  let failure = match reason {
    0 => @catalog.DescribeFailure::PermissionDenied
    1 => RateLimited
    2 => ProviderUnavailable
    3 => TransportInterrupted
    4 => InvalidMetadata
    5 => Cancelled
    _ => raise InvalidResource
  }
  match @catalog.catalog_sync_unavailable(sync, name, failure) {
    Ok(_) => true
    Err(issue) => raise Sync(issue)
  }
}

///|
#export_name("salesforceCatalogCancel")
pub fn salesforce_catalog_cancel(
  sync : @catalog.CatalogSync,
) -> Bool raise SalesforceCatalogBridgeIssue {
  match @catalog.cancel_catalog_sync(sync) {
    Ok(_) => true
    Err(issue) => raise Sync(issue)
  }
}

///|
#export_name("salesforceCatalogFinish")
pub fn salesforce_catalog_finish(
  sync : @catalog.CatalogSync,
) -> Bool raise SalesforceCatalogBridgeIssue {
  match @catalog.finish_catalog_sync(sync) {
    Ok(_) => @catalog.catalog_sync_is_complete(sync)
    Err(issue) => raise Sync(issue)
  }
}

///|
#export_name("salesforceCatalogResourceState")
pub fn salesforce_catalog_resource_state(
  sync : @catalog.CatalogSync,
  name : String,
) -> Int {
  match @catalog.catalog_sync_outcome(sync, name) {
    Some(@catalog.ResourceDescribeOutcome::Pending) => 0
    Some(Described(_)) => 1
    Some(Unavailable(failure)) =>
      match failure {
        PermissionDenied => 2
        RateLimited => 3
        ProviderUnavailable => 4
        TransportInterrupted => 5
        InvalidMetadata => 6
        Cancelled => 7
      }
    None => -1
  }
}

///|
#export_name("salesforceCatalogResourceNames")
pub fn salesforce_catalog_resource_names(
  listing : @catalog.ResourceListing,
) -> Array[String] {
  let names = []
  for resource in listing.selected {
    names.push(resource.name)
  }
  names
}

///|
#export_name("salesforceCatalogHttpFailure")
pub fn salesforce_catalog_http_failure(
  status : Int,
  body : Bytes,
  max_body_bytes : Int,
) -> Int {
  match @catalog.catalog_http_failure(status, body, max_body_bytes) {
    PermissionDenied => 0
    RateLimited => 1
    ProviderUnavailable => 2
    TransportInterrupted => 3
    InvalidMetadata => 4
    Cancelled => 5
  }
}
