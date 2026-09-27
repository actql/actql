///|
fn local_values_watermark_program(variant : String) -> String {
  let (threshold, policy) = match variant {
    "fixed_mark" => ("\"watermark_ms\":90", "mark")
    "prefix_drop" => ("\"max_skew\":10", "drop")
    _ => abort("unknown Local watermark fixture")
  }
  let fields = "[\"id\",\"time\",\"watermark_ms\"," +
    "\"watermark_late\",\"watermark_decision\"]"
  let reversed = "[\"watermark_decision\",\"watermark_late\"," +
    "\"watermark_ms\",\"time\",\"id\"]"
  "{\"version\":\"actql/0.1\",\"id\":\"p\",\"params\":" +
  "{\"minimum\":{\"type\":\"number\",\"nullable\":false}}," +
  "\"stages\":[" +
  "{\"id\":\"a\",\"inputs\":{\"remote\":{\"connector\":" +
  "\"crm/main\",\"resource\":\"r\"}},\"steps\":[{\"filter\":" +
  "\"id > $minimum\",\"as\":\"filtered\"},{\"select\":[\"id\"]," +
  "\"as\":\"captured\"}],\"results\":{\"r\":{\"from\":" +
  "\"captured\",\"fields\":[\"id\"]}}}," +
  "{\"id\":\"watermarked\",\"inputs\":{},\"steps\":[{\"values\":" +
  "{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}," +
  "\"time\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[" +
  "{\"id\":1,\"time\":100},{\"id\":2,\"time\":80}," +
  "{\"id\":3,\"time\":95}]},\"as\":\"seed\"},{\"from\":\"seed\"," +
  "\"watermark_rows\":{\"time\":\"time\",\"late_policy\":\"" +
  policy +
  "\"," +
  threshold +
  "},\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\"," +
  "\"fields\":" +
  fields +
  "}}}," +
  "{\"id\":\"consumer_a\",\"inputs\":{\"x\":{\"result\":" +
  "{\"stage\":\"watermarked\",\"result\":\"r\"}}},\"steps\":[" +
  "{\"select\":" +
  fields +
  ",\"as\":\"out\"}],\"results\":{\"r\":" +
  "{\"from\":\"out\",\"fields\":" +
  fields +
  "}}}," +
  "{\"id\":\"consumer_b\",\"inputs\":{\"x\":{\"result\":" +
  "{\"stage\":\"watermarked\",\"result\":\"r\"}}},\"steps\":[" +
  "{\"select\":" +
  reversed +
  ",\"as\":\"out\"}],\"results\":{\"r\":" +
  "{\"from\":\"out\",\"fields\":" +
  reversed +
  "}}}]," +
  "\"results\":{\"source\":{\"from\":{\"stage\":\"a\"," +
  "\"result\":\"r\"}}}}"
}

///|
fn run_local_managed_watermark_case(variant : String) -> Unit raise {
  let (run, issuer) = captured_graph_fixture(
    local_values_watermark_chain=true,
    local_values_watermark_variant=variant,
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
        max_bytes: 3000,
        max_nodes: 300,
        max_depth: 10,
        max_columns: 5,
      },
      row: {
        max_bytes: 3000,
        max_nodes: 300,
        max_depth: 10,
        max_text_bytes: 3000,
      },
      max_batch_bytes: 3000,
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
  let input_rows = local_managed_test_rows(values_ops)
  assert_eq(input_rows, [
    "{\"id\":1,\"time\":100}", "{\"id\":2,\"time\":80}", "{\"id\":3,\"time\":95}",
  ])
  let watermark_live = Ref(true)
  let advances = Ref(0)
  let (producer_ops, producer) = run_local_managed_test_task(
    installed,
    run,
    2,
    [values],
    [input_rows],
    2,
    watermark_live,
    execution_quantum=1,
    execution_advances=Some(advances),
    require_provider=true,
  )
  assert_true(advances.val > 4)
  let rows = local_managed_test_rows(producer_ops)
  let expected = if variant == "fixed_mark" {
    [
      "{\"id\":1,\"time\":100,\"watermark_decision\":\"keep\"," +
      "\"watermark_late\":false,\"watermark_ms\":90}",
      "{\"id\":2,\"time\":80,\"watermark_decision\":\"mark\"," +
      "\"watermark_late\":true,\"watermark_ms\":90}",
      "{\"id\":3,\"time\":95,\"watermark_decision\":\"keep\"," +
      "\"watermark_late\":false,\"watermark_ms\":90}",
    ]
  } else {
    [
      "{\"id\":1,\"time\":100,\"watermark_decision\":\"keep\"," +
      "\"watermark_late\":false,\"watermark_ms\":90}",
      "{\"id\":3,\"time\":95,\"watermark_decision\":\"keep\"," +
      "\"watermark_late\":false,\"watermark_ms\":90}",
    ]
  }
  assert_eq(rows, expected)

  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    3,
    [producer],
    [rows],
    3,
    first_live,
  )
  let authored = if variant == "fixed_mark" {
    [
      "{\"id\":1,\"time\":100,\"watermark_ms\":90," +
      "\"watermark_late\":false,\"watermark_decision\":\"keep\"}",
      "{\"id\":2,\"time\":80,\"watermark_ms\":90," +
      "\"watermark_late\":true,\"watermark_decision\":\"mark\"}",
      "{\"id\":3,\"time\":95,\"watermark_ms\":90," +
      "\"watermark_late\":false,\"watermark_decision\":\"keep\"}",
    ]
  } else {
    [
      "{\"id\":1,\"time\":100,\"watermark_ms\":90," +
      "\"watermark_late\":false,\"watermark_decision\":\"keep\"}",
      "{\"id\":3,\"time\":95,\"watermark_ms\":90," +
      "\"watermark_late\":false,\"watermark_decision\":\"keep\"}",
    ]
  }
  assert_eq(local_managed_test_rows(first_ops), authored)
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    4,
    [producer],
    [rows],
    4,
    second_live,
  )
  assert_eq(local_managed_test_rows(second_ops).length(), expected.length())

  first_live.val = false
  @strategy.close_captured_task_output(run, 3)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(producer))

  second_live.val = false
  @strategy.close_captured_task_output(run, 4)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  watermark_live.val = false
  @strategy.close_captured_task_output(run, 2)
  (producer_ops.close)()
  (producer_ops.cleanup_refresh)() |> ignore
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
test "Local managed fixed watermark feeds two downstream Computes" {
  run_local_managed_watermark_case("fixed_mark")
}

///|
test "Local managed prefix watermark feeds two downstream Computes" {
  run_local_managed_watermark_case("prefix_drop")
}
