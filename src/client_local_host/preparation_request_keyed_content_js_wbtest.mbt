///|
// Actual checked Request, acquired Graph, Query/acquisition, prefix/provider and
// Content compiler/adoption. Resource and installation are explicit fixtures;
// no Account/Source IO/Store/ordinary Host acceptance follows from this case.
struct RequestKeyedConstructorFixture {
  parent : ClientRequestPreparation[Array[Int]]
  input : Array[Int]
  prepared : @publication_host.PreparedClientProgram
  original : (
    SplitKeyedContentLimitsFixture,
    String,
    @checked.CheckEnvironment,
    @row_source_host.RowDeclaration,
  )
  holder : @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientProgram,
  ]
  keyed : @publication_host.ClientKeyedAcquisition
  request : @publication_host.ClientRequestIdentity
  contracts : ClientInstalledSequenceContracts
  manifests : @publication_host.ClientCompilationManifests
  compilation_limits : @publication_host.ClientPureCompilationLimits
  graph : @publication_host.ClientSerializationPlanGraph
  execution : @execution.SequenceExecutionLimits
  measurement : @execution.FixedInputGuardMeasureLimits
}

///|
fn request_keyed_constructor_fixture(
  current? : () -> Bool = () => true,
) -> RequestKeyedConstructorFixture raise {
  let (parent, input, prepared, original) = request_content_compile_fixture(
    current~,
  )
  let holder = borrow_request_content_plan_input(parent, input).unwrap()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let keyed = @publication_host.select_client_single_keyed_acquisition(prepared)
    .unwrap()
    .unwrap()
  let (task, step) = @publication_host.prepared_client_serialization_occurrences(
      prepared,
    )[0]
  let manifests = request_program_module_manifests()
  let compilation_limits = @publication_host.client_standard_pure_compilation_limits()
  let graph = prepare_request_acquired_serialization_graph(
    parent,
    input,
    task,
    step,
    3,
    4096,
    true,
    contracts,
    manifests~,
    compilation_limits~,
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "request-keyed-constructor",
  ).unwrap()
  let (_, execution, measurement) = client_local_execution_limits(max_rows=3)
  {
    parent,
    input,
    prepared,
    original,
    holder,
    keyed,
    request,
    contracts,
    manifests,
    compilation_limits,
    graph,
    execution,
    measurement,
  }
}

///|
fn request_keyed_constructor(
  fixture : RequestKeyedConstructorFixture,
  protocol? : String = original_row_query_contract_fixture,
) -> Result[
  ClientInstalledManagedKeyedPreparation,
  ClientRequestProgramPlanIssue,
] {
  prepare_request_keyed_content_plan(
    fixture.parent,
    fixture.input,
    fixture.request,
    fixture.keyed,
    fixture.original.3,
    fixture.original.3,
    original_keyed_child_limits(),
    protocol,
    original_row_evidence_contract_fixture,
    [8192L, 8192L],
    [4096L, 4096L],
    4096,
    1000000,
    fixture.contracts,
    fixture.graph.task,
    fixture.graph.step,
    fixture.execution,
    fixture.measurement,
    None,
  )
}

///|
test "keyed Content constructs one Query and retains its actual prefix on the same Request before compiler and adoption" {
  let calls = Ref(0)
  let fixture = request_keyed_constructor_fixture(current=() => {
    calls.val += 1
    true
  })
  let parent = fixture.parent
  let capacity = parent.program_capacity.unwrap()
  let before = @resources.preparation_capacity_working_extents(
    capacity,
    fixture.input,
  ).unwrap()
  let selected = request_keyed_constructor(fixture).unwrap()
  let after = @resources.preparation_capacity_working_extents(
    capacity,
    fixture.input,
  ).unwrap()
  assert_true(after.0 > before.0 && after.1 > before.1)
  assert_true(
    parent.program_content is KeyedContent(original, None) &&
    physical_equal(original, selected),
  )
  assert_true(
    parent.program_content_request is Some(original) &&
    physical_equal(original, fixture.request),
  )
  let prefix = selected.prefix.unwrap()
  assert_true(@execution.generated_sequence_step_count(prefix.sequence) > 0)
  let selected_capacity = @local.managed_provider_capacity(
    prefix.provider,
    prefix.sequence,
  ).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(selected_capacity),
    @execution.execution_capacity_retained_bytes(prefix.capacity),
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(selected_capacity),
    @execution.execution_capacity_execution_bytes(prefix.capacity),
  )
  assert_true(
    request_keyed_constructor(fixture) is Err(Preparation(ForeignOriginal)),
  )
  let compilation = prepare_request_keyed_serialization_compilation(
    parent,
    fixture.input,
    selected,
    fixture.graph,
    manifests=fixture.manifests,
    compilation_limits=fixture.compilation_limits,
  ).unwrap()
  assert_true(
    @publication_host.client_task_compilation_serialization(compilation)
    is Some(original) &&
    physical_equal(original, fixture.graph),
  )
  assert_true(
    parent.program_content is KeyedContent(original, None) &&
    physical_equal(original, selected),
  )
  complete_request_content_preparation(
    parent,
    fixture.input,
    fixture.request,
    selected,
  ).unwrap()
  let run = begin_request_content_managed_run(parent, fixture.request).unwrap()
  assert_true(
    run.content is KeyedContent(original, _) &&
    physical_equal(original, selected),
  )
  assert_true(physical_equal(selected.prefix.unwrap(), prefix))
  // The installed reader with its originalReader asks this exact closed
  // variant getter before the original acquisition handoff below. It is DATA,
  // not another current callback, query, grant or capacity constructor.
  let before_kind = calls.val
  assert_eq(
    installed_managed_source_input_kind(run, fixture.prepared, fixture.request).unwrap(),
    "query",
  )
  assert_eq(calls.val, before_kind)
  let foreign_request = @publication_host.prepare_source_free_client_request_identity(
    fixture.prepared,
    "sha256:" + "a".repeat(64),
    "foreign-reader-request",
  ).unwrap()
  assert_true(
    installed_managed_source_input_kind(run, fixture.prepared, foreign_request)
    is Err(ForeignOriginal),
  )
  // The already-existing managed Source getter returns these exact selected
  // originals. No new getter, query/capacity reconstruction or grant is needed.
  let (read, requirement, acquisition, direct) = begin_installed_managed_capture_source_read(
    run,
    fixture.prepared,
    fixture.request,
    fixture.original.3,
    selected.direct_stage,
  ).unwrap()
  assert_true(physical_equal(direct, selected.direct))
  assert_true(physical_equal(requirement, selected.direct.requirement))
  assert_true(
    selected.direct.acquisition is Some(original) &&
    physical_equal(original, acquisition),
  )
  let ledger = prepare_installed_managed_run_ledger(
    run,
    fixture.prepared,
    fixture.request,
    [direct],
    [8192L],
    [4096L],
    fixture.contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  assert_true(physical_equal(ledger, parent.ledger))
  retire_installed_source_read(read).unwrap()
  assert_false(
    @resources.return_preparation_body_borrow(fixture.holder).unwrap(),
  )
  retire_installed_managed_run(run).unwrap()
  assert_true(
    installed_managed_source_input_kind(run, fixture.prepared, fixture.request)
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "keyed Content current refusal precedes original Query and prefix construction and preserves the same abort owner" {
  let armed = Ref(false)
  let calls = Ref(0)
  let fixture = request_keyed_constructor_fixture(current=() => {
    if armed.val {
      calls.val += 1
      false
    } else {
      true
    }
  })
  let before = request_preparation_accounting(fixture.parent)
  armed.val = true
  assert_true(
    request_keyed_constructor(fixture) is Err(Preparation(Capacity(_))),
  )
  armed.val = false
  assert_true(calls.val > 0)
  assert_eq(request_preparation_accounting(fixture.parent), before)
  assert_true(
    fixture.parent.phase == ProgramBodyFailed &&
    fixture.parent.program_content is NoContent &&
    fixture.parent.program_compilation is None,
  )
  assert_false(
    @resources.return_preparation_body_borrow(fixture.holder).unwrap(),
  )
  abort_request_preparation_after_cleanup(fixture.parent).unwrap()
  assert_eq(@resources.ledger_usage(fixture.parent.ledger).live_reservations, 0)
}

///|
test "keyed Content protocol failure keeps its grown constructor debit and never selects a replacement prefix" {
  let fixture = request_keyed_constructor_fixture()
  let before = request_preparation_accounting(fixture.parent)
  assert_true(
    request_keyed_constructor(fixture, protocol="{}") is Err(ContentSource(_)),
  )
  let after = request_preparation_accounting(fixture.parent)
  assert_true(after.4 > before.4 && after.5 > before.5)
  assert_true(
    fixture.parent.phase == ProgramBodyFailed &&
    fixture.parent.program_content is NoContent,
  )
  assert_true(
    request_keyed_constructor(fixture) is Err(Preparation(ForeignOriginal)),
  )
  assert_false(
    @resources.return_preparation_body_borrow(fixture.holder).unwrap(),
  )
  abort_request_preparation_after_cleanup(fixture.parent).unwrap()
  assert_eq(@resources.ledger_usage(fixture.parent.ledger).live_reservations, 0)
}
