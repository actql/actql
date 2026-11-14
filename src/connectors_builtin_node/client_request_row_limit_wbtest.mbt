///|
fn request_row_limit_fixture(
  rows : Int,
  max_rows : Int,
) -> (
  @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  ClientLocalPreparationInputOriginal,
  @resources.PreparationBodyBorrow[@publication_host.PreparedClientProgram],
  @publication_host.PreparedClientProgram,
) raise {
  let environment = keyed_source_environment()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let values = Array::makei(rows, n => "{\"id\":" + n.to_string() + "}").join(
    ",",
  )
  let document = "{\"version\":\"actql/0.1\",\"id\":\"selected-row-limit\",\"stages\":[{\"id\":\"s\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[" +
    values +
    "]},\"as\":\"v\"}],\"results\":{\"rows\":{\"from\":\"v\",\"fields\":[\"id\"]}}}],\"results\":{\"rows\":{\"from\":{\"stage\":\"s\",\"result\":\"rows\"}}}}"
  let (parent, receipt) = request_diagnostic_test_parent()
  client_program_prepare_request_native_computation(
    parent,
    receipt,
    request_diagnostic_test_json(document),
    request_diagnostic_test_json("null"),
    environment,
    publication,
    Some(max_rows),
  ).unwrap()
  assert_eq(
    client_program_finish_request_computation(
      parent, receipt, environment, publication,
    ).unwrap(),
    "effect_free",
  )
  let holder = client_program_borrow_request_program_plan_input(parent, receipt).unwrap()
  let prepared = client_program_preparation_borrow_read(holder).unwrap()
  assert_eq(client_program_values_max_rows(prepared), max_rows)
  let limits = @publication_host.prepared_client_values_sequence_limits(
    prepared,
  )
  assert_eq(
    limits.max_cells,
    @publication_host.client_standard_values_sequence_limits().max_cells,
  )
  (parent, receipt, holder, prepared)
}

///|
test "first Request Values ceiling stays on the same compiler original and actual Plan Run" {
  let (parent, receipt, holder, prepared) = request_row_limit_fixture(2, 2)
  let assets = @publication_host.client_local_product_assets()
  let contracts = @client_local_host.prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  client_program_prepare_request_program_module_body(
    parent,
    receipt,
    contracts,
    false,
    None,
    None,
  ).unwrap()
  assert_true(
    physical_equal(
      client_program_preparation_borrow_read(holder).unwrap(),
      prepared,
    ),
  )
  assert_eq(client_program_values_max_rows(prepared), 2)
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "first-request-row-limit",
  ).unwrap()
  let run = client_program_adopt_request_program_preparation(parent, request).unwrap()
  assert_true(client_program_preparation_borrow_return(holder) is Ok(false))
  @client_local_host.retire_installed_managed_run(run).unwrap()
}

///|
test "selected Request one-row-short ceiling retains original typed Plan refusal and cleanup" {
  let (parent, receipt, holder, prepared) = request_row_limit_fixture(3, 2)
  let assets = @publication_host.client_local_product_assets()
  let contracts = @client_local_host.prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let refusal = client_program_prepare_request_program_module_body(
    parent,
    receipt,
    contracts,
    false,
    None,
    None,
  )
  assert_true(
    refusal
    is Err(Preparation(Installed(Sequence(ValuesFailure(0, ValuesLimit))))),
  )
  assert_eq(
    client_program_request_program_module_issue_code(refusal),
    Some("values_profile_unsupported"),
  )
  assert_true(
    physical_equal(
      client_program_preparation_borrow_read(holder).unwrap(),
      prepared,
    ),
  )
  assert_eq(client_program_values_max_rows(prepared), 2)
  assert_true(client_program_abort_request_preparation(parent) is Err(_))
  assert_true(client_program_preparation_borrow_retirement_started(holder))
  assert_true(client_program_preparation_borrow_return(holder).unwrap())
  client_program_abort_request_preparation(parent).unwrap()
}

///|
test "module limit projection keeps actual foreign and retiring preparation failures uncertain" {
  let (parent, receipt, holder, _) = request_row_limit_fixture(2, 2)
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
    None,
  )
  assert_true(foreign is Err(Preparation(Preparation(ForeignOriginal))))
  assert_eq(client_program_request_program_module_issue_code(foreign), None)
  let success = client_program_prepare_request_program_module_body(
    parent,
    receipt,
    contracts,
    false,
    None,
    None,
  )
  assert_true(success is Ok(_))
  assert_eq(client_program_request_program_module_issue_code(success), None)
  assert_true(client_program_abort_request_preparation(parent) is Err(_))
  let retiring = client_program_prepare_request_program_module_body(
    parent,
    receipt,
    contracts,
    false,
    None,
    None,
  )
  assert_true(retiring is Err(Preparation(Preparation(WrongPhase))))
  assert_eq(client_program_request_program_module_issue_code(retiring), None)
  assert_true(client_program_preparation_borrow_retirement_started(holder))
  assert_true(client_program_preparation_borrow_return(holder).unwrap())
  client_program_abort_request_preparation(parent).unwrap()
}

///|
test "large Source actual Node module keeps its original Request codec and provider factory" {
  let document = "SELECT [" + "0,".repeat(19999) + "0] AS cells"
  let environment = keyed_source_environment()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let receipt = request_diagnostic_test_receipt()
  let policy = client_local_resource_policy_original()
  let original = request_diagnostic_test_original(
    request_diagnostic_test_loader(request_diagnostic_test_url()),
    receipt,
    client_local_preparation_resource_limits(
      policy,
      Some(1073741824L),
      Some(1073741824L),
    ),
  )
  let initial = client_program_prepare_local_preparation_admission(
    original, receipt,
  ).unwrap()
  let parent = client_program_begin_request_preparation(
    initial, receipt, policy,
  ).unwrap()
  client_program_reserve_request_snapshot(
    parent,
    receipt,
    document.length().to_int64() + 32L,
    document.length().to_int64() + 32L,
  ).unwrap()
  client_program_prepare_request_source_computation(
    parent,
    receipt,
    request_diagnostic_test_json(
      "{\"format\":\"sql\",\"text\":\"" + document + "\"}",
    ),
    request_diagnostic_test_json("null"),
    environment,
    publication,
    Some(
      client_local_resource_policy_row_ceiling(
        policy,
        Some(1073741824L),
        Some(1073741824L),
      ),
    ),
  ).unwrap()
  assert_eq(
    client_program_finish_request_computation(
      parent, receipt, environment, publication,
    ).unwrap(),
    "effect_free",
  )
  let holder = client_program_borrow_request_program_plan_input(parent, receipt).unwrap()
  let prepared = client_program_preparation_borrow_read(holder).unwrap()
  let before = @client_local_host.request_preparation_work_calls(parent)
  assert_eq(before, (1L, 1L, 1L, 1L))
  let assets = @publication_host.client_local_product_assets()
  let contracts = @client_local_host.prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  client_program_prepare_request_program_module_body(
    parent,
    receipt,
    contracts,
    false,
    None,
    Some(30000000),
  ).unwrap()
  assert_true(
    physical_equal(
      client_program_preparation_borrow_read(holder).unwrap(),
      prepared,
    ),
  )
  assert_eq(@client_local_host.request_preparation_work_calls(parent), before)
  assert_true(client_program_preparation_borrow_return(holder) is Ok(false))
  @client_local_host.abort_request_preparation_after_cleanup(parent).unwrap()
}
