///|
fn local_values_lag_program(variant : String) -> String {
  let offset = match variant {
    "literal" => "1"
    "parameter" => "{\"$param\":\"minimum\"}"
    _ => abort("unknown Local lag fixture")
  }
  "{\"version\":\"actql/0.1\",\"id\":\"p\",\"params\":" +
  "{\"minimum\":{\"type\":\"number\",\"nullable\":false}}," +
  "\"stages\":[" +
  "{\"id\":\"a\",\"inputs\":{\"remote\":{\"connector\":" +
  "\"crm/main\",\"resource\":\"r\"}},\"steps\":[{\"filter\":" +
  "\"id > $minimum\",\"as\":\"filtered\"},{\"select\":[\"id\"]," +
  "\"as\":\"captured\"}],\"results\":{\"r\":{\"from\":" +
  "\"captured\",\"fields\":[\"id\"]}}}," +
  "{\"id\":\"lagged\",\"inputs\":{},\"steps\":[{\"values\":" +
  "{\"schema\":{\"group\":{\"type\":\"string\",\"nullable\":true}," +
  "\"id\":{\"type\":\"number\",\"nullable\":false},\"amount\":" +
  "{\"type\":\"number\",\"nullable\":true}},\"rows\":[" +
  "{\"group\":\"a\",\"id\":3,\"amount\":30}," +
  "{\"group\":null,\"id\":2,\"amount\":20}," +
  "{\"group\":\"a\",\"id\":1,\"amount\":10}," +
  "{\"group\":null,\"id\":4,\"amount\":null}," +
  "{\"group\":\"a\",\"id\":5,\"amount\":30}]},\"as\":\"seed\"}," +
  "{\"from\":\"seed\",\"assert_rows\":{\"unique_by\":[\"id\"]}," +
  "\"as\":\"unique\"},{\"from\":\"unique\",\"lag\":" +
  "{\"partition_by\":[\"group\",\"group\"],\"order_by\":[" +
  "{\"amount\":\"desc\"}],\"field\":\"amount\",\"output\":" +
  "\"previous\",\"offset\":" +
  offset +
  "},\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
  "\"fields\":[\"amount\",\"group\",\"id\",\"previous\"]}}}," +
  "{\"id\":\"consumer_a\",\"inputs\":{\"x\":{\"result\":" +
  "{\"stage\":\"lagged\",\"result\":\"r\"}}},\"steps\":[" +
  "{\"select\":[\"amount\",\"group\",\"id\",\"previous\"]," +
  "\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
  "\"fields\":[\"amount\",\"group\",\"id\",\"previous\"]}}}," +
  "{\"id\":\"consumer_b\",\"inputs\":{\"x\":{\"result\":" +
  "{\"stage\":\"lagged\",\"result\":\"r\"}}},\"steps\":[" +
  "{\"select\":[\"previous\",\"id\",\"group\",\"amount\"]," +
  "\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
  "\"fields\":[\"previous\",\"id\",\"group\",\"amount\"]}}}]," +
  "\"results\":{\"source\":{\"from\":{\"stage\":\"a\"," +
  "\"result\":\"r\"}}}}"
}

///|
fn run_local_managed_lag_case(variant : String) -> Unit raise {
  let (run, issuer) = captured_graph_fixture(
    local_values_lag_chain=true,
    local_values_lag_variant=variant,
    ledger_limits=Some({
      planning_work: 10000,
      attempts: 10,
      holdings: 10,
      transfer_bytes: 300000L,
      retained_bytes: 134217728L,
      execution_bytes: 134217728L,
    }),
  )
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let installed = @local_driver.prepare_local_dispatch_module(
    @host_driver.open_dispatch_driver(run),
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    dispatch_test_generated(run),
    limits.local_execution,
    limits.guards,
    limits.candidate_work,
  ).unwrap()
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: limits.local_execution.rows.input_values,
      wire: {
        ..retained_attempt_wire_limits(),
        max_bytes: 2000,
        max_nodes: 200,
        max_depth: 10,
        max_columns: 4,
      },
      row: {
        max_bytes: 2000,
        max_nodes: 200,
        max_depth: 10,
        max_text_bytes: 2000,
      },
      max_batch_bytes: 2000,
    },
    None,
  ).unwrap()

  let producer_live = Ref(true)
  let (values_ops, values) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    producer_live,
  )
  let values_rows = local_managed_test_rows(values_ops)
  let unique_live = Ref(true)
  let (unique_ops, unique) = run_local_managed_test_task(
    installed,
    run,
    2,
    [values],
    [values_rows],
    2,
    unique_live,
    execution_quantum=1,
    require_provider=true,
  )
  let unique_rows = local_managed_test_rows(unique_ops)
  let lag_live = Ref(true)
  let advances = Ref(0)
  let (producer_ops, producer) = run_local_managed_test_task(
    installed,
    run,
    3,
    [unique],
    [unique_rows],
    3,
    lag_live,
    execution_quantum=1,
    execution_advances=Some(advances),
    require_provider=true,
  )
  assert_true(advances.val > 5)
  let rows = local_managed_test_rows(producer_ops)
  assert_eq(rows, [
    "{\"amount\":30,\"group\":\"a\",\"id\":3,\"previous\":null}", "{\"amount\":20,\"group\":null,\"id\":2,\"previous\":null}",
    "{\"amount\":10,\"group\":\"a\",\"id\":1,\"previous\":30}", "{\"amount\":null,\"group\":null,\"id\":4,\"previous\":20}",
    "{\"amount\":30,\"group\":\"a\",\"id\":5,\"previous\":30}",
  ])

  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    4,
    [producer],
    [rows],
    4,
    first_live,
  )
  assert_eq(local_managed_test_rows(first_ops), rows)
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    5,
    [producer],
    [rows],
    5,
    second_live,
  )
  assert_eq(local_managed_test_rows(second_ops), [
    "{\"previous\":null,\"id\":3,\"group\":\"a\",\"amount\":30}", "{\"previous\":null,\"id\":2,\"group\":null,\"amount\":20}",
    "{\"previous\":30,\"id\":1,\"group\":\"a\",\"amount\":10}", "{\"previous\":20,\"id\":4,\"group\":null,\"amount\":null}",
    "{\"previous\":30,\"id\":5,\"group\":\"a\",\"amount\":30}",
  ])

  close_retained_host_consumer(run, 4, first_ops, first_live, first)
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(producer))

  close_retained_host_consumer(run, 5, second_ops, second_live, second)
  lag_live.val = false
  @strategy.close_captured_task_output(run, 3)
  (producer_ops.close)()
  (producer_ops.cleanup_refresh)() |> ignore
  unique_live.val = false
  @strategy.close_captured_task_output(run, 2)
  (unique_ops.close)()
  (unique_ops.cleanup_refresh)() |> ignore
  producer_live.val = false
  @strategy.close_captured_task_output(run, 1)
  (values_ops.close)()
  (values_ops.cleanup_refresh)() |> ignore
  @strategy.stop_captured_dag(run)
  @strategy.close_captured_task_output(run, 0)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}

///|
test "Local managed literal lag feeds two downstream Computes" {
  run_local_managed_lag_case("literal")
}

///|
test "Local managed parameter lag feeds two downstream Computes" {
  run_local_managed_lag_case("parameter")
}

///|
test "Local lag chain pre-execution values cancellation reclaims" {
  let (run, issuer) = captured_graph_fixture(
    local_values_lag_chain=true,
    local_values_lag_variant="literal",
  )
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let installed = @local_driver.prepare_local_dispatch_module(
    @host_driver.open_dispatch_driver(run),
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    dispatch_test_generated(run),
    limits.local_execution,
    limits.guards,
    limits.candidate_work,
  ).unwrap()
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: limits.local_execution.rows.input_values,
      wire: {
        ..retained_attempt_wire_limits(),
        max_bytes: 2000,
        max_nodes: 200,
        max_depth: 10,
        max_columns: 4,
      },
      row: {
        max_bytes: 2000,
        max_nodes: 200,
        max_depth: 10,
        max_text_bytes: 2000,
      },
      max_batch_bytes: 2000,
    },
    None,
  ).unwrap()
  let owner = @strategy.graph_task_owner(@strategy.captured_dag_graph(run), 1).unwrap()
  let setup = @local_driver.prepare_local_managed_dispatch(
      installed,
      [],
      @execution.process_managed_obligations(owner),
      0L,
    )
    .unwrap()
    .unwrap()
  let operations = @local_driver.start_local_managed_dispatch_node(setup).unwrap()
  (operations.close)()
  assert_true((operations.execute)() is Err(_))
  assert_true(
    (operations.complete)(1, operations.storage_bytes, fn() { true }) is Err(_),
  )
  (operations.settle)().unwrap()
  (operations.cleanup_refresh)() |> ignore
  assert_false(@strategy.captured_task_completed(run, 1))
  @strategy.stop_captured_dag(run)
  for task in 0..<6 {
    @strategy.close_captured_task_output(run, task)
  }
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}
