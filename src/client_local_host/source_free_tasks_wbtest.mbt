///|
// The original public SQL and packaged Environment, not a hand-flattened
// Values graph. This diagnostic supplies unaccounted test Ledger limits only;
// it is not a Native operational service, Account or durable Run admission.
fn source_free_tasks_original_union() -> @publication_host.PreparedClientProgram raise {
  let assets = @publication_host.client_local_product_assets()
  guard @json.parse(assets.environment) is Object(fields) &&
    fields.get("evidence_bundle_cid") is Some(String(cid)) else {
    fail("original product Environment evidence")
  }
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let context = @frontend.bind_query_context([], cid).unwrap()
  let original = @frontend.lower(
    "SELECT 1 AS n UNION ALL SELECT 2 AS n",
    @frontend.Sql,
    Some(context),
  ).unwrap()
  @publication_host.prepare_parsed_effect_free_client_program(
    original.program.unwrap(),
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
}

///|
test "the original eight-task public UNION quotes every original input and executes on one Ledger" {
  let prepared = source_free_tasks_original_union()
  let assets = @publication_host.client_local_product_assets()
  let asset_contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let graph = @publication_host.prepared_client_graph(prepared)
  assert_eq(@strategy.graph_task_count(graph), 8)
  assert_eq(@strategy.graph_result_task(graph, 0), Some(7))
  let original = prepare_source_free_local_requirements(
    prepared,
    asset_contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let limits = original.maximum_limits()
  assert_eq(limits.attempts, 8)
  assert_eq(limits.holdings, 8)
  assert_true(limits.retained_bytes <= 536870912L)
  assert_eq(limits.execution_bytes, 536870912L)
  let ledger = @resources.create_ledger(limits).unwrap()
  let setup = open_source_free_local_retained_host_on_ledger(
    prepared,
    ledger,
    asset_contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    requirements=Some(original),
  ).unwrap()
  let execution = match
    execute_source_free_local_tasks_guarded(setup, 64, 100000, () => true) {
    Ok(value) => value
    Err(failure) => {
      retry_local_values_execution_failure_cleanup(failure) |> ignore
      fail("original UNION execution failed")
    }
  }
  assert_eq(execution.rows().unwrap(), ["{\"n\":1}", "{\"n\":2}"])
  assert_eq(@resources.ledger_usage(ledger).attempts, 8)
  let rows : @execution.RetainedRowDecodeLimits = {
    max_bytes: 100,
    max_nodes: 20,
    max_depth: 4,
    max_text_bytes: 100,
  }
  let wire : @execution.RowWireLimits = {
    max_columns: 10,
    max_order_work: 100,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 20,
  }
  let export_limits : @publication_host.PublicationOutputExportLimits = {
    max_result_fields: 10,
    max_result_mapping_work: 100,
    max_result_order_work: 100,
    max_result_workspace_entries: 100,
    max_rows: 100,
    values: {
      max_nodes: 1000,
      max_text_bytes: 10000,
      max_depth: 20,
      max_work: 10000,
    },
    payload_wire: wire,
    logical_wire: wire,
    schema: {
      max_fields: 10,
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 20,
    },
    max_batch_bytes: 64,
  }
  assert_true(
    execution.prepare_result_export(1, rows, 100, 10000, export_limits)
    is Err(UnknownResult),
  )
  let result = execution
    .prepare_result_export(0, rows, 100, 10000, export_limits)
    .unwrap()
  let stream = result.output_export()
  let text = StringBuilder()
  while stream.next().unwrap() is Some(chunk) {
    text.write_string(chunk)
  }
  text.write_string(stream.finish().unwrap())
  assert_eq(text.to_string(), "[{\"n\":1},{\"n\":2}]")
  assert_eq(stream.result_fields().unwrap(), ["n"])
  result.close()
  assert_true(execution.close())
  assert_true(execution.close())
  assert_true(
    execution.prepare_result_export(0, rows, 100, 10000, export_limits)
    is Err(MissingOutput),
  )
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
}

///|
test "source-free multi-task current refusal cannot execute or replace the original graph" {
  let prepared = source_free_tasks_original_union()
  let assets = @publication_host.client_local_product_assets()
  let asset_contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let original = prepare_source_free_local_requirements(
    prepared,
    asset_contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let limits = original.maximum_limits()
  let ledger = @resources.create_ledger(limits).unwrap()
  let setup = open_source_free_local_retained_host_on_ledger(
    prepared,
    ledger,
    asset_contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    requirements=Some(original),
  ).unwrap()
  guard execute_source_free_local_tasks_guarded(setup, 64, 100000, () => false)
    is Err(failure) else {
    fail("current refusal expected")
  }
  assert_true(local_values_execution_failure_issue(failure) is Fenced)
  assert_true(retry_local_values_execution_failure_cleanup(failure))
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
}

///|
test "source-free multi-task current loss after the first completed task retains one cleanup and never executes another task" {
  let prepared = source_free_tasks_original_union()
  let assets = @publication_host.client_local_product_assets()
  let asset_contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let original = prepare_source_free_local_requirements(
    prepared,
    asset_contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let limits = original.maximum_limits()
  let ledger = @resources.create_ledger(limits).unwrap()
  let setup = open_source_free_local_retained_host_on_ledger(
    prepared,
    ledger,
    asset_contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    requirements=Some(original),
  ).unwrap()
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(setup),
  )
  let observed_completion = Ref(false)
  let current = fn() {
    if @strategy.captured_task_completed(run, 0) {
      observed_completion.val = true
      false
    } else {
      !observed_completion.val
    }
  }
  guard execute_source_free_local_tasks_guarded(setup, 64, 100000, current)
    is Err(failure) else {
    fail("current loss after the original completed predecessor expected")
  }
  assert_true(observed_completion.val)
  assert_true(local_values_execution_failure_issue(failure) is Fenced)
  assert_true(retry_local_values_execution_failure_cleanup(failure))
  assert_true(retry_local_values_execution_failure_cleanup(failure))
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.attempts, 1)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
}

///|
fn source_free_tasks_boundary_counts(
  quantum : Int,
) -> (Int, Int, Array[String]) raise {
  let prepared = source_free_tasks_original_union()
  let assets = @publication_host.client_local_product_assets()
  let asset_contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let original = prepare_source_free_local_requirements(
    prepared,
    asset_contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let limits = original.maximum_limits()
  let ledger = @resources.create_ledger(limits).unwrap()
  let setup = open_source_free_local_retained_host_on_ledger(
    prepared,
    ledger,
    asset_contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    requirements=Some(original),
  ).unwrap()
  let boundaries = Ref(0)
  let polls = Ref(0)
  let execution = match
    execute_source_free_local_tasks_guarded(
      setup,
      quantum,
      100000,
      () => {
        boundaries.val += 1
        true
      },
      require_live=Some(() => {
        polls.val += 1
        true
      }),
    ) {
    Ok(value) => value
    Err(failure) => {
      retry_local_values_execution_failure_cleanup(failure) |> ignore
      fail("source-free execution refused")
    }
  }
  let rows = execution.rows().unwrap()
  assert_true(execution.close())
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  (boundaries.val, polls.val, rows)
}

///|
test "closed source-free finalization quantum changes lifetime polling but not authorization boundaries" {
  let (small_boundaries, small_polls, small_rows) = source_free_tasks_boundary_counts(
    1,
  )
  let (large_boundaries, large_polls, large_rows) = source_free_tasks_boundary_counts(
    64,
  )
  assert_eq(small_rows, ["{\"n\":1}", "{\"n\":2}"])
  assert_eq(small_rows, large_rows)
  assert_eq(small_boundaries, large_boundaries)
  assert_true(small_polls > large_polls)
}

///|
test "a retired source-free lifetime refuses before dispatch despite unchanged authority" {
  let prepared = source_free_tasks_original_union()
  let assets = @publication_host.client_local_product_assets()
  let asset_contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let original = prepare_source_free_local_requirements(
    prepared,
    asset_contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let limits = original.maximum_limits()
  let ledger = @resources.create_ledger(limits).unwrap()
  let setup = open_source_free_local_retained_host_on_ledger(
    prepared,
    ledger,
    asset_contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    requirements=Some(original),
  ).unwrap()
  guard execute_source_free_local_tasks_guarded(
      setup,
      64,
      100000,
      () => true,
      require_live=Some(() => false),
    )
    is Err(failure) else {
    fail("retired original lifetime must refuse")
  }
  assert_true(local_values_execution_failure_issue(failure) is Fenced)
  assert_true(retry_local_values_execution_failure_cleanup(failure))
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
}
