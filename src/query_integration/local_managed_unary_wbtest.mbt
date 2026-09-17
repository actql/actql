///|
fn local_managed_unary_expected(kind : String) -> Array[String] {
  match kind {
    "filter_text" | "filter_structured" => ["{\"id\":2,\"amount\":null}"]
    "assert_where" | "assert_unique" =>
      ["{\"id\":1,\"amount\":10}", "{\"id\":2,\"amount\":null}"]
    "derive_map" =>
      [
        "{\"id\":1,\"amount\":10,\"next\":2}", "{\"id\":2,\"amount\":null,\"next\":3}",
      ]
    "derive_ordered" =>
      [
        "{\"id\":2,\"amount\":10,\"saved\":1,\"next\":3}", "{\"id\":3,\"amount\":null,\"saved\":2,\"next\":5}",
      ]
    "rename" => ["{\"total\":10,\"id\":1}", "{\"total\":null,\"id\":2}"]
    "drop" => ["{\"id\":1}", "{\"id\":2}"]
    "json_pick" =>
      [
        "{\"id\":1,\"payload\":{\"inner\":{\"leaf\":3}},\"picked\":3}", "{\"id\":2,\"payload\":null,\"picked\":null}",
      ]
    _ => abort("unknown Local unary expectation")
  }
}

///|
fn local_managed_unary_input_expected(kind : String) -> Array[String] {
  if kind == "json_pick" {
    [
      "{\"id\":1,\"payload\":{\"inner\":{\"leaf\":3}}}", "{\"id\":2,\"payload\":null}",
    ]
  } else {
    ["{\"amount\":10,\"id\":1}", "{\"amount\":null,\"id\":2}"]
  }
}

///|
fn local_managed_unary_consumer_expected(kind : String) -> Array[String] {
  if kind == "rename" {
    ["{\"id\":1,\"total\":10}", "{\"id\":2,\"total\":null}"]
  } else {
    local_managed_unary_expected(kind)
  }
}

///|
fn run_local_managed_unary_case(kind : String) -> Unit raise {
  let (run, issuer) = captured_graph_fixture(
    local_values_unary_chain=Some(kind),
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
        max_bytes: 200,
        max_nodes: 40,
        max_depth: 4,
        max_columns: 4,
        max_order_work: 100,
      },
      row: { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
      max_batch_bytes: 64,
    },
    None,
  ).unwrap()

  let values_live = Ref(true)
  let (values_ops, values) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    values_live,
  )
  let value_rows = local_managed_test_rows(values_ops)
  assert_eq(value_rows, local_managed_unary_input_expected(kind))

  let unary_live = Ref(true)
  let (unary_ops, unary) = run_local_managed_test_task(
    installed,
    run,
    2,
    [values],
    [value_rows],
    2,
    unary_live,
  )
  let expected = local_managed_unary_expected(kind)
  assert_eq(local_managed_test_rows(unary_ops), expected)
  let consumer_expected = local_managed_unary_consumer_expected(kind)

  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    3,
    [unary],
    [expected],
    3,
    first_live,
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    4,
    [unary],
    [expected],
    4,
    second_live,
  )
  assert_eq(local_managed_test_rows(first_ops), consumer_expected)
  assert_eq(local_managed_test_rows(second_ops), consumer_expected)

  first_live.val = false
  @strategy.close_captured_task_output(run, 3)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(unary))

  second_live.val = false
  @strategy.close_captured_task_output(run, 4)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  unary_live.val = false
  @strategy.close_captured_task_output(run, 2)
  (unary_ops.close)()
  (unary_ops.cleanup_refresh)() |> ignore
  values_live.val = false
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
test "Local managed unary source forms feed two downstream Computes" {
  for
    kind in [
      "filter_text", "filter_structured", "derive_map", "derive_ordered", "rename",
      "drop", "json_pick", "assert_where", "assert_unique",
    ] {
    run_local_managed_unary_case(kind)
  }
}
