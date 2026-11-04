///|
// The original Source Program/check/compiler, actual nominal Row acquisition
// and shared Compute Plan run on one Request. Empty providers are an explicit
// component port, not a Host/Account/physical Source acceptance claim.
fn request_capture_fixture(
  document? : String = source_query_original_document,
  environment_wire? : String = source_query_original_environment,
  environment_cid? : String = "sha256:05ee9059ef5f173069a3f3f1896e16ee62d34d0c842d81e9b0f8421db62e67a8",
  current? : () -> Bool = () => true,
  events? : Bool = false,
) -> (
  ClientRequestPreparation[Array[Int]],
  Array[Int],
  @publication_host.PreparedClientProgram,
) raise {
  let environment = @publication_host.admit_client_check_environment(
    environment_wire,
    environment_cid,
    { text_time: events, veca: false, },
    { rela: true, sga: false, tea: events, calendar: false, text_rank: false, },
  ).unwrap()
  let (parent, child, _, input) = registration_parent_fixture(
    current~,
    text=document,
    environment=Some(environment),
  )
  guard finish_program_check_preparation(child).unwrap() is @checked.Checked(_) else {
    fail("original captured Source must finish its supported check")
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
  (parent, input, prepared)
}

///|
fn request_capture_plan_fixture(
  prepared : @publication_host.PreparedClientProgram,
  original_contracts? : ClientInstalledSequenceContracts? = None,
  factory? : (@execution.ExecutionCapacity) -> Array[@local.ManagedProvider] = _ => {
    []
  },
) -> (
  ClientInstalledManagedCapturePlan,
  @publication_host.ClientRequestIdentity,
) {
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "original-request-capture-plan",
  ).unwrap()
  let contracts = match original_contracts {
    Some(value) => value
    None =>
      prepare_installed_sequence_contracts(
        source_query_original_registry,
        source_query_original_values,
        Some(source_query_original_fragment),
        None,
      ).unwrap()
  }
  let requirement = prepare_local_query_requirement(
    prepared,
    0,
    0,
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let acquisition = original_row_acquisition_fixture(requirement)
  let capacity = installed_row_capture_capacity(acquisition).unwrap()
  let plan = prepare_installed_managed_capture_plan(
    prepared,
    request,
    [capacity],
    [4096L],
    [2048L],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    retained_output=true,
    provider_factory=factory,
  ).unwrap()
  (plan, request)
}

///|
fn request_capture_ledger_fixture(
  run : ClientInstalledManagedRun,
  plan : ClientInstalledManagedCapturePlan,
) -> Result[@resources.Ledger, ClientInstalledManagedRunIssue] {
  prepare_installed_managed_run_ledger(
    run,
    plan.prepared,
    plan.request,
    plan.captures,
    plan.transport_bytes,
    plan.transport_execution_bytes,
    plan.installed_contracts,
    plan.values_body,
    plan.fragment_body,
    plan.ordered_body,
  )
}

///|
test "one actual captured Request ledger handoff observes original external current once" {
  let calls = Ref(0)
  let (parent, input, prepared) = request_capture_fixture(current=() => {
    calls.val += 1
    true
  })
  let (plan, request) = request_capture_plan_fixture(prepared)
  complete_request_capture_preparation(parent, input, plan).unwrap()
  let run = begin_request_capture_managed_run(parent, request).unwrap()
  let read = begin_installed_managed_capture_read(run, 0).unwrap()
  let before = calls.val
  let ledger = request_capture_ledger_fixture(run, plan).unwrap()
  let observed = calls.val - before
  assert_true(physical_equal(ledger, parent.ledger))
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  assert_eq(observed, 1)
}

///|
test "captured Request retains original Plan acquisition sequences and manager custody" {
  let factories = Ref(0)
  let (parent, input, prepared) = request_capture_fixture()
  let (plan, request) = request_capture_plan_fixture(prepared, factory=_ => {
    factories.val += 1
    []
  })
  assert_eq(factories.val, 1)
  assert_eq(plan.sequences.length(), 2)
  assert_eq(plan.compute_sequences.length(), 1)
  let acquisition = prepared_installed_managed_capture_acquisition(plan, 0).unwrap()
  assert_true(prepared_installed_managed_capture_acquisition(plan, 1) is None)
  let before = @resources.ledger_usage(parent.ledger)
  complete_request_capture_preparation(parent, input, plan).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  let manager = borrow_request_program_preparation(parent).unwrap()
  assert_true(
    physical_equal(
      @resources.preparation_body_borrow_value(manager).unwrap(),
      prepared,
    ),
  )
  let copied = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "original-request-capture-plan",
  ).unwrap()
  assert_true(
    begin_request_capture_managed_run(parent, copied) is Err(ForeignOriginal),
  )
  let run = begin_request_capture_managed_run(parent, request).unwrap()
  assert_true(
    parent.phase == Selected &&
    parent.input is None &&
    parent.program_captured is None &&
    parent.program_capacity is None,
  )
  assert_true(
    physical_equal(
      installed_managed_capture_plan(run, prepared, request).unwrap(),
      plan,
    ),
  )
  assert_true(
    installed_managed_capture_plan(run, prepared, copied)
    is Err(ForeignOriginal),
  )
  let read = begin_installed_managed_capture_read(run, 0).unwrap()
  assert_true(physical_equal(read.acquisition.unwrap(), acquisition))
  assert_true(
    physical_equal(read.requirement.unwrap(), plan.captures[0].requirement),
  )
  assert_true(begin_installed_managed_capture_read(run, 0) is Err(AlreadyBound))
  assert_true(
    physical_equal(
      request_capture_ledger_fixture(run, plan).unwrap(),
      parent.ledger,
    ),
  )
  assert_true(
    installed_managed_publication_limits(run, prepared, 1000000) is Some(_),
  )
  assert_eq(factories.val, 1)
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  retire_installed_source_read(read).unwrap()
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(run.captured_preparation is None)
  assert_true(@resources.return_preparation_body_borrow(manager).unwrap())
  retire_installed_managed_run(run).unwrap()
  let usage = @resources.ledger_usage(parent.ledger)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.live_reservations, 0)
}

///|
test "captured Request refuses foreign equal input inventory and changed selected Plan DATA" {
  let (parent, input, prepared) = request_capture_fixture()
  let (other, _, foreign) = request_capture_fixture()
  let (plan, request) = request_capture_plan_fixture(prepared)
  let (foreign_plan, _) = request_capture_plan_fixture(foreign)
  let factories = Ref(0)
  assert_true(
    prepare_installed_managed_capture_plan(
      prepared,
      request,
      foreign_plan.captures,
      plan.transport_bytes,
      plan.transport_execution_bytes,
      plan.installed_contracts,
      plan.values_body,
      plan.fragment_body,
      plan.ordered_body,
      retained_output=true,
      provider_factory=_ => {
        factories.val += 1
        []
      },
    )
    is Err(ForeignOriginal),
  )
  assert_eq(factories.val, 0)
  assert_true(
    complete_request_capture_preparation(parent, input, foreign_plan)
    is Err(WrongPhase),
  )
  assert_true(parent.program_captured is None && !parent.program_body_attempted)
  complete_request_capture_preparation(parent, input, plan).unwrap()
  let run = begin_request_capture_managed_run(parent, request).unwrap()
  let read = begin_installed_managed_capture_read(run, 0).unwrap()
  assert_true(
    prepare_installed_managed_run_ledger(
      run,
      prepared,
      request,
      foreign_plan.captures,
      plan.transport_bytes,
      plan.transport_execution_bytes,
      plan.installed_contracts,
      plan.values_body,
      plan.fragment_body,
      plan.ordered_body,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    prepare_installed_managed_run_ledger(
      run,
      prepared,
      request,
      plan.captures,
      [4097L],
      plan.transport_execution_bytes,
      plan.installed_contracts,
      plan.values_body,
      plan.fragment_body,
      plan.ordered_body,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    prepare_installed_managed_run_ledger(
      run,
      prepared,
      request,
      plan.captures,
      plan.transport_bytes,
      plan.transport_execution_bytes,
      foreign_plan.installed_contracts,
      plan.values_body,
      plan.fragment_body,
      plan.ordered_body,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    open_installed_managed_capture_host(run, prepared, request, [])
    is Err(Managed(ForeignOriginal)),
  )
  assert_false(run.source_free_opening)
  assert_true(run.source_free_captured is None)
  assert_true(
    physical_equal(
      request_capture_ledger_fixture(run, plan).unwrap(),
      parent.ledger,
    ),
  )
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(run).unwrap()
  abort_request_preparation_after_cleanup(other).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  assert_eq(@resources.ledger_usage(other.ledger).live_reservations, 0)
}

///|
test "captured Request ledger current reentry cannot return a retired original" {
  let action : Ref[(() -> Unit)?] = Ref(None)
  let (parent, input, prepared) = request_capture_fixture(current=() => {
    if action.val is Some(run) {
      action.val = None
      run()
    }
    true
  })
  let (plan, request) = request_capture_plan_fixture(prepared)
  complete_request_capture_preparation(parent, input, plan).unwrap()
  let run = begin_request_capture_managed_run(parent, request).unwrap()
  let read = begin_installed_managed_capture_read(run, 0).unwrap()
  action.val = Some(() => {
    retire_installed_source_read(read).unwrap()
    retire_installed_managed_run(run).unwrap()
  })
  assert_true(request_capture_ledger_fixture(run, plan) is Err(_))
  assert_true(run.ledger is None && run.captured_preparation is None)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "captured Request opens its same accounted capture with retained configuration once" {
  let factories = Ref(0)
  let (parent, input, prepared) = request_capture_fixture()
  let (plan, request) = request_capture_plan_fixture(prepared, factory=_ => {
    factories.val += 1
    []
  })
  complete_request_capture_preparation(parent, input, plan).unwrap()
  let run = begin_request_capture_managed_run(parent, request).unwrap()
  let read = begin_installed_managed_capture_read(run, 0).unwrap()
  let ledger = request_capture_ledger_fixture(run, plan).unwrap()
  let acquisition = prepared_installed_managed_capture_acquisition(plan, 0).unwrap()
  let rows = start_installed_source_read_rows(
    read,
    acquisition,
    "same-request-source",
    _ => true,
    4096L,
    2048L,
  ).unwrap()
  @row_source_host.begin_row_run(rows, 2048, 2, 2).unwrap()
  let bytes = @utf8.encode("[{\"id\":3,\"amount\":7}]")
  let charged = @row_source_host.charge_row_run_page(rows, bytes).unwrap()
  assert_eq(
    @row_source_host.accept_charged_row_run_page(rows, charged, bytes).unwrap(),
    1,
  )
  @row_source_host.finish_row_run(rows).unwrap()
  @row_source_host.begin_row_capture(rows).unwrap()
  let mut complete = false
  for _ in 0..<10000 {
    if @row_source_host.advance_row_capture(rows, 256).unwrap().0 {
      complete = true
      break
    }
  }
  assert_true(complete)
  let capture = @row_source_host.capture_row_run(rows).unwrap()
  let source = @row_source_host.row_capture_source(capture).unwrap()
  let (_, dag, sequences) = open_installed_managed_capture_host(
    run,
    prepared,
    request,
    [source],
  ).unwrap()
  assert_true(physical_equal(@strategy.captured_dag_ledger(dag), ledger))
  assert_true(
    physical_equal(
      installed_managed_publication_dag(run, prepared).unwrap(),
      dag,
    ),
  )
  assert_true(physical_equal(sequences, plan.sequences))
  assert_eq(factories.val, 1)
  assert_true(
    open_installed_managed_capture_host(run, prepared, request, [source])
    is Err(Managed(AlreadyBound)),
  )
  ignore(reject_client_local_run(dag))
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(run).unwrap()
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.live_reservations, 0)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.attempts, 1)
  assert_true(usage.transferred_bytes > 0L)
}

///|
test "captured QueryTime requirement preserves the same invocation original without default substitution" {
  let (parent, input, prepared) = request_capture_fixture()
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).unwrap()
  let compilation = @publication_host.issue_prepared_client_task_compilation(
    prepared,
    manifests,
    @publication_host.client_standard_values_sequence_limits(),
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  let compiled = @publication_host.issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "captured-query-time", "original", "2026-10-29T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let (created, _) = @publication.run_definition_lifetime(definition).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "captured-query-time",
  ).unwrap()
  let original = @publication_host.prepare_client_query_time(
    prepared, request, created,
  ).unwrap()
  @publication_host.bind_client_query_evaluation_time(
    original, prepared, compiled, definition, request,
  ).unwrap()
  |> ignore
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let requirement = prepare_local_query_requirement_at_query_time(
    prepared,
    0,
    0,
    original,
    request,
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  assert_true(
    @publication_host.client_query_requirement_matches_original_query_time(
      prepared,
      0,
      0,
      requirement,
      Some(original),
      request,
    ),
  )
  assert_false(
    @publication_host.client_query_requirement_matches_original_query_time(
      prepared,
      0,
      0,
      requirement,
      None,
      request,
    ),
  )
  assert_false(
    @publication_host.client_query_requirement_matches_original_query_time(
      prepared,
      1,
      0,
      requirement,
      Some(original),
      request,
    ),
  )
  let copied = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "captured-query-time",
  ).unwrap()
  assert_false(
    @publication_host.client_query_requirement_matches_original_query_time(
      prepared,
      0,
      0,
      requirement,
      Some(original),
      copied,
    ),
  )
  let other = @publication_host.prepare_client_query_time(
    prepared, request, created,
  ).unwrap()
  @publication_host.bind_client_query_evaluation_time(
    other, prepared, compiled, definition, request,
  ).unwrap()
  |> ignore
  assert_false(
    @publication_host.client_query_requirement_matches_original_query_time(
      prepared,
      0,
      0,
      requirement,
      Some(other),
      request,
    ),
  )
  let capacity = installed_row_capture_capacity(
    original_row_acquisition_fixture(requirement),
  ).unwrap()
  let plan = prepare_installed_managed_capture_plan(
    prepared,
    request,
    [capacity],
    [4096L],
    [2048L],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    query_time=Some(original),
    retained_output=true,
    provider_factory=_ => [],
  ).unwrap()
  assert_true(physical_equal(plan._observed_query_time.unwrap(), original))
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  ignore(input)
}

///|
// Same actual checked Source and original Request/Plan. No reader, transport,
// physical admission or public Run is supplied by this compiler-path counter.
test "Source Compute Plan retains its checked leaf demand through original Request adoption" {
  let (parent, input, prepared) = request_capture_fixture()
  let (plan, request) = request_capture_plan_fixture(prepared)
  complete_request_capture_preparation(parent, input, plan).unwrap()
  let run = begin_request_capture_managed_run(parent, request).unwrap()
  let original = installed_managed_capture_plan(run, prepared, request).unwrap()
  assert_true(physical_equal(original, plan))
  let capacity = original.capacity_plan
  let scalar = match (capacity.scalar_demand, capacity.schema_inventory) {
    (Some(demand), Some(inventory)) =>
      physical_equal(demand.original, inventory)
    _ => false
  }
  let leaves = match (capacity.value_node_demand, capacity.demand_inventory) {
    (Some(demand), Some(inventory)) =>
      physical_equal(demand.original, inventory)
    _ => false
  }
  // Retire the real unused original even when this new positive assertion
  // finds the missing immutable proof. No physical attempt occurred here.
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  assert_true(scalar && leaves)
}

///|
test "captured Request retains the same accounted compilation for publication without recompiling" {
  let (parent, input, prepared) = request_capture_fixture()
  let holder = borrow_request_program_plan_input(parent, input).unwrap()
  let (plan, request) = request_capture_plan_fixture(prepared)
  assert_true(plan.compilation is None)
  prepare_request_capture_module_body(
    parent,
    input,
    plan,
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    provider_factory=_ => [],
  ).unwrap()
  let compilation = plan.compilation.unwrap()
  let spent = parent.program_artifact_work_spent
  assert_eq(spent, parent.program_artifact_plan_encoding_nodes.val)
  assert_true(spent > 0L)
  let run = begin_request_capture_managed_run(parent, request).unwrap()
  assert_true(physical_equal(run.captured_preparation.unwrap(), plan))
  for _ in 0..<3 {
    assert_true(
      physical_equal(
        installed_managed_run_compilation_original(run, prepared).unwrap(),
        compilation,
      ),
    )
  }
  assert_eq(parent.program_artifact_work_spent, spent)
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(installed_managed_run_compilation_original(run, prepared) is None)
  assert_true(@resources.return_preparation_body_borrow(holder).unwrap())
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
// Actual Request/Row capture/compilation/Run. The existing finite identity
// fixture supplies only identity-scanner limits; no Host IO/permission or
// physical cleanup acknowledgement is asserted by this publication case.
test "captured Source publication retains original evidence Plan and one invocation slot" {
  let (parent, input, prepared) = request_capture_fixture(
    environment_wire=captured_publication_source_environment,
    environment_cid="sha256:d11b776446b2301cf841d09e06b8aa9524463eec78d219f65123c32aab50b709",
  )
  let holder = borrow_request_program_plan_input(parent, input).unwrap()
  let (plan, request) = request_capture_plan_fixture(prepared)
  prepare_request_capture_module_body(
    parent,
    input,
    plan,
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    provider_factory=_ => [],
  ).unwrap()
  let run = begin_request_capture_managed_run(parent, request).unwrap()
  let compiled = match
    installed_managed_run_compilation_original(run, prepared).unwrap() {
    @publication_host.Tasks(compilation) =>
      @publication_host.issue_client_task_compiled_run(
        prepared,
        compilation,
        "sha256:" + "a".repeat(64),
        "sha256:" + "b".repeat(64),
        "2099-01-01T00:00:00.000Z",
      ).unwrap()
    _ => fail("original captured Tasks compilation required")
  }
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "captured-publication", "original-request-capture-plan", "2026-10-30T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let read = begin_installed_managed_capture_read(run, 0).unwrap()
  let acquisition = prepared_installed_managed_capture_acquisition(plan, 0).unwrap()
  let requirement = plan.captures[0].requirement
  let rows = start_installed_source_read_rows(
    read,
    acquisition,
    "same-request-publication-source",
    _ => true,
    4096L,
    2048L,
  ).unwrap()
  @row_source_host.begin_row_run(rows, 2048, 2, 2).unwrap()
  let bytes = @utf8.encode("[{\"id\":3,\"amount\":7}]")
  let charged = @row_source_host.charge_row_run_page(rows, bytes).unwrap()
  assert_eq(
    @row_source_host.accept_charged_row_run_page(rows, charged, bytes).unwrap(),
    1,
  )
  @row_source_host.finish_row_run(rows).unwrap()
  @row_source_host.begin_row_capture(rows).unwrap()
  let mut done = false
  for _ in 0..<10000 {
    if @row_source_host.advance_row_capture(rows, 256).unwrap().0 {
      done = true
      break
    }
  }
  assert_true(done)
  let capture = @row_source_host.capture_row_run(rows).unwrap()
  let source = @row_source_host.row_capture_source(capture).unwrap()
  let limits = original_keyed_content_workspace().export_limits
  let identity = @query.identify_captured_source_relation(
    source,
    3,
    limits.values,
    limits.payload_wire,
    limits.logical_wire,
    limits.schema,
    limits.max_batch_bytes,
  ).unwrap()
  let logical = @publication_host.issue_captured_source_input_logical(
    @publication_host.prepared_client_graph(prepared),
    source,
    identity,
    requirement,
  ).unwrap()
  let authority = "sha256:" + "2".repeat(64)
  let policy = @publication_host.prepared_client_publication_data_policy_cid(
    prepared,
  ).unwrap()
  let source_policy = @planning.query_requirement_source_evidence_facts(
      requirement,
    ).unwrap().source_data_policy_cid
  let evidence = match
    @row_source_host.issue_row_source_evidence(
      acquisition, capture, identity, logical, authority, source_policy, "2026-10-30T00:00:01.000Z",
    ) {
    Ok(value) => value
    Err(@row_source_host.SourceEvidence(@row_source_host.InvalidPolicy)) =>
      fail("fixture SourceEvidence.InvalidPolicy")
    Err(@row_source_host.SourceEvidence(@row_source_host.Member(_))) =>
      fail("fixture SourceEvidence.Member")
    Err(@row_source_host.SourceEvidence(@row_source_host.LogicalInput(_))) =>
      fail("fixture SourceEvidence.LogicalInput")
    Err(
      @row_source_host.SourceEvidence(@row_source_host.ObservationUnavailable)
    ) => fail("fixture SourceEvidence.ObservationUnavailable")
    Err(@row_source_host.SourceEvidence(@row_source_host.ObservationMismatch)) =>
      fail("fixture SourceEvidence.ObservationMismatch")
    Err(@row_source_host.SourceEvidence(@row_source_host.Evidence(_))) =>
      fail("fixture SourceEvidence.Evidence")
    Err(_) => fail("fixture other Row evidence issue")
  }
  // A retained value does not waive a later tighter per-value envelope.
  // This exact source is larger than the resulting Observation Set.
  let evidence_wire = @publication.run_evidence_value_json(evidence)
  let tight_bytes = @utf8.encode(evidence_wire).length() - 1
  assert_true(
    @publication.admit_run_evidence_value(
      "source_evidence", evidence_wire, tight_bytes, 8192, 64,
    )
    is Err(_),
  )
  assert_true(
    @publication_host.issue_client_compiled_captured_invocation(
      compiled,
      definition,
      [source],
      [identity],
      [requirement],
      [evidence],
      [logical],
      None,
      authority,
      policy,
      "2026-10-30T00:00:00.000Z",
      "2026-10-30T00:00:01.000Z",
      tight_bytes,
      8192,
      64,
    )
    is Err(_),
  )
  let (observation, invocation) = issue_program_captured_publication_invocation(
    run,
    prepared,
    compiled,
    definition,
    [source],
    [identity],
    [requirement],
    [evidence],
    [logical],
    None,
    authority,
    policy,
    "2026-10-30T00:00:00.000Z",
    "2026-10-30T00:00:01.000Z",
    65536,
    8192,
    64,
  ).unwrap()
  assert_true(physical_equal(run.publication_definition.unwrap(), definition))
  assert_true(physical_equal(run.publication_invocation.unwrap(), invocation))
  assert_true(
    @publication.run_evidence_value_json(observation).contains(
      @publication.run_evidence_value_identity(evidence),
    ),
  )
  assert_true(
    issue_program_captured_publication_invocation(
      run,
      prepared,
      compiled,
      definition,
      [source],
      [identity],
      [requirement],
      [evidence],
      [logical],
      None,
      authority,
      policy,
      "2026-10-30T00:00:00.000Z",
      "2026-10-30T00:00:01.000Z",
      65536,
      8192,
      64,
    )
    is Err(WrongPhase),
  )
  let (_, dag, _) = open_installed_managed_capture_host(
    run,
    prepared,
    request,
    [source],
  ).unwrap()
  let publication = reserve_program_publication(run, prepared)
  ignore(reject_client_local_run(dag))
  retire_installed_source_read(read).unwrap()
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(@resources.return_preparation_body_borrow(holder).unwrap())
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  assert_true(publication is Ok(_))
}

///|
// Same authored Source catalogue, explicitly declaring the existing query
// evidence contract required by the actual Row Source-evidence issuer.
let captured_publication_source_environment : String =
  #|{"command_contracts":[],"connector_capabilities":[{"capability_contract_cids":["sha256:2e9959187141ac09be2f4684ac2d0dc7a2819059c6764b1a527b48e0cee6a08d","sha256:dcf4b1e2c8a078d96f9160a75a9f8279047e7448ea39b3b882588e18b9ab0929"],"read_mode":"snapshot","source_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","source_ref":"connector://crm/main/r#v","source_view_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3"}],"connector_catalogs":[{"catalog_cid":"sha256:71498e8a82b1fe64683daf4a0b2e9fa9e4cc8a5e02ab801e42520fb27460ea4a","commands":[],"connector_id":"crm/main","connector_version":"fixture","contracts":[{"body":{"additional_properties":false,"fields":{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"}],"schema":"actql.connector_catalog/0.1","source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","output":{"carrier":"relation","data_policy":{"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","version":"fixture"},"facts":{"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}]},{"catalog_cid":"sha256:9faf09f5a3177d36dc7c9fab868f6fe4437e4597dd12bcdc051166ec2e6ad8fd","commands":[],"connector_id":"crm","connector_version":"fixture","contracts":[],"schema":"actql.connector_catalog/0.1","source_views":[]}],"connector_manifest":{"connectors":[{"connector":"crm","connector_id":"crm","connector_version":"fixture"}],"version":"actql-connectors/0.1"},"contract_registry":[{"body":{},"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{},"nullable":false,"type":"object"},"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{"amount":{"nullable":true,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"}],"evidence_bundle_cid":"sha256:d11b776446b2301cf841d09e06b8aa9524463eec78d219f65123c32aab50b709","host_policy_profile":{"capacity":{"max_aggregate_array_items":10000,"max_artifact_bytes":10000,"max_artifact_rows":10000,"max_effect_items":10000,"max_graph_input_edges":10000,"max_graph_input_nodes":10000,"max_graph_output_rows":10000,"max_graph_paths":10000,"max_infer_items":10000,"max_model_input_tokens_per_item":10000,"max_model_request_bytes_per_item":10000,"max_model_total_duration_ms":10000,"max_nested_value_bytes":10000,"max_nested_value_depth":10000,"max_relation_output_rows":10000,"max_temporal_matches_per_key":10000,"max_temporal_output_rows":10000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[{"connector_manifest_cid":"sha256:b1b75d3b468de053f98c678ec9eedfb2f1fe7b6fcb76562b0f392121378ec7c1","conversions":[],"mapping_contract_cid":"sha256:f6a45e666ca86c60fe3ce8ec72cb43dff5757740391cd2e8a883834baa681d1f","mapping_ref":"mapping:crm.account.v1","minimum_approval":"required","permission_rules":[{"effect_kind":"update","permissions":["scope:update"],"selector_class":"id","write_fields":["Name"]}],"primary_identity":"Id","required_fields":[],"required_permissions":[],"resource_identity_cid":"sha256:b257547d26294b5e2f7131d760d54cb8e6783fb8f44504e59c4f8917211387fb","row_mapping":{"Name":{"field":"id","null_behavior":"reject"}},"schema":"actql.mapping_contract/0.1","target_ref":"connector://crm/account","target_schema":{"additional_properties":false,"fields":{"Id":{"nullable":false,"type":"number"},"Name":{"nullable":true,"type":"number"}},"nullable":false,"type":"object"},"target_schema_identity":"sha256:c000fb12383456a0e123e74501d164b96bb886251dbb44f301661070321be8e0","version":"fixture-v1","writable_fields":["Name"]}],"model_task_contracts":[],"schema_snapshots":[{"carrier_schema_contract_cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","data_classification":"unknown","output_carrier":"relation","read_mode":"snapshot","source_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","source_data_policy_cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","source_ref":"connector://crm/main/r#v","source_view_contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3"}],"source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:bcb09919b8eef2947328d975739353f2717a7781b6ae42617da071a54930aa74","id":"fixture-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","output":{"carrier":"relation","data_policy":{"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","version":"fixture"},"facts":{"cid":"sha256:804b56a824b1f2249b87fefa25e45e7e327d3aaf519b264df52bc6296d86c905","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}],"version":"actql-check-environment/0.1"}

///|
test "captured publication foreign definition leaves slot intact but semantic failure consumes it" {
  let calls = Ref(0)
  let (parent, input, prepared) = request_capture_fixture(current=() => {
    calls.val += 1
    true
  })
  let holder = borrow_request_program_plan_input(parent, input).unwrap()
  let (plan, request) = request_capture_plan_fixture(prepared)
  prepare_request_capture_module_body(
    parent,
    input,
    plan,
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    provider_factory=_ => [],
  ).unwrap()
  let run = begin_request_capture_managed_run(parent, request).unwrap()
  let compiled = match
    installed_managed_run_compilation_original(run, prepared).unwrap() {
    @publication_host.Tasks(original) =>
      @publication_host.issue_client_task_compiled_run(
        prepared,
        original,
        "sha256:" + "a".repeat(64),
        "sha256:" + "b".repeat(64),
        "2099-01-01T00:00:00.000Z",
      ).unwrap()
    _ => fail("original Tasks compilation required")
  }
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "captured-failure", "original-request-capture-plan", "2026-10-30T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let copied = @publication.admit_publication_contract(
    "run_definition",
    @publication.publication_contract_json(definition),
    65536,
    8192,
    64,
  ).unwrap()
  let before = calls.val
  let issue = definition => {
    issue_program_captured_publication_invocation(
      run,
      prepared,
      compiled,
      definition,
      [],
      [],
      [],
      [],
      [],
      None,
      "sha256:" + "2".repeat(64),
      "sha256:" + "3".repeat(64),
      "2026-10-30T00:00:00.000Z",
      "2026-10-30T00:00:01.000Z",
      65536,
      8192,
      64,
    )
  }
  assert_true(issue(copied) is Err(ForeignOriginal))
  assert_false(run.publication_invocation_started)
  assert_true(issue(definition) is Err(PublicationInvocation(_)))
  assert_true(run.publication_invocation_started)
  assert_true(issue(definition) is Err(WrongPhase))
  assert_eq(calls.val, before)
  assert_true(run.publication_invocation is None)
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(@resources.return_preparation_body_borrow(holder).unwrap())
  retire_installed_managed_run(run).unwrap()
  let usage = @resources.ledger_usage(parent.ledger)
  assert_eq(usage.live_reservations, 0)
  assert_eq(usage.attempts, 0)
}

///|
test "captured Event Plan adopts the same backed Request and retires without changing resource policy" {
  let (parent, input, prepared) = request_capture_fixture(
    document=captured_events_schema_budget_program,
    events=true,
  )
  let (plan, request) = request_capture_plan_fixture(prepared)
  complete_request_capture_preparation(parent, input, plan).unwrap()
  let run = begin_request_capture_managed_run(parent, request).unwrap()
  assert_true(
    physical_equal(
      installed_managed_capture_plan(run, prepared, request).unwrap(),
      plan,
    ),
  )
  assert_true(plan.capacity_plan.demand_inventory.unwrap().carrier_values)
  let original = require_installed_managed_run(run).unwrap()
  let read = begin_installed_managed_capture_read(run, 0).unwrap()
  assert_true(
    physical_equal(request_capture_ledger_fixture(run, plan).unwrap(), original),
  )
  assert_eq(@resources.ledger_limits(original).execution_bytes, 536870912L)
  assert_eq(@resources.ledger_limits(original).retained_bytes, 536870912L)
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "captured Event Program reserves its original first task on the same finite Request before Start" {
  for exhaust in [false, true] {
    let (parent, input, prepared) = request_capture_fixture(
      document=captured_events_schema_budget_program,
      events=true,
    )
    let (plan, request) = request_capture_plan_fixture(prepared)
    complete_request_capture_preparation(parent, input, plan).unwrap()
    let run = begin_request_capture_managed_run(parent, request).unwrap()
    let read = begin_installed_managed_capture_read(run, 0).unwrap()
    let ledger = request_capture_ledger_fixture(run, plan).unwrap()
    assert_true(physical_equal(ledger, parent.ledger))
    let limits = @resources.ledger_limits(ledger)
    let acquisition = prepared_installed_managed_capture_acquisition(plan, 0).unwrap()
    let rows = start_installed_source_read_rows(
      read,
      acquisition,
      "same-request-events",
      _ => true,
      4096L,
      2048L,
    ).unwrap()
    @row_source_host.begin_row_run(rows, 2048, 2, 2).unwrap()
    let bytes = @utf8.encode("[{\"id\":3,\"amount\":7}]")
    let charged = @row_source_host.charge_row_run_page(rows, bytes).unwrap()
    assert_eq(
      @row_source_host.accept_charged_row_run_page(rows, charged, bytes).unwrap(),
      1,
    )
    @row_source_host.finish_row_run(rows).unwrap()
    @row_source_host.begin_row_capture(rows).unwrap()
    let mut complete = false
    for _ in 0..<10000 {
      if @row_source_host.advance_row_capture(rows, 256).unwrap().0 {
        complete = true
        break
      }
    }
    assert_true(complete)
    let capture = @row_source_host.capture_row_run(rows).unwrap()
    let (host, dag, _) = open_installed_managed_capture_host(
      run,
      prepared,
      request,
      [@row_source_host.row_capture_source(capture).unwrap()],
    ).unwrap()
    @row_source_host.retain_row_capture_task(capture, dag, 0).unwrap()
    assert_true(physical_equal(@strategy.captured_dag_ledger(dag), ledger))
    let graph = @strategy.captured_dag_graph(dag)
    let task = @strategy.next_captured_task(dag).unwrap()
    assert_eq(task, 1)
    assert_eq(
      @strategy.captured_task_target(dag, task),
      Some(@pipeline.Step(0)),
    )
    let installed = @builtin.configured_local_module(
      @builtin.configured_host_modules(host),
    ).unwrap()
    let dispatch = @local_driver.prepare_local_managed_dispatch_with_outputs(
        installed,
        [@local_driver.local_managed_captured_relation_input()],
        @execution.process_managed_obligations(
          @strategy.graph_task_owner(graph, task).unwrap(),
        ),
        0L,
      )
      .unwrap()
      .unwrap()
    @strategy.select_captured_managed_registration(
      dag,
      task,
      @local_driver.local_dispatch_registration(installed),
    ).unwrap()
    let before = @resources.ledger_usage(ledger)
    let blocker = if exhaust {
      Some(
        @resources.reserve_capacity(
          ledger,
          0L,
          limits.execution_bytes - before.reserved_execution_bytes,
        ).unwrap(),
      )
    } else {
      None
    }
    let started = @local_driver.start_local_managed_dispatch_node(dispatch)
    let mut cleanup : (() -> Bool)? = None
    let mut stopped : (() -> Bool)? = None
    if exhaust {
      assert_true(started is Err(Execution(Physical(ExecutionLimit))))
      assert_eq(@resources.ledger_usage(ledger).attempts, before.attempts)
      assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
      @resources.settle_capacity(ledger, blocker.unwrap()).unwrap()
    } else {
      let operations = started.unwrap()
      cleanup = Some(operations.cleanup_refresh)
      stopped = Some(operations.execution_stopped)
      assert_eq(@resources.ledger_usage(ledger).attempts, before.attempts)
      assert_eq(
        @resources.ledger_usage(ledger).reserved_attempts,
        before.reserved_attempts + 1,
      )
      (operations.execute)().unwrap()
      assert_eq(@resources.ledger_usage(ledger).attempts, before.attempts + 1)
      let output_live = Ref(true)
      (operations.prepare_finalization)(task, operations.storage_bytes, () => {
        output_live.val
      }).unwrap()
      let mut finalized = false
      for _ in 0..<10000 {
        if (operations.advance_finalization)(256).unwrap().complete {
          finalized = true
          break
        }
      }
      assert_true(finalized)
      (operations.settle)().unwrap()
      let completed = (operations.complete)(task, operations.storage_bytes, () => {
        output_live.val
      }).unwrap()
      assert_eq(@execution.managed_completed_output_row_count(completed), 1)
      assert_eq(
        (operations.output_row)(0).unwrap(),
        // The exact Step(0) derives clock_ms=id and the literal label before
        // the later Events barrier. It has not produced a windowed Result.
        "{\"clock_ms\":3,\"id\":3,\"label\":\"event\"}",
      )
      output_live.val = false
      (operations.close)()
    }
    ignore(reject_client_local_run(dag))
    for output in 0..<@strategy.graph_task_count(graph) {
      @strategy.close_captured_task_output(dag, output)
    }
    retire_installed_source_read(read).unwrap()
    @strategy.refresh_captured_retention(dag)
    if cleanup is Some(refresh) {
      let mut cleaned = false
      for _ in 0..<10000 {
        let released = refresh()
        @strategy.refresh_captured_retention(dag)
        if stopped.unwrap()() && released {
          cleaned = true
          break
        }
      }
      assert_true(cleaned)
    }
    retire_installed_managed_run(run).unwrap()
    assert_eq(@resources.ledger_limits(ledger), limits)
    assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  }
}
