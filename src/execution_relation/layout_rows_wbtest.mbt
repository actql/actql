///|
// Test-only metadata wrapper. It retains checked ownership, not an extra row
// matrix. Column reads never materialize an input row for the evaluator.
priv struct LayoutRelation {
  candidate : LayoutCandidate
  owner : @lower.BoundPrepared
  id : String
  names : Array[String]
  storage : LayoutStorage
}

///|
impl IndexedRows for LayoutRelation with fn row_count(self) {
  self.storage.count
}

///|
impl IndexedRows for LayoutRelation with fn column_count(self) {
  self.storage.width
}

///|
impl IndexedRows for LayoutRelation with fn row_width(self, _row) {
  self.storage.width
}

///|
impl IndexedRows for LayoutRelation with fn read_cell(self, row, column) {
  layout_cell(self.storage, row, column).unwrap()
}

///|
impl RelationRows for LayoutRelation with fn checked_owner(self) {
  self.owner
}

///|
impl RelationRows for LayoutRelation with fn relation_id(self) {
  self.id
}

///|
impl RelationRows for LayoutRelation with fn field_names(self) {
  self.names
}

///|
fn layout_relation(
  input : CapturedRows,
  candidate : LayoutCandidate,
) -> LayoutRelation {
  let prepared = @lower.bound_preparation(input.owner)
  let id = match input.origin {
    ValuesNode(i) => @lower.node_id(@lower.node_at(prepared, i).unwrap())
    SuppliedInput(i) => @lower.input_id(prepared, i).unwrap()
  }
  {
    candidate,
    owner: input.owner,
    id,
    names: Array::makei(@schema.field_count(input.schema), i => {
      @schema.reference_name(@schema.field_at(input.schema, i).unwrap().name)
    }),
    storage: import_layout(
      input,
      candidate,
      layout_allocation(100000, 100000, 100000),
    ).unwrap(),
  }
}

///|
test "column inputs use shared ordered evaluation with exact work live bytes and failure positions" {
  let owner = row_owner(
    ",{\"derive\":[{\"old\":\"a\"},{\"a\":\"old + 1\"},{\"total\":\"old + a\"}]}",
  )
  let captured = capture_values(owner, 0, max_rows=2, run_limits().input_values).unwrap()
  let kernel = row_kernel(owner, 1)
  for candidate in [RowLayout, ValueColumns, TypedColumns] {
    let input = layout_relation(captured, candidate)
    for _repeat = 0; _repeat < 2; _repeat = _repeat + 1 {
      let b = ordered_row_budget(84L, 78L, bytes=31L)
      let output = evaluate_row_body(
        PreparedBody(kernel),
        input,
        "derive_1",
        2,
        { remaining: 100000, max_frames: 100, },
        row_output(),
        { limit: 100000, live: 0, peak: 0, },
        ordered_budget=Some(b),
      ).unwrap()
      assert_eq(output.names, ["a", "b", "old", "total"])
      for
        (row, expected) in [
          (0, [2.0, 0.0, 1.0, 3.0]),
          (1, [1.0, 1.0, 0.0, 1.0]),
        ] {
        for column, value in expected {
          assert_true(output.rows[row][column] is Number(n) && n == value)
        }
      }
      assert_eq((b.work, b.peak, b.live), (84L, 78L, 0L))
      assert_false(b.failed)
      assert_true(layout_cell(input.storage, 0, 0) is Some(Number(1)))
    }
    for
      b in [
        ordered_row_budget(83L, 78L),
        ordered_row_budget(84L, 77L),
        ordered_row_budget(84L, 78L, bytes=30L),
      ] {
      let output = evaluate_row_body(
        PreparedBody(kernel),
        input,
        "derive_1",
        2,
        { remaining: 100000, max_frames: 100, },
        row_output(),
        { limit: 100000, live: 0, peak: 0, },
        ordered_budget=Some(b),
      )
      assert_true(output is Err(_))
      assert_true(b.failed)
      assert_eq(b.live, 0L)
    }
    let wrong_id = { ..input, id: "unrelated", }
    assert_true(
      evaluate_row_body(
        PreparedBody(kernel),
        wrong_id,
        "derive_1",
        2,
        { remaining: 100000, max_frames: 100, },
        row_output(),
        { limit: 100000, live: 0, peak: 0, },
      )
      is Err(InputMismatch),
    )
    let foreign = {
      ..input,
      owner: row_owner(",{\"derive\":[{\"a\":\"a + 1\"}]}"),
    }
    assert_true(
      evaluate_row_body(
        PreparedBody(kernel),
        foreign,
        "derive_1",
        2,
        { remaining: 100000, max_frames: 100, },
        row_output(),
        { limit: 100000, live: 0, peak: 0, },
      )
      is Err(OwnerMismatch),
    )
  }
}

///|
test "column map and filter preserve snapshot lazy branches and atomic late failure" {
  for
    (tail, expected_count, fails) in [
      (",{\"derive\":{\"c\":\"if(a = 1, 7, 1 / b)\"}}", 2, false),
      (",{\"filter\":\"a > 0\"}", 1, false),
      (",{\"derive\":{\"unused\":\"1 / a\"}}", 0, true),
    ] {
    let owner = row_owner(tail)
    let captured = capture_values(
      owner,
      0,
      max_rows=2,
      run_limits().input_values,
    ).unwrap()
    let kernel = row_kernel(owner, 1)
    let original = table_from_capture(captured)
    let baseline_control = { remaining: 100000, max_frames: 100, }
    let baseline_budget = ordered_row_budget(10000L, 10000L)
    let baseline = evaluate_row_body(
      PreparedBody(kernel),
      original,
      "output",
      2,
      baseline_control,
      row_output(),
      { limit: 100000, live: 0, peak: 0, },
      ordered_budget=Some(baseline_budget),
    )
    for candidate in [RowLayout, ValueColumns, TypedColumns] {
      let input = layout_relation(captured, candidate)
      let control = { remaining: 100000, max_frames: 100, }
      let b = ordered_row_budget(10000L, 10000L)
      let output = evaluate_row_body(
        PreparedBody(kernel),
        input,
        "output",
        2,
        control,
        row_output(),
        { limit: 100000, live: 0, peak: 0, },
        ordered_budget=Some(b),
      )
      assert_eq(control.remaining, baseline_control.remaining)
      assert_eq(
        (b.work, b.peak, b.live, b.failed),
        (
          baseline_budget.work,
          baseline_budget.peak,
          baseline_budget.live,
          baseline_budget.failed,
        ),
      )
      if fails {
        assert_true(
          baseline
          is Err(Evaluation(1, 0, { kind: Scalar(ArithmeticFailure), .. })),
        )
        assert_true(
          output
          is Err(Evaluation(1, 0, { kind: Scalar(ArithmeticFailure), .. })),
        )
      } else {
        let expected = baseline.unwrap()
        let actual = output.unwrap()
        assert_eq(actual.rows.length(), expected_count)
        assert_eq(actual.names, expected.names)
        for row = 0; row < expected_count; row = row + 1 {
          for column = 0; column < actual.names.length(); column = column + 1 {
            assert_eq(
              compare(actual.rows[row][column], expected.rows[row][column]).unwrap(),
              0,
            )
          }
        }
        if actual.names.length() == 3 {
          assert_true(actual.rows[0][2] is Number(7))
          assert_true(actual.rows[1][2] is Number(1))
        } else {
          assert_true(actual.rows[0][0] is Number(1))
        }
      }
    }
  }
}
