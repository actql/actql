///|
fn local_values_window_program(variant : String) -> String {
  let (schema, rows, window) = match variant {
    "fixed" =>
      (
        "{\"at\":{\"type\":\"number\",\"nullable\":false},\"id\":{\"type\":\"number\",\"nullable\":false}}",
        "[{\"at\":-1,\"id\":1},{\"at\":2,\"id\":2},{\"at\":12,\"id\":3}]", "{\"kind\":\"fixed\",\"time\":\"at\",\"size\":10,\"step\":3,\"offset\":2}",
      )
    "sliding" =>
      (
        "{\"at\":{\"type\":\"number\",\"nullable\":false},\"id\":{\"type\":\"number\",\"nullable\":false}}",
        "[{\"at\":5,\"id\":1},{\"at\":7,\"id\":2}]", "{\"kind\":\"sliding\",\"time\":\"at\",\"size\":10,\"step\":6,\"offset\":2}",
      )
    "timestamp" =>
      (
        "{\"at\":{\"type\":\"timestamp\",\"nullable\":false},\"id\":{\"type\":\"number\",\"nullable\":false}}",
        "[{\"at\":\"1969-12-31T23:59:59.999Z\",\"id\":1},{\"at\":\"1970-01-01T00:00:00.250Z\",\"id\":2}]",
        "{\"kind\":\"fixed\",\"time\":\"at\",\"size\":1000,\"offset\":250}",
      )
    _ => abort("unknown Local window fixture")
  }
  "{\"version\":\"actql/0.1\",\"id\":\"p\",\"params\":{\"minimum\":{\"type\":\"number\",\"nullable\":false}},\"stages\":[" +
  "{\"id\":\"a\",\"inputs\":{\"remote\":{\"connector\":\"crm/main\",\"resource\":\"r\"}},\"steps\":[{\"filter\":\"id > $minimum\",\"as\":\"filtered\"},{\"select\":[\"id\"],\"as\":\"captured\"}],\"results\":{\"r\":{\"from\":\"captured\",\"fields\":[\"id\"]}}}," +
  "{\"id\":\"windowed\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":" +
  schema +
  ",\"rows\":" +
  rows +
  "},\"as\":\"seed\"},{\"from\":\"seed\",\"row_window\":" +
  window +
  ",\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"at\",\"id\",\"window_start\",\"window_end\"]}}}," +
  "{\"id\":\"consumer_a\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"windowed\",\"result\":\"r\"}}},\"steps\":[{\"select\":[\"at\",\"id\",\"window_end\",\"window_start\"],\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"at\",\"id\",\"window_end\",\"window_start\"]}}}," +
  "{\"id\":\"consumer_b\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"windowed\",\"result\":\"r\"}}},\"steps\":[{\"select\":[\"window_start\",\"id\",\"window_end\",\"at\"],\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":[\"window_start\",\"id\",\"window_end\",\"at\"]}}}]," +
  "\"results\":{\"source\":{\"from\":{\"stage\":\"a\",\"result\":\"r\"}}}}"
}

///|
fn run_local_managed_window_case(
  variant : String,
  expected : Array[String],
  reordered : Array[String],
) -> Unit raise {
  let (run, issuer) = captured_graph_fixture(
    local_values_window_chain=true,
    local_values_window_variant=variant,
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
        max_bytes: 1000,
        max_nodes: 100,
        max_depth: 10,
        max_columns: 4,
      },
      row: {
        max_bytes: 1000,
        max_nodes: 100,
        max_depth: 10,
        max_text_bytes: 1000,
      },
      max_batch_bytes: 1000,
    },
    None,
  ).unwrap()

  let producer_live = Ref(true)
  let (producer_ops, producer) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    producer_live,
  )
  let rows = local_managed_test_rows(producer_ops)
  assert_eq(rows, expected)

  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    2,
    [producer],
    [rows],
    2,
    first_live,
  )
  assert_eq(local_managed_test_rows(first_ops), expected)

  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    3,
    [producer],
    [rows],
    3,
    second_live,
  )
  assert_eq(local_managed_test_rows(second_ops), reordered)
  assert_true(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))

  first_live.val = false
  @strategy.close_captured_task_output(run, 2)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(producer))

  second_live.val = false
  @strategy.close_captured_task_output(run, 3)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  producer_live.val = false
  @strategy.close_captured_task_output(run, 1)
  (producer_ops.close)()
  (producer_ops.cleanup_refresh)() |> ignore
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
test "Local managed fixed row windows feed two downstream Computes" {
  run_local_managed_window_case(
    "fixed",
    [
      "{\"at\":-1,\"id\":1,\"window_end\":2,\"window_start\":-8}", "{\"at\":2,\"id\":2,\"window_end\":12,\"window_start\":2}",
      "{\"at\":12,\"id\":3,\"window_end\":22,\"window_start\":12}",
    ],
    [
      "{\"window_start\":-8,\"id\":1,\"window_end\":2,\"at\":-1}", "{\"window_start\":2,\"id\":2,\"window_end\":12,\"at\":2}",
      "{\"window_start\":12,\"id\":3,\"window_end\":22,\"at\":12}",
    ],
  )
}

///|
test "Local managed sliding row windows feed two downstream Computes" {
  run_local_managed_window_case(
    "sliding",
    [
      "{\"at\":5,\"id\":1,\"window_end\":6,\"window_start\":-4}", "{\"at\":5,\"id\":1,\"window_end\":12,\"window_start\":2}",
      "{\"at\":7,\"id\":2,\"window_end\":12,\"window_start\":2}",
    ],
    [
      "{\"window_start\":-4,\"id\":1,\"window_end\":6,\"at\":5}", "{\"window_start\":2,\"id\":1,\"window_end\":12,\"at\":5}",
      "{\"window_start\":2,\"id\":2,\"window_end\":12,\"at\":7}",
    ],
  )
}

///|
test "Local managed timestamp row windows use epoch milliseconds" {
  run_local_managed_window_case(
    "timestamp",
    [
      "{\"at\":\"1969-12-31T23:59:59.999Z\",\"id\":1,\"window_end\":250,\"window_start\":-750}",
      "{\"at\":\"1970-01-01T00:00:00.250Z\",\"id\":2,\"window_end\":1250,\"window_start\":250}",
    ],
    [
      "{\"window_start\":-750,\"id\":1,\"window_end\":250,\"at\":\"1969-12-31T23:59:59.999Z\"}",
      "{\"window_start\":250,\"id\":2,\"window_end\":1250,\"at\":\"1970-01-01T00:00:00.250Z\"}",
    ],
  )
}
