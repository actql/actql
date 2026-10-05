///|
fn binding_nested_logical_fixture(
  keep? : Bool = true,
  logical_work? : Int64 = 100000L,
  logical_live? : Int64 = 10000L,
  workspace? : Int = 10000,
) -> (@bounded.Control, BoundedBindingRowsExecution, ProducerRead) raise {
  bounded_binding_rows_fixture(
    "[{\"id\":" +
    (if keep { "2" } else { "1" }) +
    ",\"payload\":[" +
    Array::make(256, "1").join(",") +
    "]}]",
    filter=true,
    unused_payload=true,
    max_entries=workspace,
    fragment_rows=1L,
    logical_limits=Some({
      max_input_rows: 1L,
      max_value_bytes: 1000L,
      max_live_value_bytes: logical_live,
      max_work: logical_work,
    }),
  )
}

///|
test "binding logical input and output retention stop within nested cells" {
  for output_phase in [false, true] {
    let (control, execution, input) = binding_nested_logical_fixture()
    let logical = execution.state.logical.unwrap()
    let mut reached = false
    let mut previous_work = 0L
    for _ in 0..<6000 {
      match advance_bounded_binding_rows(execution, 1).unwrap() {
        BoundedBindingRowsContinue(work~, ..) => {
          assert_true(work - previous_work <= 1L)
          previous_work = work
        }
        _ => fail("nested binding finished before its retention boundary")
      }
      reached = if output_phase {
        execution.state.output_logical is Some(DenseBindingLogicalRow(cursor)) &&
        cursor.measure is Some(_) &&
        logical.work > 280L
      } else {
        execution.state.input_logical is Some(cursor) &&
        cursor.measure is Some(_) &&
        logical.work > 12L
      }
      if reached {
        break
      }
    }
    assert_true(reached)
    assert_eq(execution.state.input_row, if output_phase { 1 } else { 0 })
    assert_eq(logical.live, if output_phase { 532L } else { 0L })
    if output_phase {
      assert_false(execution.state.input_roots[0].root.released)
    }
    let charged = logical.work
    let held = execution.state.workspace.live
    assert_true(held > 0)
    assert_true(@bounded.request_cancel(control))
    assert_true(
      advance_bounded_binding_rows(execution, 1).unwrap()
      is BoundedBindingRowsStopped(@bounded.Cancelled, ..),
    )
    assert_eq((logical.work, execution.state.workspace.live), (charged, held))
    assert_true(execution.state.rows.val is None)
    assert_false(execution.accepted.val)
    assert_true(producer_read_available(input))
    if output_phase {
      assert_false(execution.state.input_roots[0].root.released)
    }
    assert_true(cleanup_bounded_binding_rows(execution).unwrap())
    assert_eq((logical.work, logical.live), (charged, 0L))
    assert_eq(execution.state.workspace.live, 0)
    assert_true(execution.state.input_logical is None)
    assert_true(execution.state.output_logical is None)
    assert_true(producer_read_available(input))
    assert_true(
      advance_bounded_binding_rows(execution, 1)
      is Err(Execution(@bounded.Terminal)),
    )
  }
}

///|
test "binding logical retention preserves exact cumulative work and live bounds" {
  // The outer row, id, array and 256 items cost 259 nodes; its two
  // keys cost nine bytes: 268 work and 532 wire bytes. Row entry costs
  // one. The three predicate entries, two scalar results, two operand
  // consumptions and Boolean result cost eight. Keeping the row adds
  // another 268 work and retains both 532-byte roots during transfer.
  for
    (keep, work, live, failure) in [
      (false, 277L, 10000L, 0),
      (false, 276L, 10000L, 1),
      (true, 545L, 1064L, 0),
      (true, 544L, 1064L, 2),
      (true, 545L, 1063L, 3),
    ] {
    let (_, execution, input) = binding_nested_logical_fixture(
      keep~,
      logical_work=work,
      logical_live=live,
    )
    let logical = execution.state.logical.unwrap()
    let mut terminal = false
    let mut polls = 0
    let mut previous_work = 0L
    for _ in 0..<6000 {
      polls += 1
      match advance_bounded_binding_rows(execution, 1).unwrap() {
        BoundedBindingRowsContinue(work~, ..) => {
          assert_true(work - previous_work <= 1L)
          previous_work = work
        }
        BoundedBindingRowsComplete(output, ..) => {
          assert_eq(failure, 0)
          assert_eq(completed_row_count(output), if keep { 1 } else { 0 })
          if keep {
            assert_true(completed_cell(output, 0, 0) is Some(Number(2)))
            guard completed_cell(output, 0, 1)
              is Some(Captured(@admitted.Array(items))) else {
              fail("nested output lost its array")
            }
            assert_eq(@admitted.element_count(items), 256)
            for index in 0..<256 {
              assert_true(
                @admitted.element_at(items, index) is Some(@admitted.Number(1)),
              )
            }
          }
          assert_eq(logical.work, work)
          assert_eq(logical.live, 0L)
          terminal = true
        }
        BoundedBindingRowsFailed(issue, ..) => {
          match failure {
            1 =>
              assert_true(
                issue
                is Rows(
                  Evaluation(
                    _,
                    _,
                    { kind: LogicalValue(ValueMeasure(LogicalWorkLimit)), .. }
                  )
                ),
              )
            2 =>
              assert_true(
                issue is Rows(LogicalRows(ValueMeasure(LogicalWorkLimit))),
              )
            3 => assert_true(issue is Rows(LogicalRows(LiveValueLimit)))
            _ => fail("exact nested binding allowance failed")
          }
          assert_true(execution.state.rows.val is None)
          assert_false(execution.accepted.val)
          terminal = true
        }
        _ => fail("nested binding had another outcome")
      }
      if terminal {
        break
      }
    }
    assert_true(terminal)
    assert_true(polls > 256)
    let charged = logical.work
    assert_true(cleanup_bounded_binding_rows(execution).unwrap())
    assert_eq((logical.work, logical.live), (charged, 0L))
    assert_eq(execution.state.workspace.live, 0)
    assert_true(producer_read_available(input))
  }
}

///|
test "binding cancellation before advance does not start logical retention" {
  let (control, execution, input) = binding_nested_logical_fixture()
  let logical = execution.state.logical.unwrap()
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(execution, 1).unwrap()
    is BoundedBindingRowsStopped(@bounded.Cancelled, ..),
  )
  assert_eq((logical.work, logical.live), (0L, 0L))
  assert_true(execution.state.input_logical is None)
  assert_true(execution.state.output_logical is None)
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(producer_read_available(input))
}

///|
test "binding logical output custody has an exact structural workspace bound" {
  // Six metadata entries, one input-root handle, two snapshot cells, two
  // output cells, two checked cells and two capture cells remain live during
  // output measurement. The nested-row cursor adds thirteen entries at its
  // peak, including the reserved successor: 15 + 13 = 28, not array length.
  for limit in [28, 27] {
    let (_, execution, input) = binding_nested_logical_fixture(workspace=limit)
    let logical = execution.state.logical.unwrap()
    let mut terminal = false
    for _ in 0..<6000 {
      match advance_bounded_binding_rows(execution, 1).unwrap() {
        BoundedBindingRowsContinue(..) => ()
        BoundedBindingRowsComplete(output, ..) => {
          assert_eq(limit, 28)
          assert_eq(completed_row_count(output), 1)
          assert_eq(execution.state.workspace.peak, 28)
          terminal = true
        }
        BoundedBindingRowsFailed(Rows(RowLimit), ..) => {
          assert_eq(limit, 27)
          assert_true(execution.state.output_logical is Some(_))
          assert_false(execution.state.input_roots[0].root.released)
          assert_true(execution.state.rows.val is None)
          terminal = true
        }
        _ => fail("logical workspace boundary had another cause")
      }
      if terminal {
        break
      }
    }
    assert_true(terminal)
    let work = logical.work
    assert_true(cleanup_bounded_binding_rows(execution).unwrap())
    assert_eq((logical.work, logical.live), (work, 0L))
    assert_eq(execution.state.workspace.live, 0)
    assert_true(producer_read_available(input))
  }
}

///|
fn binding_presence_logical_fixture() -> (
  @bounded.Control,
  BoundedBindingRowsExecution,
  ProducerRead,
) raise {
  let schema = @schema.from_presence_fields(
    [
      (
        Unqualified("id"),
        @contract.primitive(NumberType, nullable=false),
        Required,
      ),
      (
        Unqualified("p"),
        @contract.primitive(StringType, nullable=true),
        Conditional,
      ),
    ],
    max_fields=2,
    max_name_bytes=3,
  ).unwrap()
  presence_filter_fixture(
    source_schema=Some(schema),
    wires=Some([
      "{\"id\":1,\"p\":\"" + String::make(512, 'g') + "\"}",
      "{\"id\":2,\"p\":null}",
      "{\"id\":3}",
    ]),
  )
}

///|
test "binding stepped roots preserve present Text NULL and omission" {
  let (_, execution, input) = binding_presence_logical_fixture()
  let logical = execution.state.logical.unwrap()
  let mut completed : CompletedOutput? = None
  let mut input_steps = 0
  let mut output_steps = 0
  for _ in 0..<2000 {
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => {
        if execution.state.input_logical is Some(_) {
          input_steps += 1
        }
        if execution.state.output_logical is Some(PresenceBindingLogicalRow(_)) {
          output_steps += 1
        }
      }
      BoundedBindingRowsComplete(output, ..) => {
        completed = Some(output)
        break
      }
      _ => fail("presence logical retention failed")
    }
  }
  guard completed is Some(output) else { fail("presence retention stalled") }
  assert_true(input_steps > 16 && output_steps > 16)
  assert_eq(completed_row_count(output), 3)
  assert_true(
    completed_presence_cell(output, 0, 1) is Ok(Present(@admitted.Text(text))) &&
    text == String::make(512, 'g'),
  )
  assert_true(
    completed_presence_cell(output, 1, 1) is Ok(Present(@admitted.Null)),
  )
  assert_true(completed_presence_cell(output, 2, 1) is Ok(Absent))
  // Row weights are 518 (Text), 6 (NULL), and 4 (omitted). Each is
  // retained once as input and once as output. Three row entries and
  // three eight-unit scalar predicates add 27: 2 * 528 + 27 = 1,083.
  assert_eq((logical.work, logical.live), (1083L, 0L))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_eq(execution.state.workspace.live, 0)
  assert_true(producer_read_available(input))
}

///|
test "binding presence output cancellation keeps its wrapper and input owner" {
  let (control, execution, input) = binding_presence_logical_fixture()
  let logical = execution.state.logical.unwrap()
  let mut pending : SteppedLogicalRow[Ref[Array[@admitted.Value?]]]? = None
  for _ in 0..<2000 {
    assert_true(
      advance_bounded_binding_rows(execution, 1)
      is Ok(BoundedBindingRowsContinue(..)),
    )
    if execution.state.output_logical is Some(PresenceBindingLogicalRow(cursor)) &&
      cursor.measure is Some(measure) &&
      measure.text is Some((_, offset)) &&
      offset > 0 {
      pending = Some(cursor)
      break
    }
  }
  guard pending is Some(cursor) else { fail("presence output had no yield") }
  assert_false(execution.state.input_roots[0].root.released)
  assert_true(logical.live > 0L)
  let work = logical.work
  let held = execution.state.workspace.live
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(execution, 1)
    is Ok(BoundedBindingRowsStopped(@bounded.Cancelled, ..)),
  )
  assert_false(cursor.closed)
  assert_eq(execution.state.workspace.live, held)
  assert_true(execution.state.rows.val is None)
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(cursor.closed)
  assert_eq((logical.work, logical.live), (work, 0L))
  assert_eq(execution.state.workspace.live, 0)
  assert_true(producer_read_available(input))
}
