///|
test "producer accounting is identical for typed columns and row storage" {
  let owner = row_owner("")
  let captured = capture_values(owner, 0, max_rows=100, {
    max_nodes: 1000,
    max_text_bytes: 10000,
    max_depth: 100,
    max_work: 10000,
  }).unwrap()
  let rows = table_from_capture(captured)
  let columns = layout_relation(captured, TypedColumns)
  // Independent totals: two row nodes, four scalar nodes, and four
  // one-byte field-name occurrences. Physical sharing does not reduce them.
  let exact = value_budget({
    max_nodes: 6,
    max_text_bytes: 4,
    max_depth: 2,
    max_work: 10,
  }).unwrap()
  let exact_control = { remaining: 2, max_frames: 0, }
  assert_true(charge_completed_rows(columns, 2, exact_control, exact))
  assert_eq(exact.nodes, 6)
  assert_eq(exact.text, 4)
  assert_eq(exact.work, 10)
  assert_eq(exact_control.remaining, 0)
  let short = row_output()
  assert_false(
    charge_completed_rows(columns, 2, { remaining: 1, max_frames: 0, }, short),
  )
  assert_eq(short.nodes, 3)
  assert_eq(short.text, 2)
  assert_eq(short.work, 5)
  // Include both sides of each accounting frontier. This compares the real
  // receiver admission helper, not a test-only alternative admission path.
  for remaining_rows in [0, 1, 2, 3] {
    for work = 0; work < 20; work = work + 1 {
      for nodes = 0; nodes < 12; nodes = nodes + 1 {
        let limits = {
          max_nodes: nodes,
          max_text_bytes: 10000,
          max_depth: 100,
          max_work: work,
        }
        let left = value_budget(limits).unwrap()
        let right = value_budget(limits).unwrap()
        let lc = { remaining: work, max_frames: 0, }
        let rc = { remaining: work, max_frames: 0, }
        assert_eq(
          charge_completed_rows(rows, remaining_rows, lc, left),
          charge_completed_rows(columns, remaining_rows, rc, right),
        )
        assert_eq(lc.remaining, rc.remaining)
        assert_eq(left.nodes, right.nodes)
        assert_eq(left.text, right.text)
        assert_eq(left.work, right.work)
      }
    }
  }
}

///|
test "producer zero-column rows retain cardinality and input charges" {
  let owner = row_owner("")
  let rows : Table = { owner, id: "empty", names: [], rows: [[], [], []], }
  let columns : LayoutRelation = {
    owner,
    id: "empty",
    names: [],
    candidate: TypedColumns,
    storage: {
      body: ColumnArrays([]),
      width: 0,
      count: 3,
      selection: None,
      owned_selection: None,
    },
  }
  for count in [2, 3] {
    let left = row_output()
    let right = row_output()
    let lc = { remaining: 3, max_frames: 0, }
    let rc = { remaining: 3, max_frames: 0, }
    assert_eq(charge_completed_rows(rows, count, lc, left), count == 3)
    assert_eq(charge_completed_rows(columns, count, rc, right), count == 3)
    assert_eq(lc.remaining, rc.remaining)
    assert_eq(left.nodes, right.nodes)
    assert_eq(left.work, right.work)
    if count == 3 {
      assert_eq(lc.remaining, 0)
      assert_eq(left.nodes, 3)
    }
  }
}
