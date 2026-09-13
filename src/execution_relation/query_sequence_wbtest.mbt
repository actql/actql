///|
fn query_sequence_fixture(
  filter? : String = "id > $minimum",
  extra? : String = "",
) -> (@acquisition.QueryAcquisition, @lower.BoundPrepared) {
  let wire = "{\"version\":\"actql/0.1\",\"id\":\"p\",\"params\":{\"minimum\":{\"type\":\"number\",\"nullable\":false}},\"stages\":[{\"id\":\"a\",\"inputs\":{\"remote\":{\"connector\":\"crm/main\",\"resource\":\"r\"}},\"steps\":[{\"filter\":\"" +
    filter +
    "\",\"as\":\"filtered\"},{\"select\":[\"id\"],\"as\":\"captured\"}" +
    extra +
    "],\"results\":{\"r\":{\"from\":\"captured\",\"fields\":[\"id\"]}}}],\"results\":{\"out\":{\"from\":{\"stage\":\"a\",\"result\":\"r\"}}}}"
  let program = @syntax.parse(
    wire,
    {
      source: { max_input_bytes: 1000000, max_nodes: 100000, max_depth: 100, },
      tree: {
        max_nodes: 100000,
        max_depth: 100,
        max_string_bytes: 1000000,
        max_total_string_bytes: 1000000,
      },
      max_stages: 10,
    },
    format=Json,
  ).unwrap()
  let source = @stages.prepare(program, {
    max_parameters: 100,
    max_nodes: 100,
    max_depth: 100,
    max_text_bytes: 1000,
  }).unwrap()
  let inputs = @source_inputs.collect(source, {
    max_work: 1000000,
    max_order_keys: 100,
  }).unwrap()
  let resolved = @acquisition.resolve(inputs, query_catalog_fixture(), {
    max_work: 1000000,
    max_inputs: 100,
    max_views: 100,
  }).unwrap()
  let registered = @acquisition.prepare_pipeline_inputs(resolved, 1000000).unwrap()
  let body = @decode.open_object(
    @syntax.stage_body(@stages.stage_at(source, 0).unwrap()),
  ).unwrap()
  let pipeline = @pipeline.check_with_evidence(
    @decode.required(body, "steps").unwrap(),
    [@acquisition.pipeline_input_at(registered, 0, 0).unwrap()],
    Some(@stages.declarations(source)),
    None,
    {
      max_steps: 100,
      max_work: 1000000,
      max_text_bytes: 1000000,
      max_nodes: 100000,
      max_tokens: 100000,
      max_depth: 100,
    },
  ).unwrap()
  let operations = @stages.collect_operations(source, [pipeline], {
    max_work: 1000000,
    max_slots: 1000,
    max_references: 1000,
    max_pointer_units: 1000000,
    max_direct_text_bytes: 1000000,
  }).unwrap()
  let attachment = @acquisition.attach_pipeline_inputs(
    registered,
    @stages.operations_stage_at(operations, 0).unwrap(),
    1000000,
  ).unwrap()
  let results = @stage_results.check(operations, {
    max_results: 100,
    max_work: 1000000,
    max_nodes: 100000,
    max_text_bytes: 1000000,
    max_depth: 100,
  }).unwrap()
  let uses = @acquisition.collect_pipeline_uses(attachment, results, 1000000).unwrap()
  let bindings = @bindings.prepare(program, {
    max_bindings: 100,
    max_work: 1000000,
  }).unwrap()
  let slots = @request_slots.collect(source, bindings, {
    max_work: 1000000,
    max_slots: 100,
  }).unwrap()
  let context = @acquisition.prepare_requests(resolved, slots, 1000000).unwrap()
  let limits : @admitted.Limits = {
    max_nodes: 10000,
    max_depth: 100,
    max_text_bytes: 100000,
  }
  let bound = @parameter.bind(
    @stages.declarations(source),
    Some(input_cursor("{\"minimum\":1}")),
    limits,
  ).unwrap()
  guard bound is @parameter.Ready(values) else { abort("fixture bindings") }
  let parameters = @acquisition.prepare_request_parameters(
    context, values, 1000000,
  ).unwrap()
  let requests = @acquisition.check_pipeline_requests(uses, parameters, {
    max_work: 1000000,
    max_pairs: 1000,
    values: limits,
  }).unwrap()
  let query = @acquisition.derive_query_acquisition(requests, 0, 1000000).unwrap()
  let prepared = @lower.prepare(pipeline, {
    max_nodes: 100,
    max_references: 100,
    max_work: 100000,
    max_identifier_bytes: 10000,
  }).unwrap()
  let owner = @lower.bind_parameters(
    prepared,
    Some(values),
    max_parameters=100,
    max_name_bytes=10000,
  ).unwrap()
  (query, owner)
}

///|
fn query_generated(
  owner : @lower.BoundPrepared,
  retained? : Array[String] = ["select_1"],
) -> GeneratedSequence raise {
  let sequence = prepared_sequence(owner)
  prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [sequence_fragment_context(sequence, 0, 10L)],
    retained,
    100000,
    10000,
  ).unwrap()
}

///|
test "shared acquisition binds the exact checked graph and parameters" {
  let (query, owner) = query_sequence_fixture()
  let generated = query_generated(owner)
  let prepared = prepare_query_sequence(query, generated, 10000).unwrap()
  assert_true(physical_equal(prepared.query, query))
  let (_, foreign) = query_sequence_fixture()
  assert_true(
    prepare_query_sequence(query, query_generated(foreign), 10000)
    is Err(ForeignPipeline),
  )
  let bindings = @acquisition.request_parameter_values(
    @acquisition.pipeline_requests_parameters(
      @acquisition.query_acquisition_owner(query),
    ),
  )
  let other = @parameter.bind(
    @parameter.bound_declarations(bindings),
    Some(input_cursor("{\"minimum\":2}")),
    { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, },
  ).unwrap()
  guard other is @parameter.Ready(values) else { fail("fixture parameters") }
  let rebound = @lower.bind_parameters(
    @lower.bound_preparation(owner),
    Some(values),
    max_parameters=100,
    max_name_bytes=10000,
  ).unwrap()
  assert_true(
    prepare_query_sequence(query, query_generated(rebound), 10000)
    is Err(ForeignParameters),
  )
}

///|
test "query preparation is bounded and never captures before select or runs consumers early" {
  let (query, owner) = query_sequence_fixture()
  let generated = query_generated(owner)
  assert_true(
    prepare_query_sequence(query, generated, -1) is Err(InvalidLimits),
  )
  assert_true(prepare_query_sequence(query, generated, 0) is Err(Limit))
  let exact = 1 + 2 * "select_1".length()
  assert_true(prepare_query_sequence(query, generated, exact) is Ok(_))
  assert_true(prepare_query_sequence(query, generated, exact - 1) is Err(Limit))
  assert_true(
    prepare_query_sequence(
      query,
      query_generated(owner, retained=["where_0"]),
      10000,
    )
    is Err(CaptureNotRetained),
  )
  assert_true(
    prepare_query_sequence(
      query,
      query_generated(owner, retained=["where_0", "select_1"]),
      10000,
    )
    is Err(CaptureNotRetained),
  )
  let (longer, longer_owner) = query_sequence_fixture(
    extra=",{\"select\":[\"id\"]}",
  )
  assert_true(
    prepare_query_sequence(longer, query_generated(longer_owner), 10000)
    is Err(UnsupportedExecutionShape),
  )
}

///|
test "broad receipt validates all rows before residual and retains reusable completed output" {
  let (query, owner) = query_sequence_fixture()
  let prepared = prepare_query_sequence(query, query_generated(owner), 10000).unwrap()
  let rows = [
    input_cursor("{\"id\":3}"),
    input_cursor("{\"id\":1}"),
    input_cursor("{\"id\":2}"),
  ]
  for _ in 0..<2 {
    let result = evaluate_query_receipt(
      prepared,
      rows,
      3,
      run_limits().input_values,
      compute_test_limits(),
    ).unwrap()
    let output = completed_output(result, Step(1)).unwrap()
    assert_eq(completed_row_count(output), 2)
    assert_true(completed_cell(output, 0, 0) is Some(Number(3)))
    assert_true(completed_cell(output, 1, 0) is Some(Number(2)))
  }
  assert_true(
    evaluate_query_receipt(
      prepared,
      rows,
      2,
      run_limits().input_values,
      compute_test_limits(),
    )
    is Err(ReceiptAdmission(CaptureLimit)),
  )
  let empty = evaluate_query_receipt(
    prepared,
    [],
    0,
    run_limits().input_values,
    compute_test_limits(),
  ).unwrap()
  assert_eq(completed_row_count(completed_output(empty, Step(1)).unwrap()), 0)
  let (failing_query, failing_owner) = query_sequence_fixture(
    filter="1 / (id - id) > 0",
  )
  let failing = prepare_query_sequence(
    failing_query,
    query_generated(failing_owner),
    10000,
  ).unwrap()
  // Whole-scan admission precedes even an earlier row's expression failure.
  assert_true(
    evaluate_query_receipt(
      failing,
      [rows[0], input_cursor("{\"id\":\"invalid\"}")],
      3,
      run_limits().input_values,
      compute_test_limits(),
    )
    is Err(ReceiptAdmission(InputValue(1, _))),
  )
  assert_true(
    evaluate_query_receipt(
      failing,
      rows,
      3,
      run_limits().input_values,
      compute_test_limits(),
    )
    is Err(Execution(Rows(_, _))),
  )
}

///|
test "query residual completion uses the product producer boundary without claiming observation capture" {
  let (query, owner) = query_sequence_fixture()
  let prepared = prepare_query_sequence(query, query_generated(owner), 10000).unwrap()
  let rows = [
    input_cursor("{\"id\":3}"),
    input_cursor("{\"id\":1}"),
    input_cursor("{\"id\":2}"),
  ]
  let completed = evaluate_query_receipt(
    prepared,
    rows,
    3,
    run_limits().input_values,
    compute_test_limits(),
  ).unwrap()
  let output = completed_output(completed, Step(1)).unwrap()
  rows.clear()
  let receiver = typed_receiver(
    owner, "[{\"filter\":\"id < 3\"},{\"select\":[\"id\"]}]",
  )
  let bound = bind_completed_input(receiver, 0, owner, output).unwrap()
  let generated = query_generated(receiver)
  let failed = prepare_local_compute_attempt(generated, [bound], 3).unwrap()
  assert_true(
    execute_local_compute_attempt(failed, {
      ..compute_test_limits(),
      max_work: 0,
    })
    is Err(Execution(_)),
  )
  assert_true(local_compute_result(failed) is Err(Execution(_)))
  for _ in 0..<2 {
    let next = prepare_local_compute_attempt(generated, [bound], 3).unwrap()
    let success = execute_local_compute_attempt(next, compute_test_limits()).unwrap()
    let result = completed_output(success, Step(1)).unwrap()
    assert_eq(completed_row_count(result), 1)
    assert_true(completed_cell(result, 0, 0) is Some(Number(2)))
  }
  assert_eq(completed_row_count(output), 2)
  assert_true(completed_cell(output, 0, 0) is Some(Number(3)))
}
