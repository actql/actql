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
  client_program_prepare_request_native_computation(
    parent,
    receipt,
    program,
    request_diagnostic_test_json("null"),
    environment,
    publication,
    None,
  ).unwrap()
  assert_eq(
    client_program_finish_request_computation(
      parent, receipt, environment, publication,
    ).unwrap(),
    "effectful",
  )
  let holder = client_program_borrow_request_effect_plan_input(
    parent, receipt, false,
  ).unwrap()
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
test "checked static Effect Explanation bridge reads the original Request and its three wires" {
  let (parent, receipt, holder, prepared, _, _) = request_effect_bridge_fixture()
  let foreign = request_diagnostic_test_receipt()
  assert_true(
    client_program_read_request_checked_static_effect_explanation(
      parent,
      foreign,
      65536,
      8192,
      64,
      10000,
      [],
      false,
    )
    is Err(Projection(Preparation(ForeignOriginal))),
  )
  {
    let projection = client_program_read_request_checked_static_effect_explanation(
      parent,
      receipt,
      65536,
      8192,
      64,
      10000,
      [],
      true,
    ).unwrap()
    let parse = (name, wire) => {
      @publication.parse_interactive_run_control_shape(
        name, wire, 65536, 8192, 64,
      ).unwrap()
    }
    let plan = parse(
      "effectful_static_plan_view",
      client_program_static_effect_explanation_plan_wire(projection),
    )
    let facts = parse(
      "explanation_facts",
      client_program_static_effect_explanation_facts_wire(projection),
    )
    let context = parse(
      "explanation_context",
      client_program_static_effect_explanation_context_wire(projection),
    )
    let view = @identity.object_field(
      @identity.object_field(plan, "computation").unwrap(),
      "plan_view",
    ).unwrap()
    let map = @identity.object_field(view, "logical_map").unwrap()
    let binding = @identity.object_field(context, "binding").unwrap()
    guard @identity.object_field(view, "compiled_plan_cid")
      is Some(@identity.String(plan_cid)) &&
      @identity.object_field(map, "self_cid") is Some(@identity.String(map_cid)) else {
      fail("an original Plan and Map must be present")
    }
    for facet in [facts, binding] {
      assert_true(
        @identity.object_field(facet, "compiled_plan_cid")
        is Some(@identity.String(value)) &&
        value == plan_cid,
      )
      assert_true(
        @identity.object_field(facet, "logical_map_cid")
        is Some(@identity.String(value)) &&
        value == map_cid,
      )
    }
    assert_true(
      @identity.object_field(plan, "provider_io") is Some(@identity.Number(0.0)),
    )
    assert_true(
      physical_equal(
        client_program_effect_preparation_input_read(holder).unwrap(),
        prepared,
      ),
    )
  }
  assert_false(client_program_effect_preparation_input_return(holder).unwrap())
  client_program_abort_request_preparation(parent).unwrap()
  assert_true(client_program_effect_preparation_input_read(holder) is None)
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
