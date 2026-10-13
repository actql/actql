///|
// Production Row page/admission/finish functions with an independent
// ReferenceIssuer fixture. This does not prove Source authority, installed
// capacity or Store acknowledgement. The same Array/captured scan is tested.
test "listing terminal clear transfers exact reports once without rewriting raw duplicate cells" {
  let storage = new_row_listing_reports()
  let read = selection_read_fixture(
    ExactPaths(["a.csv"]),
    reports=Some(storage),
  )
  let raw = "Text/Plain;Label=\"é\""
  let row = selection_row("d", "a.csv", version="9007199254740993").replace(
    old="\"media_type\":null",
    new="\"media_type\":" + Json::string(raw).stringify(),
  )
  assert_eq(
    selection_accept(read, "[" + row + "]", None, Some("next"), 1).unwrap(),
    1,
  )
  let progress = read.listing.unwrap()
  let original_cells = progress.observations
    .get(
      "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
    )
    .unwrap()
  assert_true(
    listing_named_cell(read, original_cells, "media_type")
    is Some({ value: @admitted.Text(actual), .. }) &&
    actual == raw,
  )
  let original_array = storage.rows.unwrap()
  assert_eq(original_array.length(), 1)
  assert_eq(original_array[0].row_ordinal, 0)
  assert_eq(
    original_array[0].resource_ref_cid,
    "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
  )
  assert_eq(original_array[0].version, Some("9007199254740993"))
  assert_eq(original_array[0].reported_media_type, Some(raw))
  assert_eq(original_array[0].media_type, Some("text/plain;label=\"é\""))
  assert_false(progress.complete)
  // A repeated physical observation is not another selected occurrence.
  assert_eq(
    selection_accept(read, "[" + row + "]", Some("next"), Some("end"), 7).unwrap(),
    0,
  )
  assert_eq(storage.rows.unwrap().length(), 1)
  assert_eq(selection_accept(read, "[]", Some("end"), None, 1).unwrap(), 0)
  assert_true(progress.complete)
  assert_eq(progress.observations.length(), 0)
  assert_true(physical_equal(original_array, storage.rows.unwrap()))
  let scan = finish_row_source_read(read).unwrap()
  assert_true(physical_equal(scan, storage.scan.unwrap()))
  assert_eq(@execution.captured_row_count(scan), 1)
  assert_true(
    @execution.captured_presence_cell(
      scan,
      0,
      read.columns.search("media_type").unwrap(),
    )
    is Ok(@execution.Present(@admitted.Text(value))) &&
    value == "text/plain;label=\"é\"",
  )
  assert_true(finish_row_source_read(read) is Err(Closed))
  assert_true(finish_row_listing_reports(read, scan) is Err(ListingProtocol))
  assert_true(physical_equal(original_array, storage.rows.unwrap()))
  assert_true(reclaim_row_listing_reports(storage, 1))
  assert_true(storage.rows is None && storage.scan is None)
}

///|
test "listing excluded metadata still validates and raw-equivalent projection is not duplicate equality" {
  let excluded = new_row_listing_reports()
  let read = selection_read_fixture(
    ExactPaths(["a.csv"]),
    reports=Some(excluded),
  )
  let malformed = selection_row("d", "ignored.csv").replace(
    old="\"media_type\":null",
    new="\"media_type\":\"not a media type\"",
  )
  assert_true(
    selection_accept(read, "[" + malformed + "]", None, None, 1)
    is Err(Value("media_type")),
  )
  assert_eq(read.rows, 0L)
  assert_false(read.open)
  assert_eq(excluded.rows.unwrap().length(), 0)
  assert_true(excluded.scan is None)
  assert_true(reclaim_row_listing_reports(excluded, 1))
  let collision = new_row_listing_reports()
  let read = selection_read_fixture(
    ExactPaths(["a.csv"]),
    reports=Some(collision),
  )
  let first = selection_row("d", "a.csv").replace(
    old="\"media_type\":null",
    new="\"media_type\":\"Text/Plain\"",
  )
  let second = selection_row("d", "a.csv").replace(
    old="\"media_type\":null",
    new="\"media_type\":\"text/plain\"",
  )
  assert_eq(
    selection_accept(read, "[" + first + "]", None, Some("next"), 1).unwrap(),
    1,
  )
  assert_true(
    selection_accept(read, "[" + second + "]", Some("next"), None, 1)
    is Err(ListingConflictingResource("metadata")),
  )
  // Even though both project to text/plain, only the original raw observation
  // participates in duplicate equality. No complete scan exists on failure.
  assert_eq(collision.rows.unwrap().length(), 1)
  assert_true(collision.scan is None)
  assert_eq(collision.rows.unwrap()[0].reported_media_type, Some("Text/Plain"))
  assert_false(read.open)
  assert_true(reclaim_row_listing_reports(collision, 1))
}

///|
test "listing report cancellation keeps partial custody and sliced cleanup severs backing references" {
  let storage = new_row_listing_reports()
  let read = selection_read_fixture(AllFiles, reports=Some(storage))
  let first = selection_row("d", "a.csv")
  let second = selection_row("e", "b.csv")
  assert_eq(
    selection_accept(
      read,
      "[" + first + "," + second + "]",
      None,
      Some("more"),
      7,
    ).unwrap(),
    2,
  )
  let backing = storage.rows.unwrap()
  assert_true(cancel_row_source_read(read))
  assert_true(storage.scan is None)
  assert_true(physical_equal(backing, storage.rows.unwrap()))
  assert_eq(backing.length(), 2)
  assert_false(reclaim_row_listing_reports(storage, 0))
  assert_eq(backing.length(), 2)
  // The fixture explicitly exercises the existing owner's later cleanup,
  // not the cancellation request. One bounded step cannot retire both rows.
  assert_false(reclaim_row_listing_reports(storage, 1))
  assert_eq(backing.length(), 1)
  assert_eq(
    backing[0].resource_ref_cid,
    "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
  )
  assert_true(storage.rows is Some(_))
  assert_true(reclaim_row_listing_reports(storage, 1))
  assert_true(storage.rows is None && storage.scan is None)
  assert_eq(backing.length(), 0)
  assert_true(reclaim_row_listing_reports(storage, 1))
}

///|
test "explicit empty listing reports finish with zero requests while glob miss still observes pages" {
  let explicit = new_row_listing_reports()
  let read = selection_read_fixture(ExactPaths([]), reports=Some(explicit))
  assert_eq(read.listing.unwrap().attempts, 0L)
  assert_eq(read.pages, 0L)
  let scan = finish_row_source_read(read).unwrap()
  assert_eq(@execution.captured_row_count(scan), 0)
  assert_eq(explicit.rows.unwrap().length(), 0)
  assert_true(physical_equal(scan, explicit.scan.unwrap()))
  assert_true(reclaim_row_listing_reports(explicit, 1))
  let glob = new_row_listing_reports()
  let read = selection_read_fixture(
    GlobFiles(compile_listing_glob("*.pdf", 32).unwrap()),
    reports=Some(glob),
  )
  assert_eq(
    selection_accept(
      read,
      "[" + selection_row("d", "a.csv") + "]",
      None,
      None,
      1,
    ).unwrap(),
    0,
  )
  let scan = finish_row_source_read(read).unwrap()
  assert_eq(@execution.captured_row_count(scan), 0)
  assert_eq(glob.rows.unwrap().length(), 0)
  assert_eq(read.pages, 1L)
  assert_eq(read.listing.unwrap().attempts, 1L)
  assert_true(reclaim_row_listing_reports(glob, 1))
}
