///|
fn cursor_progress_test_page(wire : String) -> RowSourceProjectedJsonPage {
  project_row_source_typed_json_page(
    @utf8.encode(wire),
    ["items"],
    true,
    ["next"],
    4096,
    256,
    16,
    8,
    64,
  ).unwrap()
}

///|
test "portable cursor progress preserves empty and Unicode cursors until exact EOF" {
  let progress = prepare_row_source_cursor_progress(3, 3, 2, 2).unwrap()
  assert_false(row_source_cursor_has_next(progress))
  assert_true(row_source_cursor_next(progress) is Err(NoNextCursor))
  assert_eq(row_source_cursor_remaining_rows(progress, 0, 0).unwrap(), 2)
  let first = cursor_progress_test_page("{\"items\":[{}],\"next\":\"\"}")
  assert_false(
    advance_row_source_cursor_progress(progress, 0, 0, first, first).unwrap(),
  )
  assert_true(row_source_cursor_has_next(progress))
  assert_eq(row_source_cursor_next(progress).unwrap(), "")
  let second = cursor_progress_test_page("{\"items\":[],\"next\":\"é\"}")
  assert_false(
    advance_row_source_cursor_progress(progress, 1, 1, second, second).unwrap(),
  )
  assert_eq(row_source_cursor_next(progress).unwrap(), "é")
  let last = cursor_progress_test_page("{\"items\":[{},{}],\"next\":null}")
  assert_true(
    advance_row_source_cursor_progress(progress, 2, 1, last, last).unwrap(),
  )
  assert_false(row_source_cursor_has_next(progress))
  assert_true(
    row_source_cursor_remaining_rows(progress, 3, 3) is Err(Completed),
  )
}

///|
test "portable cursor progress uses transformed count but the original envelope cursor" {
  let progress = prepare_row_source_cursor_progress(4, 4, 2, 8).unwrap()
  let envelope = cursor_progress_test_page("{\"items\":[{}],\"next\":\"next\"}")
  let changed = cursor_progress_test_page("{\"items\":[{},{}]}")
  assert_false(
    advance_row_source_cursor_progress(progress, 0, 0, envelope, changed).unwrap(),
  )
  assert_eq(row_source_cursor_next(progress).unwrap(), "next")
  assert_eq(row_source_cursor_remaining_rows(progress, 1, 2).unwrap(), 2)
  assert_true(
    advance_row_source_cursor_progress(progress, 1, 2, envelope, changed)
    is Err(CursorCycle),
  )
  // Refused continuation did not mutate the original counters or replace EOF.
  assert_eq(row_source_cursor_remaining_rows(progress, 1, 2).unwrap(), 2)
  assert_eq(row_source_cursor_next(progress).unwrap(), "next")
  let last = cursor_progress_test_page("{\"items\":[{},{}]}")
  assert_true(
    advance_row_source_cursor_progress(progress, 1, 2, last, last).unwrap(),
  )
}

///|
test "portable cursor progress rejects limits and mismatched managed progress before mutation" {
  for
    (pages, rows, page_rows, cursor) in [
      (0, 1, 1, 0),
      (1, 0, 1, 0),
      (1, 1, 0, 0),
      (1, 1, 1, -1),
    ] {
    assert_true(
      prepare_row_source_cursor_progress(pages, rows, page_rows, cursor)
      is Err(InvalidLimits),
    )
  }
  let progress = prepare_row_source_cursor_progress(2, 3, 2, 0).unwrap()
  for (index, count) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
    assert_true(
      row_source_cursor_remaining_rows(progress, index, count)
      is Err(ProgressMismatch),
    )
  }
  let page = cursor_progress_test_page("{\"items\":[{}]}")
  let foreign = { ..page, origin: Ref(()), }
  assert_true(
    advance_row_source_cursor_progress(progress, 0, 0, foreign, page)
    is Err(ForeignPage),
  )
  assert_true(
    advance_row_source_cursor_progress(progress, 0, 0, page, foreign)
    is Err(ForeignPage),
  )
  assert_eq(row_source_cursor_remaining_rows(progress, 0, 0).unwrap(), 2)
  assert_true(
    advance_row_source_cursor_progress(progress, 0, 0, page, page).unwrap(),
  )
}

///|
test "portable cursor progress refuses cycle and finite continuation exhaustion" {
  let next = cursor_progress_test_page("{\"items\":[{}],\"next\":\"x\"}")
  let pages = prepare_row_source_cursor_progress(1, 4, 2, 1).unwrap()
  assert_true(
    advance_row_source_cursor_progress(pages, 0, 0, next, next)
    is Err(PageLimit),
  )
  let rows = prepare_row_source_cursor_progress(3, 1, 2, 1).unwrap()
  assert_true(
    advance_row_source_cursor_progress(rows, 0, 0, next, next) is Err(RowLimit),
  )
  let bytes = prepare_row_source_cursor_progress(3, 4, 2, 1).unwrap()
  let unicode = cursor_progress_test_page("{\"items\":[],\"next\":\"é\"}")
  assert_true(
    advance_row_source_cursor_progress(bytes, 0, 0, unicode, unicode)
    is Err(CursorLimit),
  )
  let too_many = cursor_progress_test_page("{\"items\":[{},{},{}]}")
  assert_true(
    advance_row_source_cursor_progress(bytes, 0, 0, too_many, too_many)
    is Err(RowLimit),
  )
  let last = cursor_progress_test_page("{\"items\":[]}")
  assert_true(
    advance_row_source_cursor_progress(pages, 0, 0, last, last).unwrap(),
  )
}
