///|
test "original SQL SHA256 returns a checked BYTES row through the retained Local task" {
  let setup = source_free_subquery_retained_fixture(
    "SELECT SHA256('a') AS x, SHA256(NULL) AS missing, SHA256(SHA256('a')) AS twice",
  )
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(setup),
  )
  let graph = @strategy.captured_dag_graph(run)
  let program = @strategy.graph_program(graph)
  let results = @stage_results.stage_at(
    @program_check.checked_stage_results(program),
    0,
  ).unwrap()
  let original = @relation_results.lookup(results, "rows").unwrap()
  let schema = @relation_results.output_schema(original)
  assert_eq(@schema.field_count(schema), 3)
  assert_eq(@relation_results.fields(original), ["x", "missing", "twice"])
  for (name, nullable) in [("x", false), ("missing", true), ("twice", false)] {
    let checked = @schema.lookup(schema, Unqualified(name)).unwrap()
    assert_true(checked.shape is Bytes)
    assert_eq(checked.nullable, nullable)
  }
  let execution = match
    @client_local_host.execute_source_free_local_tasks_guarded(
      setup,
      16,
      10000,
      () => true,
    ) {
    Ok(value) => value
    Err(failure) => {
      assert_false(
        @client_local_host.local_values_execution_failure_cleanup_pending(
          failure,
        ),
      )
      let reason = match
        @client_local_host.local_values_execution_failure_issue(failure) {
        Driver(issue) =>
          @local_driver.local_managed_failure_cause(issue).unwrap_or(
            "unclassified Local failure",
          )
        _ => "original Local execution failed"
      }
      fail(reason)
    }
  }
  assert_eq(execution.rows().unwrap(), [
    "{\"x\":\"ypeBEsobvcr6wjGzmiPcTaeG7/gUfE5yuYB3ha/uSLs=\",\"missing\":null,\"twice\":\"v106/7c+/S7Gw2rTES3ZM+/tY8Thy//PqI4nWcFE8tg=\"}",
  ])
  assert_true(execution.close())
}
