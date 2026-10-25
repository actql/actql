///|
// White-box row-layout fixture: only view construction is exercised here;
// ordinary completion/publication is covered by the public scale regression.
test "unordered Result index construction consumes exactly one work unit per row at scale" {
  let owner = result_export_owner()
  let original = export_fixture(owner)
  let occurrence = result_export_occurrence(
    owner, "answer", "{\"answer\":{\"from\":\"selected\",\"fields\":[\"s\"]}}",
  )
  for count in [0, 10001, 100000] {
    let table : Table = {
      owner,
      id: "select_1",
      names: ["s", "n"],
      rows: Array::make(count, [Text("value"), Number(1)]),
    }
    let source = { ..original, table: Some(RowTable(table)), }
    for work in (if count == 0 { [0] } else { [count - 1, count] }) {
      let cursor = start_completed_result_rows(source, occurrence, {
        max_fields: 1,
        max_mapping_work: 10,
        max_order_work: work,
        max_workspace_entries: Int::max(1, 2 * count),
      }).unwrap()
      let mut succeeded = false
      let mut failed = false
      for _ in 0..<(count + 20) {
        match advance_completed_result_rows(cursor, 256) {
          Ok((true, _)) => {
            succeeded = true
            break
          }
          Ok((false, _)) => ()
          Err(Limit) => {
            failed = true
            break
          }
          Err(_) => abort("unexpected Result view issue")
        }
      }
      assert_eq(succeeded, work == count)
      assert_eq(failed, work != count)
      if succeeded {
        assert_eq(cursor.order_work.remaining, 0)
        let rows = finish_completed_result_rows(cursor).unwrap()
        assert_eq(IndexedRows::row_count(rows), count)
        assert_true(cancel_completed_result_rows(cursor) == false)
      } else {
        assert_true(cursor.closed)
        assert_true(cursor.rows.is_empty())
      }
    }
  }
}
