///|
test "sealed mixed columns compose selections without row materialization" {
  let owner = row_owner("")
  let source : CompletedTable = ColumnTable({
    owner,
    id: "source",
    names: ["a", "b"],
    columns: [[Number(1), Number(2), Number(3)], [Text("x"), Null, Text("z")]],
    count: 3,
    selection: None,
  })
  let first = completed_selection(
    source,
    "first",
    [2, 0],
    { remaining: 2, max_frames: 0, },
    { limit: 2, live: 0, peak: 0, },
  ).unwrap()
  let second = completed_selection(
    first,
    "second",
    [1],
    { remaining: 1, max_frames: 0, },
    { limit: 1, live: 0, peak: 0, },
  ).unwrap()
  guard second is ColumnTable(table) else { fail("column table") }
  assert_eq(table.count, 1)
  assert_eq(table.selection, Some([0]))
  assert_true(IndexedRows::read_cell(second, 0, 0) is Number(1))
  assert_true(IndexedRows::read_cell(second, 0, 1) is Text("x"))
}

///|
test "mixed column storage reserves every retained buffer and selection" {
  let owner = row_owner("")
  let table : CompletedTable = ColumnTable({
    owner,
    id: "selected",
    names: ["a", "b"],
    columns: [[Number(1), Number(2), Number(3)], [Text("x"), Null, Text("z")]],
    count: 1,
    selection: Some([2]),
  })
  let exact_work = { remaining: 2, max_frames: 0, }
  let exact_slots = { limit: 9, live: 0, peak: 0, }
  assert_true(reserve_completed_storage(table, exact_slots, exact_work))
  assert_eq(exact_work.remaining, 0)
  assert_eq(exact_slots.live, 9)
  assert_false(
    reserve_completed_storage(table, { limit: 8, live: 0, peak: 0, }, {
      remaining: 2,
      max_frames: 0,
    }),
  )
}
