///|
// Keep selected report rows and examined observations in distinct domains.
// Missing finite bounds never become zero, infinity, or an observed count.
fn row_listing_report_bounds(
  limits : Array[(String, Int64)],
  resolved_rows : RowListingRows?,
) -> Result[(Int64, Int64), RowSourceIssue] {
  let selected = match
    row_listing_bound(limits, resolved_rows, "max_listing_items") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let examined = match
    row_listing_bound(limits, resolved_rows, "max_examined_items") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok((selected, examined))
}

///|
// Core-only count facts from the same checked acquisition. The trusted
// preparation may inspect these before allocating listing/report control.
// They do not construct that control, lend a Ledger, reserve bytes, authorize
// I/O or supply a normal physical profile. The result/control lifetime still
// belongs in the caller's existing funded preparation envelope.
pub fn row_acquisition_listing_report_bounds(
  value : RowAcquisition,
) -> Result[(Int64, Int64), RowSourceIssue] {
  guard value.preparation.file_listing is Some(profile) else {
    return Err(ForeignSource)
  }
  guard value.configuration.listing_rows is Some(resolved) else {
    return Err(ListingLimitUnresolved("max_listing_items"))
  }
  guard @environment.file_listing_declared_limit(profile, "max_examined_items")
    is Some(examined) else {
    return Err(ListingLimitUnresolved("max_examined_items"))
  }
  // No temporary candidate Array or raw profile-body reparsing. Selected
  // rows still come from the original Catalog/Host resolved witness.
  Ok((listing_rows_maximum(resolved), examined))
}
