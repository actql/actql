///|
fn current_configuration_host_test_limits() -> @model.ModelExecutionLimits {
  {
    ..standard_limits().model,
    ledger: {
      planning_work: 17,
      attempts: 100,
      holdings: 16,
      transfer_bytes: 200000L,
      retained_bytes: 256L,
      execution_bytes: 256L,
    },
  }
}

///|
fn current_configuration_host_test_wire() -> String {
  // Independent configuration: attempts4/wire133072 are the checked fixture
  // ceilings intersected with Host100/200000. Remaining limits are Host facts.
  // The installed quantity declaration10000/10000/10000 is intersected with
  // checked128/0/1000. This data fixture issues no original custody or grant.
  // No attempts or output holdings have issued; the bootstrap and one open
  // reservation are the two live reservations. Neither has an attempt reserved or started.
  "[\"actql-original-ledger-state/0.1\",[\"17\",\"4\",\"16\",\"133072\",\"256\",\"256\"],[\"17\",\"0\",\"0\",\"0\",\"0\",\"0\",\"0\",\"10\",\"7\",\"10\",\"0\",\"2\",\"0\"],[\"0\",\"0\",\"0\"],[\"128\",\"0\",\"1000\"],[[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"],[\"0\",\"0\",\"0\"]],[\"-3\",\"0\",\"0\"],[\"4\",\"0\",\"0\",true,true,false,\"parked\",true],[\"-1\",\"0\",\"3\",\"2\",true,false,null,null,[false,false,false],null,false,false],[[\"-2\",\"0\",\"7\",\"5\",true,false,null,null,[false,false,false],null,false,false]],[],[]]"
}

///|
fn current_configuration_host_test_document(
  wire : String,
) -> @resources.OriginalCurrentStateDocument {
  let source = @source.parse_json(wire, {
    max_input_bytes: 4000,
    max_nodes: 400,
    max_depth: 10,
  }).unwrap()
  let tree : @decode.Limits = {
    max_nodes: 400,
    max_depth: 10,
    max_string_bytes: 100,
    max_total_string_bytes: 4000,
  }
  let cursor = @decode.admit(source, tree).unwrap()
  let read = @resources.start_original_current_state_document_read(
    cursor, 4, 0, 0, 3, tree,
  ).unwrap()
  match @resources.advance_original_current_state_document_read(read, 3) {
    @resources.CurrentDocumentComplete(document, work=3) => document
    _ => abort("independent current configuration Reader failed")
  }
}

///|
fn current_configuration_host_test_quantities() -> @model.ModelQuantityCapacity {
  {
    limits: { tokens: 10000L, cost_units: 10000L, duration_ms: 10000L, },
    per_attempt: { tokens: 33L, cost_units: 0L, duration_ms: 500L, },
  }
}

///|
test "cold Model configuration uses the original checked intersections without creating a Scope" {
  let prepared = fixture_prepared()
  let plan = call_identity_plan(prepared)
  let (compiled, definition) = original_input_capacity_run(prepared, plan)
  let document = current_configuration_host_test_document(
    current_configuration_host_test_wire(),
  )
  let limits = current_configuration_host_test_limits()
  let quantities = current_configuration_host_test_quantities()
  assert_true(
    check_original_model_current_configuration(
      compiled,
      definition,
      plan,
      document,
      limits,
      Some(quantities),
    )
    is Ok(_),
  )
  assert_true(
    check_original_model_current_configuration(
      compiled,
      definition,
      plan,
      document,
      limits,
      None,
    )
    is Err(@resources.Document(@resources.InvalidRecord)),
  )
  assert_true(
    check_original_model_current_configuration(
      compiled,
      definition,
      plan,
      document,
      { ..limits, ledger: { ..limits.ledger, attempts: 1, }, },
      Some(quantities),
    )
    is Err(@resources.Document(@resources.InvalidRecord)),
  )
  // Refusal does not retire the original borrowed document or replace it.
  assert_true(
    check_original_model_current_configuration(
      compiled,
      definition,
      plan,
      document,
      limits,
      Some(quantities),
    )
    is Ok(_),
  )
  @resources.retire_original_current_state_document(document)
}

///|
test "cold Model configuration rejects foreign originals and invalid installed quantities" {
  let prepared = fixture_prepared()
  let plan = call_identity_plan(prepared)
  let (compiled, definition) = original_input_capacity_run(prepared, plan)
  let foreign_prepared = fixture_prepared()
  let foreign_plan = call_identity_plan(foreign_prepared)
  let (foreign, _) = original_input_capacity_run(foreign_prepared, foreign_plan)
  let document = current_configuration_host_test_document(
    current_configuration_host_test_wire(),
  )
  let limits = current_configuration_host_test_limits()
  let quantities = current_configuration_host_test_quantities()
  assert_true(
    check_original_model_current_configuration(
      foreign,
      definition,
      plan,
      document,
      limits,
      Some(quantities),
    )
    is Err(@resources.Original(@resources.ForeignOrigin)),
  )
  assert_true(
    check_original_model_current_configuration(
      compiled,
      definition,
      plan,
      document,
      limits,
      Some({ ..quantities, limits: { ..quantities.limits, tokens: -1L, }, }),
    )
    is Err(@resources.Original(@resources.Resource(@resources.InvalidLimits))),
  )
  @resources.retire_original_current_state_document(document)
  assert_true(
    check_original_model_current_configuration(
      compiled,
      definition,
      plan,
      document,
      limits,
      Some(quantities),
    )
    is Err(@resources.Document(@resources.Terminal)),
  )
}
