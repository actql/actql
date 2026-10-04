///|
fn local_values_asof_program() -> String {
  (
    #|{"version":"actql/0.1","id":"p","params":{"minimum":{"type":"number","nullable":false}},"stages":[{"id":"a","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > $minimum","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"r":{"from":"captured","fields":["id"]}}},{"id":"left_values","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"key":{"type":"number","nullable":false},"clock":{"type":"number","nullable":false}},"rows":[{"id":1,"key":1,"clock":100}]},"as":"out"}],"results":{"r":{"from":"out","fields":["id","key","clock"]}}},{"id":"right_values","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"key":{"type":"number","nullable":false},"clock":{"type":"number","nullable":false},"priority":{"type":"number","nullable":true},"value":{"type":"number","nullable":false}},"rows":[{"id":11,"key":1,"clock":90,"priority":5,"value":100},{"id":11,"key":1,"clock":90,"priority":5,"value":200},{"id":11,"key":1,"clock":100,"priority":0,"value":300}]},"as":"out"}],"results":{"r":{"from":"out","fields":["id","key","clock","priority","value"]}}},{"id":"joined","inputs":{"l":{"result":{"stage":"left_values","result":"r"}},"r":{"result":{"stage":"right_values","result":"r"}}},"steps":[{"from":"l","asof_join":{"with":"r","kind":"inner","by":[{"left":"key","right":"key"}],"left_id":"id","left_time":"clock","right_time":"clock","direction":"backward","tolerance":10,"right_tie_break":["priority"],"select":{"id":"left.id","value":"right.value"}},"as":"out"}],"results":{"r":{"from":"out","fields":["id","value"]}}},{"id":"consumer_a","inputs":{"x":{"result":{"stage":"joined","result":"r"}}},"steps":[{"select":["id","value"],"as":"out"}],"results":{"r":{"from":"out","fields":["id","value"]}}},{"id":"consumer_b","inputs":{"x":{"result":{"stage":"joined","result":"r"}}},"steps":[{"select":["value","id"],"as":"out"}],"results":{"r":{"from":"out","fields":["value","id"]}}}],"results":{"source":{"from":{"stage":"a","result":"r"}}}}
  )
}

///|
test "standard Host runs bounded as-of join for two consumers" {
  let (run, issuer) = captured_graph_fixture(
    local_values_asof_chain=true,
    managed_publication=true,
    ledger_limits=Some({
      planning_work: 10000,
      attempts: 20,
      holdings: 20,
      transfer_bytes: 300000L,
      retained_bytes: 134217728L,
      execution_bytes: 536870912L,
    }),
  )
  assert_true(
    @strategy.configure_captured_managed_identity_policy(
      run, true, false, false, false,
    ),
  )
  assert_eq(@strategy.captured_task_asof_search_count(run, 3), Some(1))
  assert_eq(@strategy.captured_task_asof_search_at(run, 3, 0), Some((0, 3L)))
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let generated = dispatch_test_generated(run)
  let asof_capacity = @execution.generated_sequence_capacity(
    generated[2],
    limits.local_execution,
    limits.guards,
  ).unwrap()
  let asof_provider = @local_tea_provider.asof_join_provider(
    carrier_events_storage_limits(),
    asof_capacity,
  )
  let installed = @local_driver.prepare_local_dispatch_module(
    @host_driver.open_dispatch_driver(run),
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    generated,
    limits.local_execution,
    limits.guards,
    limits.candidate_work,
    managed_providers=[asof_provider],
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
  let left_live = Ref(true)
  let (left_ops, left) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    left_live,
    obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
  )
  let left_rows = local_managed_test_rows(left_ops)
  let right_live = Ref(true)
  let (right_ops, right) = run_local_managed_test_task(
    installed,
    run,
    2,
    [],
    [],
    2,
    right_live,
    obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
  )
  let right_rows = local_managed_test_rows(right_ops)
  let join_live = Ref(true)
  let join_obligations = @strategy.captured_next_managed_obligations(run, 10).unwrap()
  let (join_ops, joined) = run_local_managed_test_task(
    installed,
    run,
    3,
    [left, right],
    [left_rows, right_rows],
    3,
    join_live,
    obligations=join_obligations,
  )
  let joined_rows = local_managed_test_rows(join_ops)
  assert_eq(joined_rows, ["{\"id\":1,\"value\":300}"])
  let requirements = @execution.managed_obligations_identities(join_obligations)
  let published = requirements.filter(requirement => {
    requirement.domain == @execution.LogicalRelation &&
    requirement.subject == @execution.NamedResult
  })
  assert_eq(published.length(), 1)
  assert_eq(
    @execution.managed_completed_identity_requirement_status(
      joined,
      published[0],
    ),
    Some(
      @execution.EstablishedSourceRetained(
        @execution.logical_relation_canonical_contract_cid(),
        "sha256:db07d32e15ad106975d22c1b251a3f6d5e2a0e3c86ec495d405f892de12df8db",
      ),
    ),
  )
  let first_live = Ref(true)
  let (first_ops, first) = run_local_managed_test_task(
    installed,
    run,
    4,
    [joined],
    [joined_rows],
    4,
    first_live,
    obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
  )
  let second_live = Ref(true)
  let (second_ops, second) = run_local_managed_test_task(
    installed,
    run,
    5,
    [joined],
    [joined_rows],
    5,
    second_live,
    obligations=@strategy.captured_next_managed_obligations(run, 10).unwrap(),
  )
  assert_eq(local_managed_test_rows(first_ops), joined_rows)
  assert_eq(local_managed_test_rows(second_ops), ["{\"value\":300,\"id\":1}"])
  close_retained_host_consumer(run, 4, first_ops, first_live, first)
  assert_true(@execution.managed_completed_output_available(second))
  assert_true(@execution.managed_completed_output_available(joined))
  close_retained_host_consumer(run, 5, second_ops, second_live, second)
  join_live.val = false
  @strategy.close_captured_task_output(run, 3)
  (join_ops.close)()
  (join_ops.cleanup_refresh)() |> ignore
  left_live.val = false
  @strategy.close_captured_task_output(run, 1)
  (left_ops.close)()
  (left_ops.cleanup_refresh)() |> ignore
  right_live.val = false
  @strategy.close_captured_task_output(run, 2)
  (right_ops.close)()
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
