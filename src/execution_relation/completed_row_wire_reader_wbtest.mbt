///|
priv struct CountedRowWireMetadata {
  table : CompletedTable
  calls : Ref[Int]
}

///|
impl IndexedRows for CountedRowWireMetadata with fn row_count(self) {
  IndexedRows::row_count(self.table)
}

///|
impl IndexedRows for CountedRowWireMetadata with fn column_count(self) {
  IndexedRows::column_count(self.table)
}

///|
impl IndexedRows for CountedRowWireMetadata with fn row_width(self, row) {
  IndexedRows::row_width(self.table, row)
}

///|
impl IndexedRows for CountedRowWireMetadata with fn read_cell(self, row, column) {
  IndexedRows::read_cell(self.table, row, column)
}

///|
impl RelationRows for CountedRowWireMetadata with fn checked_owner(self) {
  RelationRows::checked_owner(self.table)
}

///|
impl RelationRows for CountedRowWireMetadata with fn relation_id(self) {
  RelationRows::relation_id(self.table)
}

///|
impl RelationRows for CountedRowWireMetadata with fn field_names(self) {
  self.calls.val += 1
  RelationRows::field_names(self.table)
}

///|
test "completed row wire reader prepares immutable metadata once for eight reads" {
  let output = export_fixture(result_export_owner())
  let table = output.table.unwrap()
  let metadata = CountedRowWireMetadata::{ table, calls: Ref(0), }
  let expected = ["{\"s\":\"é\",\"n\":1}", "{\"s\":\"😀\",\"n\":2}"]
  // Reproduce the old per-row layout preparation with the real encoder.
  for index in 0..<8 {
    let row = index % 2
    let columns = prepare_completed_row_wire_columns(output, metadata, 3).unwrap()
    assert_eq(
      encode_completed_row_wire(table, columns, row, 100, 5, 2).unwrap(),
      expected[row],
    )
  }
  assert_eq(metadata.calls.val, 8)
  metadata.calls.val = 0
  let columns = prepare_completed_row_wire_columns(output, metadata, 3).unwrap()
  let positions = columns.positions
  let order = columns.ordered.unwrap()
  for index in 0..<8 {
    let row = index % 2
    check_completed_row_wire_input(output, row, 100, 5, 2).unwrap() |> ignore
    assert_eq(
      encode_completed_row_wire(table, columns, row, 100, 5, 2).unwrap(),
      expected[row],
    )
    assert_true(physical_equal(columns.positions, positions))
    assert_true(physical_equal(columns.ordered.unwrap(), order))
  }
  assert_eq(metadata.calls.val, 1)
}

///|
test "completed row wire reader keeps per-row bounds and original current checks" {
  let source = export_fixture(result_export_owner())
  let live = Ref(true)
  let checks = Ref(0)
  let output = restrict_completed_output(source, fn() {
    checks.val += 1
    live.val
  })
  let read = prepare_completed_output_row_wire_reader(output, 3, 2).unwrap()
  assert_eq(read(0, 16).unwrap(), "{\"s\":\"é\",\"n\":1}")
  assert_eq(read(1, 18).unwrap(), "{\"s\":\"😀\",\"n\":2}")
  assert_eq(checks.val, 3)
  assert_true(read(0, 15) is Err(Wire(Encoding(_))))
  assert_true(read(-1, 100) is Err(Wire(InvalidLayout)))
  assert_true(read(2, 100) is Err(Wire(InvalidLayout)))
  assert_true(read(0, -1) is Err(Wire(InvalidLimits)))
  let short_nodes = prepare_completed_output_row_wire_reader(source, 2, 2).unwrap()
  assert_true(short_nodes(0, 100) is Err(Wire(Encoding(_))))
  let short_depth = prepare_completed_output_row_wire_reader(source, 5, 0).unwrap()
  assert_true(short_depth(0, 100) is Err(Wire(Encoding(_))))
  live.val = false
  let before = checks.val
  assert_true(read(0, 100) is Err(Unavailable))
  assert_eq(checks.val, before + 1)
  assert_true(
    prepare_completed_output_row_wire_reader(output, 3, 2) is Err(Unavailable),
  )
}
