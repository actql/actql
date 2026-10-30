///|
// Existing authored Mapping environment and actual ordinary Resource original.
// Operation extents and empty providers are explicit component DATA/ports, not
// a normal Host funding, permission, dispatch or physical-cleanup assertion.
fn request_effect_bridge_fixture() -> (
  @client_local_host.ClientRequestPreparation[
    ClientLocalPreparationInputOriginal,
  ],
  ClientLocalPreparationInputOriginal,
  @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientEffectComputation,
  ],
  @publication_host.PreparedClientEffectComputation,
  @client_local_host.ClientInstalledEffectManagedPlan,
  @publication_host.ClientRequestIdentity,
) raise {
  let environment = keyed_source_environment()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let (parent, receipt) = request_diagnostic_test_parent()
  let program = request_diagnostic_test_json(
    (
      #|{"version":"actql/0.1","id":"request-effect-bridge","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"name":{"type":"string","nullable":false}},"rows":[{"id":"one","name":"original"}]},"as":"seed"}],"results":{"rows":{"from":"seed","fields":["id","name"]}},"effects":{"save":{"update":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"rows"},"id":"id","set":{"Name":{"field":"name"}}}}}}],"results":{"rows":{"from":{"stage":"main","result":"rows"}}}}
    ),
  )
  assert_eq(
    client_program_prepare_request_native_computation(
      parent,
      receipt,
      program,
      request_diagnostic_test_json("null"),
      environment,
      publication,
      None,
    ).unwrap(),
    "effectful",
  )
  let holder = client_program_borrow_request_effect_plan_input(parent, receipt).unwrap()
  let prepared = client_program_effect_preparation_input_read(holder).unwrap()
  let request = @publication_host.prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "request-effect-bridge",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  let assets = @publication_host.client_local_product_assets()
  let contracts = @client_local_host.prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let extent = @client_local_host.prepare_installed_effect_operation_extent(
    "component-operation",
    @execution.execution_capacity(100L, 200L).unwrap(),
    17L,
    true,
  ).unwrap()
  let demand = @client_local_host.prepare_installed_effect_operation_demand(
    prepared,
    0,
    "save",
    [extent],
    [extent],
  ).unwrap()
  let plan = @client_local_host.prepare_installed_effect_managed_plan(
    prepared,
    request,
    [],
    "",
    "",
    [],
    [],
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    [demand],
    provider_factory=_ => [],
  ).unwrap()
  (parent, receipt, holder, prepared, plan, request)
}

///|
test "actual Request Effect bridge completes and adopts original Plan while existing input holder retains retirement" {
  let (parent, receipt, holder, prepared, plan, request) = request_effect_bridge_fixture()
  client_program_complete_request_effect_preparation(parent, receipt, plan).unwrap()
  assert_true(
    physical_equal(
      client_program_effect_preparation_input_read(holder).unwrap(),
      prepared,
    ),
  )
  let copied = @publication_host.prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "request-effect-bridge",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  assert_true(
    client_program_adopt_request_effect_preparation(parent, copied)
    is Err(ForeignOriginal),
  )
  let run = client_program_adopt_request_effect_preparation(parent, request).unwrap()
  assert_true(
    physical_equal(
      @client_local_host.installed_effect_managed_operation_plan(
        run, prepared, request,
      ).unwrap(),
      plan,
    ),
  )
  assert_true(
    @client_local_host.retire_installed_managed_run(run) is Err(CleanupPending),
  )
  assert_true(
    client_program_effect_preparation_input_retirement_started(holder),
  )
  assert_true(client_program_effect_preparation_input_return(holder).unwrap())
  @client_local_host.retire_installed_managed_run(run).unwrap()
  assert_true(client_program_effect_preparation_input_read(holder) is None)
}

///|
test "actual Request Effect bridge retains its original after foreign input and rejects repeated handoff" {
  let (parent, receipt, holder, prepared, plan, request) = request_effect_bridge_fixture()
  assert_true(
    client_program_adopt_request_effect_preparation(parent, request)
    is Err(ForeignOriginal),
  )
  let foreign = request_diagnostic_test_receipt()
  assert_true(
    client_program_complete_request_effect_preparation(parent, foreign, plan)
    is Err(ForeignOriginal),
  )
  assert_true(
    physical_equal(
      client_program_effect_preparation_input_read(holder).unwrap(),
      prepared,
    ),
  )
  client_program_complete_request_effect_preparation(parent, receipt, plan).unwrap()
  assert_true(
    client_program_complete_request_effect_preparation(parent, receipt, plan)
    is Err(WrongPhase),
  )
  let run = client_program_adopt_request_effect_preparation(parent, request).unwrap()
  assert_true(
    client_program_adopt_request_effect_preparation(parent, request)
    is Err(ForeignOriginal),
  )
  // Returning a borrow is not retirement of the still-live Run.
  assert_false(client_program_effect_preparation_input_return(holder).unwrap())
  assert_true(client_program_effect_preparation_input_read(holder) is None)
  @client_local_host.retire_installed_managed_run(run).unwrap()
}
