///|
test "ordinary source-free Program installs REPLACE and LENGTH through the retained factory" {
  let (_, environment, limits) = local_effect_export_fixture()
  let document =
    #|{"version":"actql/0.1","id":"common-text-control","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"},{"derive":{"replaced":{"replace":[{"literal":"banana"},{"literal":"ana"},{"literal":"X"}]},"length":{"len":{"literal":"é😀"}}},"as":"derived"},{"select":["id","replaced","length"],"as":"out"}],"results":{"out":{"from":"out","fields":["id","replaced","length"]}}}],"results":{"answer":{"from":{"stage":"source","result":"out"}}}}
  let prepared = @publication_host.prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    limits.program,
  ).unwrap()
  let result = @client_local_host.open_source_free_local_retained_host(
    prepared,
    @identity.stringify_value(registered_body(), 100000, 10000, 100),
    @identity.stringify_value(registered_values(), 100000, 10000, 100),
    1L,
    0L,
    0L,
    0L,
    fragment_body=Some(
      @identity.stringify_value(registered_fragment(), 100000, 10000, 100),
    ),
    ordered_body=Some(
      @identity.stringify_value(registered_ordered(), 100000, 10000, 100),
    ),
  )
  let setup = match result {
    Some(setup) => setup
    None => fail("retained factory rejected Text call")
  }
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(setup),
  )
  assert_true(@strategy.captured_dag_strategy(run) is Some(_))
  assert_eq(@strategy.graph_task_count(@strategy.captured_dag_graph(run)), 1)
  assert_eq(
    @local_driver.local_dispatch_rejection(
      @builtin.configured_local_module(@builtin.configured_host_modules(setup)).unwrap(),
      0,
    ),
    None,
  )
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(
    (usage.attempts, usage.held_bytes, usage.reserved_execution_bytes),
    (0, 0L, 0L),
  )
}
