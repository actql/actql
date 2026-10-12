///|
// The acquisition owner retains the common resolved Catalog/Host ceiling.
// Construction is not a data-count observation or read authorization.
priv struct RowListingRows {
  resolved : @environment.FileListingRows
}

///|
fn resolve_row_listing_rows(
  preparation : RowSourcePreparation,
  policy : @capacity.Policy?,
) -> Result[RowListingRows?, RowSourceIssue] {
  guard preparation.file_listing is Some(profile) else { return Ok(None) }
  @environment.resolve_file_listing_rows(
    profile,
    policy,
    "file-listing:" + @planning.query_requirement_cid(preparation.requirement),
  )
  .map(resolved => Some({ resolved, }))
  .map_err(_ => ListingLimitUnresolved("max_listing_items"))
}

///|
fn listing_rows_maximum(value : RowListingRows) -> Int64 {
  @environment.file_listing_rows_maximum(value.resolved)
}
