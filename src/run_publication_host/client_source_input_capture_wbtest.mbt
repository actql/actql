///|
fn whole_source_capture_contracts() -> @execution.RegisteredRelationContracts {
  @execution.admit_relation_registry(
    product_asset_value(compiler_registered_body_wire()).unwrap(),
    product_asset_value(compiler_registered_values_wire()).unwrap(),
    { max_body_bytes: 1000000, max_body_nodes: 100000, max_body_depth: 100, },
  ).unwrap()
}

///|
test "original unfiltered Source input captures before authored Select Sort and retains lifetime" {
  let prepared = source_input_unfiltered_program()
  let acquisition = prepare_client_source_acquisition(prepared, 0, 0).unwrap()
  let owner = @strategy.graph_task_owner(prepared.graph, 0).unwrap()
  let sequence = @lower.prepare_sequence(owner, run_materials_limits().sequence).unwrap()
  let rows = @execution.capture_input(
    owner,
    0,
    [
      scalar_profile_cursor("{\"amount\":8,\"id\":2}"),
      scalar_profile_cursor("{\"amount\":7,\"id\":1}"),
    ],
    max_rows=2,
    string_try_number_execution_limits().rows.input_values,
  ).unwrap()
  let live = Ref(true)
  let original = @execution.prepare_supplied_relation_read(owner, 0, rows, () => {
    live.val
  }).unwrap()
  let proof = Ref(original)
  let port = @query.prepare_trusted_source_input_capture_port(
    whole_source_capture_contracts(),
    sequence,
    acquisition,
    @checked.source_identity(@strategy.graph_program(prepared.graph)),
    2,
    8,
    fn(actual : Ref[@execution.SuppliedRelationRead]) {
      if physical_equal(actual, proof) && live.val {
        Some((actual.val, 41))
      } else {
        None
      }
    },
  ).unwrap()
  let source = @query.capture_verified_source_input(port, proof).unwrap()
  assert_true(
    @query.captured_source_matches_input_acquisition(source, acquisition),
  )
  assert_true(
    @query.captured_source_matches(
      source,
      @checked.source_identity(@strategy.graph_program(prepared.graph)),
      owner,
    ),
  )
  assert_eq(@query.captured_source_row_count(source), Some(2))
  let storage = @query.captured_source_storage(source, 10, 100).unwrap()
  assert_true(
    @execution.producer_storage_cell(storage, 0, 1) is Some(Number(2.0)),
  )
  // The Source keeps provider order; the authored Sort has not executed yet.
  let edge = @query.bind_captured_source_operation(source, owner, 0, 0).unwrap()
  let consumer = @execution.prepare_producer_read(owner, edge, 10, 100).unwrap()
  assert_true(
    @execution.producer_read_cell(consumer, 0, 1) is Some(Number(2.0)),
  )
  let replacement = @execution.prepare_supplied_relation_read(owner, 0, rows, () => {
    live.val
  }).unwrap()
  proof.val = replacement
  assert_false(@query.captured_source_available(source))
  assert_false(@execution.producer_read_available(consumer))
  proof.val = original
  live.val = false
  assert_false(@query.captured_source_available(source))
}

///|
test "Source input capture rejects equal foreign Program and changed bound invocation" {
  let prepared = source_input_unfiltered_program()
  let foreign = source_input_unfiltered_program()
  let acquisition = prepare_client_source_acquisition(prepared, 0, 0).unwrap()
  let owner = @strategy.graph_task_owner(prepared.graph, 0).unwrap()
  let sequence = @lower.prepare_sequence(owner, run_materials_limits().sequence).unwrap()
  let contracts = whole_source_capture_contracts()
  assert_true(
    @query.prepare_trusted_source_input_capture_port(
      contracts,
      sequence,
      acquisition,
      @checked.source_identity(@strategy.graph_program(foreign.graph)),
      2,
      8,
      fn(_ : Unit) { None },
    )
    is Err(Unavailable),
  )
  let wrong = @lower.prepare_sequence(
    @strategy.graph_task_owner(foreign.graph, 0).unwrap(),
    run_materials_limits().sequence,
  ).unwrap()
  assert_true(
    @query.prepare_trusted_source_input_capture_port(
      contracts,
      wrong,
      acquisition,
      @checked.source_identity(@strategy.graph_program(prepared.graph)),
      2,
      8,
      fn(_ : Unit) { None },
    )
    is Err(Unavailable),
  )
}
