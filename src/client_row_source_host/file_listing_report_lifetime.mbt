///|
// Data backing in the existing Row configuration/read/capture, not a new
// owner, resource token or completion authority. The actual Row/Query states
// still decide availability. It is allocated only under the Source envelope.
priv struct RowListingReports {
  mut rows : Array[@publication.CompletedFileListingReportRow]?
  mut scan : @execution.CapturedRows?
  empty : @publication.CompletedFileListingReportRow
  mut original_configuration : RowHostConfiguration?
}

///|
fn new_row_listing_reports() -> RowListingReports {
  {
    rows: Some([]),
    scan: None,
    original_configuration: None,
    // This invalid data sentinel only severs non-JS backing references before
    // pop. It is never admitted, encoded, returned or used as evidence.
    empty: {
      row_ordinal: -1,
      resource_ref_cid: "",
      version: None,
      reported_media_type: None,
      media_type: None,
    },
  }
}

///|
fn row_read_listing_reports(read : RowSourceRead) -> RowListingReports? {
  guard read.listing is Some(progress) &&
    progress.resolved_rows is Some(ReportListingRows(_, reports)) else {
    return None
  }
  Some(reports)
}

///|
// Validate every admitted report, even for excluded rows. Original cells are
// never replaced in the duplicate Map. Only the checked input append receives
// a separate seven-reference copy with its projected media cell.
fn append_row_listing_report(
  read : RowSourceRead,
  reports : RowListingReports,
  cells : Array[@admitted.CheckedValue?],
) -> Result[Unit, RowSourceIssue] {
  guard reports.rows is Some(rows) &&
    reports.scan is None &&
    read.rows == rows.length().to_int64() &&
    read.columns.search("media_type") is Some(media) else {
    return Err(ListingProtocol)
  }
  let (report, projected) = match row_listing_original_report(read) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let input_cells = cells.copy()
  input_cells[media] = Some(projected)
  match
    append_row_source_cells(
      read.input,
      read.schema,
      input_cells,
      read.retention,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  rows.push(report)
  Ok(())
}

///|
// The original reader may perform this transfer only once at its actual
// finish transition. The same backing remains reachable through the capture
// configuration; no receiving Array or provider metadata is reconstructed.
fn finish_row_listing_reports(
  read : RowSourceRead,
  scan : @execution.CapturedRows,
) -> Result[Unit, RowSourceIssue] {
  guard row_read_listing_reports(read) is Some(reports) else { return Ok(()) }
  guard !read.open &&
    reports.scan is None &&
    reports.rows is Some(rows) &&
    read.listing is Some(progress) &&
    progress.complete &&
    read.rows == rows.length().to_int64() &&
    @execution.captured_row_count(scan).to_int64() == read.rows else {
    return Err(ListingProtocol)
  }
  reports.scan = Some(scan)
  Ok(())
}

///|
// Called only after the existing Row child/transport cleanup confirms. Cancel,
// terminal listing or callback return cannot call this as retirement. Remove
// each owned record before shrinking so non-JS backing retains no old value.
fn reclaim_row_listing_reports(
  reports : RowListingReports,
  quantum : Int,
) -> Bool {
  guard reports.rows is Some(rows) else { return true }
  if quantum <= 0 {
    return false
  }
  let mut remaining = quantum
  while remaining > 0 && !rows.is_empty() {
    rows[rows.length() - 1] = reports.empty
    rows.pop() |> ignore
    remaining -= 1
  }
  if !rows.is_empty() {
    return false
  }
  reports.scan = None
  reports.original_configuration = None
  reports.rows = None
  true
}
