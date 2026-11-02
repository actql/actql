///|
// Actual portable Kintone declaration/Mapping and checked CREATE preparation.
// Metadata and authored values are fixture DATA, not a Site/current grant or
// physical observation. The normal constructor/backing connection is separate.
fn installed_kintone_create_fixture() -> (
  @publication_host.PreparedClientEffectComputation,
  @publication_host.ClientRequestIdentity,
  ClientInstalledSequenceContracts,
  @kintone_host.RecordDeclaration,
  @kintone_host.RecordCreateMapping,
) raise {
  let bounds : @row_source_host.RowDeclarationLimits = {
    max_bytes: 200000,
    max_nodes: 20000,
    max_depth: 32,
    max_views: 1,
    max_fields: 16,
  }
  let catalog = @kintone_catalog.project_form_fields(
    b"{\"revision\":\"7\",\"properties\":{\"Subject\":{\"code\":\"Subject\",\"type\":\"SINGLE_LINE_TEXT\",\"expression\":\"\",\"required\":true,\"defaultValue\":\"server\"}}}",
    "12",
    {
      max_bytes: 8192,
      max_nodes: 1000,
      max_depth: 16,
      max_fields: 16,
      max_name_units: 512,
    },
  ).unwrap()
  let original = @kintone_host.declare_records(
    catalog,
    None,
    ["Subject"],
    "kintone",
    "kintone/0.1",
    "inquiries",
    {
      max_columns: 8,
      max_name_bytes: 128,
      max_nodes: 1000,
      max_depth: 16,
      max_text_bytes: 8192,
    },
    bounds,
  ).unwrap()
  let selected = @kintone_host.prepare_record_create_mapping(
    original,
    "inquiries",
    [{ target: "Subject", field: "originalSubject", null_behavior: "reject", }],
    "required",
    bounds,
  ).unwrap()
  let mapping = @kintone_host.record_create_mapping(selected)
  let declaration = @kintone_host.record_declaration(original)
  let parsed = @json.parse(source_query_original_environment)
  guard parsed is Object(base) else { fail("fixture Environment object") }
  base.remove("evidence_bundle_cid")
  let (schemas, capabilities) = @row_source_host.row_declaration_evidence_members(
    declaration,
  )
  for
    (field, additions) in [
      ("connector_catalogs", [declaration.catalog]),
      ("contract_registry", declaration.contracts),
      ("source_views", declaration.view_bodies),
      ("schema_snapshots", schemas),
      ("connector_capabilities", capabilities),
      ("mapping_contracts", [mapping.body]),
    ] {
    base[field] = effect_plan_fixture_members(base[field], additions)
  }
  guard base["connector_manifest"] is Object(manifest) else {
    fail("fixture connector manifest")
  }
  manifest["connectors"] = effect_plan_fixture_members(manifest["connectors"], [
    declaration.manifest_entry,
  ])
  let canonical = () => {
    @identity.stringify_value(
      @identity.from_json(parsed, 100000, 100, 1000000),
      1000000,
      100000,
      100,
    )
  }
  let evidence = "sha256:" + @sha.hex(@utf8.encode(canonical()))
  base["evidence_bundle_cid"] = @json.parse("\"" + evidence + "\"")
  let environment = @publication_host.admit_client_check_environment(
    canonical(),
    evidence,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"installed-kintone-create","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"originalSubject":{"type":"string","nullable":false}},"rows":[{"originalSubject":"requested 東京"}]},"as":"seed"}],"results":{"rows":{"from":"seed","fields":["originalSubject"]}},"effects":{"createOne":{"create":{"target":"connector://kintone/inquiries","mapping":"mapping:fixture/create","from":{"result":"rows"}}}}}],"results":{"rows":{"from":{"stage":"main","result":"rows"}}}}
  let prepared = @publication_host.prepare_client_effect_computation(
    document.replace(old="mapping:fixture/create", new=mapping.mapping_ref),
    Json,
    environment,
    None,
    [],
    @publication_host.client_standard_effect_computation_limits(),
  ).unwrap()
  let request = @publication_host.prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "installed-kintone-create",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  (prepared, request, contracts, original, selected)
}

///|
test "same Request CREATE Plan backs separate native Form and acknowledgement constructors before projection" {
  let (prepared, request, contracts, _, mapping) = installed_kintone_create_fixture()
  let write : @kintone_catalog.RecordWriteLimits = {
    max_fields: 16,
    max_name_bytes: 512,
    max_nodes: 1000,
    max_depth: 16,
    max_text_bytes: 8192,
    max_output_bytes: 8192,
  }
  let mutation : @kintone_catalog.RecordMutationLimits = {
    max_records: 1,
    max_identity_bytes: 1000,
    max_comparison_work: 10000,
    max_output_bytes: 8192,
    max_output_nodes: 1000,
    max_output_depth: 16,
  }
  let form : @kintone_catalog.FormFieldLimits = {
    max_bytes: 8192,
    max_nodes: 1000,
    max_depth: 16,
    max_fields: 16,
    max_name_units: 512,
  }
  let construct = installed_json_effect_request_construction_capacity(
    @kintone_host.record_create_mapped_request_construction_capacity(
      mapping, 8192, write, mutation,
    ).unwrap(),
    8192,
    1000,
    16,
  ).unwrap()
  let form_capacity = installed_json_effect_response_construction_capacity(
    @kintone_host.record_create_mapped_form_recheck_construction_capacity(
      mapping, form,
    ).unwrap(),
    8192,
    1000,
    16,
  ).unwrap()
  let response_capacity = installed_json_effect_response_construction_capacity(
    @kintone_host.record_create_mapped_response_construction_capacity(
      mapping, mutation,
    ).unwrap(),
    8192,
    1000,
    16,
  ).unwrap()
  // These are native constructor occurrences only, not read/write attempts,
  // a full standard Host recipe, transport backing or permission.
  let names = ["native-create", "native-form", "native-response"]
  let capacities = [construct, form_capacity, response_capacity]
  let extents = capacities.mapi((i, value) => {
    prepare_installed_effect_operation_extent(names[i], value, 0L, false).unwrap()
  })
  let demand = prepare_installed_effect_operation_demand(
    prepared,
    0,
    "createOne",
    [],
    extents,
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
    [demand],
    provider_factory=_ => [],
  ).unwrap()
  let (input, initial, _, initial_capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  // Existing explicit ten-byte initial carrier fixture; it does not attest
  // complete ordinary initial metadata/provider/Host backing.
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, initial_capacity, prepared, request, plan,
  ).unwrap()
  let ledger = owner.ledger.unwrap()
  let tokens = []
  for index in 0..<3 {
    let before = @resources.ledger_usage(ledger)
    let token = borrow_installed_effect_operation(
      owner,
      prepared,
      request,
      plan,
      0,
      true,
      index,
      0,
      names[index],
    ).unwrap()
    tokens.push(token)
    assert_true(
      @resources.ledger_usage(ledger).reserved_retention_bytes >=
      before.reserved_retention_bytes +
      @execution.execution_capacity_retained_bytes(capacities[index]),
    )
  }
  let mut native = Some(
    @kintone_host.prepare_record_create_execution_request(
      mapping, b"[{\"Subject\":\"intended\"}]", 8192, write, mutation,
    ).unwrap(),
  )
  assert_true(
    @kintone_catalog.recheck_record_create_form(
      native.unwrap(),
      b"{\"revision\":\"7\",\"properties\":{\"Subject\":{\"code\":\"Subject\",\"type\":\"SINGLE_LINE_TEXT\",\"expression\":\"\",\"required\":true,\"defaultValue\":\"server\"}}}",
      form,
    )
    is Ok(_),
  )
  let mut acknowledgement = Some(
    @kintone_catalog.project_record_create_acknowledgement(
      native.unwrap(),
      200,
      b"{\"ids\":[\"9007199254740993\"],\"revisions\":[\"7\"]}",
      mutation,
    ).unwrap(),
  )
  let mut outcome = Some(
    @kintone_catalog.project_record_create_effect_outcome(
      native.unwrap(),
      acknowledgement.unwrap(),
      mutation,
    ).unwrap(),
  )
  assert_eq(
    @kintone_catalog.record_create_effect_outcome_wire(outcome.unwrap()),
    "{\"result\":{\"created\":true,\"record_id\":\"9007199254740993\",\"revision\":\"7\"},\"state\":\"applied\"}",
  )
  assert_true(retire_installed_managed_run(owner) is Err(CleanupPending))
  for token in tokens {
    assert_true(retire_installed_effect_operation(token, false) is Ok(false))
  }
  native = None
  acknowledgement = None
  outcome = None
  assert_true(native is None && acknowledgement is None && outcome is None)
  for token in tokens {
    assert_true(retire_installed_effect_operation(token, true) is Ok(true))
  }
  tokens.clear()
  retire_installed_managed_run(owner).unwrap()
}

///|
test "actual Kintone Mapping and original declaration reach checked CREATE preparation" {
  let (prepared, _, _, original, selected) = installed_kintone_create_fixture()
  let mapping = @kintone_host.record_create_mapping(selected)
  assert_true(
    @kintone_host.record_create_mapping_matches_declaration(selected, original),
  )
  let descriptor = @publication_host.client_effect_member_descriptor(
    prepared, 0, "createOne", 1000,
  ).unwrap()
  assert_eq(descriptor.0, 0)
  assert_eq(descriptor.2, "create")
  assert_eq(descriptor.3, "connector://kintone/inquiries")
  assert_eq(descriptor.4, mapping.mapping_ref)
  assert_eq(descriptor.5, mapping.mapping_cid)
}

///|
fn installed_kintone_create_constructor_plan() -> (
  @publication_host.PreparedClientEffectComputation,
  @publication_host.ClientRequestIdentity,
  ClientInstalledEffectManagedPlan,
  @kintone_host.RecordCreateMapping,
  @kintone_catalog.RecordWriteLimits,
  @kintone_catalog.RecordMutationLimits,
  @execution.ExecutionCapacity,
) raise {
  let (prepared, request, contracts, _, mapping) = installed_kintone_create_fixture()
  let write : @kintone_catalog.RecordWriteLimits = {
    max_fields: 16,
    max_name_bytes: 512,
    max_nodes: 1000,
    max_depth: 16,
    max_text_bytes: 8192,
    max_output_bytes: 8192,
  }
  let mutation : @kintone_catalog.RecordMutationLimits = {
    max_records: 1,
    max_identity_bytes: 1000,
    max_comparison_work: 10000,
    max_output_bytes: 8192,
    max_output_nodes: 1000,
    max_output_depth: 16,
  }
  let provider = @kintone_host.record_create_mapped_request_construction_capacity(
    mapping, 8192, write, mutation,
  ).unwrap()
  let capacity = installed_json_effect_request_construction_capacity(
    provider, 8192, 1000, 16,
  ).unwrap()
  let extent = prepare_installed_effect_operation_extent(
    "kintone:create:construct", capacity, 0L, false,
  ).unwrap()
  let demand = prepare_installed_effect_operation_demand(
    prepared,
    0,
    "createOne",
    [],
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
    [demand],
    provider_factory=_ => [],
  ).unwrap()
  (prepared, request, plan, mapping, write, mutation, capacity)
}

///|
test "Kintone CREATE constructor borrows its typed demand from the same Request Plan before allocation" {
  let (prepared, request, plan, mapping, write, mutation, capacity) = installed_kintone_create_constructor_plan()
  let (input, initial, _, initial_capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  // This is the existing explicit10-byte Request carrier fixture, not proof
  // of complete normal metadata/Host/physical constructor backing.
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, initial_capacity, prepared, request, plan,
  ).unwrap()
  let ledger = owner.ledger.unwrap()
  let before = @resources.ledger_usage(ledger)
  let operation = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 0, 0, "kintone:create:construct",
  ).unwrap()
  let charged = @resources.ledger_usage(ledger)
  assert_true(
    charged.reserved_retention_bytes >=
    before.reserved_retention_bytes +
    @execution.execution_capacity_retained_bytes(capacity),
  )
  assert_true(
    charged.reserved_execution_bytes >=
    before.reserved_execution_bytes +
    @execution.execution_capacity_execution_bytes(capacity),
  )
  assert_eq(charged.reserved_attempts, before.reserved_attempts)
  let mut native : @kintone_catalog.RecordCreateRequest? = Some(
    @kintone_host.prepare_record_create_execution_request(
      mapping, b"[{\"Subject\":\"requested 東京\"}]", 8192, write, mutation,
    ).unwrap(),
  )
  assert_true(
    @kintone_host.record_create_mapping_matches_request(
      mapping,
      native.unwrap(),
    ),
  )
  let mut saved = Some(
    @kintone_catalog.record_create_request_values_json(
      native.unwrap(),
      8192,
      1000,
      16,
    ).unwrap(),
  )
  assert_eq(saved, Some("[{\"Subject\":\"requested 東京\"}]"))
  assert_true(retire_installed_managed_run(owner) is Err(CleanupPending))
  assert_true(retire_installed_effect_operation(operation, false) is Ok(false))
  assert_eq(@resources.ledger_usage(ledger), charged)
  // Remove the actual owned constructor outputs before the same-child ACK.
  saved = None
  native = None
  assert_true(saved is None && native is None)
  assert_true(retire_installed_effect_operation(operation, true) is Ok(true))
  retire_installed_managed_run(owner).unwrap()
}

///|
test "one-short same-parent CREATE debit refuses before running the native constructor" {
  let (prepared, request, plan, mapping, write, mutation, capacity) = installed_kintone_create_constructor_plan()
  let (input, initial, _, initial_capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, initial_capacity, prepared, request, plan,
  ).unwrap()
  let ledger = owner.ledger.unwrap()
  let limits = @resources.ledger_limits(ledger)
  let before = @resources.ledger_usage(ledger)
  let body = @execution.execution_capacity_retained_bytes(capacity)
  let controls = @execution.execution_capacity_retained_bytes(
    plan.operation_control_capacity,
  )
  let occupy = limits.retained_bytes -
    before.held_bytes -
    before.reserved_retention_bytes -
    controls -
    body +
    1L
  assert_true(occupy > 0L)
  // Accounting pressure fixture only: reserve unused capacity on this SAME
  // Ledger. No memory/permission/physical backing is inferred from the number.
  let pressure = @resources.reserve_capacity(ledger, occupy, 0L).unwrap()
  let calls = Ref(0)
  let result = borrow_installed_effect_operation(
    owner, prepared, request, plan, 0, true, 0, 0, "kintone:create:construct",
  )
  match result {
    Ok(_) => {
      calls.val += 1
      ignore(
        @kintone_host.prepare_record_create_execution_request(
          mapping, b"[{\"Subject\":\"requested 東京\"}]", 8192, write, mutation,
        ),
      )
      fail("one-short debit unexpectedly constructed native request")
    }
    Err(Ledger(@resources.RetentionLimit)) => ()
    Err(_) => fail("unexpected constructor debit refusal")
  }
  assert_eq(calls.val, 0)
  assert_eq(owner.effect_operations.length(), 0)
  assert_true(owner.effect_operation_controls is Some(_))
  @resources.settle_capacity(ledger, pressure).unwrap()
  retire_installed_managed_run(owner).unwrap()
}

///|
#external
priv type InstalledCreateChildLoader

///|
#module("node:module")
extern "js" fn installed_create_child_loader(
  url : String,
) -> InstalledCreateChildLoader = "createRequire"

///|
extern "js" fn installed_create_child_url() -> String =
  #|() => import.meta.url

///|
// Actual shared JS child with original compiled native reservation/Plan and
// Kintone constructor callees. This is not a generated Node namespace, initial
// Host metadata backing, captured Result, Account/physical operation or normal Run.
extern "js" fn installed_create_original_child(
  loader : InstalledCreateChildLoader,
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  plan : ClientInstalledEffectManagedPlan,
  read : (
    ClientInstalledManagedRun,
    @publication_host.PreparedClientEffectComputation,
    @publication_host.ClientRequestIdentity,
  ) -> Result[ClientInstalledEffectManagedPlan, ClientInstalledManagedRunIssue],
  borrow : (
    ClientInstalledManagedRun,
    @publication_host.PreparedClientEffectComputation,
    @publication_host.ClientRequestIdentity,
    ClientInstalledEffectManagedPlan,
    Int,
    Bool,
    Int,
    Int,
    String,
  ) -> Result[
    ClientInstalledEffectOperationBorrow,
    ClientInstalledManagedRunIssue,
  ],
  retire : (ClientInstalledEffectOperationBorrow, Bool) -> Result[
    Bool,
    ClientInstalledManagedRunIssue,
  ],
  construct : () -> Result[
    @kintone_catalog.RecordCreateRequest,
    @kintone_host.RecordCreateExecutionIssue,
  ],
  matches : (@kintone_catalog.RecordCreateRequest) -> Bool,
) -> Bool =
  #|(loader,owner,prepared,request,plan,read,borrow,retire,construct,matches)=>{
  #| const {prepareInstalledEffectRequestChild:create}=loader('../../../../../adapters/host-node/installed-effect-plan.mjs');
  #| const runtime={clientProgramInstalledEffectManagedOperationPlan:read,clientProgramInstalledEffectOperationBorrow:borrow,clientProgramInstalledEffectOperationRetire:retire};
  #| const run={runtime,value:owner,prepared,request,operationPlan:plan,readPlan:read};
  #| let aliasesRetired=false,calls=0;
  #| const child=create({run,memberIndex:0,rowIndex:0,operationIndex:0,operation:'kintone:create:construct',requestsRetired:()=>aliasesRetired,
  #|   construct(){calls++;const r=construct();if(r.$tag!==1)throw r._0;return r._0;}});
  #| if(calls!==0||child.status().pending!==true)return false;
  #| let native=child.prepare();
  #| if(calls!==1||!matches(native)||child.release()!==false)return false;
  #| native=undefined;aliasesRetired=true;
  #| return child.release()===true&&child.status().pending===false;
  #| }

///|
test "actual shared JS constructor child retains the original native Kintone request debit" {
  let (prepared, request, plan, mapping, write, mutation, _) = installed_kintone_create_constructor_plan()
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  assert_true(
    installed_create_original_child(
      installed_create_child_loader(installed_create_child_url()),
      owner,
      prepared,
      request,
      plan,
      installed_effect_managed_operation_plan,
      borrow_installed_effect_operation,
      retire_installed_effect_operation,
      () => {
        @kintone_host.prepare_record_create_execution_request(
          mapping, b"[{\"Subject\":\"requested 東京\"}]", 8192, write, mutation,
        )
      },
      native => {
        @kintone_host.record_create_mapping_matches_request(mapping, native)
      },
    ),
  )
  assert_eq(owner.effect_operations.length(), 1)
  assert_true(owner.effect_operations[0] is None)
  retire_installed_managed_run(owner).unwrap()
}
