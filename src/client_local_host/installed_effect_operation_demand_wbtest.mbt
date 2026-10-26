///|
fn effect_plan_fixture_members(
  original : Json,
  additions : Array[String],
) -> Json raise {
  guard original is Array(bodies) else { fail("fixture evidence members") }
  let wires = additions.copy()
  for body in bodies {
    let wire = @identity.stringify_value(
      @identity.from_json(body, 100000, 100, 1000000),
      1000000,
      100000,
      100,
    )
    if !wires.contains(wire) {
      wires.push(wire)
    }
  }
  original_keyed_environment_members(wires)
}

///|
fn effect_plan_fixture_failure(
  cause : @checked.LocalConstructionFailure,
) -> String {
  match cause {
    InvalidLimits => "InvalidLimits"
    Program(_) => "Program"
    CapacityInputs(_) => "CapacityInputs"
    Environment(issue) =>
      match issue {
        BudgetExceeded => "Environment.BudgetExceeded"
        Registry(_) => "Environment.Registry"
        Catalog(_) => "Environment.Catalog"
        References(_) => "Environment.References"
        Policies(_) => "Environment.Policies"
        Values(_) => "Environment.Values"
        Shapes(_) => "Environment.Shapes"
        Modes(_) => "Environment.Modes"
        Carriers(_) => "Environment.Carriers"
        Requests(_) => "Environment.Requests"
        ForeignPreparedCatalog => "Environment.ForeignPreparedCatalog"
      }
    Source(issue) =>
      match issue {
        DeclarationWorkLimit => "Source.DeclarationWorkLimit"
        CapacityMetadataBudget => "Source.CapacityMetadataBudget"
        UnsupportedBindings(_) => "Source.UnsupportedBindings"
        UnsupportedEffects(_) => "Source.UnsupportedEffects"
        Requests(_) => "Source.Requests"
        RequestForm(_) => "Source.RequestForm"
        Checks(_) => "Source.Checks"
        Identity(_) => "Source.Identity"
        Declarations(_) => "Source.Declarations"
        Registration(_) => "Source.Registration"
        SourceView(_) => "Source.SourceView"
      }
    Closure(_) => "Closure"
    Units(_) => "Units"
    Template(_, _) => "Template"
  }
}

///|
// Checked authored Effect Program and immutable implementation DATA only.
// No physical dispatcher, permission, Resource root or ordinary package here.
fn effect_operation_plan_inputs() -> (
  @publication_host.PreparedClientEffectComputation,
  @publication_host.ClientRequestIdentity,
  ClientInstalledSequenceContracts,
) {
  let prepared = installed_effect_managed_fixture()
  let request = @publication_host.prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "effect-operation-plan",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  (prepared, request, contracts)
}

///|
fn effect_operation_plan_fixture(
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  contracts : ClientInstalledSequenceContracts,
  query_time? : @publication_host.ClientQueryTimePreparation? = None,
) -> ClientInstalledEffectManagedPlan {
  let metadata = prepare_installed_effect_operation_extent(
    "operation",
    @execution.execution_capacity(100L, 200L).unwrap(),
    17L,
    true,
  ).unwrap()
  let send = prepare_installed_effect_operation_extent(
    "operation",
    @execution.execution_capacity(300L, 500L).unwrap(),
    13L,
    true,
  ).unwrap()
  let capture = prepare_installed_effect_operation_extent(
    "operation",
    @execution.execution_capacity(50L, 70L).unwrap(),
    0L,
    false,
  ).unwrap()
  let demand = prepare_installed_effect_operation_demand(
    prepared,
    0,
    "save",
    [metadata],
    [send, send, capture],
  ).unwrap()
  prepare_installed_effect_managed_plan(
    prepared,
    request,
    [],
    "",
    "",
    [],
    [],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    [demand],
    query_time~,
  ).unwrap()
}

///|
// Authored primitive Source and checked Effect closure. Declaration/Environment
// generation supplies only fixture inputs; no Source/physical observation is
// generated, and expected identities/rows are not taken from execution output.
fn effect_operation_source_plan_fixture(
  provider? : @execution.ExecutionCapacity? = None,
  query_time_for? : ((
    @publication_host.PreparedClientEffectComputation,
    @publication_host.ClientRequestIdentity,
  ) -> @publication_host.ClientQueryTimePreparation)? = None,
) -> ClientInstalledEffectManagedPlan raise {
  let declaration = @row_source_host.generate_row_declaration(
    "operation-source",
    "fixture",
    "fixture/0.1",
    [
      {
        resource: "r",
        resource_kind: "record",
        fields: [{ name: "id", value_type: "number", nullable: false, }],
      },
    ],
    {
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 100,
      max_views: 1,
      max_fields: 1,
    },
  ).unwrap()
  let parsed = @json.parse(source_query_original_environment)
  guard parsed is Object(base) else { fail("fixture Environment object") }
  base.remove("evidence_bundle_cid")
  let (schemas, capabilities) = @row_source_host.row_declaration_evidence_members(
    declaration,
  )
  base["connector_catalogs"] = effect_plan_fixture_members(
    base["connector_catalogs"],
    [declaration.catalog],
  )
  base["contract_registry"] = effect_plan_fixture_members(
    base["contract_registry"],
    declaration.contracts,
  )
  base["source_views"] = effect_plan_fixture_members(
    base["source_views"],
    declaration.view_bodies,
  )
  base["schema_snapshots"] = effect_plan_fixture_members(
    base["schema_snapshots"],
    schemas,
  )
  base["connector_capabilities"] = effect_plan_fixture_members(
    base["connector_capabilities"],
    capabilities,
  )
  guard base["connector_manifest"] is Object(manifest) &&
    manifest["connectors"] is Array(connectors) else {
    fail("fixture connector manifest")
  }
  manifest["connectors"] = effect_plan_fixture_members(manifest["connectors"], [
    declaration.manifest_entry,
  ])
  let wire = @identity.stringify_value(
    @identity.from_json(parsed, 100000, 100, 1000000),
    1000000,
    100000,
    100,
  )
  let evidence = "sha256:" + @sha.hex(@utf8.encode(wire))
  base["evidence_bundle_cid"] = @json.parse("\"" + evidence + "\"")
  let environment_wire = @identity.stringify_value(
    @identity.from_json(parsed, 100000, 100, 1000000),
    1000000,
    100000,
    100,
  )
  let environment = @publication_host.admit_client_check_environment(
    environment_wire,
    evidence,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"source-effect-operation-plan","stages":[{"id":"acquire","inputs":{"remote":{"connector":"operation-source","resource":"r"}},"steps":[{"filter":"id > 0"},{"select":["id"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id"]}}},{"id":"apply","inputs":{"input":{"result":{"stage":"acquire","result":"rows"}}},"steps":[{"filter":"id > 2","as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}},"effects":{"save":{"update":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"rows"},"id":"id","set":{"Name":{"field":"id"}}}}}}],"results":{"rows":{"from":{"stage":"apply","result":"rows"}}}}
  let document = if query_time_for is Some(_) {
    document.replace(
      old="id > 0",
      new="current_timestamp() = current_timestamp()",
    )
  } else {
    document
  }
  let prepared = match
    @publication_host.prepare_client_effect_computation(
      document,
      Json,
      environment,
      None,
      [],
      @publication_host.client_standard_effect_computation_limits(),
    ) {
    Ok(value) => value
    Err(Syntax(_)) => fail("fixture Source Effect Syntax")
    Err(Candidate(@checked.Computation(cause))) =>
      fail(
        "fixture Source Effect Computation: " +
        effect_plan_fixture_failure(cause),
      )
    Err(Candidate(@checked.Headers(issue))) =>
      fail("fixture Source Effect Headers")
    Err(Candidate(_)) => fail("fixture Source Effect Candidate")
    Err(Mapping(_)) => fail("fixture Source Effect Mapping")
    Err(Static(_)) => fail("fixture Source Effect Static")
    Err(Stage(_)) => fail("fixture Source Effect Stage")
    Err(Graph(_)) => fail("fixture Source Effect Graph")
    Err(TargetSelection(_)) => fail("fixture Source Effect TargetSelection")
  }
  let request = @publication_host.prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "source-effect-operation-plan",
    if query_time_for is Some(_) {
      @publication_host.source_free_caller_input_intent_cid()
    } else {
      "sha256:" + "b".repeat(64)
    },
  ).unwrap()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let extent = prepare_installed_effect_operation_extent(
    "operation",
    @execution.execution_capacity(3L, 5L).unwrap(),
    7L,
    true,
  ).unwrap()
  let demand = prepare_installed_effect_operation_demand(
    prepared,
    1,
    "save",
    [extent],
    [extent],
  ).unwrap()
  prepare_installed_effect_managed_plan(
    prepared,
    request,
    [declaration],
    original_row_query_contract_fixture,
    original_row_evidence_contract_fixture,
    [1024L],
    [2048L],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    [demand],
    query_time=query_time_for.map(make => make(prepared, request)),
    source_providers=provider.map(value => [value]),
  ).unwrap()
}

///|
// Existing compilation, Allow DATA and original definition issue/binding.
// No clock, Journal, Account, physical provider or second Run owner.
fn effect_operation_time_run(
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  created : String,
) -> (
  @publication_host.PreparedClientEffectRun,
  @publication_host.ClientQueryTimePreparation,
) {
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    100000,
    10000,
    100,
  ).unwrap()
  let compiled = @publication_host.issue_prepared_client_effect_compilation(
    prepared,
    manifests,
    @publication_host.client_standard_values_sequence_limits(),
    1000,
    10000,
    1000000,
    100000,
    100,
  ).unwrap()
  let time = @publication_host.prepare_client_effect_query_time(
    prepared, request, created,
  ).unwrap()
  let allowed = @publication_host.issue_client_effect_allowed_run(
    compiled,
    "sha256:" + "c".repeat(64),
    "sha256:" + "d".repeat(64),
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_effect_run_definition(
    allowed, "scope", "effect-query-time", created, "2027-01-01T00:00:00.000Z",
  ).unwrap()
  @publication_host.bind_client_effect_query_evaluation_time(
    time, prepared, allowed, definition, request,
  ).unwrap()
  |> ignore
  (
    @publication_host.bind_client_effect_compiled_run(
      prepared, allowed, definition,
    ).unwrap(),
    time,
  )
}

///|
test "temporal Effect plan quotes original Source requirement and retained contexts from the same invocation" {
  let plan = effect_operation_source_plan_fixture(
    query_time_for=Some((prepared, request) => {
      let (_, original) = effect_operation_time_run(
        prepared, request, "2026-10-25T01:02:03.123Z",
      )
      original
    }),
  )
  guard plan.query_time is Some(original) &&
    @publication_host.client_query_time_preparation_context(original)
    is Some(context) else {
    fail("same admitted invocation must remain in the plan")
  }
  for sequence in plan.sequences {
    assert_true(
      @execution.generated_sequence_query_time(sequence) is Some(value) &&
      physical_equal(value, context),
    )
  }
  let (declaration, requirement, acquisition, capacity) = prepared_installed_effect_managed_source(
    plan, 0,
  ).unwrap()
  @row_source_host.check_row_acquisition_original(
    acquisition, declaration, requirement,
  ).unwrap()
  assert_true(physical_equal(requirement, capacity.requirement))
  let wire = @encode.document_text(
    @planning.query_requirement_document(requirement),
  )
  let definition = @publication.query_evaluation_time_definition(context)
  assert_true(
    wire.contains(
      "\"run_definition_cid\":\"" +
      @publication.publication_contract_identity(definition) +
      "\"",
    ),
  )
  assert_true(plan.capacity_plan.demand_inventory is Some(_))
  assert_eq(plan.capacity_plan.graph_offset, 1)
}

///|
test "selected Effect operations add actual occurrence demand to the same Compute quote" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  assert_eq(plan.rows, 1)
  assert_eq(plan.limits.attempts - plan.compute_limits.attempts, 3)
  assert_eq(
    plan.limits.transfer_bytes - plan.compute_limits.transfer_bytes,
    43L,
  )
  // Equal send-extent references at two occurrences remain two holdings/uses.
  assert_eq(prepared_installed_effect_managed_capture_children(plan), 4)
  assert_true(
    plan.limits.retained_bytes >= plan.compute_limits.retained_bytes + 750L,
  )
  assert_true(
    plan.limits.execution_bytes >= plan.compute_limits.execution_bytes + 1270L,
  )
  assert_true(
    physical_equal(plan.source_free.unwrap().sequences, plan.sequences),
  )
  let first = prepared_installed_effect_managed_operation(
    plan, 0, true, 0, "operation",
  ).unwrap()
  let second = prepared_installed_effect_managed_operation(
    plan, 0, true, 1, "operation",
  ).unwrap()
  assert_true(physical_equal(first, second))
  assert_true(installed_effect_operation_extent_physical(first))
  assert_false(
    installed_effect_operation_extent_physical(
      prepared_installed_effect_managed_operation(plan, 0, true, 2, "operation").unwrap(),
    ),
  )
  assert_true(
    prepared_installed_effect_managed_operation(plan, 1, true, 0, "operation")
    is Err(ForeignOriginal),
  )
  assert_true(
    prepared_installed_effect_managed_source(plan, 0) is Err(Unsupported),
  )
  assert_true(
    prepared_installed_effect_managed_operation(plan, 0, true, 0, "foreign")
    is Err(ForeignOriginal),
  )
}

///|
test "Effect plan snapshots selected arrays and never treats returned quote DATA as its original" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let extent = prepare_installed_effect_operation_extent(
    "operation",
    @execution.execution_capacity(3L, 5L).unwrap(),
    7L,
    true,
  ).unwrap()
  let extents = [extent]
  let demand = prepare_installed_effect_operation_demand(
    prepared,
    0,
    "save",
    extents,
    [],
  ).unwrap()
  extents.clear()
  let demands = [demand]
  let plan = prepare_installed_effect_managed_plan(
    prepared,
    request,
    [],
    "",
    "",
    [],
    [],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    demands,
  ).unwrap()
  demands.clear()
  let quote = prepared_installed_effect_managed_requirements(plan)
  let original = quote.copy()
  quote.fill(0L)
  assert_eq(prepared_installed_effect_managed_requirements(plan), original)
  assert_eq(plan.operations.length(), 1)
  assert_eq(prepared_installed_effect_managed_capture_children(plan), 1)
}

///|
test "Effect operation demand preserves exact checked member and request binding" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let other = installed_effect_managed_fixture()
  let extent = prepare_installed_effect_operation_extent(
    "operation",
    @execution.execution_capacity(0L, 0L).unwrap(),
    0L,
    false,
  ).unwrap()
  assert_true(
    prepare_installed_effect_operation_demand(prepared, 1, "save", [extent], [])
    is Err(ForeignOriginal),
  )
  assert_true(
    prepare_installed_effect_operation_demand(
      prepared,
      0,
      "foreign",
      [extent],
      [],
    )
    is Err(ForeignOriginal),
  )
  let foreign = prepare_installed_effect_operation_demand(
    other,
    0,
    "save",
    [extent],
    [],
  ).unwrap()
  assert_true(
    prepare_installed_effect_managed_plan(
      prepared,
      request,
      [],
      "",
      "",
      [],
      [],
      contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
      [foreign],
    )
    is Err(ForeignOriginal),
  )
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  assert_false(installed_effect_plan_matches(plan, other, request))
  let reconstructed = @publication_host.prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "effect-operation-plan",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  assert_true(request == reconstructed)
  assert_false(installed_effect_plan_matches(plan, prepared, reconstructed))
}

///|
test "Effect demand refuses invalid and overflowing extents without raising a bound" {
  let capacity = @execution.execution_capacity(0L, 0L).unwrap()
  assert_true(
    prepare_installed_effect_operation_extent("operation", capacity, -1L, true)
    is Err(Unsupported),
  )
  assert_true(
    prepare_installed_effect_operation_extent("operation", capacity, 1L, false)
    is Err(Unsupported),
  )
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let huge = prepare_installed_effect_operation_extent(
    "operation",
    @execution.execution_capacity(9223372036854775807L, 9223372036854775807L).unwrap(),
    0L,
    true,
  ).unwrap()
  let demand = prepare_installed_effect_operation_demand(
    prepared,
    0,
    "save",
    [huge],
    [],
  ).unwrap()
  assert_true(
    prepare_installed_effect_managed_plan(
      prepared,
      request,
      [],
      "",
      "",
      [],
      [],
      contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
      [demand],
    )
    is Err(Unsupported),
  )
  assert_eq(
    installed_effect_add_extent(9223372036854775807L, 1L, 0L),
    Some(9223372036854775807L),
  )
}

///|
test "failed schema proof records actual small work arrays instead of padding its work budget" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  let workspace : ClientLocalSchemaProofWorkspace = {
    owners: 0,
    rows: 0,
    input_rows: 0,
    row_bounds: 0,
  }
  assert_true(
    client_local_schema_proof_inventory(
      plan.sequences,
      max_work=1,
      graph=Some(installed_managed_owner_graph(Effect(prepared))),
      scalar_only=false,
      workspace=Some(workspace),
    )
    is None,
  )
  assert_eq(workspace.owners, 1)
  assert_true(workspace.rows <= 1)
  assert_eq(workspace.input_rows, 0)
  assert_true(workspace.row_bounds <= workspace.rows)
}

///|
test "Source Effect plan retains original declaration requirement acquisition capacity and generated inventory" {
  let plan = effect_operation_source_plan_fixture()
  assert_true(plan.source_free is None)
  let (declaration, requirement, acquisition, capacity) = prepared_installed_effect_managed_source(
    plan, 0,
  ).unwrap()
  assert_true(physical_equal(declaration, plan.declarations[0]))
  assert_true(physical_equal(requirement, capacity.requirement))
  assert_true(physical_equal(acquisition, plan.acquisitions[0]))
  assert_true(physical_equal(capacity, plan.captures[0]))
  assert_true(
    @publication_host.client_query_requirement_matches_effect_program(
      plan.prepared,
      0,
      0,
      requirement,
    ),
  )
  assert_eq(
    plan.sequences.length(),
    @strategy.graph_task_count(
      installed_managed_owner_graph(Effect(plan.prepared)),
    ),
  )
  assert_true(plan.limits.attempts > plan.compute_limits.attempts)
}

///|
test "Source Effect tail keeps checked input schema and exact graph offset in its retained configuration" {
  let plan = effect_operation_source_plan_fixture()
  let graph = installed_managed_owner_graph(Effect(plan.prepared))
  assert_eq(plan.capacity_plan.graph_offset, 1)
  guard plan.capacity_plan.demand_inventory is Some(inventory) else {
    fail("known Source-input schema must retain its inventory")
  }
  assert_eq(inventory.fields, 1)
  assert_true(inventory.ports > 0)
  assert_true(inventory.closed_rows is None)
  assert_eq(plan.capacity_plan.imports.wire.max_columns, 1)
  assert_eq(plan.capacity_plan.exports.wire.max_columns, 1)
  assert_true(
    client_local_capacity_plan_matches(
      plan.capacity_plan,
      plan.compute_sequences,
      plan.capacity_plan.admitted_rows,
    ),
  )
  assert_true(
    client_local_schema_proof_inventory(
      plan.compute_sequences,
      graph=Some(graph),
      graph_offset=0,
      scalar_only=false,
    )
    is None,
  )
  let wrong_offset = { ..plan.capacity_plan, graph_offset: 0, }
  assert_false(
    client_local_capacity_plan_matches(
      wrong_offset,
      plan.compute_sequences,
      wrong_offset.admitted_rows,
    ),
  )
  let foreign = effect_operation_source_plan_fixture()
  assert_true(
    client_local_schema_proof_inventory(
      foreign.compute_sequences,
      graph=Some(graph),
      graph_offset=1,
      scalar_only=false,
    )
    is None,
  )
}

///|
test "operation demand follows checked zero or three rows and both ordered Effect members" {
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    "sha256:05ee9059ef5f173069a3f3f1896e16ee62d34d0c842d81e9b0f8421db62e67a8",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  for count in [0, 3] {
    let rows = if count == 0 {
      "[]"
    } else {
      "[{\"id\":1},{\"id\":2},{\"id\":3}]"
    }
    let document = "{\"version\":\"actql/0.1\",\"id\":\"two-operation-members\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":" +
      rows +
      "},\"as\":\"seed\"}],\"results\":{\"rows\":{\"from\":\"seed\",\"fields\":[\"id\"]}},\"effects\":{\"first\":{\"update\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"result\":\"rows\"},\"id\":\"id\",\"set\":{\"Name\":{\"field\":\"id\"}}}},\"second\":{\"update\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"from\":{\"result\":\"rows\"},\"id\":\"id\",\"set\":{\"Name\":{\"field\":\"id\"}}}}}}],\"results\":{\"rows\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}"
    let prepared = @publication_host.prepare_client_effect_computation(
      document,
      Json,
      environment,
      None,
      [],
      @publication_host.client_standard_effect_computation_limits(),
    ).unwrap()
    let request = @publication_host.prepare_client_effect_request_identity(
      prepared,
      "sha256:" + "a".repeat(64),
      "two-operation-members",
      "sha256:" + "b".repeat(64),
    ).unwrap()
    let extent = prepare_installed_effect_operation_extent(
      "operation",
      @execution.execution_capacity(4L, 8L).unwrap(),
      3L,
      true,
    ).unwrap()
    let first = prepare_installed_effect_operation_demand(
      prepared,
      0,
      "first",
      [extent],
      [extent],
    ).unwrap()
    let second = prepare_installed_effect_operation_demand(
      prepared,
      0,
      "second",
      [extent],
      [extent],
    ).unwrap()
    let plan = prepare_installed_effect_managed_plan(
      prepared,
      request,
      [],
      "",
      "",
      [],
      [],
      contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
      [first, second],
    ).unwrap()
    assert_eq(plan.rows, count)
    assert_eq(
      plan.limits.attempts - plan.compute_limits.attempts,
      2 + 2 * count,
    )
    assert_eq(
      plan.limits.transfer_bytes - plan.compute_limits.transfer_bytes,
      (2 + 2 * count).to_int64() * 3L,
    )
    assert_eq(
      prepared_installed_effect_managed_capture_children(plan),
      2 + 2 * count,
    )
    assert_true(
      prepare_installed_effect_managed_plan(
        prepared,
        request,
        [],
        "",
        "",
        [],
        [],
        contracts,
        source_query_original_values,
        Some(source_query_original_fragment),
        None,
        [second, first],
      )
      is Err(ForeignOriginal),
    )
  }
}

///|
test "Effect extent preserves zero-byte domains and shares exact positive composition" {
  let maximum = 9223372036854775807L
  assert_eq(installed_effect_add_extent(maximum, maximum, 0L), Some(maximum))
  assert_eq(installed_effect_add_extent(0L, maximum, 0L), Some(0L))
  assert_true(installed_effect_add_extent(-1L, 0L, 0L) is None)
  assert_true(installed_effect_add_extent(0L, -1L, 0L) is None)
  assert_true(installed_effect_add_extent(0L, 0L, -1L) is None)
  for coefficient in [1L, 2L, 8L, 256L, maximum] {
    for total in [0L, 1L, maximum - 1L, maximum] {
      let count = (maximum - total) / coefficient
      assert_eq(
        installed_effect_add_extent(total, count, coefficient),
        Some(total + count * coefficient),
      )
      if count < maximum {
        assert_true(
          installed_effect_add_extent(total, count + 1L, coefficient) is None,
        )
      }
    }
  }
  assert_true(installed_effect_add_extent(-1L, 0L, 1L) is None)
  assert_true(installed_effect_add_extent(0L, -1L, 1L) is None)
}
