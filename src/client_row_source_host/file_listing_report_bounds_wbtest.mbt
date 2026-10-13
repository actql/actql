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
  for
    limits in [
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
    row_listing_report_bounds(
      [("max_listing_items", 3L), ("max_examined_items", 9L)],
      None,
    )
    is Err(ListingLimitUnresolved("max_listing_items")),
  )
  // A lower examined ceiling is a separate runtime enforcement obligation,
  // not grounds to reinterpret or raise the selected Catalog/Host bound.
  assert_eq(
    row_listing_report_bounds([("max_examined_items", 1L)], selected).unwrap(),
    (2L, 1L),
  )
}

///|
test "scalar listing limits borrow the same checked Catalog without candidate copy aliases" {
  let profile = listing_profile_fixture(Some(3L), examined=Some(9L)) catch {
    _ => abort("checked listing ceiling fixture")
  }
  assert_eq(
    @environment.file_listing_declared_limit(profile, "max_examined_items"),
    Some(9L),
  )
  // The scalar candidate remains declared three. It must not replace the
  // separate Catalog/Host witness that resolves selected rows to two.
  assert_eq(
    @environment.file_listing_declared_limit(profile, "max_listing_items"),
    Some(3L),
  )
  assert_eq(@environment.file_listing_declared_limit(profile, "missing"), None)
  let before = @environment.file_listing_facts_cid(profile)
  let copied = @environment.file_listing_limit_candidates(profile)
  for index in 0..<copied.length() {
    if copied[index].0 == "max_examined_items" {
      copied[index] = ("max_examined_items", 1L)
    }
  }
  // Mutation of an escaped candidate copy is not a mutation of its opaque
  // checked profile and cannot change the original acquisition's count fact.
  assert_eq(
    @environment.file_listing_declared_limit(profile, "max_examined_items"),
    Some(9L),
  )
  assert_eq(@environment.file_listing_facts_cid(profile), before)
  let absent = listing_profile_fixture(Some(3L)) catch {
    _ => abort("checked missing examined ceiling fixture")
  }
  assert_eq(
    @environment.file_listing_declared_limit(absent, "max_examined_items"),
    None,
  )
}
