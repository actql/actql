///|
fn local_managed_unary_expected(kind : String) -> Array[String] {
  match kind {
    "select" => ["{\"total\":10,\"id\":1}", "{\"total\":null,\"id\":2}"]
    "filter_nested" => ["{\"id\":2,\"payload\":[]}"]
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
    "top_k" => ["{\"amount\":30,\"id\":2}", "{\"amount\":20,\"id\":2}"]
    "top_k_parameter" => ["{\"amount\":30,\"id\":2}"]
    "top_k_compound" =>
      [
        "{\"amount\":null,\"id\":1}", "{\"amount\":null,\"id\":2}", "{\"amount\":30,\"id\":3}",
      ]
    "top_k_by" => ["{\"amount\":10,\"id\":1}", "{\"amount\":30,\"id\":2}"]
    "top_k_by_parameter" =>
      ["{\"amount\":10,\"id\":1}", "{\"amount\":30,\"id\":2}"]
    "top_k_by_nullable" =>
      [
        "{\"amount\":30,\"group\":null,\"id\":3}", "{\"amount\":40,\"group\":\"a\",\"id\":4}",
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
    "unpivot" | "unpivot_unused_payload" =>
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
        "{\"amount\":20,\"id\":2}", "{\"amount\":10,\"id\":1}", "{\"amount\":30,\"id\":2}",
      ]
    "distinct_keyed_nullable" =>
      [
        "{\"amount\":20,\"id\":2}", "{\"amount\":null,\"id\":1}", "{\"amount\":null,\"id\":3}",
      ]
    "dedupe_rows" => ["{\"amount\":10,\"id\":1}", "{\"amount\":30,\"id\":2}"]
    "dedupe_compound_nullable" =>
      [
        "{\"amount\":30,\"bucket\":1,\"group\":null,\"id\":2}", "{\"amount\":40,\"bucket\":2,\"group\":\"a\",\"id\":4}",
      ]
    _ => abort("unknown Local unary expectation")
  }
}

///|
fn local_managed_unary_input_expected(kind : String) -> Array[String] {
  if kind == "filter_nested" {
    [local_count_payload_row(), "{\"id\":2,\"payload\":[]}"]
  } else if kind == "unnest" || kind == "unnest_inner" {
    [
      "{\"id\":1,\"items\":[2,null]}", "{\"id\":2,\"items\":[]}", "{\"id\":3,\"items\":null}",
    ]
  } else if kind == "unpivot_unused_payload" {
    let payload = "1" + ",1".repeat(255)
    [
      "{\"feb\":null,\"id\":1,\"jan\":10,\"payload\":[" + payload + "]}",
      "{\"feb\":20,\"id\":2,\"jan\":null,\"payload\":[]}",
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
  } else if kind == "dedupe_rows" {
    ["{\"id\":1,\"amount\":10}", "{\"id\":2,\"amount\":30}"]
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
  } else if kind == "top_k" {
    ["{\"id\":2,\"amount\":30}", "{\"id\":2,\"amount\":20}"]
  } else if kind == "top_k_parameter" {
    ["{\"id\":2,\"amount\":30}"]
  } else if kind == "top_k_compound" {
    [
      "{\"id\":1,\"amount\":null}", "{\"id\":2,\"amount\":null}", "{\"id\":3,\"amount\":30}",
    ]
  } else if kind == "top_k_by" || kind == "top_k_by_parameter" {
    ["{\"id\":1,\"amount\":10}", "{\"id\":2,\"amount\":30}"]
  } else if kind == "distinct" {
    [
      "{\"id\":2,\"amount\":20}", "{\"id\":1,\"amount\":10}", "{\"id\":2,\"amount\":30}",
    ]
  } else {
    local_managed_unary_expected(kind)
  }
}

///|
fn run_local_managed_unary_case(
  kind : String,
  publication? : Bool = false,
) -> Unit raise {
  let bounded_top_k_chain = kind == "top_k" ||
    kind == "top_k_parameter" ||
    kind == "top_k_compound" ||
    kind == "top_k_by" ||
    kind == "top_k_by_parameter" ||
    kind == "top_k_by_nullable"
  let large_nested_input = kind == "filter_nested" ||
    kind == "unpivot_unused_payload"
  let (run, issuer) = captured_graph_fixture(
    local_values_unary_chain=Some(kind),
    managed_publication=publication,
    ledger_limits=if bounded_top_k_chain {
      Some({
        planning_work: 10000,
        attempts: 10,
        holdings: 10,
        transfer_bytes: 300000L,
        retained_bytes: 128000000L,
        execution_bytes: 134217728L,
      })
    } else {
      None
    },
  )
  if bounded_top_k_chain {
    let graph = @strategy.captured_dag_graph(run)
    assert_eq(@strategy.graph_task_count(graph), 6)
    assert_eq(@strategy.graph_task_selected_step(graph, 2), Some(0))
    assert_eq(@strategy.graph_task_selected_step(graph, 3), Some(1))
  }
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
        max_bytes: if large_nested_input {
          2048
        } else {
          1000
        },
        max_nodes: if large_nested_input {
          512
        } else {
          200
        },
        max_depth: 4,
        max_columns: 4,
        max_order_work: 100,
      },
      row: {
        max_bytes: if large_nested_input {
          2048
        } else {
          100
        },
        max_nodes: if large_nested_input {
          512
        } else {
          20
        },
        max_depth: 4,
        max_text_bytes: if large_nested_input {
          2048
        } else {
          100
        },
      },
      max_batch_bytes: if large_nested_input {
        2048
      } else {
        64
      },
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

  let preliminary = if bounded_top_k_chain {
    let live = Ref(true)
    let obligations = if publication {
      Some(@strategy.captured_next_managed_obligations(run, 10).unwrap())
    } else {
      None
    }
    let advances = Ref(0)
    let (ops, output) = run_local_managed_test_task(
      installed,
      run,
      2,
      [values],
      [value_rows],
      2,
      live,
      obligations?,
      execution_quantum=1,
      execution_advances=Some(advances),
      require_provider=true,
    )
    assert_true(advances.val > 4)
    Some((ops, output, local_managed_test_rows(ops), live))
  } else {
    None
  }
  let unary_input = match preliminary {
    Some((_, output, _, _)) => output
    None => values
  }
  let unary_input_rows = match preliminary {
    Some((_, _, rows, _)) => rows
    None => value_rows
  }
  let unary_task = if bounded_top_k_chain { 3 } else { 2 }

  let unary_live = Ref(true)
  let unary_obligations = if publication {
    Some(@strategy.captured_next_managed_obligations(run, 10).unwrap())
  } else {
    None
  }
  let bounded_unary = kind == "json_pick" ||
    kind == "select" ||
    kind == "derive_map" ||
    kind == "derive_empty" ||
    kind == "derive_ordered" ||
    kind == "assert_where" ||
    kind == "assert_unique" ||
    kind == "rename" ||
    kind == "rename_swap" ||
    kind == "rename_empty" ||
    kind == "drop" ||
    kind == "drop_empty" ||
    kind == "drop_repeated" ||
    kind == "filter_text" ||
    kind == "filter_nested" ||
    kind == "filter_structured" ||
    kind == "filter_null" ||
    kind == "sort" ||
    kind == "sort_compound" ||
    kind == "take" ||
    kind == "take_parameter" ||
    kind == "top_k" ||
    kind == "top_k_parameter" ||
    kind == "top_k_compound" ||
    kind == "top_k_by" ||
    kind == "top_k_by_parameter" ||
    kind == "top_k_by_nullable" ||
    kind == "dedupe_rows" ||
    kind == "dedupe_compound_nullable" ||
    kind == "unnest" ||
    kind == "unnest_inner" ||
    kind == "unpivot" ||
    kind == "unpivot_unused_payload" ||
    kind == "unpivot_empty" ||
    kind == "pivot" ||
    kind == "pivot_min_fill" ||
    kind == "pivot_empty_axis" ||
    kind == "pivot_numeric" ||
    kind == "pivot_decimal_sum" ||
    kind == "pivot_parameter_fill" ||
    kind == "pivot_max" ||
    kind == "pivot_first"
  let bounded_advances = Ref(0)
  let (unary_ops, unary) = run_local_managed_test_task(
    installed,
    run,
    unary_task,
    [unary_input],
    [unary_input_rows],
    unary_task,
    unary_live,
    obligations?=unary_obligations,
    execution_quantum=if bounded_unary { 1 } else { 0 },
    execution_advances=Some(bounded_advances),
    require_provider=bounded_unary || bounded_top_k_chain,
  )
  if bounded_unary {
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
    unary_task + 1,
    [unary],
    [expected],
    unary_task + 1,
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
    unary_task + 2,
    [unary],
    [expected],
    unary_task + 2,
    second_live,
    obligations?=second_obligations,
  )
  assert_eq(local_managed_test_rows(first_ops), consumer_expected)
  assert_eq(local_managed_test_rows(second_ops), consumer_expected)

  first_live.val = false
  @strategy.close_captured_task_output(run, unary_task + 1)
  (first_ops.close)()
  (first_ops.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(first))
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(unary))

  second_live.val = false
  @strategy.close_captured_task_output(run, unary_task + 2)
  (second_ops.close)()
  (second_ops.cleanup_refresh)() |> ignore
  unary_live.val = false
  @strategy.close_captured_task_output(run, unary_task)
  (unary_ops.close)()
  (unary_ops.cleanup_refresh)() |> ignore
  if preliminary is Some((ops, _, _, live)) {
    live.val = false
    @strategy.close_captured_task_output(run, 2)
    (ops.close)()
    ignore((ops.cleanup_refresh)())
  }
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
      "unnest_inner", "unpivot_empty", "unpivot_unused_payload", "pivot", "pivot_min_fill",
      "pivot_empty_axis", "pivot_numeric", "pivot_decimal_sum", "pivot_parameter_fill",
      "pivot_max", "pivot_first",
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
test "ordinary Local partitioned top-k resumes and feeds two Computes" {
  run_local_managed_unary_case("top_k_by")
  run_local_managed_unary_case("top_k_by_parameter")
  run_local_managed_unary_case("top_k_by_nullable")
}

///|
test "ordinary Local filters resume within quantum" {
  run_local_managed_unary_case("filter_text")
  run_local_managed_unary_case("filter_structured")
  run_local_managed_unary_case("filter_null")
  run_local_managed_unary_case("filter_nested")
}

///|
test "standard Host cancels a unary kernel inside a nested input" {
  for
    kind in [
      "filter_nested", "unpivot_unused_payload", "unnest_long_items", "row_window_nested",
    ] {
    run_local_managed_nested_input_cancel(kind)
  }
}

///|
test "standard Host cancels pivot after bounded work" {
  for kind in ["pivot", "pivot_numeric", "pivot_decimal_sum"] {
    run_local_managed_nested_input_cancel(kind, before_cancel=20)
  }
}

///|
fn run_local_managed_nested_input_cancel(
  kind : String,
  before_cancel? : Int = 100,
) -> Unit raise {
  let (run, issuer) = if kind == "row_window_nested" {
    captured_graph_fixture(
      local_values_window_chain=true,
      local_values_window_variant="nested",
    )
  } else {
    captured_graph_fixture(local_values_unary_chain=Some(kind))
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
        ..retained_attempt_wire_limits(),
        max_bytes: 2048,
        max_nodes: 512,
      },
      row: {
        max_bytes: 2048,
        max_nodes: 512,
        max_depth: 4,
        max_text_bytes: 2048,
      },
      max_batch_bytes: 2048,
    },
    None,
  ).unwrap()
  let values_live = Ref(true)
  let (value_ops, values) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    values_live,
  )
  let operations = start_local_managed_test_task_operations(
    installed,
    run,
    2,
    [values],
    [local_managed_test_rows(value_ops)],
    require_provider=true,
  )
  for _ in 0..<before_cancel {
    let next = (operations.advance)(1).unwrap()
    assert_false(next.complete)
    assert_eq(next.work, 1L)
  }
  assert_true((operations.request_cancel)())
  assert_true((operations.advance)(1) is Err(_))
  assert_true((operations.execution_stopped)())
  assert_true((operations.output_row)(0) is Err(_))
  assert_true(
    (operations.complete)(2, operations.storage_bytes, fn() { true }) is Err(_),
  )
  (operations.settle)().unwrap()
  assert_true((operations.cleanup_refresh)())
  assert_false(@strategy.captured_task_completed(run, 2))
  assert_true(@execution.managed_completed_output_available(values))
  values_live.val = false
  @strategy.close_captured_task_output(run, 1)
  (value_ops.close)()
  (value_ops.cleanup_refresh)() |> ignore
  @strategy.stop_captured_dag(run)
  @strategy.close_captured_task_output(run, 0)
  @strategy.close_captured_task_output(run, 2)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}

///|
test "ordinary captured Relation chains feed two bounded consumers" {
  for
    variant in ["filter", "count", "keyed_count", "window", "unpivot", "dedupe"] {
    let expected = match variant {
      "count" => ["{\"id\":2}"]
      "keyed_count" => ["{\"id\":2}", "{\"id\":3}"]
      "window" => ["{\"id\":3}", "{\"id\":2}"]
      "unpivot" => ["{\"value\":3}"]
      _ => ["{\"id\":3}"]
    }
    let (run, issuer) = captured_graph_fixture(
      dag_two_consumers_of_compute_a=true,
      count=variant == "count" || variant == "keyed_count",
      count_filter_chain=variant == "count" || variant == "keyed_count",
      keyed_count_filter_chain=variant == "keyed_count",
      window_filter_chain=variant == "window",
      unpivot_filter_chain=variant == "unpivot",
      dedupe_filter_chain=variant == "dedupe",
    )
    let graph = @strategy.captured_dag_graph(run)
    assert_eq(@strategy.graph_task_count(graph), 4)
    assert_eq(@strategy.graph_task_selected_step(graph, 1), None)
    assert_eq(@strategy.graph_data_at(graph, 1).unwrap().producer, 1)
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
        wire: retained_attempt_wire_limits(),
        row: {
          max_bytes: 100,
          max_nodes: 20,
          max_depth: 4,
          max_text_bytes: 100,
        },
        max_batch_bytes: 256,
      },
      None,
    ).unwrap()
    let owner = @strategy.graph_task_owner(graph, 1).unwrap()
    let setup : @local_driver.LocalManagedDispatchConfiguration[Int] = @local_driver.prepare_local_managed_dispatch_with_outputs(
        installed,
        [@local_driver.local_managed_captured_relation_input()],
        @execution.process_managed_obligations(owner),
        0L,
      )
      .unwrap()
      .unwrap()
    assert_true(@local_driver.local_managed_dispatch_uses_provider(setup))
    let operations = @local_driver.start_local_managed_dispatch_node(setup).unwrap()
    assert_eq(operations.inputs.length(), 0)
    let mut polls = 0
    let mut charged_work = 0L
    while polls < 1000 {
      polls += 1
      let observation = (operations.advance)(1).unwrap()
      assert_true(observation.work <= 1L)
      charged_work += observation.work
      if observation.complete {
        break
      }
    }
    if variant == "keyed_count" {
      assert_eq(charged_work, 91L)
    }
    assert_true(polls > 2 && polls < 1000)
    assert_eq(local_managed_test_rows(operations), expected)
    let live = Ref(true)
    (operations.prepare_finalization)(1, operations.storage_bytes, fn() {
      live.val
    }).unwrap()
    while true {
      if (operations.advance_finalization)(1).unwrap().complete {
        break
      }
    }
    (operations.settle)().unwrap()
    let completed = (operations.complete)(1, operations.storage_bytes, fn() {
      live.val
    }).unwrap()
    assert_true(@execution.managed_completed_output_available(completed))
    let first_live = Ref(true)
    let first_advances = Ref(0)
    let (first_ops, first) = run_local_managed_test_task(
      installed,
      run,
      2,
      [completed],
      [expected],
      2,
      first_live,
      execution_quantum=1,
      execution_advances=Some(first_advances),
      require_provider=true,
    )
    let second_live = Ref(true)
    let second_advances = Ref(0)
    let (second_ops, second) = run_local_managed_test_task(
      installed,
      run,
      3,
      [completed],
      [expected],
      3,
      second_live,
      execution_quantum=1,
      execution_advances=Some(second_advances),
      require_provider=true,
    )
    assert_true(first_advances.val > 2 && second_advances.val > 2)
    assert_eq(local_managed_test_rows(first_ops), expected)
    assert_eq(local_managed_test_rows(second_ops), expected)
    first_live.val = false
    @strategy.close_captured_task_output(run, 2)
    (first_ops.close)()
    (first_ops.cleanup_refresh)() |> ignore
    assert_false(@execution.managed_completed_output_available(first))
    assert_true(@execution.managed_completed_output_available(second))
    assert_true(@execution.managed_completed_output_available(completed))
    second_live.val = false
    @strategy.close_captured_task_output(run, 3)
    (second_ops.close)()
    (second_ops.cleanup_refresh)() |> ignore
    live.val = false
    @strategy.close_captured_task_output(run, 1)
    (operations.close)()
    (operations.cleanup_refresh)() |> ignore
    assert_false(@execution.managed_completed_output_available(completed))
    @strategy.stop_captured_dag(run)
    for task in 0..<4 {
      @strategy.close_captured_task_output(run, task)
    }
    @strategy.refresh_captured_retention(run)
    let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
    assert_eq(usage.reserved_execution_bytes, 0L)
    assert_eq(usage.reserved_retention_bytes, 0L)
    assert_eq(usage.held_bytes, 0L)
    @mock.close_mock_query_issuer(issuer)
  }
}

///|
fn assert_captured_keyed_count_chain_budget(
  max_work : Int,
  expected : String,
  max_entries? : Int = 10000,
) -> Unit raise {
  let (run, issuer) = captured_graph_fixture(
    count=true,
    count_filter_chain=true,
    keyed_count_filter_chain=true,
  )
  let registry = search_registry()
  let defaults = dispatch_test_limits()
  let execution : @execution.SequenceExecutionLimits = {
    rows: { ..defaults.local_execution.rows, operation_entries: max_entries, },
    max_work,
    max_frames: defaults.local_execution.max_frames,
  }
  let installed = @local_driver.prepare_local_dispatch_module(
    @host_driver.open_dispatch_driver(run),
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    dispatch_test_generated(run),
    execution,
    defaults.guards,
    defaults.candidate_work,
  ).unwrap()
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: execution.rows.input_values,
      wire: retained_attempt_wire_limits(),
      row: { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
      max_batch_bytes: 256,
    },
    None,
  ).unwrap()
  let owner = @strategy.graph_task_owner(@strategy.captured_dag_graph(run), 1).unwrap()
  let setup : @local_driver.LocalManagedDispatchConfiguration[Int] = @local_driver.prepare_local_managed_dispatch_with_outputs(
      installed,
      [@local_driver.local_managed_captured_relation_input()],
      @execution.process_managed_obligations(owner),
      0L,
    )
    .unwrap()
    .unwrap()
  assert_true(@local_driver.local_managed_dispatch_uses_provider(setup))
  let operations = @local_driver.start_local_managed_dispatch_node(setup).unwrap()
  let mut done = false
  let mut rejected = false
  let mut charged_work = 0L
  for _ in 0..<1000 {
    if !done && !rejected {
      match (operations.advance)(1) {
        Ok(observation) => {
          assert_true(observation.work <= 1L)
          charged_work += observation.work
          done = observation.complete
        }
        Err(
          @local_driver.Configuration(
            @connector.Execution(@execution.InputLimit)
          )
        ) => rejected = expected == "work"
        Err(
          @local_driver.Configuration(
            @connector.Execution(@execution.Rows(_, @execution.RowLimit))
          )
        ) => rejected = expected == "workspace"
        Err(_) => fail("keyed count chain rejected with another issue")
      }
    }
  }
  if expected == "complete" {
    assert_true(done && !rejected)
    assert_eq(charged_work, 91L)
    assert_eq(local_managed_test_rows(operations), ["{\"id\":2}", "{\"id\":3}"])
    let live = Ref(true)
    (operations.prepare_finalization)(1, operations.storage_bytes, fn() {
      live.val
    }).unwrap()
    while true {
      if (operations.advance_finalization)(1).unwrap().complete {
        break
      }
    }
    (operations.settle)().unwrap()
    let output = (operations.complete)(1, operations.storage_bytes, fn() {
      live.val
    }).unwrap()
    assert_true(@execution.managed_completed_output_available(output))
    live.val = false
    @strategy.close_captured_task_output(run, 1)
    (operations.close)()
    (operations.cleanup_refresh)() |> ignore
  } else {
    assert_true(rejected && !done)
    if expected == "work" {
      assert_true(
        (operations.advance)(1)
        is Err(
          @local_driver.Configuration(
            @connector.Execution(@execution.InputLimit)
          )
        ),
      )
      assert_true(
        (operations.execute)()
        is Err(
          @local_driver.Configuration(
            @connector.Execution(@execution.InputLimit)
          )
        ),
      )
    } else if expected == "workspace" {
      assert_true(
        (operations.advance)(1)
        is Err(
          @local_driver.Configuration(
            @connector.Execution(@execution.Rows(_, @execution.RowLimit))
          )
        ),
      )
      assert_true(
        (operations.execute)()
        is Err(
          @local_driver.Configuration(
            @connector.Execution(@execution.Rows(_, @execution.RowLimit))
          )
        ),
      )
    }
    assert_true((operations.output_row)(0) is Err(_))
    assert_false(@strategy.captured_task_completed(run, 1))
    (operations.settle)().unwrap()
    (operations.close)()
    assert_true((operations.cleanup_refresh)())
  }
  @strategy.stop_captured_dag(run)
  for task in 0..<4 {
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
test "ordinary keyed count chain admits exact work and one-short limits" {
  assert_captured_keyed_count_chain_budget(91, "complete")
  assert_captured_keyed_count_chain_budget(90, "work")
}

///|
test "ordinary keyed count chain admits exact workspace and one-short limit" {
  // Count holds eight metadata slots. Three input rows add six sort slots;
  // the later filter and select each stay below this 14-slot peak.
  assert_captured_keyed_count_chain_budget(91, "complete", max_entries=14)
  assert_captured_keyed_count_chain_budget(91, "workspace", max_entries=13)
  assert_captured_keyed_count_chain_budget(91, "workspace", max_entries=12)
}

///|
test "ordinary keyed count chain reserves overlapping child capacity" {
  let (run, issuer) = captured_graph_fixture(
    count=true,
    count_filter_chain=true,
    keyed_count_filter_chain=true,
  )
  let sequence = dispatch_test_generated(run)[0]
  let limits = dispatch_test_limits()
  let registry = search_registry()
  let installed = @local_connector.prepare_local_compute_module(
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    [sequence],
    limits.local_execution,
    limits.guards,
    limits.candidate_work,
    1,
  ).unwrap()
  let provider = @local_connector.local_module_managed_provider(
    installed, sequence,
  ).unwrap()
  let capacity = @local_connector.managed_provider_capacity(provider, sequence).unwrap()
  let base = @execution.generated_sequence_capacity(
    sequence,
    limits.local_execution,
    limits.guards,
  ).unwrap()
  let mut overlapping = 0L
  let count = @execution.generated_sequence_step_count(sequence)
  assert_eq(count, 3)
  for index in 0..<count {
    let step = @execution.generated_sequence_step_index_at(sequence, index).unwrap()
    let selected = @execution.select_generated_sequence_step(sequence, step).unwrap()
    let child = @execution.generated_sequence_capacity(
      selected,
      limits.local_execution,
      limits.guards,
    ).unwrap()
    overlapping += child.retained_bytes + child.execution_bytes
  }
  assert_true(overlapping > base.execution_bytes)
  assert_eq(capacity.retained_bytes, base.retained_bytes)
  assert_eq(capacity.execution_bytes, overlapping + count.to_int64() * 256L)
  @strategy.stop_captured_dag(run)
  @mock.close_mock_query_issuer(issuer)
}

///|
fn run_ordinary_captured_relation_chain_cancel(kind : String) -> Unit raise {
  let (run, issuer) = captured_graph_fixture(
    unpivot_filter_chain=kind == "unpivot",
    dedupe_filter_chain=kind == "dedupe",
    count=kind == "keyed_count",
    count_filter_chain=kind == "keyed_count",
    keyed_count_filter_chain=kind == "keyed_count",
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
      wire: retained_attempt_wire_limits(),
      row: { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
      max_batch_bytes: 256,
    },
    None,
  ).unwrap()
  let owner = @strategy.graph_task_owner(@strategy.captured_dag_graph(run), 1).unwrap()
  let setup : @local_driver.LocalManagedDispatchConfiguration[Int] = @local_driver.prepare_local_managed_dispatch_with_outputs(
      installed,
      [@local_driver.local_managed_captured_relation_input()],
      @execution.process_managed_obligations(owner),
      0L,
    )
    .unwrap()
    .unwrap()
  assert_true(@local_driver.local_managed_dispatch_uses_provider(setup))
  let operations = @local_driver.start_local_managed_dispatch_node(setup).unwrap()
  let first = (operations.advance)(1).unwrap()
  assert_false(first.complete)
  assert_eq(first.work, 1L)
  assert_true((operations.request_cancel)())
  assert_true((operations.advance)(1) is Err(_))
  assert_true((operations.execution_stopped)())
  assert_true((operations.output_row)(0) is Err(_))
  assert_true(
    (operations.complete)(1, operations.storage_bytes, fn() { true }) is Err(_),
  )
  (operations.settle)().unwrap()
  assert_true((operations.cleanup_refresh)())
  assert_false(@strategy.captured_task_completed(run, 1))
  @strategy.stop_captured_dag(run)
  for task in 0..<4 {
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
test "ordinary captured Relation chain cancels after bounded work" {
  for kind in ["filter", "unpivot", "keyed_count", "dedupe"] {
    run_ordinary_captured_relation_chain_cancel(kind)
  }
}

///|
test "ordinary Local select preserves authored order within quantum" {
  run_local_managed_unary_case("select")
}

///|
test "ordinary Local derive resumes within quantum and preserves row order" {
  for kind in ["derive_map", "derive_empty", "derive_ordered"] {
    run_local_managed_unary_case(kind)
  }
}

///|
test "ordinary Local assertions resume within quantum and retain input rows" {
  run_local_managed_unary_case("assert_where")
  run_local_managed_unary_case("assert_unique")
}

///|
test "ordinary Local rename resumes within quantum" {
  for kind in ["rename", "rename_swap", "rename_empty"] {
    run_local_managed_unary_case(kind)
  }
}

///|
test "ordinary Local drop resumes within quantum" {
  for kind in ["drop", "drop_empty", "drop_repeated"] {
    run_local_managed_unary_case(kind)
  }
}

///|
test "ordinary Local take resumes within quantum and feeds two Computes" {
  run_local_managed_unary_case("take")
  run_local_managed_unary_case("take_parameter")
}

///|
test "ordinary Local global top-k resumes within quantum" {
  for kind in ["top_k", "top_k_parameter", "top_k_compound"] {
    run_local_managed_unary_case(kind)
  }
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
    require_provider=true,
    execution_quantum=1,
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
