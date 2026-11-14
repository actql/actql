///|
// Actual typed bridge and original Request/module handoff. Existing bounded
// fixture ports are explicit; this is not ordinary Host or physical funding.
test "pre-module QueryTime bridge forwards its original Option into the same Request module" {
  let environment = keyed_source_environment()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"bridge-clock","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"},{"derive":{"stamp":"current_timestamp()"},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","stamp"]}}}],"results":{"rows":{"from":{"stage":"main","result":"rows"}}}}
  let (parent, input) = request_diagnostic_test_parent()
  assert_eq(
    client_program_prepare_request_native_computation(
      parent,
      input,
      request_diagnostic_test_json(document),
      request_diagnostic_test_json("null"),
      environment,
      publication,
      None,
    ).unwrap(),
    (),
  )
  assert_eq(
    client_program_finish_request_computation(
      parent, input, environment, publication,
    ).unwrap(),
    "effect_free",
  )
  let held = client_program_borrow_request_program_plan_input(parent, input).unwrap()
  let prepared = client_program_preparation_borrow_read(held).unwrap()
  assert_true(
    client_program_requires_query_time(prepared, 100000, 10000).unwrap(),
  )
  let assets = @publication_host.client_local_product_assets()
  let contracts = @client_local_host.prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let artifact = client_program_prepare_request_program_compilation(
    parent, input, contracts, true,
  ).unwrap()
  let compiled = match artifact {
    Values(_) =>
      client_program_issue_original_values_compiled_run(
        prepared,
        artifact,
        "sha256:" + "a".repeat(64),
        "sha256:" + "b".repeat(64),
        "2027-01-01T00:00:00.000Z",
      ).unwrap()
    Tasks(_) =>
      client_program_issue_original_task_compiled_run(
        prepared,
        artifact,
        "sha256:" + "a".repeat(64),
        "sha256:" + "b".repeat(64),
        "2027-01-01T00:00:00.000Z",
      ).unwrap()
    _ => fail("Pure compilation required")
  }
  let definition = client_program_issue_compiled_run_definition(
    compiled, "query-time-bridge", "original", "2026-10-31T00:00:00.000Z", "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "query-time-bridge",
  ).unwrap()
  let time = client_program_prepare_query_time(
    prepared, request, "2026-10-31T00:00:00.000Z",
  ).unwrap()
  assert_true(
    client_program_query_time_invocation_original(time, prepared) is None,
  )
  client_program_bind_query_time(time, prepared, compiled, definition, request).unwrap()
  |> ignore
  let invocation = client_program_query_time_invocation_original(time, prepared)
  assert_true(invocation is Some(_))
  // Pass the bridge result itself, with no constructed Option or tuple.
  client_program_prepare_request_program_module_body(
    parent,
    input,
    contracts,
    true,
    invocation,
    None,
  ).unwrap()
  let run = client_program_adopt_request_program_preparation(parent, request).unwrap()
  let adopted = client_program_installed_managed_run_invocation_original(
    run, prepared,
  ).unwrap()
  assert_true(physical_equal(adopted.0, time))
  assert_true(physical_equal(adopted.1, request))
  assert_true(physical_equal(adopted.2, compiled))
  assert_true(physical_equal(adopted.3, definition))
  assert_true(client_program_preparation_borrow_return(held) is Ok(false))
  @client_local_host.retire_installed_managed_run(run).unwrap()
}
