///|
fn local_managed_unary_expected(kind : String) -> Array[String] {
  match kind {
    "select" => ["{\"total\":10,\"id\":1}", "{\"total\":null,\"id\":2}"]
    "filter_text" | "filter_structured" => ["{\"amount\":null,\"id\":2}"]
    "filter_null" => ["{\"amount\":10,\"id\":1}"]
    "assert_where" | "assert_unique" =>
      ["{\"id\":1,\"amount\":10}", "{\"id\":2,\"amount\":null}"]
    "derive_map" =>
      [
        "{\"id\":1,\"amount\":10,\"next\":2}", "{\"id\":2,\"amount\":null,\"next\":3}",
      ]
    "derive_empty" => ["{\"id\":1,\"amount\":10}", "{\"id\":2,\"amount\":null}"]
    "rename_empty" | "drop_empty" =>
      ["{\"amount\":10,\"id\":1}", "{\"amount\":null,\"id\":2}"]
    "derive_ordered" =>
      [
        "{\"id\":2,\"amount\":10,\"saved\":1,\"next\":3}", "{\"id\":3,\"amount\":null,\"saved\":2,\"next\":5}",
      ]
    "rename" => ["{\"total\":10,\"id\":1}", "{\"total\":null,\"id\":2}"]
    "rename_swap" => ["{\"id\":10,\"amount\":1}", "{\"id\":null,\"amount\":2}"]
    "drop" | "drop_repeated" => ["{\"id\":1}", "{\"id\":2}"]
    "json_pick" =>
      [
        "{\"id\":1,\"payload\":{\"inner\":{\"leaf\":3}},\"picked\":3}", "{\"id\":2,\"payload\":null,\"picked\":null}",
      ]
    // Bounded sort and take emit the checked schema's canonical field order.
    // Downstream selects still use their authored projection order.
    "sort" =>
      [
        "{\"amount\":10,\"id\":1}", "{\"amount\":20,\"id\":2}", "{\"amount\":20,\"id\":2}",
        "{\"amount\":30,\"id\":2}",
      ]
    "sort_compound" =>
      [
        "{\"amount\":null,\"id\":1}", "{\"amount\":null,\"id\":2}", "{\"amount\":30,\"id\":1}",
        "{\"amount\":20,\"id\":2}",
      ]
    "take" => ["{\"amount\":10,\"id\":1}", "{\"amount\":20,\"id\":2}"]
    "take_parameter" => ["{\"amount\":10,\"id\":1}"]
    "top_k" => ["{\"id\":2,\"amount\":30}", "{\"id\":2,\"amount\":20}"]
    "top_k_parameter" => ["{\"id\":2,\"amount\":30}"]
    "top_k_compound" =>
      [
        "{\"id\":1,\"amount\":null}", "{\"id\":2,\"amount\":null}", "{\"id\":3,\"amount\":30}",
      ]
    "top_k_by" => ["{\"id\":1,\"amount\":10}", "{\"id\":2,\"amount\":30}"]
    "top_k_by_parameter" =>
      ["{\"id\":1,\"amount\":10}", "{\"id\":2,\"amount\":30}"]
    "top_k_by_nullable" =>
      [
        "{\"id\":3,\"amount\":30,\"group\":null}", "{\"id\":4,\"amount\":40,\"group\":\"a\"}",
      ]
    "unnest" =>
      [
        "{\"id\":1,\"item\":2,\"items\":[2,null],\"position\":0}", "{\"id\":1,\"item\":null,\"items\":[2,null],\"position\":1}",
        "{\"id\":2,\"item\":null,\"items\":[],\"position\":null}", "{\"id\":3,\"item\":null,\"items\":null,\"position\":null}",
      ]
    "unnest_inner" =>
      [
        "{\"id\":1,\"item\":2,\"items\":[2,null]}", "{\"id\":1,\"item\":null,\"items\":[2,null]}",
      ]
    "unpivot" =>
      [
        "{\"amount\":10,\"id\":1,\"jan\":10,\"metric\":\"jan\"}", "{\"amount\":null,\"id\":1,\"jan\":10,\"metric\":\"feb\"}",
        "{\"amount\":10,\"id\":1,\"jan\":10,\"metric\":\"jan\"}", "{\"amount\":null,\"id\":2,\"jan\":null,\"metric\":\"jan\"}",
        "{\"amount\":20,\"id\":2,\"jan\":null,\"metric\":\"feb\"}", "{\"amount\":null,\"id\":2,\"jan\":null,\"metric\":\"jan\"}",
      ]
    "unpivot_empty" => []
    "pivot" =>
      ["{\"id\":1,\"open\":0,\"won\":1}", "{\"id\":2,\"open\":2,\"won\":0}"]
    "pivot_numeric" =>
      [
        "{\"id\":1,\"open\":null,\"won\":10}", "{\"id\":2,\"open\":50,\"won\":null}",
      ]
    "pivot_min_fill" =>
      ["{\"id\":1,\"open\":0,\"won\":10}", "{\"id\":2,\"open\":20,\"won\":0}"]
    "pivot_parameter_fill" =>
      ["{\"id\":1,\"open\":1,\"won\":10}", "{\"id\":2,\"open\":20,\"won\":1}"]
    "pivot_max" =>
      [
        "{\"id\":1,\"open\":null,\"won\":10}", "{\"id\":2,\"open\":30,\"won\":null}",
      ]
    "pivot_first" =>
      [
        "{\"id\":1,\"open\":null,\"won\":10}", "{\"id\":2,\"open\":20,\"won\":null}",
      ]
    "pivot_empty_axis" => ["{\"id\":2}", "{\"id\":1}"]
    "pivot_decimal_sum" =>
      [
        "{\"id\":1,\"open\":\"1.00\",\"won\":null}", "{\"id\":2,\"open\":\"2.00\",\"won\":\"3.00\"}",
      ]
    "distinct" =>
      [
        "{\"id\":2,\"amount\":20}", "{\"id\":1,\"amount\":10}", "{\"id\":2,\"amount\":30}",
      ]
    "distinct_keyed_nullable" =>
      [
        "{\"amount\":20,\"id\":2}", "{\"amount\":null,\"id\":1}", "{\"amount\":null,\"id\":3}",
      ]
    "dedupe_rows" => ["{\"id\":1,\"amount\":10}", "{\"id\":2,\"amount\":30}"]
    "dedupe_compound_nullable" =>
      [
        "{\"id\":2,\"amount\":30,\"group\":null,\"bucket\":1}", "{\"id\":4,\"amount\":40,\"group\":\"a\",\"bucket\":2}",
      ]
    _ => abort("unknown Local unary expectation")
  }
}

///|
fn local_managed_unary_input_expected(kind : String) -> Array[String] {
  if kind == "unnest" || kind == "unnest_inner" {
    [
      "{\"id\":1,\"items\":[2,null]}", "{\"id\":2,\"items\":[]}", "{\"id\":3,\"items\":null}",
    ]
  } else if kind == "unpivot" {
    ["{\"feb\":null,\"id\":1,\"jan\":10}", "{\"feb\":20,\"id\":2,\"jan\":null}"]
  } else if kind == "unpivot_empty" {
    []
  } else if kind == "pivot" ||
    kind == "pivot_numeric" ||
    kind == "pivot_min_fill" ||
    kind == "pivot_parameter_fill" ||
    kind == "pivot_max" ||
    kind == "pivot_first" ||
    kind == "pivot_empty_axis" {
    [
      "{\"amount\":20,\"id\":2,\"status\":\"open\"}", "{\"amount\":10,\"id\":1,\"status\":\"won\"}",
      "{\"amount\":30,\"id\":2,\"status\":\"open\"}", "{\"amount\":null,\"id\":1,\"status\":\"open\"}",
      "{\"amount\":99,\"id\":1,\"status\":\"other\"}", "{\"amount\":5,\"id\":1,\"status\":null}",
    ]
  } else if kind == "pivot_decimal_sum" {
    [
      "{\"amount\":\"1.23\",\"id\":1,\"status\":\"open\"}", "{\"amount\":\"-0.23\",\"id\":1,\"status\":\"open\"}",
      "{\"amount\":null,\"id\":1,\"status\":\"won\"}", "{\"amount\":\"2.00\",\"id\":2,\"status\":\"open\"}",
      "{\"amount\":\"3.00\",\"id\":2,\"status\":\"won\"}",
    ]
  } else if kind == "json_pick" {
    [
      "{\"id\":1,\"payload\":{\"inner\":{\"leaf\":3}}}", "{\"id\":2,\"payload\":null}",
    ]
  } else if kind == "sort_compound" {
    [
      "{\"amount\":20,\"id\":2}", "{\"amount\":null,\"id\":1}", "{\"amount\":30,\"id\":1}",
      "{\"amount\":null,\"id\":2}",
    ]
  } else if kind == "top_k_compound" {
    [
      "{\"amount\":20,\"id\":4}", "{\"amount\":null,\"id\":1}", "{\"amount\":30,\"id\":3}",
      "{\"amount\":null,\"id\":2}",
    ]
  } else if kind == "top_k_by_nullable" {
    [
      "{\"amount\":20,\"group\":null,\"id\":1}", "{\"amount\":10,\"group\":\"a\",\"id\":2}",
      "{\"amount\":30,\"group\":null,\"id\":3}", "{\"amount\":40,\"group\":\"a\",\"id\":4}",
    ]
  } else if kind == "distinct_keyed_nullable" {
    [
      "{\"amount\":20,\"id\":2}", "{\"amount\":null,\"id\":1}", "{\"amount\":20,\"id\":2}",
      "{\"amount\":null,\"id\":3}",
    ]
  } else if kind == "dedupe_compound_nullable" {
    [
      "{\"amount\":10,\"bucket\":1,\"group\":null,\"id\":1}", "{\"amount\":30,\"bucket\":1,\"group\":null,\"id\":2}",
      "{\"amount\":20,\"bucket\":2,\"group\":\"a\",\"id\":3}", "{\"amount\":40,\"bucket\":2,\"group\":\"a\",\"id\":4}",
    ]
  } else if kind == "dedupe_tie_failure" {
    [
      "{\"amount\":20,\"id\":2}", "{\"amount\":10,\"id\":1}", "{\"amount\":20,\"id\":2}",
      "{\"amount\":5,\"id\":1}",
    ]
  } else if kind == "sort" ||
    kind == "take" ||
    kind == "take_parameter" ||
    kind == "top_k" ||
    kind == "top_k_parameter" ||
    kind == "top_k_by" ||
    kind == "top_k_by_parameter" ||
    kind == "distinct" ||
    kind == "dedupe_rows" {
    [
      "{\"amount\":20,\"id\":2}", "{\"amount\":10,\"id\":1}", "{\"amount\":20,\"id\":2}",
      "{\"amount\":30,\"id\":2}",
    ]
  } else {
    ["{\"amount\":10,\"id\":1}", "{\"amount\":null,\"id\":2}"]
  }
}

///|
fn local_managed_unary_consumer_expected(kind : String) -> Array[String] {
  if kind == "filter_text" || kind == "filter_structured" {
    ["{\"id\":2,\"amount\":null}"]
  } else if kind == "filter_null" {
    ["{\"id\":1,\"amount\":10}"]
  } else if kind == "rename" {
    ["{\"id\":1,\"total\":10}", "{\"id\":2,\"total\":null}"]
  } else if kind == "rename_swap" {
    ["{\"amount\":1,\"id\":10}", "{\"amount\":2,\"id\":null}"]
  } else if kind == "derive_empty" ||
    kind == "rename_empty" ||
    kind == "drop_empty" {
    ["{\"id\":1,\"amount\":10}", "{\"id\":2,\"amount\":null}"]
  } else if kind == "top_k_by_nullable" {
    [
      "{\"id\":3,\"amount\":30,\"group\":null}", "{\"id\":4,\"amount\":40,\"group\":\"a\"}",
    ]
  } else if kind == "distinct_keyed_nullable" {
    [
      "{\"id\":2,\"amount\":20}", "{\"id\":1,\"amount\":null}", "{\"id\":3,\"amount\":null}",
    ]
  } else if kind == "dedupe_compound_nullable" {
    [
      "{\"id\":2,\"amount\":30,\"group\":null,\"bucket\":1}", "{\"id\":4,\"amount\":40,\"group\":\"a\",\"bucket\":2}",
    ]
  } else if kind == "sort" {
    [
      "{\"id\":1,\"amount\":10}", "{\"id\":2,\"amount\":20}", "{\"id\":2,\"amount\":20}",
      "{\"id\":2,\"amount\":30}",
    ]
  } else if kind == "sort_compound" {
    [
      "{\"id\":1,\"amount\":null}", "{\"id\":2,\"amount\":null}", "{\"id\":1,\"amount\":30}",
      "{\"id\":2,\"amount\":20}",
    ]
  } else if kind == "take" {
    ["{\"id\":1,\"amount\":10}", "{\"id\":2,\"amount\":20}"]
  } else if kind == "take_parameter" {
    ["{\"id\":1,\"amount\":10}"]
  } else {
    local_managed_unary_expected(kind)
  }
}

///|
fn run_local_managed_unary_case(
  kind : String,
  publication? : Bool = false,
) -> Unit raise {
  let (run, issuer) = captured_graph_fixture(
    local_values_unary_chain=Some(kind),
    managed_publication=publication,
  )
  if publication {
    assert_true(
      @strategy.configure_captured_managed_identity_policy(
        run, true, false, false, false,
      ),
    )
  }
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
        max_bytes: 1000,
        max_nodes: 200,
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
  let values_obligations = if publication {
    Some(@strategy.captured_next_managed_obligations(run, 10).unwrap())
  } else {
    None
  }
  let (values_ops, values) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    values_live,
    obligations?=values_obligations,
  )
  let value_rows = local_managed_test_rows(values_ops)
  assert_eq(value_rows, local_managed_unary_input_expected(kind))

  let unary_live = Ref(true)
  let unary_obligations = if publication {
    Some(@strategy.captured_next_managed_obligations(run, 10).unwrap())
  } else {
    None
  }
  let bounded_advances = Ref(0)
  let (unary_ops, unary) = run_local_managed_test_task(
    installed,
    run,
    2,
    [values],
    [value_rows],
    2,
    unary_live,
    obligations?=unary_obligations,
    execution_quantum=if kind == "filter_text" ||
      kind == "filter_structured" ||
      kind == "filter_null" ||
      kind == "sort" ||
      kind == "sort_compound" ||
      kind == "take" ||
      kind == "take_parameter" {
      1
    } else {
      0
    },
    execution_advances=Some(bounded_advances),
  )
  if kind == "filter_text" ||
    kind == "filter_structured" ||
    kind == "filter_null" ||
    kind == "sort" ||
    kind == "sort_compound" ||
    kind == "take" ||
    kind == "take_parameter" {
    assert_true(bounded_advances.val > 4)
  }
  let expected = local_managed_unary_expected(kind)
  assert_eq(local_managed_test_rows(unary_ops), expected)
  if unary_obligations is Some(obligations) {
    let requirements = @execution.managed_obligations_identities(obligations)
    let published = requirements.filter(requirement => {
      requirement.domain == @execution.LogicalRelation &&
      requirement.subject == @execution.NamedResult
    })
    assert_eq(published.length(), 1)
    assert_eq(
      @execution.managed_completed_identity_requirement_status(
        unary,
        published[0],
      ),
      Some(
        @execution.EstablishedSourceRetained(
          @execution.logical_relation_canonical_contract_cid(),
          "sha256:ba372259aded413375251cdfa441942f50af17a015693aea14883407d171dbcd",
        ),
      ),
    )
    assert_true(
      @execution.managed_completed_deadline_satisfied(
        unary,
        @execution.BeforePublication,
      ),
    )
  }
  let consumer_expected = local_managed_unary_consumer_expected(kind)

  let first_live = Ref(true)
  let first_obligations = if publication {
    Some(@strategy.captured_next_managed_obligations(run, 10).unwrap())
  } else {
    None
  }
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    3,
    [unary],
    [expected],
    3,
    first_live,
    obligations?=first_obligations,
  )
  let second_live = Ref(true)
  let second_obligations = if publication {
    Some(@strategy.captured_next_managed_obligations(run, 10).unwrap())
  } else {
    None
  }
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    4,
    [unary],
    [expected],
    4,
    second_live,
    obligations?=second_obligations,
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
test "Local establishes the exact Named Result identity before publication" {
  run_local_managed_unary_case("select", publication=true)
}

///|
test "Local managed unary source forms feed two downstream Computes" {
  for
    kind in [
      "select", "filter_text", "filter_structured", "filter_null", "derive_map",
      "derive_empty", "derive_ordered", "rename", "rename_swap", "rename_empty",
      "drop", "drop_empty", "drop_repeated", "json_pick", "assert_where", "assert_unique",
      "sort", "sort_compound", "take", "take_parameter", "distinct", "top_k", "top_k_parameter",
      "top_k_compound", "top_k_by", "top_k_by_parameter", "top_k_by_nullable", "dedupe_rows",
      "distinct_keyed_nullable", "dedupe_compound_nullable", "unnest", "unpivot",
      "unnest_inner", "unpivot_empty", "pivot", "pivot_min_fill", "pivot_empty_axis",
      "pivot_numeric", "pivot_decimal_sum", "pivot_parameter_fill", "pivot_max",
      "pivot_first",
    ] {
    run_local_managed_unary_case(kind)
  }
}

///|
test "ordinary Local sort resumes within quantum and feeds two Computes" {
  run_local_managed_unary_case("sort")
  run_local_managed_unary_case("sort_compound")
}

///|
test "ordinary Local filters resume within quantum" {
  run_local_managed_unary_case("filter_text")
  run_local_managed_unary_case("filter_structured")
  run_local_managed_unary_case("filter_null")
}

///|
test "ordinary Local take resumes within quantum and feeds two Computes" {
  run_local_managed_unary_case("take")
  run_local_managed_unary_case("take_parameter")
}

///|
fn run_local_managed_unary_failure_case(kind : String) -> Unit raise {
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
        max_bytes: 1000,
        max_nodes: 200,
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
  let rows = local_managed_test_rows(values_ops)
  let owner = @strategy.graph_task_owner(@strategy.captured_dag_graph(run), 2).unwrap()
  let setup = @local_driver.prepare_local_managed_dispatch(
      installed,
      [values],
      @execution.process_managed_obligations(owner),
      0L,
    )
    .unwrap()
    .unwrap()
  let failed = @local_driver.start_local_managed_dispatch_node(setup).unwrap()
  for row in rows {
    (failed.inputs[0].append)(row).unwrap()
  }
  (failed.inputs[0].finish)().unwrap()
  let result = (failed.execute)()
  match kind {
    "filter_failure" | "derive_failure" | "assert_where_eval_failure" =>
      assert_true(
        result
        is Err(
          @local_driver.Configuration(
            @connector.Execution(
              @execution.Rows(_, @execution.Evaluation(0, 0, _))
            )
          )
        ),
      )
    "assert_where_failure" =>
      assert_true(
        result
        is Err(
          @local_driver.Configuration(
            @connector.Execution(
              @execution.Rows(_, @execution.AssertionPredicate(0))
            )
          )
        ),
      )
    "assert_unique_null_failure" =>
      assert_true(
        result
        is Err(
          @local_driver.Configuration(
            @connector.Execution(
              @execution.Rows(_, @execution.AssertionNullKey(1, 0))
            )
          )
        ),
      )
    "dedupe_tie_failure" =>
      assert_true(
        result
        is Err(
          @local_driver.Configuration(
            @connector.Execution(
              @execution.Rows(_, @execution.DedupeTopTie(0, 2))
            )
          )
        ),
      )
    _ => abort("unknown Local unary failure fixture")
  }
  assert_false(@strategy.captured_task_completed(run, 2))
  assert_true(@execution.managed_completed_output_available(values))
  (failed.settle)().unwrap()
  (failed.close)()
  (failed.cleanup_refresh)() |> ignore

  values_live.val = false
  @strategy.close_captured_task_output(run, 1)
  (values_ops.close)()
  (values_ops.cleanup_refresh)() |> ignore
  @strategy.stop_captured_dag(run)
  for task in [0, 2, 3, 4] {
    @strategy.close_captured_task_output(run, task)
  }
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}

///|
test "Local managed demanded failures publish nothing and release their use" {
  for
    kind in [
      "filter_failure", "derive_failure", "assert_where_failure", "assert_where_eval_failure",
      "assert_unique_null_failure", "dedupe_tie_failure",
    ] {
    run_local_managed_unary_failure_case(kind)
  }
}

///|
test "Local qualified select feeds two downstream Computes" {
  let ledger_limits : @resources.LedgerLimits = {
    planning_work: 10000,
    attempts: 20,
    holdings: 20,
    transfer_bytes: 300000L,
    retained_bytes: 134217728L,
    execution_bytes: 536870912L,
  }
  let (run, issuer) = captured_graph_fixture(
    local_select_qualified_chain=true,
    ledger_limits=Some(ledger_limits),
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
        max_bytes: 1000,
        max_nodes: 200,
        max_depth: 4,
        max_columns: 4,
        max_order_work: 100,
      },
      row: { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
      max_batch_bytes: 64,
    },
    None,
  ).unwrap()

  let left_live = Ref(true)
  let (left_ops, left) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    left_live,
  )
  let left_rows = local_managed_test_rows(left_ops)
  assert_eq(left_rows, ["{\"id\":1,\"l\":\"l1\"}", "{\"id\":2,\"l\":\"l2\"}"])

  let right_live = Ref(true)
  let (right_ops, right) = run_local_managed_test_task(
    installed,
    run,
    2,
    [],
    [],
    2,
    right_live,
  )
  let right_rows = local_managed_test_rows(right_ops)
  assert_eq(right_rows, [
    "{\"id\":1,\"r\":\"r1\"}", "{\"id\":3,\"r\":\"r3\"}", "{\"id\":4,\"r\":\"r4\"}",
  ])

  let selected_live = Ref(true)
  let (selected_ops, selected) = run_local_managed_test_task(
    installed,
    run,
    3,
    [left, right],
    [left_rows, right_rows],
    3,
    selected_live,
  )
  let selected_rows = local_managed_test_rows(selected_ops)
  assert_eq(selected_rows, [
    "{\"right_value\":\"r1\",\"left_value\":\"l1\",\"id\":1}",
  ])

  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    4,
    [selected],
    [selected_rows],
    4,
    first_live,
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    5,
    [selected],
    [selected_rows],
    5,
    second_live,
  )
  assert_eq(local_managed_test_rows(first_ops), [
    "{\"id\":1,\"left_value\":\"l1\",\"right_value\":\"r1\"}",
  ])
  assert_eq(local_managed_test_rows(second_ops), [
    "{\"right_value\":\"r1\",\"id\":1,\"left_value\":\"l1\"}",
  ])

  first_live.val = false
  @strategy.close_captured_task_output(run, 4)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(selected))

  second_live.val = false
  @strategy.close_captured_task_output(run, 5)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  selected_live.val = false
  @strategy.close_captured_task_output(run, 3)
  (selected_ops.close)()
  (selected_ops.cleanup_refresh)() |> ignore
  left_live.val = false
  right_live.val = false
  @strategy.close_captured_task_output(run, 1)
  @strategy.close_captured_task_output(run, 2)
  (left_ops.close)()
  (right_ops.close)()
  (left_ops.cleanup_refresh)() |> ignore
  (right_ops.cleanup_refresh)() |> ignore
  @strategy.stop_captured_dag(run)
  @strategy.close_captured_task_output(run, 0)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}
