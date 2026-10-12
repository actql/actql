///|
fn original_input_capacity_run(
  prepared : @publication_host.PreparedClientProgram,
  plan : @publication_host.ClientInferPlanGraph,
) -> (@publication_host.ClientCompiledRun, @publication.PublicationContract) {
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    100000,
    10000,
    100,
  ).unwrap()
  let compilation = @publication_host.issue_prepared_client_infer_compilation(
    prepared, plan, manifests, 1000, 10000, 1000000, 100000, 100,
  ).unwrap()
  let compiled = @publication_host.issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "original-input", "run", "2026-10-12T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  (compiled, definition)
}

///|
fn original_input_capacity_fixture(
  prepared : @publication_host.PreparedClientProgram,
  plan : @publication_host.ClientInferPlanGraph,
) -> (
  @input.ClientInferInputExecution,
  @relation.PreparedInferRows,
  @publication_host.ClientInferCallScope,
) raise {
  let (input, rows, _, _) = call_identity_fixture(prepared)
  let completed = @input.client_infer_completed_input(input).unwrap()
  let wire : @relation.RowWireLimits = {
    max_columns: 10,
    max_order_work: 10000,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 20,
  }
  let scan = @relation.start_completed_relation_identity_scan(
    completed,
    10,
    standard_limits().output_values,
    wire,
    wire,
    { max_fields: 10, max_bytes: 10000, max_nodes: 1000, max_depth: 20, },
    10000,
    10000,
  ).unwrap()
  while !@relation.advance_completed_relation_identity_scan(scan, 1).unwrap().0 {
    ()
  }
  let receipt = @relation.finish_completed_relation_identity_scan(scan).unwrap()
  let scope = @publication_host.issue_prepared_client_infer_call_scope(
    prepared, plan, 2, completed, receipt, 100000, 10000, 100,
  ).unwrap()
  (input, rows, scope)
}

///|
fn original_input_capacity_read(
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
) -> (@resources.Ledger, @publication_host.ClientModelReadPreparation) {
  // Independent synthetic API limits, not a physical Model profile or a byte
  // upper bound for the fixture's allocations. Positive bootstrap is mandatory
  // even for zero rows. 3+7+10 retention and 2+5+5 execution are exact here.
  let ledger = @resources.create_ledger({
    planning_work: 3,
    attempts: 2,
    holdings: 3,
    transfer_bytes: 11L,
    retained_bytes: 20L,
    execution_bytes: 12L,
  }).unwrap()
  @resources.configure_quantities(ledger, {
    tokens: 13L,
    cost_units: 17L,
    duration_ms: 19L,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let scope = @publication_host.begin_client_model_read_scope(
    compiled, definition, plan, ledger, bootstrap, 2, 0, 0,
  ).unwrap()
  (ledger, @publication_host.prepare_client_model_read(scope, 7L, 5L).unwrap())
}

///|
test "original input capacity joins live prefix and same ledger including zero rows" {
  for
    source in [
      infer_fixture_program,
      infer_fixture_program.replace(
        old="\"rows\":[{\"id\":\"a\",\"text\":\"hello\"}]",
        new="\"rows\":[]",
      ),
    ] {
    let prepared = fixture_prepared(source~)
    let plan = call_identity_plan(prepared)
    let (compiled, definition) = original_input_capacity_run(prepared, plan)
    let (input, rows, scope) = original_input_capacity_fixture(prepared, plan)
    let (ledger, read) = original_input_capacity_read(
      compiled, definition, plan,
    )
    let quantities = @resources.quantity_usage(ledger)
    let (same, token) = @publication_host.handoff_client_model_read_input_capacity(
      read, compiled, definition, plan, scope, rows, 10L, 5L,
    ).unwrap()
    assert_true(physical_equal(ledger, same))
    assert_true(@resources.capacity_reservation_matches(same, token, 10L, 5L))
    assert_eq(@resources.quantity_usage(same), quantities)
    assert_eq(@resources.ledger_usage(same).attempts, 0)
    assert_true(
      @publication_host.handoff_client_model_read_input_capacity(
        read, compiled, definition, plan, scope, rows, 10L, 5L,
      )
      is Err(@publication_host.Read(Resource(@resources.SpentClaim))),
    )
    assert_true(
      @publication_host.settle_client_model_read(read, false)
      is Err(@publication_host.Resource(@resources.CleanupPending)),
    )
    assert_eq(@resources.ledger_usage(same).reserved_retention_bytes, 20L)
    @publication_host.settle_client_model_read(read, true).unwrap()
    assert_eq(@resources.ledger_usage(same).reserved_retention_bytes, 13L)
    assert_false(
      @resources.finish_original_ledger_inventory(same, true).unwrap(),
    )
    @resources.settle_capacity(same, token).unwrap()
    assert_true(
      @resources.finish_original_ledger_inventory(same, true).unwrap(),
    )
    assert_true(@input.cleanup_client_infer_input(input).unwrap())
  }
}

///|
test "original input capacity rejects equal bytes from another completed occurrence" {
  let prepared = fixture_prepared()
  let plan = call_identity_plan(prepared)
  let (compiled, definition) = original_input_capacity_run(prepared, plan)
  let (input, rows, scope) = original_input_capacity_fixture(prepared, plan)
  let (other, other_rows, _) = original_input_capacity_fixture(prepared, plan)
  let (ledger, read) = original_input_capacity_read(compiled, definition, plan)
  let before = @resources.ledger_usage(ledger)
  let quantities = @resources.quantity_usage(ledger)
  assert_true(
    @publication_host.handoff_client_model_read_input_capacity(
      read, compiled, definition, plan, scope, other_rows, 10L, 5L,
    )
    is Err(@publication_host.ForeignInput),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(@resources.quantity_usage(ledger), quantities)
  assert_true(
    @publication_host.client_model_read_available(
      read, compiled, definition, plan,
    ),
  )
  let (same, token) = @publication_host.handoff_client_model_read_input_capacity(
    read, compiled, definition, plan, scope, rows, 10L, 5L,
  ).unwrap()
  @publication_host.settle_client_model_read(read, true).unwrap()
  @resources.settle_capacity(same, token).unwrap()
  assert_true(@resources.finish_original_ledger_inventory(same, true).unwrap())
  assert_true(@input.cleanup_client_infer_input(input).unwrap())
  assert_true(@input.cleanup_client_infer_input(other).unwrap())
}

///|
test "original input capacity rejects foreign scope and preserves one-short retry" {
  let prepared = fixture_prepared()
  let plan = call_identity_plan(prepared)
  let (compiled, definition) = original_input_capacity_run(prepared, plan)
  let (input, rows, scope) = original_input_capacity_fixture(prepared, plan)
  let other_plan = call_identity_plan(prepared)
  let (other, _, other_scope) = original_input_capacity_fixture(
    prepared, other_plan,
  )
  let (ledger, read) = original_input_capacity_read(compiled, definition, plan)
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @publication_host.handoff_client_model_read_input_capacity(
      read, compiled, definition, plan, other_scope, rows, 10L, 5L,
    )
    is Err(@publication_host.ForeignCallScope),
  )
  assert_true(
    @publication_host.handoff_client_model_read_input_capacity(
      read, compiled, definition, other_plan, scope, rows, 10L, 5L,
    )
    is Err(@publication_host.Read(ForeignRun)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    @publication_host.handoff_client_model_read_input_capacity(
      read, compiled, definition, plan, scope, rows, 10L, 6L,
    )
    is Err(
      @publication_host.Read(
        Resource(@resources.Resource(@resources.ExecutionLimit))
      )
    ),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  let (same, token) = @publication_host.handoff_client_model_read_input_capacity(
    read, compiled, definition, plan, scope, rows, 10L, 5L,
  ).unwrap()
  @publication_host.settle_client_model_read(read, true).unwrap()
  @resources.settle_capacity(same, token).unwrap()
  assert_true(@resources.finish_original_ledger_inventory(same, true).unwrap())
  assert_true(@input.cleanup_client_infer_input(input).unwrap())
  assert_true(@input.cleanup_client_infer_input(other).unwrap())
}

///|
test "original input capacity rejects reclaimed rows and stopped read without releasing custody" {
  let prepared = fixture_prepared()
  let plan = call_identity_plan(prepared)
  let (compiled, definition) = original_input_capacity_run(prepared, plan)
  let (input, rows, scope) = original_input_capacity_fixture(prepared, plan)
  let (ledger, read) = original_input_capacity_read(compiled, definition, plan)
  assert_true(@input.cleanup_client_infer_input(input).unwrap())
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @publication_host.handoff_client_model_read_input_capacity(
      read, compiled, definition, plan, scope, rows, 10L, 5L,
    )
    is Err(@publication_host.ForeignInput),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  @publication_host.stop_client_model_read(read).unwrap()
  assert_false(
    @publication_host.client_model_read_available(
      read, compiled, definition, plan,
    ),
  )
  assert_true(
    @publication_host.settle_client_model_read(read, false)
    is Err(@publication_host.Resource(@resources.CleanupPending)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  @publication_host.settle_client_model_read(read, true).unwrap()
  assert_true(
    @resources.finish_original_ledger_inventory(ledger, true).unwrap(),
  )
}

///|
test "original input capacity cannot hand off a stopped read with otherwise live input" {
  let prepared = fixture_prepared()
  let plan = call_identity_plan(prepared)
  let (compiled, definition) = original_input_capacity_run(prepared, plan)
  let (input, rows, scope) = original_input_capacity_fixture(prepared, plan)
  let (ledger, read) = original_input_capacity_read(compiled, definition, plan)
  let before = @resources.ledger_usage(ledger)
  @publication_host.stop_client_model_read(read).unwrap()
  assert_true(
    @publication_host.handoff_client_model_read_input_capacity(
      read, compiled, definition, plan, scope, rows, 10L, 5L,
    )
    is Err(@publication_host.Read(Resource(@resources.SpentClaim))),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  @publication_host.settle_client_model_read(read, true).unwrap()
  assert_true(
    @resources.finish_original_ledger_inventory(ledger, true).unwrap(),
  )
  assert_true(@input.cleanup_client_infer_input(input).unwrap())
}
