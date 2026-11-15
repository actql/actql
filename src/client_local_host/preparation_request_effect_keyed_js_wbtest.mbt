///|
// Actual Request check/compiler and declared-file Source profile. There is no
// Model node/provider or physical Source execution in this component fixture.
fn request_source_keyed_graph_fixture(
  generic? : Bool = false,
) -> (
  ClientRequestPreparation[Array[Int]],
  Array[Int],
  @publication_host.PreparedClientEffectComputation,
  @publication_host.ClientKeyedAcquisition,
  ClientInstalledSequenceContracts,
  @row_source_host.RowDeclaration,
) raise {
  let (unbound, wire) = original_keyed_declaration_environment(
    relation_versions=true,
  )
  let physical = @row_source_host.generate_row_declaration(
    "source-keyed-physical",
    "fixture",
    "fixture/0.1",
    [
      {
        resource: "records",
        resource_kind: "file",
        fields: ["id", "name", "version", "mime", "text"].map(name => @row_source_host.RowField::{
          name,
          value_type: "string",
          nullable: false,
        }),
      },
    ],
    {
      max_bytes: 65536,
      max_nodes: 4096,
      max_depth: 32,
      max_views: 1,
      max_fields: 10,
    },
  ).unwrap()
  let content = unbound.views.filter(view => view.resource == "contents")[0]
  let native_declaration = @row_source_host.bind_declared_file_read_profile(
    unbound,
    content.source_ref,
    physical,
    "records",
    {
      identity: "id",
      name: "name",
      version: "version",
      media_type: "mime",
      content_utf8: "text",
      path: None,
      items_path: ["items"],
      key_path: ["id"],
    },
  ).unwrap()
  let declaration = if generic { unbound } else { native_declaration }
  guard @json.parse(wire) is Object(fields) &&
    fields["host_policy_profile"] is Object(policy) else {
    fail("original keyed Source policy")
  }
  let (environment, _) = effect_model_plan_source(
    declaration=Some(declaration),
    lookup_policy=Some(policy["lookup_execution"]),
  )
  let document =
    #|{"version":"actql/0.1","id":"source-effect-request","stages":[{"id":"read","inputs":{"contents":{"connector":"content-fixture","resource":"contents"},"files":{"connector":"content-fixture","resource":"files"}},"steps":[{"from":"files","filter":"name IS NOT NULL","as":"matched"},{"from":"matched","select":["name","resource","version"],"as":"left"},{"from":"left","join":{"with":"contents","kind":"inner","on":[{"left":"resource","right":"resource"},{"left":"version","right":"version"}],"select":{"name":"left.name","content":"right.content"}},"as":"joined"},{"derive":{"id":{"literal":1}},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}},"effects":{"save":{"update":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"rows"},"id":"id","set":{"Name":{"field":"id"}}}}}}],"results":{"rows":{"from":{"stage":"read","result":"rows"}}}}
  let (parent, child, _, input) = registration_parent_fixture(
    text=document,
    environment=Some(environment),
    effect_limits=Some(
      @publication_host.client_standard_effect_computation_limits(),
    ),
  )
  finish_effect_program_check_preparation(child).unwrap() |> ignore
  let prepared = compile_effect_program_check_preparation(child).unwrap()
  assert_true(
    physical_equal(
      continue_request_effect_preparation(parent, input).unwrap(),
      prepared,
    ),
  )
  assert_true(
    @publication_host.prepared_client_effect_infer_occurrences(prepared)
    is Some([]),
  )
  let borrowed = borrow_request_effect_plan_input(parent, input).unwrap()
  @resources.return_preparation_body_borrow(borrowed).unwrap() |> ignore
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let keyed = @publication_host.select_client_effect_single_keyed_acquisition(
      prepared,
    )
    .unwrap()
    .unwrap()
  (parent, input, prepared, keyed, contracts, declaration)
}

///|
test "Source-only Effect Request retains its actual measured keyed graph without a Model" {
  let (parent, input, prepared, keyed, contracts, declaration) = request_source_keyed_graph_fixture()
  let before = @resources.preparation_capacity_working_extents(
    parent.effect_capacity.unwrap(),
    input,
  ).unwrap()
  let graph = prepare_request_effect_keyed_plan(
    parent,
    input,
    keyed,
    contracts,
    [declaration],
  ).unwrap()
  assert_true(
    @publication_host.client_effect_keyed_plan_graph_matches(
      graph, prepared, keyed,
    ),
  )
  assert_true(parent.phase == EffectPlanReserved)
  guard parent.program_domain_compilation_inputs
    is Some(RequestEffectKeyedGraph(p, k, c, g)) else {
    fail("same Request must retain the actual issued graph")
  }
  assert_true(
    physical_equal(p, prepared) &&
    physical_equal(k, keyed) &&
    physical_equal(c, contracts) &&
    physical_equal(g, graph),
  )
  let after = @resources.preparation_capacity_working_extents(
    parent.effect_capacity.unwrap(),
    input,
  ).unwrap()
  assert_true(after.0 > before.0 && after.1 > before.1)
  assert_true(
    prepare_request_effect_keyed_plan(parent, input, keyed, contracts, [
      declaration,
    ])
    is Err(_),
  )
  abort_request_preparation_after_cleanup(parent).unwrap() |> ignore
}

///|
test "Source-only Effect Request rejects a separately prepared keyed original before graph construction" {
  let (parent, input, _, _, contracts, declaration) = request_source_keyed_graph_fixture()
  let (other, _, _, keyed, _, _) = request_source_keyed_graph_fixture()
  let before = @resources.preparation_capacity_working_extents(
    parent.effect_capacity.unwrap(),
    input,
  ).unwrap()
  assert_true(
    prepare_request_effect_keyed_plan(parent, input, keyed, contracts, [
      declaration,
    ])
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(
    @resources.preparation_capacity_working_extents(
      parent.effect_capacity.unwrap(),
      input,
    ),
    Ok(before),
  )
  assert_true(parent.program_domain_compilation_inputs is None)
  abort_request_preparation_after_cleanup(parent).unwrap() |> ignore
  abort_request_preparation_after_cleanup(other).unwrap() |> ignore
}

///|
test "generic Source-only Effect Request uses actual content_ref facts without a Native profile" {
  let (parent, input, prepared, keyed, contracts, _) = request_source_keyed_graph_fixture(
    generic=true,
  )
  let before = @resources.preparation_capacity_working_extents(
    parent.effect_capacity.unwrap(),
    input,
  ).unwrap()
  let graph = prepare_request_effect_keyed_plan(
    parent,
    input,
    keyed,
    contracts,
    [],
  ).unwrap()
  assert_true(
    @publication_host.client_effect_keyed_plan_graph_is_generic(graph),
  )
  assert_true(
    @publication_host.client_effect_keyed_plan_graph_matches(
      graph, prepared, keyed,
    ),
  )
  guard parent.program_domain_compilation_inputs
    is Some(RequestEffectKeyedGraph(p, k, c, g)) else {
    fail("same Request retains actual generic construction")
  }
  assert_true(
    physical_equal(p, prepared) &&
    physical_equal(k, keyed) &&
    physical_equal(c, contracts) &&
    physical_equal(g, graph),
  )
  let after = @resources.preparation_capacity_working_extents(
    parent.effect_capacity.unwrap(),
    input,
  ).unwrap()
  assert_true(after.0 > before.0 && after.1 > before.1)
  assert_true(
    prepare_request_effect_keyed_plan(parent, input, keyed, contracts, [])
    is Err(_),
  )
  abort_request_preparation_after_cleanup(parent).unwrap() |> ignore
}

///|
test "generic Source-only Effect Request refuses a foreign acquisition before construction" {
  let (parent, input, _, _, contracts, _) = request_source_keyed_graph_fixture(
    generic=true,
  )
  let (other, _, _, foreign, _, _) = request_source_keyed_graph_fixture(
    generic=true,
  )
  let before = @resources.preparation_capacity_working_extents(
    parent.effect_capacity.unwrap(),
    input,
  ).unwrap()
  assert_true(
    prepare_request_effect_keyed_plan(parent, input, foreign, contracts, [])
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(
    @resources.preparation_capacity_working_extents(
      parent.effect_capacity.unwrap(),
      input,
    ),
    Ok(before),
  )
  assert_true(parent.program_domain_compilation_inputs is None)
  abort_request_preparation_after_cleanup(parent).unwrap() |> ignore
  abort_request_preparation_after_cleanup(other).unwrap() |> ignore
}

///|
// Actual Request, generic Graph, selected Plan and original compiled binding.
// Empty physical ports are explicit; this is not File/STORE IO acceptance.
fn request_generic_keyed_bound_parent_fixture() -> (
  ClientRequestPreparation[Array[Int]],
  ClientInstalledManagedRun,
  ClientInstalledEffectManagedPlan,
) raise {
  let (parent, input, prepared, keyed, contracts, declaration) = request_source_keyed_graph_fixture(
    generic=true,
  )
  let graph = prepare_request_effect_keyed_plan(
    parent,
    input,
    keyed,
    contracts,
    [],
  ).unwrap()
  let request = @publication_host.prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "keyed-parent-counter",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  let extent = prepare_installed_effect_operation_extent(
    "operation",
    @execution.execution_capacity(3L, 5L).unwrap(),
    7L,
    true,
  ).unwrap()
  let demand = prepare_installed_effect_operation_demand(
    prepared,
    0,
    "save",
    [extent],
    [extent],
  ).unwrap()
  let plan = prepare_installed_effect_managed_plan(
    prepared,
    request,
    [declaration],
    original_row_query_contract_fixture,
    original_row_evidence_contract_fixture,
    [65536L],
    [65536L],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    [demand],
    provider_factory=_ => [],
  ).unwrap()
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    100000,
    10000,
    100,
  ).unwrap()
  let compilation = @publication_host.issue_prepared_client_effect_compilation(
    prepared,
    manifests,
    @publication_host.client_standard_values_sequence_limits(),
    1000,
    10000,
    1000000,
    100000,
    100,
  ).unwrap()
  let allowed = @publication_host.issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "c".repeat(64),
    "sha256:" + "d".repeat(64),
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_effect_run_definition(
    allowed, "keyed-counter-scope", "keyed-counter-original", "2026-11-15T00:00:00.000Z",
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let compiled = @publication_host.client_effect_allowed_keyed_run(
    allowed, graph, definition,
  ).unwrap()
  let before = @resources.preparation_capacity_working_extents(
    parent.effect_capacity.unwrap(),
    input,
  ).unwrap()
  let limit = @resources.ledger_limits(parent.ledger)
  println(
    "keyed-binder-original-working-retention=" +
    before.0.to_string() +
    ",execution=" +
    before.1.to_string() +
    ",limit=" +
    limit.retained_bytes.to_string(),
  )
  let bound = prepare_request_effect_keyed_original(
    parent, input, plan, compilation, compiled, definition, graph, keyed,
  )
  match bound {
    Err(Preparation(@resources.Resource(issue))) =>
      fail("actual binder Resource " + @debug.to_string(issue))
    Err(_) => fail("actual binder original refused")
    Ok(_) => ()
  }
  complete_request_effect_preparation(parent, input, plan).unwrap() |> ignore
  let owner = begin_request_effect_managed_run(parent, request).unwrap()
  (parent, owner, plan)
}

///|
#cfg(target="js")
test "generic keyed Request binder keeps its original capacity through Plan adoption" {
  let (parent, owner, plan) = request_generic_keyed_bound_parent_fixture()
  let inventory = plan.keyed_inventory.unwrap()
  assert_eq(inventory.operation_children, 0)
  assert_true(inventory.holdings < plan.held_children)
  retire_installed_managed_run(owner).unwrap() |> ignore
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_execution_bytes, 0L)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
#cfg(target="js")
test "generic keyed actual census growth refuses low capacity without constructing an operation" {
  let (parent, owner, plan) = request_generic_keyed_bound_parent_fixture()
  let inventory = plan.keyed_inventory.unwrap()
  let counts = (inventory.reservations, inventory.holdings)
  let usage = @resources.ledger_usage(parent.ledger)
  let limits = @resources.ledger_limits(parent.ledger)
  // A real coheld pure reservation exhausts unchanged available retention.
  // No Host count, business row, permission or physical stop is supplied.
  let other = @resources.reserve_capacity(
    parent.ledger,
    limits.retained_bytes - usage.reserved_retention_bytes - usage.held_bytes,
    0L,
  ).unwrap()
  assert_true(
    grow_installed_effect_keyed_operation_inventory(owner, plan)
    is Err(Preparation(@resources.Resource(@resources.RetentionLimit))),
  )
  assert_eq(inventory.operation_children, 0)
  assert_eq((inventory.reservations, inventory.holdings), counts)
  assert_eq(owner.effect_operations.length(), 0)
  @resources.settle_capacity(parent.ledger, other).unwrap() |> ignore
  // The actual independent reservation has now returned: same inventory,
  // no new Root, replenished work or fabricated allocation acknowledgement.
  grow_installed_effect_keyed_operation_inventory(owner, plan).unwrap()
  |> ignore
  assert_eq(inventory.operation_children, 1)
  assert_eq(
    (inventory.reservations, inventory.holdings),
    (counts.0 + 1, counts.1 + 1),
  )
  assert_eq(owner.effect_operations.length(), 0)
  let retained = @resources.ledger_usage(parent.ledger).reserved_retention_bytes
  grow_installed_effect_keyed_operation_inventory(owner, plan).unwrap()
  |> ignore
  assert_eq(
    @resources.ledger_usage(parent.ledger).reserved_retention_bytes,
    retained,
  )
  retire_installed_managed_run(owner).unwrap() |> ignore
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
