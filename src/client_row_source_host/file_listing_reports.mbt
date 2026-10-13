///|
// Borrow only the actual selected, admitted page row at its append transition.
// A caller-authored record/ordinal cannot replace this read's original report.
// This is private DATA projection. Its result grants no capture completion,
// custody, retention budget or Source/Content access authority. The funded
// single-transfer caller must keep this result in the same Row capture lifetime.
fn row_listing_original_report(
  read : RowSourceRead,
) -> Result[
  (@publication.CompletedFileListingReportRow, @admitted.CheckedValue),
  RowSourceIssue,
] {
  guard read.open &&
    read.listing is Some(progress) &&
    progress.selection is Some(_) &&
    progress.page is Some(page) &&
    page.selected is Some(true) &&
    !page.duplicate &&
    page.cells is Some(cells) &&
    read.rows >= 0L && read.rows <= 2147483647L else {
    return Err(ListingProtocol)
  }
  guard listing_named_cell(read, cells, "resource")
    is Some({ value: @admitted.Reference(resource), .. }) &&
    @admitted.reference_available(resource) else {
    return Err(Value("resource"))
  }
  let version = match listing_named_cell(read, cells, "version") {
    Some({ value: @admitted.Text(value), .. }) => Some(value)
    Some({ value: @admitted.Null, .. }) => None
    _ => return Err(Value("version"))
  }
  let (reported, projected, cell) = match row_listing_media_projection(read) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok((
    {
      row_ordinal: read.rows.to_int(),
      resource_ref_cid: @admitted.reference_identity_cid(resource),
      version,
      reported_media_type: reported,
      media_type: projected,
    },
    cell,
  ))
}

///|
// The funded admission caller validates this before selection/duplicate
// handling, including excluded rows. Selection cannot replace mandatory
// metadata admission. Keep the raw cells unchanged for the exact duplicate
// law; only the future append transition uses the returned projected cell.
fn row_listing_media_projection(
  read : RowSourceRead,
) -> Result[(String?, String?, @admitted.CheckedValue), RowSourceIssue] {
  guard read.open &&
    read.listing is Some(progress) &&
    progress.selection is Some(_) &&
    progress.page is Some(page) &&
    page.cells is Some(cells) else {
    return Err(ListingProtocol)
  }
  guard listing_named_cell(read, cells, "media_type") is Some(original) else {
    return Err(Value("media_type"))
  }
  match original.value {
    @admitted.Text(value) => {
      let projected = match
        @contract.normalize_content_media_type_case(value, read.page_limits.max_bytes) {
        Ok(value) => value
        Err(_) => return Err(Value("media_type"))
      }
      guard @admitted.text_value(projected, read.values.max_text_bytes)
        is Some(projected_value) &&
        @admitted.recheck_runtime_value(projected_value, original.contract, read.values)
        is Some(checked) else {
        return Err(Value("media_type"))
      }
      Ok((Some(value), Some(projected), checked))
    }
    @admitted.Null => Ok((None, None, original))
    _ => Err(Value("media_type"))
  }
}
