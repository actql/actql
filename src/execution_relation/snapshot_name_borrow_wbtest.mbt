///|
fn named_snapshot_fixture(
  name : String,
) -> (@bounded.Control, BoundedBindingRowsExecution) raise {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"" +
    name +
    "\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"" +
    name +
    "\":7}]},\"as\":\"seed\"}]",
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    [
      @lower.node_id(
        @lower.node_at(@lower.bound_preparation(owner), 0).unwrap(),
      ),
    ],
    100000,
    10000,
  ).unwrap()
  let source = completed_output(
    execute_generated_sequence(generated, [], compute_test_limits()).unwrap(),
    Step(0),
  ).unwrap()
  let receiver = typed_receiver(
    owner,
    "[{\"derive\":{\"result\":{\"field\":\"" + name + "\"}}}]",
    target=Step(0),
  )
  let sequence = prepared_sequence(receiver)
  let context = sequence_fragment_context(sequence, 0, 1L)
  let selected = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [context],
    [
      @lower.node_id(
        @lower.node_at(@lower.bound_preparation(receiver), 0).unwrap(),
      ),
    ],
    100000,
    10000,
  ).unwrap()
  let input = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, owner, source).unwrap(),
    100,
    10000,
  ).unwrap()
  let control = @bounded.control()
  let execution = start_bounded_binding_rows(
    control,
    selected,
    input,
    100,
    run_limits().input_values,
    run_limits().output_values,
    100000,
    100,
    10000,
    10000,
  ).unwrap()
  (control, execution)
}

///|
test "bounded snapshot reference copies stay fixed while real lookup and semantic name work scale" {
  let measurements : Array[(Int, Int64)] = []
  for length in [2, 256] {
    let (_, execution) = named_snapshot_fixture("x".repeat(length))
    let mut reached = false
    for _ in 0..<10000 {
      if execution.state.phase is SnapshotRow && execution.state.column == 0 {
        reached = true
        break
      }
      assert_true(
        advance_bounded_binding_rows(execution, 1)
        is Ok(BoundedBindingRowsContinue(..)),
      )
    }
    assert_true(reached)
    let before = execution.state.control.remaining
    let semantic = execution.state.logical.unwrap()
    let semantic_before = semantic.work
    assert_true(
      advance_bounded_binding_rows(execution, 1)
      is Ok(BoundedBindingRowsContinue(..)),
    )
    assert_eq(execution.state.snapshot.length(), 1)
    assert_eq(execution.state.snapshot[0].0, execution.state.input_names[0])
    assert_eq(execution.state.control.remaining, before - 1)
    assert_eq(semantic.work, semantic_before)
    assert_true(execution.state.name_charge is None)
    assert_true(execution.state.phase is SnapshotRow)
    let after_copy = execution.state.control.remaining
    let mut complete = false
    for _ in 0..<20000 {
      if !complete {
        match advance_bounded_binding_rows(execution, 1).unwrap() {
          BoundedBindingRowsContinue(..) => ()
          BoundedBindingRowsComplete(output, ..) => {
            assert_eq(completed_row_count(output), 1)
            complete = true
          }
          _ => fail("the original checked lookup must complete")
        }
      }
    }
    assert_true(complete)
    measurements.push(
      (after_copy - execution.state.control.remaining, semantic.work),
    )
    assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  }
  // The copy skips no lookup or logical name/value occurrence: those real
  // completed counters still grow with the already-checked name spelling.
  assert_true(measurements[1].0 > measurements[0].0)
  assert_true(measurements[1].1 > measurements[0].1)
}
