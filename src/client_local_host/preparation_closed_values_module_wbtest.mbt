///|
// Real original Node Resource admission and existing Core engine. These tests
// construct no Source, provider kernel, Host, permission or physical output.
extern "js" fn closed_module_test_original(
  loader : PublicationTestLoader,
  input : () -> Array[Int],
  limits : () -> Array[Int64],
  current : () -> Unit,
) -> @resources.OriginalNodeManagedRunReference =
  #|(loader,input,limits,current) => {
  #| const [p,a,h,t,r,e]=limits();
  #| return loader('../../../../../adapters/host-node/ordinary-node-resource-runtime.cjs').retainOrdinaryManagedRun(input(),{planningWork:Number(p),attempts:Number(a),holdings:Number(h),transferBytes:t,retainedBytes:r,executionBytes:e},current,()=>false,'local-preparation');
  #|}

///|
fn closed_module_fixture(
  current? : () -> Unit = () => (),
) -> (
  ClientClosedValuesPreparation[Array[Int]],
  @resources.Ledger,
  @checked.CheckEnvironment,
  @source_publication.PreparedPublishedQueryEnvironment,
  ClientInstalledSequenceContracts,
  @publication_host.ClientCompilationManifests,
) {
  let input = [1]
  let policy = client_local_resource_policy()
  let limits = client_local_preparation_initial_limits(policy).unwrap()
  let original = closed_module_test_original(
    publication_test_loader(publication_test_url()),
    () => input,
    () => {
      [
        limits.planning_work.to_int64(),
        limits.attempts.to_int64(),
        limits.holdings.to_int64(),
        limits.transfer_bytes,
        limits.retained_bytes,
        limits.execution_bytes,
      ]
    },
    current,
  )
  let initial = @resources.prepare_node_local_preparation_admission(
    original, input,
  ).unwrap()
  let ledger = @resources.start_node_preparation_admission(initial).unwrap()
  let (retained, execution) = client_closed_values_initial_control_capacity(
    policy,
    module_containers=empty_family_module_containers,
  ).unwrap()
  let capacity : @resources.PreparationCapacity[
    Array[Int],
    @publication_host.PreparedClientProgram,
  ] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    retained,
    execution,
    max_borrowers=6,
  ).unwrap()
  // Explicit initial-owner fixture keeps the original Ledger observable for
  // one-short/reentry tests. Production begin does not expose that Ledger.
  let owner : ClientClosedValuesPreparation[Array[Int]] = {
    original: None,
    input: Some(input),
    initial,
    policy,
    module_containers: empty_family_module_containers,
    capacity,
    work: None,
    header_fields: 0,
    header_rows: 0,
    retiring: false,
    module_constructing: false,
    text_checked: false,
    scan_complete: false,
    document: None,
    parsed: None,
    program: None,
    prepared: None,
    shape: None,
    lexical: None,
    envelope: None,
    retained_quote: retained,
    execution_quote: execution,
    compilation: None,
    source_free: None,
    body_ready: false,
    manager_issued: false,
    adopted: false,
    submitted_intent: None,
    manager_original: None,
  }
  owner.original = Some(owner)
  let document =
    #|{"version":"actql/0.1","id":"module","stages":[{"id":"s","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"v"}],"results":{"rows":{"from":"v","fields":["id"]}}}],"results":{"rows":{"from":{"stage":"s","result":"rows"}}}}
  let facts = closed_values_lexical_facts(document, document.length()).unwrap()
  let header = begin_closed_values_header(owner).unwrap()
  @resources.spend_preparation_phase_work(header, 50).unwrap()
  let scan = begin_closed_values_scan(owner, 1, 1).unwrap()
  @resources.spend_preparation_phase_work(
    scan,
    preparation_node_own_data_scan_work(1, 1).unwrap(),
  ).unwrap()
  finish_closed_values_scan(owner).unwrap()
  let text = begin_closed_values_text_check(owner, facts.quoted_utf16_units).unwrap()
  @resources.spend_preparation_phase_work(
    text,
    preparation_node_own_data_scan_work(1, 1).unwrap() +
    facts.quoted_utf16_units,
  ).unwrap()
  finish_closed_values_text_check(owner).unwrap()
  reserve_closed_values_snapshot(
    owner,
    {
      input_bytes_upper: facts.input_bytes,
      node_upper: facts.node_upper,
      objects: facts.objects,
      arrays: facts.arrays,
      fields_upper: facts.fields_upper,
      quoted_tokens: facts.quoted_tokens,
      quoted_utf16_units: facts.quoted_utf16_units,
      longest_quoted_utf16: facts.longest_quoted_utf16,
      longest_atom_utf16: facts.longest_atom_utf16,
      depth_upper: facts.depth_upper,
      fields: 1,
      rows: 1,
    },
    0,
  ).unwrap()
  bind_closed_values_document(owner, document).unwrap()
  let assets = @publication_host.client_local_product_assets()
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    "sha256:2217670f3f4f54047e764878501863d4eaf37cf069ab741d7306a9d8985cc94f",
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let public_environment = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    100000,
    10000,
    100,
  ).unwrap()
  (owner, ledger, environment, public_environment, contracts, manifests)
}

///|
let closed_module_no_family : @execution.PreparationRepresentationUnits = {
  record_headers: 0L,
  reference_slots: 0L,
  scalar_words: 0L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
let closed_module_empty_factory_array : @execution.PreparationRepresentationUnits = {
  record_headers: 2L,
  reference_slots: 1L,
  scalar_words: 2L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
test "module inventory retains selected output mode and separates private scratch peaks" {
  assert_eq(
    @execution.preparation_representation_cost(
      closed_values_module_construction_layout(true).retained,
    ),
    Some(1656L),
  )
  assert_eq(
    @execution.preparation_representation_cost(
      closed_values_module_construction_layout(false).retained,
    ),
    Some(1560L),
  )
  assert_eq(
    closed_values_module_construction_execution(
      closed_module_empty_factory_array, closed_module_no_family,
    ),
    Some(2360L),
  )
  let bigger = { ..closed_module_no_family, record_headers: 100L, }
  assert_eq(
    closed_values_module_construction_execution(
      closed_module_empty_factory_array, bigger,
    ),
    Some(2416L),
  )
  assert_true(
    closed_values_module_construction_execution(
      closed_module_empty_factory_array,
      { ..bigger, scalar_words: -1L, },
    )
    is None,
  )
  assert_true(
    closed_values_module_construction_execution(
      { ..bigger, owned_wire_bytes: 9223372036854775807L, },
      closed_module_no_family,
    )
    is None,
  )
}

///|
test "module factory runs once after original growth and completion waits for exact unwind" {
  for retained_output in [false, true] {
    let (owner, ledger, environment, public_environment, contracts, manifests) = closed_module_fixture()
    let calls = Ref(0)
    let observed = Ref(false)
    let before = @resources.ledger_usage(ledger).reserved_retention_bytes
    prepare_closed_values_module_body(
      owner,
      environment,
      public_environment,
      contracts,
      manifests,
      retained_output~,
      family_retained=closed_module_no_family,
      family_array=closed_module_empty_factory_array,
      family_temporary=closed_module_no_family,
      provider_factory=_ => {
        calls.val += 1
        observed.val = owner.module_constructing &&
          @resources.ledger_usage(ledger).reserved_retention_bytes > before &&
          abort_closed_values_preparation_after_cleanup(owner)
          is Err(WrongPhase) &&
          complete_closed_values_body(owner) is Err(_)
        []
      },
    ).unwrap()
    assert_eq(calls.val, 1)
    assert_true(observed.val)
    assert_false(owner.module_constructing)
    let source_free = owner.source_free.unwrap()
    let configuration = source_free.configuration.unwrap()
    assert_eq(configuration.retained_output, retained_output)
    assert_true(
      physical_equal(configuration.capacity_plan, source_free.capacity_plan),
    )
    assert_true(
      physical_equal(
        configuration.graph,
        @publication_host.prepared_client_graph(owner.prepared.unwrap()),
      ),
    )
    assert_true(owner.compilation is Some(_))
    assert_true(@resources.ledger_usage(ledger).reserved_execution_bytes > 0L)
    assert_eq(@resources.ledger_usage(ledger).attempts, 0)
    let holder = complete_closed_values_body(owner).unwrap()
    assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
    assert_true(
      abort_closed_values_preparation_after_cleanup(owner) is Err(WrongPhase),
    )
    assert_true(@resources.return_preparation_body_borrow(holder).unwrap())
    abort_closed_values_preparation_after_cleanup(owner).unwrap()
    assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  }
}
