///|
test "capacity identity borrowed output shares backing while independent copy allocates" {
  let owner = capture_fixture()
  let generated = compute_test_sequence(owner)
  let source = completed_output(test_typed_completion(generated, 1), Step(1)).unwrap()
  let shared = restrict_completed_output(source, fn() { true })
  let copy = copy_completed_output_independent(source, 2, 2).unwrap()
  assert_eq(completed_row_count(source), completed_row_count(copy))
  assert_eq(completed_column_count(source), completed_column_count(copy))
  assert_false(
    physical_equal(
      source.completion.result_identity,
      copy.completion.result_identity,
    ),
  )
  assert_true(
    physical_equal(
      source.completion.result_identity,
      shared.completion.result_identity,
    ),
  )
  match (source.table.unwrap(), shared.table.unwrap(), copy.table.unwrap()) {
    (RowTable(original), RowTable(borrowed), RowTable(copied)) => {
      assert_true(physical_equal(original.rows, borrowed.rows))
      assert_true(physical_equal(original.names, borrowed.names))
      assert_false(physical_equal(original.rows, copied.rows))
      assert_false(physical_equal(original.names, copied.names))
      for index in 0..<original.rows.length() {
        assert_false(physical_equal(original.rows[index], copied.rows[index]))
        assert_eq(original.rows[index].length(), copied.rows[index].length())
      }
    }
    (AdmittedTable(original), AdmittedTable(borrowed), AdmittedTable(copied)) => {
      assert_true(physical_equal(original.rows, borrowed.rows))
      assert_true(physical_equal(original.names, borrowed.names))
      assert_false(physical_equal(original.rows, copied.rows))
      assert_false(physical_equal(original.names, copied.names))
      for index in 0..<original.rows.length() {
        assert_false(physical_equal(original.rows[index], copied.rows[index]))
        assert_eq(original.rows[index].length(), copied.rows[index].length())
      }
    }
    _ => fail("identity fixture must inspect owned row allocations")
  }
  // Immutable cell payloads may still share. Distinct row-array identity is
  // not a claim that every nested value is deeply copied.
}
