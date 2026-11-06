///|
// Actual declaration/check/Request/Plan owners, with the existing explicit
// Node admission and empty Compute-provider fixtures. This does not fund a
// normal installation, Account, credential, transport or provider constructor.
fn pure_provider_declaration() -> @row_source_host.RowDeclaration {
  @row_source_host.generate_row_declaration(
    "pure-provider",
    "fixture",
    "fixture/0.1",
    [
      {
        resource: "records",
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
}

///|
fn pure_provider_environment(
  declaration : @row_source_host.RowDeclaration,
) -> @checked.CheckEnvironment raise {
  let parsed = @json.parse(source_query_original_environment)
  guard parsed is Object(base) else { fail("fixture Environment") }
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
  guard base["connector_manifest"] is Object(manifest) else {
    fail("fixture manifest")
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
  let wire = @identity.stringify_value(
    @identity.from_json(parsed, 100000, 100, 1000000),
    1000000,
    100000,
    100,
  )
  @publication_host.admit_client_check_environment(
    wire,
    evidence,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
}

///|
fn pure_provider_capture_fixture(
  current? : () -> Bool = () => true,
  provider_limits? : Array[Int]? = None,
  transport_bytes? : Int64 = 4096L,
  transport_execution? : Int64 = 2048L,
  original_declaration? : @row_source_host.RowDeclaration? = None,
  original_environment? : @checked.CheckEnvironment? = None,
  runtime_admission? : Bool = false,
) -> (
  ClientRequestPreparation[Array[Int]],
  ClientInstalledManagedRun,
  ClientInstalledManagedCapturePlan,
  @row_source_host.RowDeclaration,
) raise {
  let declaration = original_declaration.unwrap_or_else(
    pure_provider_declaration,
  )
  let environment = match original_environment {
    Some(original) => original
    None => pure_provider_environment(declaration)
  }
  let document =
    #|{"version":"actql/0.1","id":"pure-provider-original","stages":[{"id":"acquire","inputs":{"remote":{"connector":"pure-provider","resource":"records"}},"steps":[{"filter":"true"},{"select":["id"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id"]}}},{"id":"compute","inputs":{"input":{"result":{"stage":"acquire","result":"rows"}}},"steps":[{"filter":"id > 0"},{"select":["id"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"rows":{"from":{"stage":"compute","result":"rows"}}}}
  let (parent, child, _, input) = registration_parent_fixture(
    current~,
    text=document,
    environment=Some(environment),
  )
  guard finish_program_check_preparation(child).unwrap() is @checked.Checked(_) else {
    fail("fixture checked Pure provider Source")
  }
  let prepared = compile_program_check_preparation(
    child,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  assert_true(
    physical_equal(
      continue_request_program_preparation(parent, input).unwrap(),
      prepared,
    ),
  )
  reserve_request_program_plan(parent, input).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "same-original-pure-provider",
  ).unwrap()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let requirement = prepare_local_query_requirement(
    prepared,
    0,
    0,
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let acquisition = @row_source_host.prepare_row_acquisition(
    declaration, requirement, original_row_query_contract_fixture, original_row_evidence_contract_fixture,
  ).unwrap()
  let provider = installed_json_source_reader_capacity(
    provider_limits.unwrap_or([4, 6, 3, 4, 2, 3, 2, 2, 5, 7, 8, 2, 9, 10, 11, 4]),
    1,
    3,
  ).unwrap()
  let capacity = installed_provider_row_capture_capacity(
    acquisition,
    Some(provider),
  ).unwrap()
  let plan = prepare_installed_managed_capture_plan(
    prepared,
    request,
    [capacity],
    [transport_bytes],
    [transport_execution],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    retained_output=true,
    provider_factory=_ => [],
    runtime_admission~,
  ).unwrap()
  complete_request_capture_preparation(parent, input, plan).unwrap()
  let run = begin_request_capture_managed_run(parent, request).unwrap()
  (parent, run, plan, declaration)
}

///|
test "runtime capture keeps the original finite parent and refuses capacity before new work" {
  let (parent, owner, plan, declaration) = pure_provider_capture_fixture(
    runtime_admission=true,
  )
  assert_true(
    physical_equal(require_installed_managed_run(owner).unwrap(), parent.ledger),
  )
  let limits = @resources.ledger_limits(parent.ledger)
  let before = @resources.ledger_usage(parent.ledger)
  assert_true(
    @resources.reserve_capacity(parent.ledger, limits.retained_bytes + 1L, 0L)
    is Err(@resources.RetentionLimit),
  )
  assert_eq(@resources.ledger_limits(parent.ledger), limits)
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  let (read, _, acquisition, capacity) = begin_installed_managed_capture_source_read(
    owner,
    plan.prepared,
    plan.request,
    declaration,
    0,
  ).unwrap()
  assert_true(
    physical_equal(acquisition, plan.captures[0].acquisition.unwrap()),
  )
  assert_true(physical_equal(capacity, plan.captures[0]))
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Pure provider read reuses the same Request Plan acquisition and crosses current once" {
  let calls = Ref(0)
  let (parent, owner, plan, declaration) = pure_provider_capture_fixture(current=() => {
    calls.val += 1
    true
  })
  let before = calls.val
  let (read, requirement, acquisition, capacity) = begin_installed_managed_capture_source_read(
    owner,
    plan.prepared,
    plan.request,
    declaration,
    0,
  ).unwrap()
  assert_eq(calls.val - before, 1)
  assert_true(physical_equal(read, owner.reads[0].unwrap()))
  assert_true(physical_equal(requirement, plan.captures[0].requirement))
  assert_true(
    physical_equal(acquisition, plan.captures[0].acquisition.unwrap()),
  )
  assert_true(physical_equal(capacity, plan.captures[0]))
  assert_true(
    read.declaration is Some(original) && physical_equal(original, declaration),
  )
  assert_eq(@resources.ledger_usage(parent.ledger).attempts, 0)
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Pure provider tuple refuses foreign original request declaration and occurrence before binding" {
  let (_, owner, plan, declaration) = pure_provider_capture_fixture()
  let copied = pure_provider_declaration()
  assert_eq(copied.catalog_cid, declaration.catalog_cid)
  let request = @publication_host.prepare_source_free_client_request_identity(
    plan.prepared,
    "sha256:" + "a".repeat(64),
    "same-original-pure-provider",
  ).unwrap()
  assert_true(
    begin_installed_managed_capture_source_read(
      owner,
      plan.prepared,
      request,
      declaration,
      0,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    begin_installed_managed_capture_source_read(
      owner,
      plan.prepared,
      plan.request,
      copied,
      0,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    begin_installed_managed_capture_source_read(
      owner,
      plan.prepared,
      plan.request,
      declaration,
      1,
    )
    is Err(ForeignOriginal),
  )
  assert_true(owner.reads[0] is None)
  let (read, _, _, _) = begin_installed_managed_capture_source_read(
    owner,
    plan.prepared,
    plan.request,
    declaration,
    0,
  ).unwrap()
  assert_true(
    begin_installed_managed_capture_source_read(
      owner,
      plan.prepared,
      plan.request,
      declaration,
      0,
    )
    is Err(AlreadyBound),
  )
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(owner).unwrap()
}

///|
test "Pure provider read retains its original partial child when current replaces the selected capacity" {
  let selected_plan : Ref[ClientInstalledManagedCapturePlan?] = Ref(None)
  let replacement : Ref[ClientInstalledCaptureCapacity?] = Ref(None)
  let (parent, owner, plan, declaration) = pure_provider_capture_fixture(current=() => {
    if selected_plan.val is Some(original) && replacement.val is Some(other) {
      original.captures[0] = other
    }
    true
  })
  let original = plan.captures[0]
  let acquisition = original.acquisition.unwrap()
  let (_, provider) = original.provider.unwrap()
  replacement.val = installed_provider_row_capture_capacity(
    acquisition,
    Some(provider),
  )
  selected_plan.val = Some(plan)
  assert_true(
    begin_installed_managed_capture_source_read(
      owner,
      plan.prepared,
      plan.request,
      declaration,
      0,
    )
    is Err(ForeignOriginal),
  )
  let retained = owner.reads[0].unwrap()
  assert_true(
    retained.acquisition is Some(held) && physical_equal(held, acquisition),
  )
  assert_true(retained.declaration is None)
  assert_eq(@resources.ledger_usage(parent.ledger).attempts, 0)
  selected_plan.val = None
  retire_installed_source_read(retained).unwrap()
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
