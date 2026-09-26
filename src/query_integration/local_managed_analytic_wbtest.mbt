///|
fn local_values_analytic_program(variant : String) -> String {
  let (schema, rows, functions, fields, reordered) = match variant {
    "baseline" =>
      (
        "{\"amount\":{\"type\":\"number\",\"nullable\":true}," +
        "\"group\":{\"type\":\"string\",\"nullable\":true}," +
        "\"id\":{\"type\":\"number\",\"nullable\":false}}",
        "[{\"amount\":30,\"group\":\"a\",\"id\":3},{\"amount\":20,\"group\":null,\"id\":2},{\"amount\":10,\"group\":\"a\",\"id\":1},{\"amount\":null,\"group\":null,\"id\":4},{\"amount\":30,\"group\":\"a\",\"id\":5}]",
        "{\"n\":{\"fn\":\"count\",\"field\":\"amount\"},\"position\":{\"fn\":\"row_number\"},\"previous\":{\"fn\":\"lag\",\"expr\":\"amount\"}}",
        "[\"amount\",\"group\",\"id\",\"n\",\"position\",\"previous\"]",
        "[\"previous\",\"position\",\"n\",\"id\",\"group\",\"amount\"]",
      )
    "filtered_expression" =>
      (
        "{\"amount\":{\"type\":\"number\",\"nullable\":true}," +
        "\"group\":{\"type\":\"string\",\"nullable\":true}," +
        "\"id\":{\"type\":\"number\",\"nullable\":false}}",
        "[{\"amount\":30,\"group\":\"a\",\"id\":3},{\"amount\":20,\"group\":null,\"id\":2},{\"amount\":10,\"group\":\"a\",\"id\":1},{\"amount\":0,\"group\":null,\"id\":4},{\"amount\":30,\"group\":\"a\",\"id\":5}]",
        "{\"lowest\":{\"fn\":\"min\",\"expr\":\"amount + 1\",\"filter\":\"amount > 0\"}}",
        "[\"amount\",\"group\",\"id\",\"lowest\"]",
        "[\"lowest\",\"id\",\"group\",\"amount\"]",
      )
    "numeric" | "numeric_take" =>
      (
        "{\"amount\":{\"type\":\"number\",\"nullable\":true}," +
        "\"group\":{\"type\":\"string\",\"nullable\":true}," +
        "\"id\":{\"type\":\"number\",\"nullable\":false}}",
        "[{\"amount\":10000000000000000,\"group\":\"a\",\"id\":1}," +
        "{\"amount\":1,\"group\":\"a\",\"id\":2}," +
        "{\"amount\":-10000000000000000,\"group\":\"a\",\"id\":3}]",
        "{\"mean\":{\"fn\":\"avg\",\"field\":\"amount\"}," +
        "\"total\":{\"fn\":\"sum\",\"field\":\"amount\"}}",
        "[\"amount\",\"group\",\"id\",\"mean\",\"total\"]",
        "[\"total\",\"mean\",\"id\",\"group\",\"amount\"]",
      )
    "navigation" =>
      (
        "{\"amount\":{\"type\":\"number\",\"nullable\":true}," +
        "\"group\":{\"type\":\"string\",\"nullable\":true}," +
        "\"id\":{\"type\":\"number\",\"nullable\":false}}",
        "[{\"amount\":30,\"group\":\"a\",\"id\":3}," +
        "{\"amount\":20,\"group\":null,\"id\":2}," +
        "{\"amount\":10,\"group\":\"a\",\"id\":1}," +
        "{\"amount\":null,\"group\":null,\"id\":4}," +
        "{\"amount\":30,\"group\":\"a\",\"id\":5}]",
        "{\"dense\":{\"fn\":\"dense_rank\"}," +
        "\"first\":{\"fn\":\"first_value\",\"expr\":\"amount\"}," +
        "\"last\":{\"fn\":\"last_value\",\"expr\":\"amount\"}," +
        "\"next\":{\"fn\":\"lead\",\"expr\":\"amount\"}," +
        "\"position\":{\"fn\":\"row_number\"}," +
        "\"previous\":{\"fn\":\"lag\",\"expr\":\"amount\"}," +
        "\"ranked\":{\"fn\":\"rank\"}}",
        "[\"amount\",\"dense\",\"first\",\"group\",\"id\"," +
        "\"last\",\"next\",\"position\",\"previous\",\"ranked\"]",
        "[\"ranked\",\"previous\",\"position\",\"next\",\"last\"," +
        "\"id\",\"group\",\"first\",\"dense\",\"amount\"]",
      )
    "collections" =>
      (
        "{\"amount\":{\"type\":\"number\",\"nullable\":true}," +
        "\"group\":{\"type\":\"string\",\"nullable\":true}," +
        "\"id\":{\"type\":\"number\",\"nullable\":false}}",
        "[{\"amount\":30,\"group\":\"a\",\"id\":3}," +
        "{\"amount\":20,\"group\":null,\"id\":2}," +
        "{\"amount\":10,\"group\":\"a\",\"id\":1}," +
        "{\"amount\":null,\"group\":null,\"id\":4}," +
        "{\"amount\":30,\"group\":\"a\",\"id\":5}]",
        "{\"items\":{\"fn\":\"array_agg\",\"field\":\"amount\"," +
        "\"distinct\":true,\"max_items\":3}," +
        "\"text\":{\"fn\":\"string_agg\",\"field\":\"group\"," +
        "\"delimiter\":\"|\",\"max_bytes\":10}}",
        "[\"amount\",\"group\",\"id\",\"items\",\"text\"]",
        "[\"text\",\"items\",\"id\",\"group\",\"amount\"]",
      )
    "statistics" =>
      (
        "{\"amount\":{\"type\":\"number\",\"nullable\":true}," +
        "\"group\":{\"type\":\"string\",\"nullable\":true}," +
        "\"id\":{\"type\":\"number\",\"nullable\":false}}",
        "[{\"amount\":3,\"group\":\"a\",\"id\":3}," +
        "{\"amount\":1,\"group\":\"a\",\"id\":1}," +
        "{\"amount\":2,\"group\":\"a\",\"id\":2}]",
        "{\"continuous\":{\"fn\":\"percentile_cont\"," +
        "\"field\":\"amount\",\"fraction\":0.5}," +
        "\"discrete\":{\"fn\":\"percentile_disc\"," +
        "\"field\":\"amount\",\"fraction\":0.5}," +
        "\"population\":{\"fn\":\"var_pop\",\"field\":\"amount\"}," +
        "\"population_deviation\":{\"fn\":\"stddev_pop\"," +
        "\"field\":\"amount\"},\"sample\":{\"fn\":\"var_samp\"," +
        "\"field\":\"amount\"},\"sample_deviation\":{" +
        "\"fn\":\"stddev_samp\",\"field\":\"amount\"}}",
        "[\"amount\",\"continuous\",\"discrete\",\"group\",\"id\"," +
        "\"population\",\"population_deviation\",\"sample\"," +
        "\"sample_deviation\"]",
        "[\"sample_deviation\",\"sample\",\"population_deviation\"," +
        "\"population\",\"id\",\"group\",\"discrete\"," +
        "\"continuous\",\"amount\"]",
      )
    _ => abort("unknown Local analytic fixture")
  }
  "{\"version\":\"actql/0.1\",\"id\":\"p\",\"params\":{\"minimum\":{\"type\":\"number\",\"nullable\":false}},\"stages\":[" +
  "{\"id\":\"a\",\"inputs\":{\"remote\":{\"connector\":\"crm/main\",\"resource\":\"r\"}},\"steps\":[{\"filter\":\"id > $minimum\",\"as\":\"filtered\"},{\"select\":[\"id\"],\"as\":\"captured\"}],\"results\":{\"r\":{\"from\":\"captured\",\"fields\":[\"id\"]}}}," +
  "{\"id\":\"analytic_rows\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":" +
  schema +
  ",\"rows\":" +
  rows +
  "},\"as\":\"seed\"},{\"from\":\"seed\",\"analytic\":{\"partition_by\":[\"group\"],\"order_by\":[{\"id\":\"asc\"}],\"frame\":{\"start\":\"unbounded_preceding\",\"end\":\"current_row\"},\"functions\":" +
  functions +
  "},\"as\":\"analytic_out\"}" +
  (if variant == "numeric_take" {
    ",{\"from\":\"analytic_out\",\"take\":1,\"as\":\"out\"}"
  } else {
    ",{\"from\":\"analytic_out\",\"select\":" + fields + ",\"as\":\"out\"}"
  }) +
  "],\"results\":{\"r\":{\"from\":\"out\",\"fields\":" +
  fields +
  "}}}," +
  "{\"id\":\"consumer_a\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"analytic_rows\",\"result\":\"r\"}}},\"steps\":[{\"select\":" +
  fields +
  ",\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":" +
  fields +
  "}}}," +
  "{\"id\":\"consumer_b\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"analytic_rows\",\"result\":\"r\"}}},\"steps\":[{\"select\":" +
  reordered +
  ",\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":" +
  reordered +
  "}}}],\"results\":{\"source\":{\"from\":{\"stage\":\"a\",\"result\":\"r\"}}}}"
}

///|
fn run_local_managed_analytic_case(
  variant : String,
  expected : Array[String],
  reordered : Array[String],
) -> Unit raise {
  let (run, issuer) = captured_graph_fixture(
    local_values_analytic_chain=true,
    local_values_analytic_variant=variant,
  )
  let registry = search_registry()
  let limits = { ..dispatch_test_limits(), candidate_work: 1000, }
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
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 20,
        max_columns: 12,
      },
      row: {
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 20,
        max_text_bytes: 10000,
      },
      max_batch_bytes: 10000,
    },
    None,
  ).unwrap()

  let producer_live = Ref(true)
  let producer_advances = Ref(0)
  let (producer_ops, producer) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    producer_live,
    execution_quantum=1,
    execution_advances=Some(producer_advances),
    require_provider=true,
  )
  assert_true(producer_advances.val > 4)
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
  assert_eq(local_managed_test_rows(first_ops), rows)

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
test "Local managed analytic reaches two downstream Computes" {
  run_local_managed_analytic_case(
    "baseline",
    [
      "{\"amount\":30,\"group\":\"a\",\"id\":3,\"n\":2,\"position\":2,\"previous\":10}",
      "{\"amount\":20,\"group\":null,\"id\":2,\"n\":1,\"position\":1,\"previous\":null}",
      "{\"amount\":10,\"group\":\"a\",\"id\":1,\"n\":1,\"position\":1,\"previous\":null}",
      "{\"amount\":null,\"group\":null,\"id\":4,\"n\":1,\"position\":2,\"previous\":20}",
      "{\"amount\":30,\"group\":\"a\",\"id\":5,\"n\":3,\"position\":3,\"previous\":30}",
    ],
    [
      "{\"previous\":10,\"position\":2,\"n\":2,\"id\":3,\"group\":\"a\",\"amount\":30}",
      "{\"previous\":null,\"position\":1,\"n\":1,\"id\":2,\"group\":null,\"amount\":20}",
      "{\"previous\":null,\"position\":1,\"n\":1,\"id\":1,\"group\":\"a\",\"amount\":10}",
      "{\"previous\":20,\"position\":2,\"n\":1,\"id\":4,\"group\":null,\"amount\":null}",
      "{\"previous\":30,\"position\":3,\"n\":3,\"id\":5,\"group\":\"a\",\"amount\":30}",
    ],
  )
}

///|
test "Local managed analytic filters gate aggregate expression demand" {
  run_local_managed_analytic_case(
    "filtered_expression",
    [
      "{\"amount\":30,\"group\":\"a\",\"id\":3,\"lowest\":11}", "{\"amount\":20,\"group\":null,\"id\":2,\"lowest\":21}",
      "{\"amount\":10,\"group\":\"a\",\"id\":1,\"lowest\":11}", "{\"amount\":0,\"group\":null,\"id\":4,\"lowest\":21}",
      "{\"amount\":30,\"group\":\"a\",\"id\":5,\"lowest\":11}",
    ],
    [
      "{\"lowest\":11,\"id\":3,\"group\":\"a\",\"amount\":30}", "{\"lowest\":21,\"id\":2,\"group\":null,\"amount\":20}",
      "{\"lowest\":11,\"id\":1,\"group\":\"a\",\"amount\":10}", "{\"lowest\":21,\"id\":4,\"group\":null,\"amount\":0}",
      "{\"lowest\":11,\"id\":5,\"group\":\"a\",\"amount\":30}",
    ],
  )
}

///|
test "Local managed analytic navigation feeds two downstream Computes" {
  run_local_managed_analytic_case(
    "navigation",
    [
      "{\"amount\":30,\"dense\":2,\"first\":10,\"group\":\"a\"," +
      "\"id\":3,\"last\":30,\"next\":30,\"position\":2," +
      "\"previous\":10,\"ranked\":2}",
      "{\"amount\":20,\"dense\":1,\"first\":20,\"group\":null," +
      "\"id\":2,\"last\":20,\"next\":null,\"position\":1," +
      "\"previous\":null,\"ranked\":1}",
      "{\"amount\":10,\"dense\":1,\"first\":10,\"group\":\"a\"," +
      "\"id\":1,\"last\":10,\"next\":30,\"position\":1," +
      "\"previous\":null,\"ranked\":1}",
      "{\"amount\":null,\"dense\":2,\"first\":20,\"group\":null," +
      "\"id\":4,\"last\":null,\"next\":null,\"position\":2," +
      "\"previous\":20,\"ranked\":2}",
      "{\"amount\":30,\"dense\":3,\"first\":10,\"group\":\"a\"," +
      "\"id\":5,\"last\":30,\"next\":null,\"position\":3," +
      "\"previous\":30,\"ranked\":3}",
    ],
    [
      "{\"ranked\":2,\"previous\":10,\"position\":2,\"next\":30," +
      "\"last\":30,\"id\":3,\"group\":\"a\",\"first\":10," +
      "\"dense\":2,\"amount\":30}",
      "{\"ranked\":1,\"previous\":null,\"position\":1," +
      "\"next\":null,\"last\":20,\"id\":2,\"group\":null," +
      "\"first\":20,\"dense\":1,\"amount\":20}",
      "{\"ranked\":1,\"previous\":null,\"position\":1,\"next\":30," +
      "\"last\":10,\"id\":1,\"group\":\"a\",\"first\":10," +
      "\"dense\":1,\"amount\":10}",
      "{\"ranked\":2,\"previous\":20,\"position\":2,\"next\":null," +
      "\"last\":null,\"id\":4,\"group\":null,\"first\":20," +
      "\"dense\":2,\"amount\":null}",
      "{\"ranked\":3,\"previous\":30,\"position\":3,\"next\":null," +
      "\"last\":30,\"id\":5,\"group\":\"a\",\"first\":10," +
      "\"dense\":3,\"amount\":30}",
    ],
  )
}

///|
test "Local managed analytic collections feed two downstream Computes" {
  run_local_managed_analytic_case(
    "collections",
    [
      "{\"amount\":30,\"group\":\"a\",\"id\":3," +
      "\"items\":[10,30],\"text\":\"a|a\"}",
      "{\"amount\":20,\"group\":null,\"id\":2," +
      "\"items\":[20],\"text\":null}",
      "{\"amount\":10,\"group\":\"a\",\"id\":1," +
      "\"items\":[10],\"text\":\"a\"}",
      "{\"amount\":null,\"group\":null,\"id\":4," +
      "\"items\":[20],\"text\":null}",
      "{\"amount\":30,\"group\":\"a\",\"id\":5," +
      "\"items\":[10,30],\"text\":\"a|a|a\"}",
    ],
    [
      "{\"text\":\"a|a\",\"items\":[10,30],\"id\":3," +
      "\"group\":\"a\",\"amount\":30}",
      "{\"text\":null,\"items\":[20],\"id\":2,\"group\":null," +
      "\"amount\":20}",
      "{\"text\":\"a\",\"items\":[10],\"id\":1," +
      "\"group\":\"a\",\"amount\":10}",
      "{\"text\":null,\"items\":[20],\"id\":4,\"group\":null," +
      "\"amount\":null}",
      "{\"text\":\"a|a|a\",\"items\":[10,30],\"id\":5," +
      "\"group\":\"a\",\"amount\":30}",
    ],
  )
}

///|
test "Local managed analytic statistics feed two downstream Computes" {
  run_local_managed_analytic_case(
    "statistics",
    [
      "{\"amount\":3,\"continuous\":2,\"discrete\":2," +
      "\"group\":\"a\",\"id\":3,\"population\":" +
      "0.6666666666666666,\"population_deviation\":" +
      "0.816496580927726,\"sample\":1,\"sample_deviation\":1}",
      "{\"amount\":1,\"continuous\":1,\"discrete\":1," +
      "\"group\":\"a\",\"id\":1,\"population\":0," +
      "\"population_deviation\":0,\"sample\":null," +
      "\"sample_deviation\":null}",
      "{\"amount\":2,\"continuous\":1.5,\"discrete\":1," +
      "\"group\":\"a\",\"id\":2,\"population\":0.25," +
      "\"population_deviation\":0.5,\"sample\":0.5," +
      "\"sample_deviation\":0.7071067811865476}",
    ],
    [
      "{\"sample_deviation\":1,\"sample\":1," +
      "\"population_deviation\":0.816496580927726," +
      "\"population\":0.6666666666666666,\"id\":3," +
      "\"group\":\"a\",\"discrete\":2,\"continuous\":2," +
      "\"amount\":3}",
      "{\"sample_deviation\":null,\"sample\":null," +
      "\"population_deviation\":0,\"population\":0,\"id\":1," +
      "\"group\":\"a\",\"discrete\":1,\"continuous\":1," +
      "\"amount\":1}",
      "{\"sample_deviation\":0.7071067811865476,\"sample\":0.5," +
      "\"population_deviation\":0.5,\"population\":0.25,\"id\":2," +
      "\"group\":\"a\",\"discrete\":1,\"continuous\":1.5," +
      "\"amount\":2}",
    ],
  )
}

///|
test "Local managed analytic numeric reductions feed two downstream Computes" {
  run_local_managed_analytic_case(
    "numeric",
    [
      "{\"amount\":10000000000000000,\"group\":\"a\",\"id\":1,\"mean\":10000000000000000,\"total\":10000000000000000}",
      "{\"amount\":1,\"group\":\"a\",\"id\":2,\"mean\":5000000000000000,\"total\":10000000000000000}",
      "{\"amount\":-10000000000000000,\"group\":\"a\",\"id\":3,\"mean\":0,\"total\":0}",
    ],
    [
      "{\"total\":10000000000000000,\"mean\":10000000000000000,\"id\":1,\"group\":\"a\",\"amount\":10000000000000000}",
      "{\"total\":10000000000000000,\"mean\":5000000000000000,\"id\":2,\"group\":\"a\",\"amount\":1}",
      "{\"total\":0,\"mean\":0,\"id\":3,\"group\":\"a\",\"amount\":-10000000000000000}",
    ],
  )
}

///|
test "Local managed analytic seals numeric observations before a later take" {
  run_local_managed_analytic_case(
    "numeric_take",
    [
      "{\"amount\":10000000000000000,\"group\":\"a\",\"id\":1," +
      "\"mean\":10000000000000000,\"total\":10000000000000000}",
    ],
    [
      "{\"total\":10000000000000000,\"mean\":10000000000000000," +
      "\"id\":1,\"group\":\"a\",\"amount\":10000000000000000}",
    ],
  )
}
