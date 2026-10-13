///|
test "listing report count facts use the resolved selected ceiling and a distinct examined ceiling" {
  // Actual checked Catalog + Host policy resolution caps the declared three
  // selected rows at two. Examined observations remain nine, not two.
  let read = listing_read_fixture(policy=Some(listing_policy_fixture()))
  let progress = read.listing.unwrap()
  assert_eq(
    row_listing_report_bounds(progress.limits, progress.resolved_rows).unwrap(),
    (2L, 9L),
  )
  assert_eq(row_listing_maximum(progress, "max_listing_items").unwrap(), 2L)
  assert_eq(row_listing_maximum(progress, "max_examined_items").unwrap(), 9L)
  assert_eq(read.rows, 0L)
  assert_eq(progress.attempts, 0L)
  assert_eq(progress.work, 0)
  assert_false(progress.complete)
  assert_true(read.open)
  cancel_row_source_read(read) |> ignore
}

///|
test "listing report count facts reject missing and nonpositive examined bounds without repair" {
  let selected = listing_rows_fixture(Some(3L), Some(listing_policy_fixture()))
  for limits in [
    [("max_listing_items", 3L)],
    [("max_examined_items", 0L)],
    [("max_examined_items", -1L)],
  ] {
    assert_true(
      row_listing_report_bounds(limits, selected)
      is Err(ListingLimitUnresolved("max_examined_items")),
    )
  }
  assert_true(
    row_listing_report_bounds([("max_listing_items", 3L), ("max_examined_items", 9L)], None)
    is Err(ListingLimitUnresolved("max_listing_items")),
  )
  // A lower examined ceiling is a separate runtime enforcement obligation,
  // not grounds to reinterpret or raise the selected Catalog/Host bound.
  assert_eq(
    row_listing_report_bounds([("max_examined_items", 1L)], selected).unwrap(),
    (2L, 1L),
  )
}
