///|
fn local_values_window_group_program(variant : String) -> String {
  let (schema, rows, window, group, fields, reordered) = match variant {
    "fixed_keyed" =>
      (
        "{\"at\":{\"type\":\"number\",\"nullable\":false},\"k\":{\"type\":\"number\",\"nullable\":true}}",
        "[{\"at\":1,\"k\":null},{\"at\":2,\"k\":null},{\"at\":11,\"k\":1}]", "{\"kind\":\"fixed\",\"time\":\"at\",\"size\":10}",
        "{\"by\":[\"k\"],\"aggregates\":{\"n\":{\"fn\":\"count\"}}}", "[\"k\",\"n\",\"window_end\",\"window_start\"]",
        "[\"window_start\",\"window_end\",\"n\",\"k\"]",
      )
    "sliding_global" =>
      (
        "{\"at\":{\"type\":\"number\",\"nullable\":false}}", "[{\"at\":5},{\"at\":7}]",
        "{\"kind\":\"sliding\",\"time\":\"at\",\"size\":10,\"step\":6,\"offset\":2}",
        "{\"by\":[],\"aggregates\":{\"n\":{\"fn\":\"count\"}}}", "[\"n\",\"window_end\",\"window_start\"]",
        "[\"window_start\",\"n\",\"window_end\"]",
      )
    "numeric" =>
      (
        "{\"at\":{\"type\":\"number\",\"nullable\":false}," +
        "\"n\":{\"type\":\"number\",\"nullable\":true}}",
        "[{\"at\":1,\"n\":10000000000000000},{\"at\":2," +
        "\"n\":1},{\"at\":3,\"n\":-10000000000000000}]",
        "{\"kind\":\"fixed\",\"time\":\"at\",\"size\":10}",
        "{\"by\":[],\"aggregates\":{\"mean\":{\"fn\":\"avg\"," +
        "\"field\":\"n\"},\"total\":{\"fn\":\"sum\"," +
        "\"field\":\"n\"}}}",
        "[\"mean\",\"total\",\"window_end\",\"window_start\"]",
        "[\"window_start\",\"total\",\"mean\",\"window_end\"]",
      )
    "decimal_sum" =>
      (
        "{\"amount\":{\"type\":\"decimal\",\"precision\":38,\"scale\":2,\"nullable\":true},\"at\":{\"type\":\"number\",\"nullable\":false}}",
        "[{\"amount\":\"1.25\",\"at\":1},{\"amount\":\"2.00\",\"at\":2},{\"amount\":null,\"at\":11}]",
        "{\"kind\":\"fixed\",\"time\":\"at\",\"size\":10}", "{\"by\":[],\"aggregates\":{\"total\":{\"fn\":\"sum\",\"field\":\"amount\"}}}",
        "[\"total\",\"window_end\",\"window_start\"]", "[\"window_start\",\"total\",\"window_end\"]",
      )
    "filtered_expression" =>
      (
        "{\"amount\":{\"type\":\"number\",\"nullable\":false},\"at\":{\"type\":\"number\",\"nullable\":false}}",
        "[{\"amount\":0,\"at\":1},{\"amount\":10,\"at\":2},{\"amount\":20,\"at\":11}]",
        "{\"kind\":\"fixed\",\"time\":\"at\",\"size\":10}", "{\"by\":[],\"aggregates\":{\"lowest\":{\"fn\":\"min\",\"expr\":\"100 / amount\",\"filter\":\"amount > 0\"}}}",
        "[\"lowest\",\"window_end\",\"window_start\"]", "[\"window_start\",\"lowest\",\"window_end\"]",
      )
    "direct_aggregates" =>
      (
        "{\"amount\":{\"type\":\"decimal\",\"precision\":38," +
        "\"scale\":2,\"nullable\":true},\"at\":{\"type\":\"number\"," +
        "\"nullable\":false},\"flag\":{\"type\":\"boolean\"," +
        "\"nullable\":true},\"id\":{\"type\":\"number\"," +
        "\"nullable\":false},\"label\":{\"type\":\"string\"," +
        "\"nullable\":true}}",
        "[{\"amount\":\"1.25\",\"at\":1,\"flag\":true,\"id\":1," +
        "\"label\":\"b\"},{\"amount\":\"2.00\",\"at\":2," +
        "\"flag\":null,\"id\":2,\"label\":null},{\"amount\":null," +
        "\"at\":3,\"flag\":false,\"id\":3,\"label\":\"a\"}]",
        "{\"kind\":\"fixed\",\"time\":\"at\",\"size\":10}",
        "{\"by\":[],\"aggregates\":{\"distinct_labels\":{\"fn\":\"count\"," +
        "\"field\":\"label\",\"distinct\":true}," +
        "\"first\":{\"fn\":\"first\",\"field\":\"label\"," +
        "\"order_by\":[{\"id\":\"asc\"}]},\"highest\":{\"fn\":\"max\"," +
        "\"field\":\"label\"},\"hits\":{\"fn\":\"count_if\"," +
        "\"field\":\"flag\"},\"last\":{\"fn\":\"last\",\"field\":\"label\"," +
        "\"order_by\":[{" +
        "\"id\":\"asc\"}]},\"lowest\":{\"fn\":\"min\"," +
        "\"field\":\"label\"},\"total\":{\"fn\":\"sum\"," +
        "\"field\":\"amount\"}}}",
        "[\"distinct_labels\",\"first\",\"highest\",\"hits\",\"last\"," +
        "\"lowest\",\"total\",\"window_end\",\"window_start\"]",
        "[\"window_start\",\"total\",\"lowest\",\"last\",\"hits\"," +
        "\"highest\",\"first\",\"distinct_labels\",\"window_end\"]",
      )
    "collection_aggregates" =>
      (
        "{\"at\":{\"type\":\"number\",\"nullable\":false}," +
        "\"id\":{\"type\":\"number\",\"nullable\":false}," +
        "\"label\":{\"type\":\"string\",\"nullable\":true}}",
        "[{\"at\":1,\"id\":1,\"label\":\"b\"},{\"at\":2," +
        "\"id\":2,\"label\":null},{\"at\":3,\"id\":3," +
        "\"label\":\"a\"},{\"at\":4,\"id\":4,\"label\":\"b\"}]",
        "{\"kind\":\"fixed\",\"time\":\"at\",\"size\":10}",
        "{\"by\":[],\"aggregates\":{\"items\":{\"fn\":\"array_agg\"," +
        "\"field\":\"label\",\"distinct\":true,\"order_by\":[{" +
        "\"id\":\"asc\"}],\"max_items\":3},\"text\":{\"fn\":\"string_agg\"," +
        "\"field\":\"label\"," +
        "\"distinct\":true,\"order_by\":[{\"id\":\"desc\"}]," +
        "\"delimiter\":\"|\",\"max_bytes\":10}}}",
        "[\"items\",\"text\",\"window_end\",\"window_start\"]",
        "[\"window_start\",\"text\",\"items\",\"window_end\"]",
      )
    "statistical_aggregates" =>
      (
        "{\"at\":{\"type\":\"number\",\"nullable\":false}," +
        "\"n\":{\"type\":\"number\",\"nullable\":true}}",
        "[{\"at\":1,\"n\":1},{\"at\":2,\"n\":2},{\"at\":3," +
        "\"n\":3},{\"at\":4,\"n\":null}]",
        "{\"kind\":\"fixed\",\"time\":\"at\",\"size\":10}",
        "{\"by\":[],\"aggregates\":{\"continuous\":{\"fn\":\"percentile_cont\"," +
        "\"field\":\"n\",\"fraction\":0.5}," +
        "\"discrete\":{\"fn\":\"percentile_disc\",\"field\":\"n\"," +
        "\"fraction\":0.5},\"population\":{\"fn\":\"var_pop\"," +
        "\"field\":\"n\"},\"population_deviation\":{\"fn\":\"stddev_pop\"," +
        "\"field\":\"n\"},\"sample\":{\"fn\":\"var_samp\",\"field\":\"n\"}," +
        "\"sample_deviation\":{\"fn\":\"stddev_samp\",\"field\":\"n\"}}}",
        "[\"continuous\",\"discrete\",\"population\"," +
        "\"population_deviation\",\"sample\",\"sample_deviation\"," +
        "\"window_end\",\"window_start\"]",
        "[\"window_start\",\"sample_deviation\",\"sample\"," +
        "\"population_deviation\",\"population\",\"discrete\"," +
        "\"continuous\",\"window_end\"]",
      )
    _ => abort("unknown Local window group fixture")
  }
  let ordered = variant == "direct_aggregates" ||
    variant == "collection_aggregates"
  let order_evidence = if ordered {
    ",{\"from\":\"seed\",\"assert_rows\":{\"unique_by\":[\"id\"]}," +
    "\"as\":\"unique\"}"
  } else {
    ""
  }
  let window_input = if ordered { "unique" } else { "seed" }
  "{\"version\":\"actql/0.1\",\"id\":\"p\",\"params\":{\"minimum\":{\"type\":\"number\",\"nullable\":false}},\"stages\":[" +
  "{\"id\":\"a\",\"inputs\":{\"remote\":{\"connector\":\"crm/main\",\"resource\":\"r\"}},\"steps\":[{\"filter\":\"id > $minimum\",\"as\":\"filtered\"},{\"select\":[\"id\"],\"as\":\"captured\"}],\"results\":{\"r\":{\"from\":\"captured\",\"fields\":[\"id\"]}}}," +
  "{\"id\":\"windowed\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":" +
  schema +
  ",\"rows\":" +
  rows +
  "},\"as\":\"seed\"}" +
  order_evidence +
  ",{\"from\":\"" +
  window_input +
  "\",\"row_window\":" +
  window +
  ",\"as\":\"windowed\"},{\"from\":\"windowed\",\"window_group\":" +
  group +
  ",\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":" +
  fields +
  "}}}," +
  "{\"id\":\"consumer_a\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"windowed\",\"result\":\"r\"}}},\"steps\":[{\"select\":" +
  fields +
  ",\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":" +
  fields +
  "}}}," +
  "{\"id\":\"consumer_b\",\"inputs\":{\"x\":{\"result\":{\"stage\":\"windowed\",\"result\":\"r\"}}},\"steps\":[{\"select\":" +
  reordered +
  ",\"as\":\"out\"}],\"results\":{\"r\":{\"from\":\"out\",\"fields\":" +
  reordered +
  "}}}],\"results\":{\"source\":{\"from\":{\"stage\":\"a\",\"result\":\"r\"}}}}"
}

///|
fn run_local_managed_window_group_case(
  variant : String,
  expected : Array[String],
  reordered : Array[String],
) -> Unit raise {
  let (run, issuer) = captured_graph_fixture(
    local_values_window_group_chain=true,
    local_values_window_group_variant=variant,
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
        max_bytes: 2000,
        max_nodes: 200,
        max_depth: 10,
        max_columns: 12,
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
test "Local managed fixed window groups feed two downstream Computes" {
  run_local_managed_window_group_case(
    "fixed_keyed",
    [
      "{\"k\":null,\"n\":2,\"window_end\":10,\"window_start\":0}", "{\"k\":1,\"n\":1,\"window_end\":20,\"window_start\":10}",
    ],
    [
      "{\"window_start\":0,\"window_end\":10,\"n\":2,\"k\":null}", "{\"window_start\":10,\"window_end\":20,\"n\":1,\"k\":1}",
    ],
  )
}

///|
test "Local managed sliding window groups feed two downstream Computes" {
  run_local_managed_window_group_case(
    "sliding_global",
    [
      "{\"n\":1,\"window_end\":6,\"window_start\":-4}", "{\"n\":2,\"window_end\":12,\"window_start\":2}",
    ],
    [
      "{\"window_start\":-4,\"n\":1,\"window_end\":6}", "{\"window_start\":2,\"n\":2,\"window_end\":12}",
    ],
  )
}

///|
test "Local managed window Decimal sums feed two downstream Computes" {
  run_local_managed_window_group_case(
    "decimal_sum",
    [
      "{\"total\":\"3.25\",\"window_end\":10,\"window_start\":0}", "{\"total\":null,\"window_end\":20,\"window_start\":10}",
    ],
    [
      "{\"window_start\":0,\"total\":\"3.25\",\"window_end\":10}", "{\"window_start\":10,\"total\":null,\"window_end\":20}",
    ],
  )
}

///|
test "Local managed window filters gate aggregate expression demand" {
  run_local_managed_window_group_case(
    "filtered_expression",
    [
      "{\"lowest\":10,\"window_end\":10,\"window_start\":0}", "{\"lowest\":5,\"window_end\":20,\"window_start\":10}",
    ],
    [
      "{\"window_start\":0,\"lowest\":10,\"window_end\":10}", "{\"window_start\":10,\"lowest\":5,\"window_end\":20}",
    ],
  )
}

///|
test "Local managed window direct aggregates feed two downstream Computes" {
  run_local_managed_window_group_case(
    "direct_aggregates",
    [
      "{\"distinct_labels\":2,\"first\":\"b\",\"highest\":\"b\"," +
      "\"hits\":1,\"last\":\"a\",\"lowest\":\"a\",\"total\":\"3.25\"," +
      "\"window_end\":10,\"window_start\":0}",
    ],
    [
      "{\"window_start\":0,\"total\":\"3.25\",\"lowest\":\"a\"," +
      "\"last\":\"a\",\"hits\":1,\"highest\":\"b\",\"first\":\"b\"," +
      "\"distinct_labels\":2,\"window_end\":10}",
    ],
  )
}

///|
test "Local managed window collections feed two downstream Computes" {
  run_local_managed_window_group_case(
    "collection_aggregates",
    [
      "{\"items\":[\"b\",\"a\"],\"text\":\"b|a\",\"window_end\":10," +
      "\"window_start\":0}",
    ],
    [
      "{\"window_start\":0,\"text\":\"b|a\",\"items\":[\"b\",\"a\"]," +
      "\"window_end\":10}",
    ],
  )
}

///|
test "Local managed window statistics feed two downstream Computes" {
  run_local_managed_window_group_case(
    "statistical_aggregates",
    [
      "{\"continuous\":2,\"discrete\":2,\"population\":" +
      "0.6666666666666666,\"population_deviation\":0.816496580927726," +
      "\"sample\":1,\"sample_deviation\":1,\"window_end\":10," +
      "\"window_start\":0}",
    ],
    [
      "{\"window_start\":0,\"sample_deviation\":1,\"sample\":1," +
      "\"population_deviation\":0.816496580927726," +
      "\"population\":0.6666666666666666,\"discrete\":2," +
      "\"continuous\":2,\"window_end\":10}",
    ],
  )
}
