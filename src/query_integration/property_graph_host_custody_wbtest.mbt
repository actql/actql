///|
fn current_graph_relation_program(variant : String) -> String {
  let relation_step = match variant {
    "current_filter" | "current_edge_filter" => "\"filter\":\"true\""
    "current_degree" => "\"filter\":\"degree >= 0\""
    "current_bounds" => "\"filter\":\"actual >= 0\""
    "current_filter_false" => "\"filter\":\"false\""
    "current_select" => "\"select\":[\"id\",\"node_name\"]"
    "current_derive" => "\"derive\":{\"copy\":\"id\"}"
    "current_take" => "\"take\":1"
    "current_sort" => "\"sort\":[{\"id\":\"desc\"}]"
    "current_assert" => "\"assert_rows\":{\"where\":\"id > 0\"}"
    "current_unique" => "\"assert_rows\":{\"unique_by\":[\"id\"]}"
    _ => abort("unknown current Graph regression variant")
  }
  let matched = if variant == "current_degree" {
    "{\"degree\":{\"direction\":\"both\"},\"as\":\"projected\"}"
  } else if variant == "current_bounds" {
    "{\"graph_bounds\":{\"max_nodes\":1,\"max_edges\":1},\"as\":\"projected\"}"
  } else if variant == "current_edge_filter" {
    "{\"match_edges\":{\"definition\":\"E\",\"label\":\"Edge\",\"where\":\"true\",\"fields\":[\"src\",\"dst\",\"weight\"]},\"as\":\"projected\"}"
  } else {
    "{\"match_nodes\":{\"definition\":\"N\",\"label\":\"Node\",\"bindings\":{\"identity\":\"element\"},\"where\":\"true\",\"fields\":[\"element\",\"id\",\"node_name\"]},\"as\":\"projected\"}"
  }
  let result_fields = if variant == "current_degree" {
    "\"node\",\"degree\""
  } else if variant == "current_bounds" {
    "\"kind\",\"node_id\",\"actual\",\"max\""
  } else if variant == "current_edge_filter" {
    "\"src\",\"dst\",\"weight\""
  } else if variant == "current_derive" {
    "\"id\",\"node_name\",\"copy\""
  } else {
    "\"id\",\"node_name\""
  }
  let first_fields = if variant == "current_degree" {
    "\"node\",\"degree\""
  } else if variant == "current_bounds" {
    "\"kind\",\"actual\""
  } else if variant == "current_edge_filter" {
    "\"src\",\"weight\""
  } else {
    "\"id\",\"node_name\""
  }
  let second_fields = if variant == "current_degree" {
    "\"degree\""
  } else if variant == "current_bounds" {
    "\"kind\""
  } else if variant == "current_edge_filter" {
    "\"weight\""
  } else {
    "\"node_name\""
  }
  let template =
    #|{"version":"actql/0.1","id":"p","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}},{"id":"values","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"src":{"type":"number","nullable":false},"dst":{"type":"number","nullable":false},"node_name":{"type":"string","nullable":false},"weight":{"type":"number","nullable":false}},"rows":[{"id":1,"src":1,"dst":2,"node_name":"first","weight":10},{"id":2,"src":2,"dst":1,"node_name":"second","weight":20}]},"as":"out"}],"results":{"r":{"from":"out","fields":["id","src","dst","node_name","weight"]}}},{"id":"graph","inputs":{"rows":{"result":{"stage":"values","result":"r"}}},"steps":[{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"rows","key":["id"],"labels":[{"name":"Node","properties":{"mode":"columns","columns":[{"from":"id","to":"id"},{"from":"node_name","to":"node_name"}]}}]}],"edges":[{"name":"E","from":"rows","key":["id"],"source":{"definition":"N","key":["src"]},"target":{"definition":"N","key":["dst"]},"labels":[{"name":"Edge","properties":{"mode":"columns","columns":[{"from":"src","to":"src"},{"from":"dst","to":"dst"},{"from":"weight","to":"weight"}]}}]}]},"as":"g"},MATCH_STEP,RELATION_STEP],"results":{"r":{"from":"out","fields":[RESULT_FIELDS]}}},{"id":"consumer_a","inputs":{"x":{"result":{"stage":"graph","result":"r"}}},"steps":[{"select":[FIRST_FIELDS],"as":"out"}],"results":{"r":{"from":"out","fields":[FIRST_FIELDS]}}},{"id":"consumer_b","inputs":{"x":{"result":{"stage":"graph","result":"r"}}},"steps":[{"select":[SECOND_FIELDS],"as":"out"}],"results":{"r":{"from":"out","fields":[SECOND_FIELDS]}}}],"results":{"source":{"from":{"stage":"a","result":"r"}}}}
  template
  .replace(old="MATCH_STEP", new=matched)
  .replace(old="RELATION_STEP", new="{" + relation_step + ",\"as\":\"out\"}")
  .replace(old="RESULT_FIELDS", new=result_fields)
  .replace_all(old="FIRST_FIELDS", new=first_fields)
  .replace_all(old="SECOND_FIELDS", new=second_fields)
}

///|

///|
fn run_current_host_graph_relation_path(
  variant? : String = "current_filter",
  execution_quantum? : Int = 0,
  cancel_take_after? : Int = 0,
  cleanup_attempts? : Ref[Int]? = None,
) -> Unit raise {
  let (run, issuer) = captured_graph_fixture(
    local_carrier_graph_chain=true,
    local_carrier_graph_variant=variant,
    managed_publication=true,
    ledger_limits=Some({
      planning_work: 30000,
      attempts: 20,
      holdings: 20,
      transfer_bytes: 800000L,
      retained_bytes: 96000000L,
      execution_bytes: 402653184L,
    }),
  )
  let graph = @strategy.captured_dag_graph(run)
  assert_eq(@strategy.graph_task_count(graph), 7)
  assert_true(@strategy.graph_ordered_inputs_complete(graph))
  assert_true(
    @strategy.configure_captured_managed_identity_policy(
      run, true, false, false, false,
    ),
  )
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let sequences = dispatch_test_generated(run)
  if variant == "current_take" {
    let sequence = sequences[3]
    let pipeline = @lower.pipeline(
      @lower.bound_preparation(@execution.generated_sequence_owner(sequence)),
    )
    assert_true(@pipeline.take_order(pipeline, 2) is Some(_))
    let mut takes = 0
    for position in 0..<@execution.generated_sequence_step_count(sequence) {
      if @execution.generated_sequence_step_at(sequence, position)
        is Some(@lower.RowStep(candidate)) &&
        @lower.kernel_take(candidate) is Some(_) {
        takes += 1
      }
    }
    assert_eq(takes, 1)
  }
  let provider = @local_sga_provider.provider(
    carrier_graph_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      sequences[1],
      limits.local_execution,
      limits.guards,
    ).unwrap(),
  )
  let provider = if cleanup_attempts is Some(attempts) {
    // The installed sequence includes construction at 0 and MATCH at 1;
    // the driver selects that original occurrence for physical task 3.
    assert_true(
      @execution.generated_sequence_step_at(sequences[3], 1)
      is Some(@lower.GraphMatchStep(_)),
    )
    delayed_cleanup_provider(
      provider,
      attempts,
      only_owner=@execution.generated_sequence_owner(sequences[3]),
      only_step=@execution.generated_sequence_step_index_at(sequences[3], 1).unwrap(),
      cleanup_error=true,
    )
  } else {
    provider
  }
  let modules = @builtin.configure_compute_modules(
    @host_driver.open_dispatch_driver(run),
    registry,
    1,
    _ => @strategy.RunIssue::ForeignCandidate,
    with_local=Some(
      (
        @connector.capability_registration_at(registry, 0).unwrap(),
        {
          sequences,
          managed_providers: [provider],
          managed_capacity: limits.capacity,
          execution: limits.local_execution,
          measurement: limits.guards,
          max_work: limits.candidate_work,
        },
        _ => @strategy.RunIssue::ForeignCandidate,
        _ => @strategy.RunIssue::ForeignCandidate,
      ),
    ),
  ).unwrap()
  let installed = @builtin.configured_local_module(modules).unwrap()
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
        max_columns: 10,
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
  let values_live = Ref(true)
  let (values_ops, values) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    values_live,
    obligations?=graph_publication_obligations(run, true),
  )
  let values_rows = local_managed_test_rows(values_ops)
  let construction_inputs = Array::makei(2, _ => {
    @local_driver.local_managed_relation_output(values)
  })
  let construction_rows = Array::makei(2, _ => values_rows)
  let (construction_ops, construction, construction_material) = run_local_managed_carrier_test_task(
    installed,
    run,
    2,
    construction_inputs,
    construction_rows,
    obligations?=graph_publication_obligations(run, true),
  )
  if cleanup_attempts is Some(attempts) {
    assert_eq(attempts.val, 0)
  }
  let projected_live = Ref(true)
  let (projected_ops, projected) = run_local_managed_test_task(
    installed,
    run,
    3,
    [],
    [],
    3,
    projected_live,
    carrier_inputs=[(construction, construction_material)],
    obligations?=graph_publication_obligations(run, true),
  )
  let projected_rows = local_managed_test_rows(projected_ops)
  if cleanup_attempts is Some(attempts) {
    // Settlement observed false from the actual MATCH execution. An error
    // during refresh must preserve the same real Host reservation and holding.
    assert_eq(attempts.val, 1)
    let pending = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
    assert_true(pending.reserved_execution_bytes > 0L)
    assert_true(pending.held_bytes > 0L)
    assert_false((projected_ops.cleanup_refresh)())
    assert_eq(attempts.val, 2)
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)),
      pending,
    )
    assert_true(@execution.managed_completed_output_available(projected))
  }
  if cancel_take_after > 0 {
    let cancelled_ops = start_local_managed_test_task_operations(
      installed,
      run,
      4,
      [projected],
      [projected_rows],
      obligations?=graph_publication_obligations(run, true),
    )
    for _ in 0..<cancel_take_after {
      let observation = (cancelled_ops.advance)(1).unwrap()
      assert_false(observation.complete)
      assert_true(observation.work <= 1L)
    }
    assert_true((cancelled_ops.request_cancel)())
    assert_true((cancelled_ops.advance)(1) is Err(_))
    assert_true((cancelled_ops.execution_stopped)())
    assert_true((cancelled_ops.material)() is None)
    (cancelled_ops.settle)().unwrap()
    @strategy.close_captured_task_output(run, 4)
    (cancelled_ops.close)()
    (cancelled_ops.cleanup_refresh)() |> ignore
    projected_live.val = false
    @strategy.close_captured_task_output(run, 3)
    (projected_ops.close)()
    (projected_ops.cleanup_refresh)() |> ignore
    @strategy.close_captured_task_output(run, 2)
    (construction_ops.close)()
    (construction_ops.cleanup_refresh)() |> ignore
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
    return
  }
  let filtered_live = Ref(true)
  let execution_advances = Ref(0)
  let filtered_obligations = graph_publication_obligations(run, true).unwrap()
  let (filtered_ops, filtered) = run_local_managed_test_task(
    installed,
    run,
    4,
    [projected],
    [projected_rows],
    4,
    filtered_live,
    obligations=filtered_obligations,
    execution_quantum~,
    execution_advances=Some(execution_advances),
  )
  if execution_quantum == 1 {
    assert_true(execution_advances.val > 1)
  }
  let filtered_rows = local_managed_test_rows(filtered_ops)
  let expected_rows = if variant == "current_take" {
    1
  } else if variant == "current_filter_false" {
    0
  } else {
    2
  }
  assert_eq(filtered_rows.length(), expected_rows)
  if variant == "current_filter_false" {
    assert_true(filtered_rows.is_empty())
  } else if variant == "current_filter" {
    assert_eq(filtered_rows, projected_rows)
    assert_true(filtered_rows[0].contains("\"id\":1"))
    assert_true(filtered_rows[1].contains("\"id\":2"))
  } else if variant == "current_select" {
    assert_true(filtered_rows[0].contains("\"id\":1"))
    assert_true(filtered_rows[1].contains("\"id\":2"))
  } else if variant == "current_derive" {
    assert_true(filtered_rows[0].contains("\"copy\":1"))
    assert_true(filtered_rows[1].contains("\"copy\":2"))
  } else if variant == "current_take" {
    assert_true(filtered_rows[0].contains("\"id\":1"))
  } else if variant == "current_sort" {
    assert_true(filtered_rows[0].contains("\"id\":2"))
    assert_true(filtered_rows[1].contains("\"id\":1"))
  } else if variant == "current_assert" {
    assert_eq(filtered_rows, projected_rows)
  } else if variant == "current_unique" {
    assert_eq(filtered_rows, projected_rows)
  } else if variant == "current_degree" {
    assert_true(filtered_rows[0].contains("\"degree\":2"))
    assert_true(filtered_rows[1].contains("\"degree\":2"))
    assert_true(filtered_rows[0].contains("\"definition\":\"N\""))
    assert_true(filtered_rows[0].contains("\"key\":[1]"))
    assert_true(filtered_rows[1].contains("\"key\":[2]"))
  } else if variant == "current_bounds" {
    assert_eq(filtered_rows, [
      "{\"actual\":2,\"kind\":\"nodes\",\"max\":1,\"node_id\":null}", "{\"actual\":2,\"kind\":\"edges\",\"max\":1,\"node_id\":null}",
    ])
  } else {
    assert_true(filtered_rows[0].contains("\"src\":1"))
    assert_true(filtered_rows[1].contains("\"src\":2"))
  }
  if cleanup_attempts is Some(_) {
    assert_graph_host_match_rows(variant, filtered_rows)
  }
  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    5,
    [filtered],
    [filtered_rows],
    5,
    first_live,
    obligations?=graph_publication_obligations(run, true),
  )
  if variant == "current_degree" {
    let rows = local_managed_test_rows(first_ops)
    assert_eq(rows.length(), 2)
    assert_true(rows[0].contains("\"key\":[1]"))
    assert_true(rows[1].contains("\"key\":[2]"))
    assert_true(rows[0].contains("\"degree\":2"))
    assert_true(rows[1].contains("\"degree\":2"))
  } else if variant == "current_bounds" {
    assert_eq(local_managed_test_rows(first_ops), [
      "{\"kind\":\"nodes\",\"actual\":2}", "{\"kind\":\"edges\",\"actual\":2}",
    ])
  }
  if cleanup_attempts is Some(_) {
    if variant == "current_filter" {
      assert_eq(local_managed_test_rows(first_ops), [
        "{\"id\":1,\"node_name\":\"first\"}", "{\"id\":2,\"node_name\":\"second\"}",
      ])
    } else {
      assert_eq(local_managed_test_rows(first_ops), [
        "{\"src\":1,\"weight\":10}", "{\"src\":2,\"weight\":20}",
      ])
    }
  }
  let second_live = Ref(true)
  let mut closed_parent_bytes = 0L
  let (second_ops, second) = if cleanup_attempts is Some(attempts) {
    let operations = start_local_managed_test_task_operations(
      installed,
      run,
      6,
      [filtered],
      [filtered_rows],
      obligations?=graph_publication_obligations(run, true),
    )
    // One bounded poll has not produced a result. The remaining consumer
    // still needs its input for execution, not merely a published reread.
    let pending = (operations.advance)(1).unwrap()
    assert_false(pending.complete)
    assert_eq((operations.output_rows)(), 0)
    assert_true((operations.material)() is None)
    assert_false(@strategy.captured_task_completed(run, 6))
    close_graph_host_consumer(run, 5, first_ops, first_live, first)
    assert_true(@execution.managed_completed_output_available(filtered))
    closed_parent_bytes = @execution.managed_completed_output_storage_bytes(
      filtered,
    ).unwrap()
    assert_true(closed_parent_bytes > 0L)
    let held = @resources.ledger_usage(@strategy.captured_dag_ledger(run)).held_bytes
    // Revoke the Host public port, not the already-borrowed material.
    @strategy.close_captured_task_output(run, 4)
    (filtered_ops.close)()
    (filtered_ops.cleanup_refresh)() |> ignore
    assert_false(
      @strategy.captured_managed_task_output_matches(
        run,
        4,
        @strategy.captured_task_target(run, 4).unwrap(),
        filtered,
      ),
    )
    assert_true(@execution.managed_completed_output_available(filtered))
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)).held_bytes,
      held,
      msg="in-flight consumer must retain the closed producer holding",
    )
    // Actual execution, finalization and Host completion all happen AFTER
    // the producer port is revoked. Exact operation rows are checked below.
    (operations.execute)().unwrap()
    if variant == "current_filter" {
      assert_eq(local_managed_test_rows(operations), [
        "{\"node_name\":\"first\"}", "{\"node_name\":\"second\"}",
      ])
    } else {
      assert_eq(local_managed_test_rows(operations), [
        "{\"weight\":10}", "{\"weight\":20}",
      ])
    }
    (operations.prepare_finalization)(6, operations.storage_bytes, fn() {
      second_live.val
    }).unwrap()
    let mut polls = 0
    let mut ready = false
    while !ready && polls < 10000 {
      polls += 1
      ready = (operations.advance_finalization)(1).unwrap().complete
    }
    assert_true(ready)
    (operations.settle)().unwrap()
    let completion = (operations.complete)(6, operations.storage_bytes, fn() {
      second_live.val
    })
    if completion is Err(@local_driver.Execution(@strategy.ForeignCandidate)) {
      fail(
        "Closed producer port rejects the acquired consumer completion: Execution(ForeignCandidate)",
      )
    }
    let completed = completion.unwrap()
    assert_true(@strategy.captured_task_completed(run, 6))
    @strategy.refresh_captured_retention(run)
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)).held_bytes,
      held +
      @execution.managed_completed_output_storage_bytes(completed).unwrap(),
      msg="published consumer must retain its closed producer holding",
    )
    // Completion seals input evidence. Only now retire the fixture's source
    // material; the remaining consumer still owns the Host parent dependency.
    filtered_live.val = false
    assert_true((filtered_ops.cleanup_refresh)())
    @strategy.refresh_captured_retention(run)
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)).held_bytes,
      held +
      @execution.managed_completed_output_storage_bytes(completed).unwrap(),
      msg="last consumer must retain the producer holding after owner cleanup",
    )
    assert_eq(attempts.val, 2)
    (operations, completed)
  } else {
    run_local_managed_test_task(
      installed,
      run,
      6,
      [filtered],
      [filtered_rows],
      6,
      second_live,
      obligations?=graph_publication_obligations(run, true),
    )
  }
  assert_eq(local_managed_test_rows(second_ops).length(), expected_rows)
  if variant == "current_degree" {
    assert_eq(local_managed_test_rows(second_ops), [
      "{\"degree\":2}", "{\"degree\":2}",
    ])
  } else if variant == "current_bounds" {
    assert_eq(local_managed_test_rows(second_ops), [
      "{\"kind\":\"nodes\"}", "{\"kind\":\"edges\"}",
    ])
  }
  if cleanup_attempts is Some(_) {
    // Independent expected projections are outside the owner helpers.
    if variant == "current_filter" {
      assert_eq(local_managed_test_rows(second_ops), [
        "{\"node_name\":\"first\"}", "{\"node_name\":\"second\"}",
      ])
    } else {
      assert_eq(local_managed_test_rows(second_ops), [
        "{\"weight\":10}", "{\"weight\":20}",
      ])
    }
  } else {
    assert_eq(local_managed_test_rows(first_ops).length(), expected_rows)
    close_graph_host_consumer(run, 5, first_ops, first_live, first)
    assert_true(@execution.managed_completed_output_available(second))
    assert_true(@execution.managed_completed_output_available(filtered))
  }
  close_graph_host_consumer(
    run,
    6,
    second_ops,
    second_live,
    second,
    released_parent_bytes=closed_parent_bytes,
  )
  if cleanup_attempts is Some(attempts) {
    assert_false(@execution.managed_completed_output_available(filtered))
    assert_true(@execution.managed_completed_output_available(projected))
    assert_eq(attempts.val, 2)
    assert_true(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)).reserved_execution_bytes >
      0L,
    )
  }
  filtered_live.val = false
  @strategy.close_captured_task_output(run, 4)
  (filtered_ops.close)()
  (filtered_ops.cleanup_refresh)() |> ignore
  projected_live.val = false
  @strategy.close_captured_task_output(run, 3)
  (projected_ops.close)()
  if cleanup_attempts is Some(attempts) {
    // Disposing the execution is distinct from acknowledging scratch cleanup.
    // Both consumer outputs are already closed; the VALUES holding stays live.
    assert_eq(attempts.val, 2)
    retry_graph_host_match_cleanup(run, projected_ops, values, attempts)
  }
  (projected_ops.cleanup_refresh)() |> ignore
  @strategy.close_captured_task_output(run, 2)
  (construction_ops.close)()
  (construction_ops.cleanup_refresh)() |> ignore
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
test "standard Host composes current keyed MATCH with bounded Relation consumers and releases all capacity" {
  for
    variant in [
      "current_filter", "current_filter_false", "current_edge_filter", "current_select",
      "current_derive", "current_take", "current_sort", "current_assert", "current_unique",
    ] {
    for quantum in [1, 7, 1024] {
      run_current_host_graph_relation_path(variant~, execution_quantum=quantum)
    }
  }
}

///|
test "standard Host composes bounded Graph diagnostics with Relation consumers" {
  for variant in ["current_degree", "current_bounds"] {
    for quantum in [1, 7] {
      run_current_host_graph_relation_path(variant~, execution_quantum=quantum)
    }
  }
}

///|
test "standard Host cancellation after current MATCH preserves cleanup and returns capacity" {
  run_current_host_graph_relation_path(
    variant="current_take",
    cancel_take_after=18,
  )
}

///|
fn close_graph_host_consumer(
  run : @strategy.CapturedDAG,
  task : Int,
  operations : @local_driver.LocalManagedDispatchOperations[Int],
  live : Ref[Bool],
  output : @execution.ManagedCompletedOutput[Int],
  released_parent_bytes? : Int64 = 0L,
) -> Unit raise {
  let before = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  let bytes = @execution.managed_completed_output_storage_bytes(output).unwrap()
  live.val = false
  @strategy.close_captured_task_output(run, task)
  (operations.close)()
  (operations.cleanup_refresh)() |> ignore
  assert_false(@execution.managed_completed_output_available(output))
  let after = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(
    after.held_bytes,
    before.held_bytes - bytes - released_parent_bytes,
    msg="consumer close must return each owned holding exactly once",
  )
  // Repeating close must not credit this allocation again at an intermediate
  // nonzero ledger balance; final-zero alone cannot establish that property.
  @strategy.close_captured_task_output(run, task)
  (operations.close)()
  (operations.cleanup_refresh)() |> ignore
  assert_eq(@resources.ledger_usage(@strategy.captured_dag_ledger(run)), after)
}

///|
fn retry_graph_host_match_cleanup(
  run : @strategy.CapturedDAG,
  operations : @local_driver.LocalManagedDispatchOperations[Int],
  output : @execution.ManagedCompletedOutput[Int],
  attempts : Ref[Int],
) -> Unit raise {
  let pending = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  let work = (operations.cumulative_provider_work)().unwrap()
  (operations.cleanup_refresh)() |> ignore
  assert_eq(attempts.val, 3)
  let cleaned = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_true(
    cleaned.reserved_execution_bytes < pending.reserved_execution_bytes,
  )
  assert_eq(cleaned.held_bytes, pending.held_bytes)
  assert_eq(cleaned.reserved_retention_bytes, pending.reserved_retention_bytes)
  assert_eq(cleaned.transferred_bytes, pending.transferred_bytes)
  assert_eq((operations.cumulative_provider_work)(), Ok(work))
  assert_true(@execution.managed_completed_output_available(output))
  // A second refresh must not return any additional credit or rerun cleanup.
  (operations.cleanup_refresh)() |> ignore
  assert_eq(attempts.val, 3)
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)),
    cleaned,
  )
}

///|
fn assert_graph_host_match_rows(
  variant : String,
  rows : Array[String],
) -> Unit raise {
  if variant == "current_filter" {
    // Independent definition preimage: admitted constructor mappings, two
    // VALUES producer occurrences and their declared field projections.
    // No checker output, runtime Graph value or observed identity is used.
    let definition =
      #|{"constructor":{"edges":[{"input_occurrence":1,"key":["id"],"labels":[{"name":"Edge","properties":{"columns":[{"from":"src","to":"src"},{"from":"dst","to":"dst"},{"from":"weight","to":"weight"}],"mode":"columns"}}],"name":"E","source":{"definition":"N","key":["src"]},"target":{"definition":"N","key":["dst"]}}],"nodes":[{"input_occurrence":0,"key":["id"],"labels":[{"name":"Node","properties":{"columns":[{"from":"id","to":"id"},{"from":"node_name","to":"node_name"}],"mode":"columns"}}],"name":"N"}],"version":"actql-property-graph-constructor/0.1"},"producer_definitions":[{"producer":{"body":{"values":{"rows":[{"dst":2,"id":1,"node_name":"first","src":1,"weight":10},{"dst":1,"id":2,"node_name":"second","src":2,"weight":20}],"schema":{"dst":{"nullable":false,"type":"number"},"id":{"nullable":false,"type":"number"},"node_name":{"nullable":false,"type":"string"},"src":{"nullable":false,"type":"number"},"weight":{"nullable":false,"type":"number"}}}},"dependencies":[]},"projection":["id","src","dst","node_name","weight"]},{"producer":{"body":{"values":{"rows":[{"dst":2,"id":1,"node_name":"first","src":1,"weight":10},{"dst":1,"id":2,"node_name":"second","src":2,"weight":20}],"schema":{"dst":{"nullable":false,"type":"number"},"id":{"nullable":false,"type":"number"},"node_name":{"nullable":false,"type":"string"},"src":{"nullable":false,"type":"number"},"weight":{"nullable":false,"type":"number"}}}},"dependencies":[]},"projection":["id","src","dst","node_name","weight"]}],"version":"actql-property-graph-definition/0.1"}
    let domain = "sha256:" + @sha.hex(@utf8.encode(definition))
    let expected = Array::makei(2, index => {
      "{\"element\":{\"definition\":\"N\",\"domain\":\"" +
      domain +
      "\",\"key\":[" +
      (index + 1).to_string() +
      "],\"key_types\":[{\"kind\":\"number\"}]},\"id\":" +
      (index + 1).to_string() +
      ",\"node_name\":\"" +
      (if index == 0 { "first" } else { "second" }) +
      "\"}"
    })
    assert_eq(rows, expected)
  } else {
    assert_eq(variant, "current_edge_filter")
    assert_eq(rows, [
      "{\"dst\":2,\"src\":1,\"weight\":10}", "{\"dst\":1,\"src\":2,\"weight\":20}",
    ])
  }
}

///|
test "Host MATCH nodes retains cleanup responsibility through false error and retry" {
  for quantum in [1, 7, 1024] {
    run_current_host_graph_relation_path(
      variant="current_filter",
      execution_quantum=quantum,
      cleanup_attempts=Some(Ref(0)),
    )
  }
}

///|
test "Host MATCH edges retains cleanup responsibility through false error and retry" {
  for quantum in [1, 7, 1024] {
    run_current_host_graph_relation_path(
      variant="current_edge_filter",
      execution_quantum=quantum,
      cleanup_attempts=Some(Ref(0)),
    )
  }
}
