///|
// Independent conformance profile: it is not the Node capacity policy. These
// fixtures use actual Core preparation/dispatch and explicit test Ledger data,
// without a normal physical supplier, Source I/O or Account grant.
fn dispatch_preparation_test_inputs() -> (
  @publication_host.PreparedClientProgram,
  @connector.CapabilityRegistry,
  @connector.CapabilityRegistration,
  Array[@execution.GeneratedSequence],
  @execution.SequenceExecutionLimits,
  @execution.FixedInputGuardMeasureLimits,
  @local.LocalImportLimits,
) {
  let prepared = single_source_free_capacity_prepared()
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let sequences = prepare_client_local_sequences(
    prepared,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let registry = @connector.prepare_capability_registry(
    [{ name: "local", acquisition: false, fixed_compute: true, effect: false, }],
    1,
    100,
  ).unwrap()
  let values : @execution.ValueLimits = {
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 100,
    max_work: 100000,
  }
  let execution : @execution.SequenceExecutionLimits = {
    rows: {
      max_rows: 100,
      metadata_entries: 10000,
      retained_entries: 10000,
      operation_entries: 10000,
      input_values: values,
      output_values: values,
    },
    max_work: 100000,
    max_frames: 100,
  }
  let guards : @execution.FixedInputGuardMeasureLimits = {
    max_work: 10000,
    max_bytes: 10000,
    max_nodes: 10000,
    max_depth: 100,
  }
  let imports : @local.LocalImportLimits = {
    max_rows: 100,
    values,
    wire: {
      max_columns: 100,
      max_order_work: 1000000,
      max_bytes: 10000,
      max_nodes: 10000,
      max_depth: 64,
    },
    row: {
      max_bytes: 10000,
      max_nodes: 10000,
      max_depth: 64,
      max_text_bytes: 10000,
    },
    max_batch_bytes: 10000,
  }
  (
    prepared,
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    sequences,
    execution,
    guards,
    imports,
  )
}

///|
test "pre-Run Local preparation supplies the exact quote module and execution without another configuration" {
  let (prepared, registry, registration, sequences, execution, guards, imports) = dispatch_preparation_test_inputs()
  let graph = @publication_host.prepared_client_graph(prepared)
  let original = @local_driver.prepare_local_dispatch_plan(
    graph,
    registry,
    registration,
    sequences,
    execution,
    guards,
    100,
    inputs=Some((imports, Some(0L))),
  ).unwrap()
  // These exact checked demand facts exist before this original Ledger/Run.
  let retained = @local_driver.local_dispatch_preparation_retained_bytes(
    original,
  ).unwrap()
  let transferred = @local_driver.local_dispatch_preparation_transfer_bytes(
    original,
  ).unwrap()
  let envelope = @local_driver.local_dispatch_preparation_task_capacity(
    original, 0,
  ).unwrap()
  assert_true(
    @local_driver.local_dispatch_preparation_task_capacity(
      original, -2147483648,
    )
    is None,
  )
  assert_true(
    @local_driver.local_dispatch_preparation_task_capacity(original, 1) is None,
  )
  // The module retains the exact handles, not this caller-owned container.
  sequences.clear()
  assert_true(retained > 0L)
  assert_eq(retained, envelope.retained_bytes)
  assert_eq(transferred, 0L)
  let ledger = @resources.create_ledger({
    planning_work: 10000,
    attempts: 1,
    holdings: 1,
    transfer_bytes: transferred,
    retained_bytes: retained,
    execution_bytes: 268435456L,
  }).unwrap()
  let run = @strategy.open_source_free_dag(graph, ledger).unwrap()
  let driver = @host_driver.open_dispatch_driver(run)
  let installed = @local_driver.bind_local_dispatch_plan(driver, original).unwrap()
  assert_true(
    physical_equal(
      original,
      @local_driver.local_dispatch_original_preparation(installed).unwrap(),
    ),
  )
  assert_true(
    @local_driver.configure_local_retained_inputs(installed, imports, None)
    is Err(Configuration(InvalidLimits)),
  )
  @strategy.configure_strategy_search(run, {
    max_offers: 6,
    max_strategies: 8,
    max_work: 1000,
    max_revisions: 4,
  }).unwrap()
  let offer = @local_driver.estimate_local_dispatch_offer(
    installed,
    0,
    [{ work_slots: [0, 1, 2, 3, 4], milliseconds: Some(1L), }],
    100,
  ).unwrap()
  @strategy.revise_strategy(run, [offer], registry, None).unwrap() |> ignore
  let assessment = @strategy.strategy_assessment(
    @strategy.captured_dag_strategy(run).unwrap(),
  )
  assert_eq(assessment.retained_bytes, envelope.retained_bytes)
  assert_eq(assessment.execution_bytes, envelope.execution_bytes)
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  let entries = @connector.install_capability_implementations(
    registry,
    [
      (
        registration,
        fn(_context : Unit, task, revision, request) {
          @local_driver.prepare_local_dispatch(
            installed, task, revision, request,
          )
        },
      ),
    ],
    1,
  ).unwrap()
  let host = @host_driver.open_dispatch_host(
    driver,
    entries,
    {
      contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
      max_rows: 100,
      max_value_bytes: 10000,
      common_fragment: None,
    },
    100,
    10000,
  ).unwrap()
  let task = @host_driver.prepare_next_installed_task(host, ())
    .unwrap()
    .unwrap()
  @local_driver.execute_local_dispatch(installed, host, task).unwrap()
  let output = @strategy.captured_task_output(run, 0, Step(0)).unwrap()
  assert_eq(@execution.completed_row_count(output), 2)
  assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(1.0)))
  assert_true(@execution.completed_cell(output, 1, 0) is Some(Number(2.0)))
  @strategy.close_captured_task_output(run, 0)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.attempts, 1)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
}

///|
test "pre-Run Local plan refuses an equal foreign graph without replacing its Ledger or owner" {
  let (prepared, registry, registration, sequences, execution, guards, _) = dispatch_preparation_test_inputs()
  let original = @local_driver.prepare_local_dispatch_plan(
    @publication_host.prepared_client_graph(prepared),
    registry,
    registration,
    sequences,
    execution,
    guards,
    100,
  ).unwrap()
  let foreign = single_source_free_capacity_prepared()
  let ledger = @resources.create_ledger({
    planning_work: 10000,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 10000L,
    retained_bytes: 64000000L,
    execution_bytes: 268435456L,
  }).unwrap()
  let run = @strategy.open_source_free_dag(
    @publication_host.prepared_client_graph(foreign),
    ledger,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(
    @local_driver.bind_local_dispatch_plan(
      @host_driver.open_dispatch_driver(run),
      original,
    )
    is Err(Configuration(ForeignPreparation)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(@strategy.next_captured_task(run), Some(0))
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
}

///|
test "pre-Run Local retention one short remains typed refusal without spending a start" {
  let (prepared, registry, registration, sequences, execution, guards, imports) = dispatch_preparation_test_inputs()
  let graph = @publication_host.prepared_client_graph(prepared)
  let original = @local_driver.prepare_local_dispatch_plan(
    graph,
    registry,
    registration,
    sequences,
    execution,
    guards,
    100,
    inputs=Some((imports, Some(0L))),
  ).unwrap()
  let retained = @local_driver.local_dispatch_preparation_retained_bytes(
    original,
  ).unwrap()
  assert_true(retained > 0L)
  let ledger = @resources.create_ledger({
    planning_work: 10000,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 10000L,
    retained_bytes: retained - 1L,
    execution_bytes: 268435456L,
  }).unwrap()
  let run = @strategy.open_source_free_dag(graph, ledger).unwrap()
  let installed = @local_driver.bind_local_dispatch_plan(
    @host_driver.open_dispatch_driver(run),
    original,
  ).unwrap()
  @strategy.configure_strategy_search(run, {
    max_offers: 6,
    max_strategies: 8,
    max_work: 1000,
    max_revisions: 4,
  }).unwrap()
  let offer = @local_driver.estimate_local_dispatch_offer(
    installed,
    0,
    [{ work_slots: [0, 1, 2, 3, 4], milliseconds: Some(1L), }],
    100,
  ).unwrap()
  assert_true(
    @strategy.revise_strategy(run, [offer], registry, None) is Ok(NoFeasible),
  )
  assert_true(@strategy.strategy_report_count(run) > 0)
  assert_true(
    @strategy.strategy_report_at(run, 0).unwrap().rejection
    is Some(RetentionLimit),
  )
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
}

///|
test "pre-Run Local inventory counts both imports of one checked predecessor" {
  let (_, registry, registration, _, execution, guards, imports) = dispatch_preparation_test_inputs()
  let prepared = single_source_free_capacity_prepared(
    document=(
      #|{"version":"actql/0.1","id":"shared-input-inventory","stages":[{"id":"seed","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1},{"id":2}]},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}},{"id":"join","inputs":{"left":{"result":{"stage":"seed","result":"rows"}},"right":{"result":{"stage":"seed","result":"rows"}}},"steps":[{"from":"left","join":{"kind":"inner","with":"right","on":[{"left":"id","right":"id"}],"select":{"id":"left.id"},"max_output_rows":4},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"join","result":"rows"}}}}
    ),
  )
  let graph = @publication_host.prepared_client_graph(prepared)
  assert_eq(@strategy.graph_task_count(graph), 2)
  assert_eq(@strategy.graph_data_count(graph), 2)
  for index in 0..<2 {
    let edge = @strategy.graph_data_at(graph, index).unwrap()
    assert_eq(edge.producer, 0)
    assert_eq(edge.consumer, 1)
  }
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let sequences = prepare_client_local_sequences(
    prepared,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let base = @local_driver.prepare_local_dispatch_plan(
    graph, registry, registration, sequences, execution, guards, 100,
  ).unwrap()
  let original = @local_driver.prepare_local_dispatch_plan(
    graph,
    registry,
    registration,
    sequences,
    execution,
    guards,
    100,
    inputs=Some((imports, None)),
  ).unwrap()
  let imported = @local.local_import_retention_capacity(imports).unwrap()
  let before = @local_driver.local_dispatch_preparation_task_capacity(base, 1).unwrap()
  let selected = @local_driver.local_dispatch_preparation_task_capacity(
    original, 1,
  ).unwrap()
  assert_eq(selected.retained_bytes, before.retained_bytes + 2L * imported)
  assert_eq(
    selected.execution_bytes,
    before.execution_bytes + selected.retained_bytes,
  )
  assert_eq(selected.transfer_bytes, 2L * imports.wire.max_bytes.to_int64())
  assert_eq(
    @local_driver.local_dispatch_preparation_retained_bytes(original).unwrap(),
    @local_driver.local_dispatch_preparation_retained_bytes(base).unwrap() +
    2L * imported,
  )
  assert_eq(
    @local_driver.local_dispatch_preparation_transfer_bytes(original).unwrap(),
    selected.transfer_bytes,
  )
}

///|
test "original Local estimate eligibility uses slot zero for a source-free first task" {
  let (prepared, registry, registration, sequences, execution, guards, _) = dispatch_preparation_test_inputs()
  let graph = @publication_host.prepared_client_graph(prepared)
  assert_eq(@strategy.graph_captured_prefix(graph), 0)
  let original = @local_driver.prepare_local_dispatch_plan(
    graph, registry, registration, sequences, execution, guards, 100,
  ).unwrap()
  let ledger = @resources.create_ledger({
    planning_work: 10000,
    attempts: 1,
    holdings: 1,
    transfer_bytes: 10000L,
    retained_bytes: 64000000L,
    execution_bytes: 268435456L,
  }).unwrap()
  let run = @strategy.open_source_free_dag(graph, ledger).unwrap()
  let installed = @local_driver.bind_local_dispatch_plan(
    @host_driver.open_dispatch_driver(run),
    original,
  ).unwrap()
  let slots = @local_driver.local_dispatch_work_slots()
  let schedule = @cost.prepare_rate_schedule(
    slots,
    [
      {
        work_slots: Array::makei(slots, index => index),
        fixed_ms: Some(1L),
        per_row_ms: Some(0L),
        per_wire_byte_ms: Some(0L),
        per_pair_ms: Some(0L),
      },
    ],
    100,
  ).unwrap()
  let policy = @local_driver.prepare_local_estimate_module(
    installed,
    [schedule],
    1000,
    eligible=[false],
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  let offers = @local_driver.estimate_local_module_offers(policy, 0, {
    rows: None,
    wire_bytes: None,
    pairs: None,
  }).unwrap()
  assert_eq(offers.length(), 0)
  assert_eq(@resources.ledger_usage(ledger), before)
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
}
