///|
test "Request compatible work code forwards only the same original Common issue" {
  let environment = keyed_source_environment()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"original-work-code","stages":[{"id":"s","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"},{"from":"seed","derive":{"next":"id + 1"},"as":"derived"}],"results":{"out":{"from":"derived","fields":["next"]}}}],"results":{"answer":{"from":{"stage":"s","result":"out"}}}}
  let (parent, receipt) = request_diagnostic_test_parent()
  client_program_prepare_request_native_computation(
    parent,
    receipt,
    request_diagnostic_test_json(document),
    request_diagnostic_test_json("null"),
    environment,
    publication,
    None,
  ).unwrap()
  assert_eq(
    client_program_finish_request_computation(
      parent, receipt, environment, publication,
    ).unwrap(),
    "effect_free",
  )
  let holder = client_program_borrow_request_program_plan_input(parent, receipt).unwrap()
  let prepared = client_program_preparation_borrow_read(holder).unwrap()
  let assets = @publication_host.client_local_product_assets()
  let contracts = @client_local_host.prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let foreign = client_program_prepare_request_program_module_body(
    parent,
    request_diagnostic_test_receipt(),
    contracts,
    false,
    None,
    Some(1),
  )
  assert_true(foreign is Err(Preparation(Preparation(ForeignOriginal))))
  assert_true(client_program_request_program_module_issue_code(foreign) is None)
  let original = client_program_prepare_request_program_module_body(
    parent,
    receipt,
    contracts,
    false,
    None,
    Some(1),
  )
  assert_true(
    original is Err(Preparation(Installed(RuntimeFragmentWorkLimit(1, 1)))),
  )
  assert_eq(
    client_program_request_program_module_issue_code(original),
    Some("ClientProgramRuntimeFragmentWorkLimit"),
  )
  assert_true(
    physical_equal(
      client_program_preparation_borrow_read(holder).unwrap(),
      prepared,
    ),
  )
  assert_true(client_program_request_program_module_issue_code(Ok(())) is None)
  assert_true(client_program_abort_request_preparation(parent) is Err(_))
  assert_true(client_program_preparation_borrow_retirement_started(holder))
  assert_true(client_program_preparation_borrow_return(holder).unwrap())
  client_program_abort_request_preparation(parent).unwrap()
}
