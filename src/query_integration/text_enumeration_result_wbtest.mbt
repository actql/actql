///|
test "original Values Text enum survives checked execution and retained Named Result schema" {
  // Existing in-memory Common compute fixture and explicit test resource
  // declaration; not a physical installation, Account grant or normal profile.
  let (_, environment, limits) = local_effect_export_fixture()
  let document =
    #|{"version":"actql/0.1","id":"text-enum-result","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"level":{"type":"string","nullable":false,"enum":["low","high","low"]}},"rows":[{"level":"low"},{"level":"high"}]},"as":"selected"}],"results":{"out":{"from":"selected","fields":["level"],"order_by":[{"level":"asc"}]}}}],"results":{"answer":{"from":{"stage":"source","result":"out"}}}}
  let prepared = @publication_host.prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    limits.program,
  ).unwrap()
  let setup = @client_local_host.open_source_free_local_retained_host(
    prepared,
    registered_installed_sequence_contracts(),
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
  ).unwrap()
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(setup),
  )
  let installed = @builtin.configured_local_module(
    @builtin.configured_host_modules(setup),
  ).unwrap()
  let available = Ref(true)
  let (operations, completed) = run_local_managed_test_task(
    installed,
    run,
    0,
    [],
    [],
    1,
    available,
  )
  assert_eq(local_managed_test_rows(operations), [
    "{\"level\":\"low\"}", "{\"level\":\"high\"}",
  ])
  assert_true(@strategy.captured_task_completed(run, 0))
  let value_limits : @execution.ValueLimits = {
    max_nodes: 1000,
    max_text_bytes: 10000,
    max_depth: 20,
    max_work: 10000,
  }
  let bridge = @execution.prepare_managed_publication_bridge(
    completed,
    (operations.material)().unwrap(),
    100,
    value_limits,
    100,
    10000,
  ).unwrap()
  for row in local_managed_test_rows(operations) {
    @execution.append_managed_publication_bridge_wire(bridge, row, {
      max_bytes: 100,
      max_nodes: 20,
      max_depth: 4,
      max_text_bytes: 100,
    }).unwrap()
  }
  let output = @execution.finish_managed_publication_bridge(bridge).unwrap()
  let transformation = @publication_host.prepare_client_result_transformation(
    prepared, 0, 100000, 10000, 100,
  ).unwrap()
  let export_limits : @publication_host.PublicationOutputExportLimits = {
    max_result_fields: 10,
    max_result_mapping_work: 100,
    max_result_order_work: 100,
    max_result_workspace_entries: 100,
    max_rows: 100,
    values: value_limits,
    payload_wire: row_wire_limits(),
    logical_wire: row_wire_limits(),
    schema: {
      max_fields: 10,
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 20,
    },
    max_batch_bytes: 64,
  }
  let preparation = @publication_host.start_client_result_transformation(
    transformation, output, export_limits,
  ).unwrap()
  let mut done = false
  for _ in 0..<10000 {
    let (complete, work) = preparation.advance(1).unwrap()
    assert_true(work <= 1)
    if complete {
      done = true
      break
    }
  }
  assert_true(done)
  let exported = preparation.finish().unwrap()
  let rows = StringBuilder()
  while exported.next().unwrap() is Some(chunk) {
    rows.write_string(chunk)
  }
  rows.write_string(exported.finish().unwrap())
  assert_eq(rows.to_string(), "[{\"level\":\"high\"},{\"level\":\"low\"}]")
  assert_eq(exported.result_fields().unwrap(), ["level"])
  let schema_wire = exported.result_schema_wire().unwrap()
  assert_eq(
    schema_wire, "{\"level\":{\"enum\":[\"low\",\"high\",\"low\"],\"nullable\":false,\"type\":\"string\"}}",
  )
  let schema_cid = exported.result_schema_cid().unwrap()
  assert_true(
    @publication.validate_result_schema_wire(
      schema_cid, schema_wire, 10000, 1000, 20,
    )
    is Ok(_),
  )
  assert_true(
    @publication.validate_result_schema_wire(
      schema_cid,
      schema_wire.replace(old="high", new="other"),
      10000,
      1000,
      20,
    )
    is Err(_),
  )
  exported.cancel()
  @execution.close_managed_publication_bridge(bridge)
  @strategy.close_captured_task_output(run, 0)
  available.val = false
  (operations.close)()
  (operations.cleanup_refresh)() |> ignore
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
}

///|
test "Values enum rejects nonmembers without replacing the original declared constraint" {
  let (_, environment, limits) = local_effect_export_fixture()
  let bad =
    #|{"version":"actql/0.1","id":"text-enum-refusal","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"level":{"type":"string","nullable":false,"enum":["low","high"]}},"rows":[{"level":"other"}]},"as":"selected"}],"results":{"out":{"from":"selected","fields":["level"]}}}],"results":{"answer":{"from":{"stage":"source","result":"out"}}}}
  assert_true(
    @publication_host.prepare_effect_free_client_program(
      bad,
      Json,
      environment,
      None,
      limits.program,
    )
    is Err(_),
  )
}
