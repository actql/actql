///|
fn input_result_execution_fixture() -> (
  @bounded.Control,
  BoundedBindingRowsExecution,
  ProducerRead,
  CompletedOutput,
) raise {
  let source_owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"A\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"A\":0},{\"A\":2},{\"A\":2}]},\"as\":\"rows\"}]",
  )
  let source_sequence = prepared_sequence(source_owner)
  let source_generated = prepare_generated_sequence(
    registered_relation_contracts(),
    source_sequence,
    [],
    [
      @lower.node_id(
        @lower.node_at(@lower.bound_preparation(source_owner), 0).unwrap(),
      ),
    ],
    10000,
    10000,
  ).unwrap()
  let source = completed_output(
    execute_generated_sequence(source_generated, [], compute_test_limits()).unwrap(),
    @pipeline.Step(0),
  ).unwrap()
  let produced = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(source_owner)),
    @pipeline.Step(0),
  ).unwrap()
  let checked = @pipeline.check_with_evidence(
    input_cursor("[]"),
    [("rows", @pipeline.ProducedInput(produced))],
    None,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let receiver = @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    [],
    [@lower.input_id(@lower.bound_preparation(receiver), 0).unwrap()],
    10000,
    10000,
  ).unwrap()
  let read = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, source_owner, source).unwrap(),
    100,
    10000,
  ).unwrap()
  let control = @bounded.control()
  let execution = start_bounded_binding_rows(
    control,
    generated,
    read,
    100,
    run_limits().input_values,
    run_limits().output_values,
    10000,
    100,
    10000,
    10000,
  ).unwrap()
  (control, execution, read, source)
}

///|
test "input-only completion copies the exact input with bounded progress" {
  let (_, execution, read, source) = input_result_execution_fixture()
  let mut completed : CompletedOutput? = None
  let mut advances = 0
  while completed is None && advances < 1000 {
    advances += 1
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => completed = Some(output)
      _ => fail("input-only completion failed")
    }
  }
  guard completed is Some(output) else { fail("input-only completion stalled") }
  assert_true(advances > 3)
  assert_eq(output.target, @pipeline.Input(0))
  assert_eq(completed_row_count(output), 3)
  for row, expected in [0.0, 2.0, 2.0] {
    assert_true(
      completed_cell(output, row, 0) is Some(Number(value)) && value == expected,
    )
  }
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(producer_read_available(read))
  assert_true(completed_output_available(source))
  assert_true(completed_output_available(output))
  // Execution cleanup releases only its scratch, not the accepted material.
  assert_true(completed_cell(output, 2, 0) is Some(Number(2.0)))
}

///|
test "input-only cancellation retains the receiving input until physical stop" {
  let (control, execution, read, source) = input_result_execution_fixture()
  assert_true(
    advance_bounded_binding_rows(execution, 1).unwrap()
    is BoundedBindingRowsContinue(..),
  )
  assert_true(@bounded.request_cancel(control))
  assert_true(producer_read_available(read))
  let mut stopped = false
  for _ in 0..<1000 {
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsStopped(_, ..) => {
        stopped = true
        break
      }
      _ => fail("cancelled input-only completion issued output")
    }
  }
  assert_true(stopped)
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(producer_read_available(read))
  assert_true(completed_output_available(source))
}

///|
test "input-only completion requires receiving proof and the exact input port" {
  let (control, execution, read, _) = input_result_execution_fixture()
  let generated = execution.state.port_preparation.unwrap().generated
  for inputs in [None, Some([])] {
    assert_true(
      start_trusted_output_preparation(
        generated,
        @pipeline.Input(0),
        10000,
        10000,
        inputs,
      )
      is Err(ForeignInputs),
    )
  }
  assert_true(
    start_trusted_output_preparation(
      generated,
      @pipeline.Input(1),
      10000,
      10000,
      Some([trusted_output_relation_input(read)]),
    )
    is Err(InvalidTarget),
  )
  let verify = fn(_ : Unit) -> ManagedRetainedOutput[Unit]? { None }
  let profile = selected_managed_execution_profile()
  assert_true(
    prepare_managed_completion_port(
      profile,
      generated,
      @pipeline.Input(0),
      10000,
      10000,
      verify,
    )
    is Err(ForeignInputs),
  )
  assert_true(
    prepare_managed_completion_port(
      profile,
      generated,
      @pipeline.Input(0),
      10000,
      10000,
      verify,
      common_inputs=[],
    )
    is Err(ForeignInputs),
  )
  let managed_port = prepare_managed_completion_port(
    profile,
    generated,
    @pipeline.Input(0),
    10000,
    10000,
    verify,
    common_inputs=[ordinary_relation_input_binding(read)],
  ).unwrap()
  assert_true(cancel_managed_completion_port(managed_port))
  assert_true(@bounded.request_cancel(control))
  let mut stopped = false
  for _ in 0..<1000 {
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsStopped(_, ..) => {
        stopped = true
        break
      }
      _ => fail("proof rejection caused completion")
    }
  }
  assert_true(stopped)
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  assert_true(producer_read_available(read))
}

///|
test "input-only managed publication preserves the completed input binding" {
  let (_, execution, read, _) = input_result_execution_fixture()
  let preparation = execution.state.port_preparation.unwrap().generated
  let owner = completion_preparation_owner(preparation)
  let mut copied : CompletedOutput? = None
  for _ in 0..<1000 {
    match advance_bounded_binding_rows(execution, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => {
        copied = Some(output)
        break
      }
      _ => fail("input-only copy did not complete")
    }
  }
  let copied = copied.unwrap()
  let live = Ref(true)
  let values = prepare_managed_output_values(
    owner,
    Input(0),
    3,
    stream_value_limits(),
    100,
    managed_test_measure_limits(),
  ).unwrap()
  let retention = prepare_managed_output_retention_port(values, (
    receipt : ManagedOutputValueReceipt,
  ) => Some((receipt, 7, 46L, () => live.val))).unwrap()
  for row in 0..<3 {
    append_completed_projection_managed_values(values, copied, row).unwrap()
  }
  let material = retain_managed_output(
    retention,
    finish_managed_output_values(values).unwrap(),
  ).unwrap()
  let binding = ordinary_relation_input_binding(read)
  let port = prepare_managed_completion_port(
    selected_managed_execution_profile(),
    preparation,
    Input(0),
    10000,
    10000,
    (_ : Unit) => Some(material),
    common_inputs=[binding],
  ).unwrap()
  let output = complete_managed_output(port, ()).unwrap()
  let bridge = prepare_managed_publication_bridge(
    output,
    material,
    3,
    stream_value_limits(),
    10000,
    10000,
  ).unwrap()
  for wire in ["{\"A\":0}", "{\"A\":2}", "{\"A\":2}"] {
    append_managed_publication_bridge_wire(
      bridge,
      wire,
      retained_row_test_limits(),
    ).unwrap()
  }
  let exported = finish_managed_publication_bridge(bridge).unwrap()
  assert_eq(exported.target, Input(0))
  assert_true(managed_completed_same_occurrence(bridge.output, output))
  assert_true(managed_completed_output_matches_common_inputs(output, [binding]))
  // Common managed proof remains opaque; do not fabricate a raw input proof.
  assert_false(completed_output_matches_inputs(exported, [read]))
  let consumer = typed_receiver(
    owner,
    "[{\"select\":[\"A\"]}]",
    target=Input(0),
  )
  let downstream = prepare_managed_producer_read(
    consumer, 0, owner, output, 10000, 10000,
  ).unwrap()
  let producer_bridge = prepare_managed_producer_bridge(
    downstream,
    3,
    stream_value_limits(),
    10000,
    10000,
  ).unwrap()
  for wire in ["{\"A\":0}", "{\"A\":2}", "{\"A\":2}"] {
    append_managed_producer_bridge_wire(
      producer_bridge,
      wire,
      retained_row_test_limits(),
    ).unwrap()
  }
  let downstream_read = finish_managed_producer_bridge(
    producer_bridge, 10000, 10000,
  ).unwrap()
  assert_true(producer_read_cell(downstream_read, 2, 0) is Some(Number(2.0)))
  close_managed_producer_bridge(producer_bridge)
  assert_false(producer_read_available(downstream_read))
  for row, expected in [0.0, 2.0, 2.0] {
    assert_true(
      completed_cell(exported, row, 0) is Some(Number(value)) &&
      value == expected,
    )
  }
  close_managed_publication_bridge(bridge)
  assert_false(completed_output_available(exported))
  assert_true(managed_completed_output_available(output))
  assert_true(cleanup_bounded_binding_rows(execution).unwrap())
  live.val = false
  assert_true(
    prepare_managed_publication_bridge(
      output,
      material,
      3,
      stream_value_limits(),
      10000,
      10000,
    )
    is Err(Unavailable),
  )
}
