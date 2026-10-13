///|
// Existing Row parser/admission/selection fixture only. The reference issuer
// is the independent test fixture, not real Source authorization or funding.
// Stop at the append transition so extraction borrows the actual page cells.
fn original_listing_report_fixture(row : String) -> RowSourceRead {
  let read = selection_read_fixture(ExactPaths(["a.csv"]))
  begin_row_listing_request(read, None, 0L).unwrap()
  begin_row_source_listing_page(read, listing_page("[" + row + "]", None, None), 0L).unwrap()
  for attempts = 0; attempts < 1000; attempts = attempts + 1 {
    if read.listing.unwrap().page is Some(page) && page.selected is Some(true) {
      return read
    }
    assert_true(advance_row_source_listing_page(read, 1, 0L) is Ok(ListingPageContinue(..)))
  }
  abort("selected original listing fixture")
}

///|
test "original listing report borrows exact Resource version and raw Unicode before projection" {
  for (reported, projected) in [
    ("Text/Plain;Label=\"é\"", "text/plain;label=\"é\""),
    ("Text/Plain;Label=\"é\"", "text/plain;label=\"é\""),
  ] {
    let wire = selection_row("d", "a.csv", version="9007199254740993").replace(
      old="\"media_type\":null",
      new="\"media_type\":" + Json::string(reported).stringify(),
    )
    let read = original_listing_report_fixture(wire)
    let (report, cell) = row_listing_original_report(read).unwrap()
    assert_eq(report.row_ordinal, 0)
    assert_eq(report.resource_ref_cid,
      "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd")
    assert_eq(report.version, Some("9007199254740993"))
    assert_eq(report.reported_media_type, Some(reported))
    assert_eq(report.media_type, Some(projected))
    assert_true(cell.value is @admitted.Text(value) && value == projected)
    // Extraction neither rewrites the original duplicate-law cells nor
    // appends a second row. The future funded transfer owns that transition.
    let original = listing_named_cell(read, read.listing.unwrap().page.unwrap().cells.unwrap(), "media_type").unwrap()
    assert_true(original.value is @admitted.Text(value) && value == reported)
    assert_true(physical_equal(cell.contract, original.contract))
    assert_eq(read.rows, 0L)
    cancel_row_source_read(read) |> ignore
    assert_true(row_listing_original_report(read) is Err(ListingProtocol))
  }
}

///|
test "original listing NULL report differs from missing evidence and malformed report" {
  let nullable = original_listing_report_fixture(selection_row("d", "a.csv"))
  let (report, cell) = row_listing_original_report(nullable).unwrap()
  assert_eq(report.reported_media_type, None)
  assert_eq(report.media_type, None)
  assert_true(cell.value is @admitted.Null)
  let cells = nullable.listing.unwrap().page.unwrap().cells.unwrap()
  cells[nullable.columns.search("media_type").unwrap()] = None
  assert_true(row_listing_original_report(nullable) is Err(Value("media_type")))
  cancel_row_source_read(nullable) |> ignore
  let malformed = original_listing_report_fixture(selection_row("d", "a.csv").replace(
    old="\"media_type\":null", new="\"media_type\":\"not a media type\""))
  assert_true(row_listing_original_report(malformed) is Err(Value("media_type")))
  cancel_row_source_read(malformed) |> ignore
  // This row will not match the selector. Its already-admitted nullable Text
  // still cannot bypass the common descriptor's mandatory metadata validation.
  let excluded = selection_read_fixture(ExactPaths(["a.csv"]))
  let excluded_wire = selection_row("d", "ignore.txt").replace(
    old="\"media_type\":null", new="\"media_type\":\"not a media type\"")
  begin_row_listing_request(excluded, None, 0L).unwrap()
  begin_row_source_listing_page(excluded, listing_page("[" + excluded_wire + "]", None, None), 0L).unwrap()
  assert_true(advance_row_source_listing_page(excluded, 1, 0L) is Ok(ListingPageContinue(..)))
  assert_true(excluded.listing.unwrap().page.unwrap().selected is None)
  assert_true(row_listing_media_projection(excluded) is Err(Value("media_type")))
  assert_eq(excluded.rows, 0L)
  cancel_row_source_read(excluded) |> ignore
}

///|
test "original listing report is unavailable before selection for duplicates and after retirement" {
  let read = selection_read_fixture(ExactPaths(["a.csv"]))
  assert_true(row_listing_original_report(read) is Err(ListingProtocol))
  cancel_row_source_read(read) |> ignore
  let selected = original_listing_report_fixture(selection_row("d", "a.csv"))
  selected.listing.unwrap().page.unwrap().duplicate = true
  assert_true(row_listing_original_report(selected) is Err(ListingProtocol))
  cancel_row_source_read(selected) |> ignore
  assert_true(row_listing_original_report(selected) is Err(ListingProtocol))
}

///|
test "original listing correlation rejects reassignment of any closed report field" {
  let wire = selection_row("d", "a.csv", version="9007199254740993").replace(
    old="\"media_type\":null",
    new="\"media_type\":\"Text/Plain;Label=\\\"é\\\"\"",
  )
  let read = original_listing_report_fixture(wire)
  // Independent data oracle, not a record returned by the product extractor.
  let expected : @publication.CompletedFileListingReportRow = {
    row_ordinal: 0,
    resource_ref_cid: "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    version: Some("9007199254740993"),
    reported_media_type: Some("Text/Plain;Label=\"é\""),
    media_type: Some("text/plain;label=\"é\""),
  }
  check_row_listing_original_report(read, expected).unwrap()
  for changed in [
    { ..expected, row_ordinal: 1, },
    {
      ..expected,
      resource_ref_cid: "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
    },
    { ..expected, version: Some("9007199254740992"), },
    { ..expected, version: None, },
    { ..expected, reported_media_type: None, },
    { ..expected, media_type: None, },
    { ..expected, reported_media_type: Some("text/plain;label=\"é\""), },
    { ..expected, reported_media_type: Some("Text/Plain;Label=\"é\""), },
    { ..expected, media_type: Some("text/plain;label=\"é\""), },
  ] {
    assert_true(check_row_listing_original_report(read, changed) is Err(ListingProtocol))
    // A rejected correlation cannot consume/reorder the actual input row.
    assert_eq(read.rows, 0L)
    check_row_listing_original_report(read, expected).unwrap()
  }
  read.listing.unwrap().page.unwrap().duplicate = true
  assert_true(check_row_listing_original_report(read, expected) is Err(ListingProtocol))
  read.listing.unwrap().page.unwrap().duplicate = false
  cancel_row_source_read(read) |> ignore
  assert_true(check_row_listing_original_report(read, expected) is Err(ListingProtocol))
}
