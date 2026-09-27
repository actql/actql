///|
fn bounded_json_pick_fixture(
  row : String,
  max_work? : Int = 1000,
  max_entries? : Int = 100,
) -> (@bounded.Control, BoundedBindingRowsExecution) raise {
  let payload = json_pick_contract("{\"type\":\"number\",\"nullable\":false}")
  let schema = @schema.from_fields(
    [(@schema.Unqualified("payload"), payload)],
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let owner = checked_json_pick_operation(schema)
  let captured = capture_input(owner, 0, [input_cursor(row)], max_rows=1, {
    max_nodes: 100,
    max_text_bytes: 100,
    max_depth: 10,
    max_work: 200,
  }).unwrap()
  let read = prepare_supplied_relation_read(owner, 0, captured, fn() { true }).unwrap()
  let sequence = prepared_sequence(owner)
  let node = @lower.node_at(@lower.bound_preparation(owner), 0).unwrap()
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    [@lower.node_id(node)],
    10000,
    1000,
  ).unwrap()
  let control = @bounded.control()
  let active = start_bounded_binding_rows_supplied(
    control,
    generated,
    read,
    1,
    { max_nodes: 100, max_text_bytes: 100, max_depth: 10, max_work: 200, },
    { max_nodes: 100, max_text_bytes: 100, max_depth: 10, max_work: 200, },
    max_work,
    100,
    max_entries,
    1000,
  ).unwrap()
  (control, active)
}

///|
fn bounded_json_pick_completed_fixture(
  max_work : Int,
  max_entries : Int,
) -> (BoundedBindingRowsExecution, CompletedOutput) raise {
  let source_owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"payload\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"leaf\":{\"type\":\"number\",\"nullable\":false}}}},\"rows\":[{\"payload\":{\"leaf\":3}}]},\"as\":\"seed\"}]",
  )
  let source_generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(source_owner),
    [],
    ["values_0"],
    100000,
    10000,
  ).unwrap()
  let source = completed_output(
    execute_generated_sequence(source_generated, [], compute_test_limits()).unwrap(),
    @pipeline.Step(0),
  ).unwrap()
  let producer = @pipeline.produced_input(
    @lower.pipeline(@lower.bound_preparation(source_owner)),
    @pipeline.Step(0),
  ).unwrap()
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"from\":\"seed\",\"json_pick\":{\"column\":\"payload\",\"path\":[\"leaf\"],\"output\":\"picked\"}}]",
    ),
    [("seed", @pipeline.ProducedInput(producer))],
    None,
    None,
    {
      max_steps: 10,
      max_work: 100000,
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
      max_work: 100000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let node = @lower.node_at(@lower.bound_preparation(receiver), 0).unwrap()
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(receiver),
    [],
    [@lower.node_id(node)],
    100000,
    10000,
  ).unwrap()
  let read = prepare_producer_read(
    receiver,
    bind_completed_input(receiver, 0, source_owner, source).unwrap(),
    100,
    10000,
  ).unwrap()
  let active = start_bounded_binding_rows(
    @bounded.control(),
    generated,
    read,
    1,
    { max_nodes: 100, max_text_bytes: 100, max_depth: 10, max_work: 200, },
    { max_nodes: 100, max_text_bytes: 100, max_depth: 10, max_work: 200, },
    max_work,
    100,
    max_entries,
    1000,
  ).unwrap()
  (active, source)
}

///|
test "bounded json pick completed input admits exact work and workspace" {
  // One checked input row, field lookup, and output name emission use the
  // same bounded implementation as the supplied-input path.
  let exact_work = 2 + 5 + 7 + 6
  let exact_workspace = 9 + 2 + 2
  for
    (work, space, success) in [
      (exact_work, exact_workspace, true),
      (exact_work - 1, exact_workspace, false),
      (exact_work, exact_workspace - 1, false),
    ] {
    let (active, source) = bounded_json_pick_completed_fixture(work, space)
    let mut completed = false
    for _ in 0..<1000 {
      match advance_bounded_binding_rows(active, 1).unwrap() {
        BoundedBindingRowsContinue(..) => ()
        BoundedBindingRowsComplete(output, ..) => {
          assert_true(completed_cell(output, 0, 1) is Some(Number(3.0)))
          completed = true
          break
        }
        BoundedBindingRowsFailed(_, ..) => break
        BoundedBindingRowsStopped(_, ..) =>
          fail("completed-input json pick stopped unexpectedly")
      }
    }
    assert_eq(completed, success)
    assert_true(cleanup_bounded_binding_rows(active).unwrap())
    assert_true(completed_output_available(source))
  }
}

///|
test "bounded json pick admits exact work and workspace" {
  // Row admission and opening cost two units. The leaf probe costs one
  // field visit plus four UTF-8 bytes; output names cost seven and six.
  let exact_work = 2 + 5 + 7 + 6
  // The prepared path and schemas hold nine slots. Both output and checked
  // rows add two slots while they coexist at the commit boundary.
  let exact_workspace = 9 + 2 + 2
  for
    (work, space, success) in [
      (exact_work, exact_workspace, true),
      (exact_work - 1, exact_workspace, false),
      (exact_work, exact_workspace - 1, false),
    ] {
    let (_, active) = bounded_json_pick_fixture(
      "{\"payload\":{\"leaf\":3}}",
      max_work=work,
      max_entries=space,
    )
    let mut result = false
    for _ in 0..<1000 {
      match advance_bounded_binding_rows(active, 1).unwrap() {
        BoundedBindingRowsContinue(..) => ()
        BoundedBindingRowsComplete(_, ..) => {
          result = true
          break
        }
        BoundedBindingRowsFailed(_, ..) => break
        BoundedBindingRowsStopped(_, ..) =>
          fail("json pick stopped unexpectedly")
      }
    }
    assert_eq(result, success)
    assert_true(cleanup_bounded_binding_rows(active).unwrap())
  }
}

///|
test "bounded json pick advances field search with quantum one" {
  let (_, active) = bounded_json_pick_fixture("{\"payload\":{\"leaf\":3}}")
  let mut complete = false
  let mut polls = 0
  while !complete && polls < 1000 {
    polls += 1
    match advance_bounded_binding_rows(active, 1).unwrap() {
      BoundedBindingRowsContinue(..) => ()
      BoundedBindingRowsComplete(output, ..) => {
        assert_eq(completed_row_count(output), 1)
        assert_true(completed_cell(output, 0, 1) is Some(Number(3.0)))
        complete = true
      }
      _ => fail("bounded json pick did not complete")
    }
  }
  assert_true(complete)
  assert_true(polls > 5)
  assert_true(cleanup_bounded_binding_rows(active).unwrap())
}

///|
test "bounded json pick cancels before field search completes" {
  let (control, active) = bounded_json_pick_fixture(
    "{\"payload\":{\"leaf\":3}}",
  )
  let mut searching = false
  for _ in 0..<1000 {
    if bounded_binding_rows_comparison_state(active).0 is PickJson {
      searching = true
      break
    }
    assert_true(
      advance_bounded_binding_rows(active, 1)
      is Ok(BoundedBindingRowsContinue(..)),
    )
  }
  assert_true(searching)
  assert_true(@bounded.request_cancel(control))
  assert_true(
    advance_bounded_binding_rows(active, 1)
    is Ok(BoundedBindingRowsStopped(_, ..)),
  )
  assert_true(cleanup_bounded_binding_rows(active).unwrap())
}
