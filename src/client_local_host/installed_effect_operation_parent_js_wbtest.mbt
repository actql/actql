///|
// Existing ordinary managed Root with explicit no-I/O current/cleanup ports.
// This is a source-component connection, not an installed artifact, physical
// backing, Account/Effect grant or successful provider operation.
// Preserve the original Array FFI/input boundary under this declaration only.
#warnings("-deprecated")
extern "js" fn effect_wrong_purpose_test_original(
  loader : PublicationTestLoader,
  plan : ClientInstalledEffectManagedPlan,
  quote : FixedArray[Int64],
  current : () -> Unit,
) -> @resources.OriginalNodeManagedRunReference =
  #|(loader,plan,quote,current) => loader('../../../../../adapters/host-node/ordinary-node-resource-runtime.cjs').retainOrdinaryManagedRun(plan,{planningWork:Number(quote[0]),attempts:Number(quote[1]),holdings:Number(quote[2]),transferBytes:quote[3],retainedBytes:quote[4],executionBytes:quote[5]},current,()=>false)

///|
fn effect_wrong_purpose_test_admission(
  plan : ClientInstalledEffectManagedPlan,
  quote : Array[Int64],
  current? : () -> Unit = () => (),
) -> @resources.NodeManagedRunAdmission[ClientInstalledEffectManagedPlan] {
  let original = effect_wrong_purpose_test_original(
    publication_test_loader(publication_test_url()),
    plan,
    FixedArray::from_array(quote),
    current,
  )
  @resources.prepare_node_managed_run_admission(original, plan).unwrap()
}

///|
// Adopt the original initial input and staged Plan through the production
// preparation-owned entry. The existing 10-byte component carrier remains
// live beside the Plan, not complete ordinary constructor funding.
fn effect_parent_test_preparation(
  plan : ClientInstalledEffectManagedPlan,
  quote : Array[Int64],
  current? : () -> Unit = () => (),
) -> (
  Array[Int],
  @resources.NodePreparationAdmission[Array[Int]],
  @resources.Ledger,
  @resources.PreparationCapacity[Array[Int], ClientInstalledEffectManagedPlan],
) {
  let original = quote.copy()
  original[4] += 10L
  original[5] += 10L
  effect_preparation_test_capacity(plan, original, current~)
}

///|
test "initial preparation adopts one original Effect plan and same Ledger through retirement" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let run = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  assert_true(
    physical_equal(
      installed_effect_managed_operation_plan(run, prepared, request).unwrap(),
      plan,
    ),
  )
  let ledger = prepare_installed_effect_managed_run_ledger(
    run,
    prepared,
    request,
    [],
    [],
    [],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  assert_eq(@resources.ledger_limits(ledger), {
    ..plan.limits,
    retained_bytes: plan.limits.retained_bytes + 10L,
    execution_bytes: plan.limits.execution_bytes + 10L,
  })
  let copied_request = @publication_host.prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "effect-operation-plan",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  assert_true(copied_request == request)
  assert_true(
    check_installed_effect_managed_run(run, prepared, copied_request)
    is Err(ForeignOriginal),
  )
  assert_true(
    prepare_installed_effect_managed_run_ledger(
      run,
      prepared,
      copied_request,
      [],
      [],
      [],
      contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
    )
    is Err(ForeignOriginal),
  )
  let foreign_contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  assert_true(
    prepare_installed_effect_managed_run_ledger(
      run,
      prepared,
      request,
      [],
      [],
      [],
      foreign_contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    physical_equal(
      prepare_installed_effect_managed_run_ledger(
        run,
        prepared,
        request,
        [],
        [],
        [],
        contracts,
        source_query_original_values,
        Some(source_query_original_fragment),
        None,
      ).unwrap(),
      ledger,
    ),
  )
  retire_installed_managed_run(run).unwrap()
  assert_true(run.preparation is None)
  assert_true(require_installed_managed_run(run) is Err(Retired))
  assert_eq(
    @resources.cleanup_node_preparation_admission(initial),
    Err(@resources.AlreadyConsumed),
  )
}

///|
test "admission for an equal-quote different Effect plan cannot begin this plan" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  let foreign = effect_operation_plan_fixture(prepared, request, contracts)
  assert_eq(
    prepared_installed_effect_managed_requirements(plan),
    prepared_installed_effect_managed_requirements(foreign),
  )
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  assert_true(
    begin_preparation_owned_installed_effect_managed_run(
      initial, input, capacity, prepared, request, foreign,
    )
    is Err(Resource(ForeignOriginal)),
  )
  // Refusing the foreign plan did not start/consume a different original.
  let run = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  retire_installed_managed_run(run).unwrap()
}

///|
test "one-short actual Effect operation refuses before allocation and retains its original cleanup" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  for field in [1, 3, 4, 5] {
    let quote = prepared_installed_effect_managed_requirements(plan)
    // First member: one physical attempt, 17 transfer bytes, 100 retained
    // bytes and 200 execution bytes. Fixed controls/body coexist separately.
    quote[field] = match field {
      1 => 0L
      3 => 16L
      4 =>
        10L +
        @execution.execution_capacity_retained_bytes(
          plan.operation_control_capacity,
        ) +
        100L -
        1L
      _ => plan.operation_control_idle_execution + 200L - 1L
    }
    let (input, initial, ledger, capacity) = effect_preparation_test_capacity(
      plan, quote,
    )
    let owner = begin_preparation_owned_installed_effect_managed_run(
      initial, input, capacity, prepared, request, plan,
    ).unwrap()
    retain_installed_effect_operation_controls_before_construction(
      owner, prepared, request, plan,
    ).unwrap()
    |> ignore
    let before = @resources.ledger_usage(ledger)
    let refused = borrow_installed_effect_operation(
      owner, prepared, request, plan, 0, false, 0, 0, "operation",
    )
    match field {
      1 => assert_true(refused is Err(Ledger(AttemptLimit)))
      3 => assert_true(refused is Err(Ledger(TransferLimit)))
      4 => assert_true(refused is Err(Ledger(RetentionLimit)))
      _ => assert_true(refused is Err(Ledger(ExecutionLimit)))
    }
    assert_eq(@resources.ledger_usage(ledger).attempts, before.attempts)
    assert_eq(
      @resources.ledger_usage(ledger).transferred_bytes,
      before.transferred_bytes,
    )
    retire_installed_managed_run(owner).unwrap()
    assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
    assert_eq(
      @resources.cleanup_node_preparation_admission(initial),
      Err(@resources.AlreadyConsumed),
    )
  }
}

///|
test "same Effect parent retains pending operation budget and never refunds consumed Starts" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let run = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  let ledger = prepare_installed_effect_managed_run_ledger(
    run,
    prepared,
    request,
    [],
    [],
    [],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  // One explicit resource use/cleanup port; no real send or ACK is implied.
  let reservation = @resources.reserve_attempt(ledger, 13L, 300L, 500L).unwrap()
  @resources.consume_reserved_attempt(ledger, reservation).unwrap()
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(
    physical_equal(
      installed_effect_managed_operation_plan(run, prepared, request).unwrap(),
      plan,
    ),
  )
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  @resources.settle_reservation(ledger, reservation).unwrap()
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  assert_eq(@resources.ledger_usage(ledger).reserved_attempts, 0)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_true(run.preparation is None)
}

///|
test "planned Source parent consumes only the original quoted acquisition and capacity" {
  let plan = effect_operation_source_plan_fixture()
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let run = begin_preparation_owned_installed_effect_managed_run(
    initial,
    input,
    capacity,
    plan.prepared,
    plan.request,
    plan,
  ).unwrap()
  let (declaration, requirement, acquisition, capacity) = prepared_installed_effect_managed_source(
    plan, 0,
  ).unwrap()
  let read = begin_installed_managed_run_source_read(run, 0).unwrap()
  attach_installed_source_read_acquisition(
    read, declaration, requirement, acquisition, 0, 0,
  ).unwrap()
  let ledger = prepare_installed_effect_managed_run_ledger(
    run,
    plan.prepared,
    plan.request,
    [capacity],
    plan.transport_bytes,
    plan.transport_execution_bytes,
    plan.installed_contracts,
    plan.values_body,
    plan.fragment_body,
    plan.ordered_body,
  ).unwrap()
  let copied = { ..capacity, }
  assert_true(
    prepare_installed_effect_managed_run_ledger(
      run,
      plan.prepared,
      plan.request,
      [copied],
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
    physical_equal(require_installed_managed_run(run).unwrap(), ledger),
  )
  // No Source start occurred; retire only these original unstarted aliases.
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(run).unwrap()
}

///|
test "physical extent membership retains original identity without another current callback" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  let current_calls = Ref(0)
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
    current=() => current_calls.val += 1,
  )
  let run = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  let physical = prepared_installed_effect_managed_operation(
    plan, 0, true, 0, "operation",
  ).unwrap()
  let pure = prepared_installed_effect_managed_operation(
    plan, 0, true, 2, "operation",
  ).unwrap()
  let before = current_calls.val
  check_installed_effect_operation_extent(run, physical).unwrap()
  assert_true(
    check_installed_effect_operation_extent(run, pure) is Err(Unsupported),
  )
  let copied = { ..physical, }
  assert_true(
    check_installed_effect_operation_extent(run, copied) is Err(ForeignOriginal),
  )
  assert_eq(current_calls.val, before)
  retire_installed_managed_run(run).unwrap()
  assert_true(
    check_installed_effect_operation_extent(run, physical)
    is Err(ForeignOriginal),
  )
}

///|
// Real checked compilation and nominal Run binding, with explicit in-memory
// publication Allow DATA. This is not actual Account/Journal admission.
fn effect_parent_bound_run(
  prepared : @publication_host.PreparedClientEffectComputation,
) -> @publication_host.PreparedClientEffectRun {
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
  let allowed = @publication_host.issue_client_effect_allowed_run(
    compiled,
    "sha256:" + "c".repeat(64),
    "sha256:" + "d".repeat(64),
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_effect_run_definition(
    allowed, "scope", "planned-effect-compute", "2026-10-25T00:00:00.000Z", "2027-01-01T00:00:00.000Z",
  ).unwrap()
  @publication_host.bind_client_effect_compiled_run(
    prepared, allowed, definition,
  ).unwrap()
}

///|
test "planned Effect Compute executes retained sequence on the original managed parent Ledger" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let factories = Ref(0)
  let plan = effect_operation_plan_fixture(prepared, request, contracts, provider_factory=_ => {
    factories.val += 1
    []
  })
  assert_eq(factories.val, 1)
  let bound = effect_parent_bound_run(prepared)
  // The selected original has one actual row. A theoretical whole-Run
  // maximum is not a startup allocation; retain a genuinely smaller policy.
  let quote = prepared_installed_effect_managed_requirements(plan)
  quote[0] -= 1L
  // The preparation fixture adds its existing ten-byte input carrier.
  quote[5] -= 11L
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan, quote,
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  let ledger = require_installed_managed_run(owner).unwrap()
  assert_false(
    installed_effect_limits_fit(plan.limits, @resources.ledger_limits(ledger)),
  )
  let (host, captured, sequences) = open_installed_effect_managed_host(
      owner,
      bound,
      [],
    )
    .unwrap()
    .unwrap()
  assert_eq(factories.val, 1)
  let installed = @builtin.configured_local_module(
    @builtin.configured_host_modules(host),
  ).unwrap()
  assert_true(
    physical_equal(
      @local_driver.local_dispatch_original_preparation(installed).unwrap(),
      plan.configuration.dispatch,
    ),
  )
  let dag = @strategy.captured_effect_run_dag(captured)
  assert_true(physical_equal(@strategy.captured_dag_ledger(dag), ledger))
  assert_true(
    physical_equal(
      @host_driver.dispatch_driver_run(@builtin.configured_host_driver(host)),
      dag,
    ),
  )
  assert_true(physical_equal(sequences, plan.sequences))
  assert_true(physical_equal(sequences[0], plan.compute_sequences[0]))
  assert_true(physical_equal(owner.source_free_captured.unwrap(), dag))
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  assert_true(
    open_installed_effect_managed_host(owner, bound, []) is Err(AlreadyBound),
  )
  let execution = execute_source_free_values_guarded(host, 64, 10000, () => true).unwrap()
  assert_eq(execution.rows().unwrap(), ["{\"id\":1}"])
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  assert_true(execution.close())
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).attempts, 1)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_true(owner.source_free_captured is None)
}

///|
test "unknown Effect capture grows its same control from completed original rows before child construction" {
  unknown_effect_capture_controls(effect_operation_source_plan_fixture())
}

///|
test "same acquired Unit pins both captured and computed original Result targets" {
  unknown_effect_capture_controls(
    effect_operation_source_plan_fixture(same_unit_results=true),
    same_unit_results=true,
  )
}

///|
test "Ledger codec uses the same grown original unknown-row controls instead of the initial zero-row quote" {
  let original = effect_operation_source_plan_fixture()
  let before = original.operations[0]
  let controls = standard_create_saved_control_capacity(1000000, 64, 4).unwrap()
  let demand = prepare_installed_effect_operation_demand_with_controls(
    original.prepared,
    before.stage_index,
    before.effect_id,
    before.member_extents,
    before.row_extents,
    controls,
  ).unwrap()
  let plan = prepare_installed_effect_managed_plan(
    original.prepared,
    original.request,
    original.declarations,
    original_row_query_contract_fixture,
    original_row_evidence_contract_fixture,
    original.transport_bytes,
    original.transport_execution_bytes,
    original.installed_contracts,
    original.values_body,
    original.fragment_body,
    original.ordered_body,
    [demand],
    provider_factory=_ => [],
  ).unwrap()
  unknown_effect_capture_controls(plan, check_codec=true)
}

///|
fn unknown_effect_capture_controls(
  plan : ClientInstalledEffectManagedPlan,
  check_codec? : Bool = false,
  same_unit_results? : Bool = false,
) -> Unit raise {
  assert_true(plan.closed_rows is None)
  // Existing fixed policy and explicit transport/current ports. This does not
  // establish normal Account/SDK/Journal funding or provider acceptance.
  let quote = prepared_installed_effect_managed_requirements(plan)
  // Known and unknown inputs share this same grow-before-use route. The
  // actual two rows below need less work than the theoretical whole-Run max.
  quote[0] -= 1L
  quote[1] += 2L
  quote[3] += 14L
  // The existing preparation fixture adds its original ten-byte carrier.
  // Keep the actual admitted policy at exactly 512 MiB, including that input.
  quote[4] = 536870902L
  quote[5] = 536870902L
  let (input, initial, ledger, capacity) = effect_parent_test_preparation(
    plan, quote,
  )
  assert_eq(@resources.ledger_limits(ledger).retained_bytes, 536870912L)
  assert_eq(@resources.ledger_limits(ledger).execution_bytes, 536870912L)
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial,
    input,
    capacity,
    plan.prepared,
    plan.request,
    plan,
  ).unwrap()
  retain_installed_effect_operation_controls_before_construction(
    owner,
    plan.prepared,
    plan.request,
    plan,
  ).unwrap()
  |> ignore
  let control = owner.effect_operation_controls.unwrap()
  let token = control.reservation
  let (read, _, acquisition, _) = begin_installed_effect_managed_source_read(
    owner,
    plan.declarations[0],
    0,
  ).unwrap()
  let rows = start_installed_source_read_rows(
    read,
    acquisition,
    "unknown-effect-original-rows",
    _ => true,
    1024L,
    2048L,
  ).unwrap()
  @row_source_host.begin_row_run(rows, 128, 3, 3).unwrap()
  // This declared record view has the ordinary rows protocol, not a Files
  // listing profile. Charge/admit its one original page through that owner.
  assert_eq(
    @row_source_host.accept_row_run_page(
      rows,
      @utf8.encode("[{\"id\":3},{\"id\":5}]"),
    ).unwrap(),
    2,
  )
  @row_source_host.finish_row_run(rows).unwrap()
  @row_source_host.begin_row_capture(rows).unwrap()
  let mut captured_source = false
  for _ in 0..<10000 {
    if @row_source_host.advance_row_capture(rows, 256).unwrap().0 {
      captured_source = true
      break
    }
  }
  assert_true(captured_source)
  let source = @row_source_host.capture_row_run(rows).unwrap()
  let bound = effect_parent_bound_run(plan.prepared)
  let (host, captured, _) = open_installed_effect_managed_host(owner, bound, [
      @row_source_host.row_capture_source(source).unwrap(),
    ])
    .unwrap()
    .unwrap()
  let dag = @strategy.captured_effect_run_dag(captured)
  @row_source_host.retain_row_capture_task(source, dag, 0).unwrap()
  let graph = @strategy.captured_dag_graph(dag)
  let output_live = Ref(true)
  let completed_operations : Array[@local_driver.LocalManagedDispatchOperations[Int]] = []
  let mut available : Array[@local_driver.LocalManagedAvailableOutput[Int]] = [
    @local_driver.local_managed_captured_relation_input(),
  ]
  let tasks = if same_unit_results { 2 } else { 1 }
  for ordinal in 0..<tasks {
    let task = @strategy.next_captured_task(dag).unwrap()
    assert_eq(task, ordinal + 1)
    let installed = @builtin.configured_local_module(
      @builtin.configured_host_modules(host),
    ).unwrap()
    // The predecessor is the already captured Source, not a managed output
    // supplied by this fixture. Select that existing typed input alternative.
    let dispatch = @local_driver.prepare_local_managed_dispatch_with_outputs(
        installed,
        available,
        @execution.process_managed_obligations(
          @strategy.graph_task_owner(graph, task).unwrap(),
        ),
        0L,
      )
      .unwrap()
      .unwrap()
    // Preparation is side-effect free. The common Host must select the SAME
    // original registration before that candidate may enter the Run lifecycle.
    @strategy.select_captured_managed_registration(
      dag,
      task,
      @local_driver.local_dispatch_registration(installed),
    ).unwrap()
    let operations = match
      @local_driver.start_local_managed_dispatch_node(dispatch) {
      Ok(value) => value
      Err(Execution(Physical(issue))) =>
        fail("UnknownEffectOriginalComputePhysical: " + @debug.to_string(issue))
      Err(Execution(ActivationNotAuthorized)) =>
        fail("UnknownEffectOriginalComputeActivationNotAuthorized")
      Err(Execution(ForeignCandidate)) =>
        fail("UnknownEffectOriginalComputeForeignCandidate")
      Err(Execution(ForeignCapture)) =>
        fail("UnknownEffectOriginalComputeForeignCapture")
      Err(Execution(NotReady)) => fail("UnknownEffectOriginalComputeNotReady")
      Err(Execution(Stopped)) => fail("UnknownEffectOriginalComputeStopped")
      Err(Execution(UnsupportedGraph)) =>
        fail("UnknownEffectOriginalComputeUnsupportedGraph")
      Err(Execution(PreviewWorkLimit)) =>
        fail("UnknownEffectOriginalComputePreviewWorkLimit")
      Err(Execution(MissingOutput)) =>
        fail("UnknownEffectOriginalComputeMissingOutput")
      Err(Execution(Capture(_))) => fail("UnknownEffectOriginalComputeCapture")
      Err(Execution(Binding(_))) => fail("UnknownEffectOriginalComputeBinding")
      Err(Execution(Read(_))) => fail("UnknownEffectOriginalComputeRead")
      Err(Execution(Compute(_))) => fail("UnknownEffectOriginalComputeCandidate")
      Err(Execution(Implementation(_))) =>
        fail("UnknownEffectOriginalComputeImplementation")
      Err(Configuration(CommonInputRows)) =>
        fail("UnknownEffectOriginalComputeCommonInputRows")
      Err(Configuration(_)) => fail("UnknownEffectOriginalComputeConfiguration")
      Err(_) => fail("UnknownEffectOriginalComputeOther")
    }
    if ordinal == 0 {
      assert_true(operations.inputs.is_empty())
    } else {
      assert_eq(operations.inputs.length(), 1)
      let previous = completed_operations[ordinal - 1]
      for transfer in operations.inputs {
        for row in 0..<2 {
          (transfer.append)((previous.output_row)(row).unwrap()).unwrap()
        }
        (transfer.finish)().unwrap()
      }
    }
    (operations.execute)().unwrap()
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
    assert_eq(@execution.managed_completed_output_row_count(completed), 2)
    completed_operations.push(operations)
    available = [@local_driver.local_managed_relation_output(completed)]
  }
  let inputs = match @strategy.pin_captured_effect_sources(
    captured, if same_unit_results { 3 } else { 2 },
  ) {
    Ok(value) => value
    Err(ForeignCandidate) => fail("Effect original Result target was routed to a foreign task")
    Err(_) => fail("Effect original Result pin failed")
  }
  assert_eq(
    @strategy.captured_effect_inputs_row_inventory(inputs, plan.rows),
    Some(2),
  )
  let before = @resources.ledger_usage(ledger)
  let copied = { ..plan, rows: plan.rows, }
  assert_true(
    retain_installed_effect_captured_input_inventory(
      owner,
      plan.prepared,
      plan.request,
      copied,
      inputs,
    )
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  // Actual input metadata is still retained by these same producer pins.
  // Exhaust remaining retention before growing the original control token;
  // refusal cannot publish row inventory or release any source/output owner.
  let limits = @resources.ledger_limits(ledger)
  let blocker = @resources.reserve_capacity(
    ledger,
    limits.retained_bytes - before.held_bytes - before.reserved_retention_bytes,
    0L,
  ).unwrap()
  let blocked = @resources.ledger_usage(ledger)
  assert_true(
    retain_installed_effect_captured_input_inventory(
      owner,
      plan.prepared,
      plan.request,
      plan,
      inputs,
    )
    is Err(Ledger(RetentionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), blocked)
  assert_true(control.captured_rows is None)
  assert_true(physical_equal(control.reservation, token))
  @resources.settle_capacity(ledger, blocker).unwrap()
  retain_installed_effect_captured_input_inventory(
    owner,
    plan.prepared,
    plan.request,
    plan,
    inputs,
  ).unwrap()
  assert_true(physical_equal(owner.effect_operation_controls.unwrap(), control))
  assert_true(physical_equal(control.reservation, token))
  assert_eq(control.captured_rows, Some(2))
  if check_codec {
    // The retained original two-row inventory has already grown this SAME
    // reservation. No Host input forest or unrelated spare capacity backs it.
    let original_reservation = control.reservation
    begin_installed_effect_operation_control_construction(
      owner,
      plan.prepared,
      plan.request,
      plan,
    ).unwrap()
    let held = @resources.ledger_usage(ledger)
    begin_installed_effect_operation_ledger_codec(
      owner,
      plan.prepared,
      plan.request,
      plan,
      None,
      64,
      4,
    ).unwrap()
    assert_true(physical_equal(control.reservation, original_reservation))
    // The next decoder coexists with the already grown two-row controls.
    // Its complete retained tree is additive until this exact codec finishes.
    let next_codec = installed_effect_contract_response_construction_capacity(
      installed_effect_control_wire_bound(1, 1000000).unwrap(),
      64,
      4,
    ).unwrap()
    assert_eq(
      @resources.ledger_usage(ledger).reserved_retention_bytes,
      held.reserved_retention_bytes +
      @execution.execution_capacity_retained_bytes(next_codec),
    )
    assert_eq(@resources.ledger_usage(ledger).attempts, held.attempts)
    assert_eq(
      @resources.ledger_usage(ledger).transferred_bytes,
      held.transferred_bytes,
    )
    complete_installed_effect_operation_ledger_codec(
      owner,
      plan.prepared,
      plan.request,
      plan,
    ).unwrap()
    assert_eq(@resources.ledger_usage(ledger), held)
    complete_installed_effect_operation_control_construction(
      owner,
      plan.prepared,
      plan.request,
      plan,
    ).unwrap()
  }
  let grown = @resources.ledger_usage(ledger)
  assert_true(grown.reserved_retention_bytes > before.reserved_retention_bytes)
  assert_eq(grown.attempts, before.attempts)
  assert_eq(grown.transferred_bytes, before.transferred_bytes)
  for index in 0..<2 {
    let child = borrow_installed_effect_operation(
      owner,
      plan.prepared,
      plan.request,
      plan,
      0,
      true,
      0,
      index,
      "operation",
    ).unwrap()
    start_installed_effect_operation(child).unwrap()
    assert_false(retire_installed_effect_operation(child, false).unwrap())
    assert_true(retire_installed_effect_operation(child, true).unwrap())
  }
  assert_true(
    borrow_installed_effect_operation(
      owner,
      plan.prepared,
      plan.request,
      plan,
      0,
      true,
      0,
      2,
      "operation",
    )
    is Err(InsufficientCapacity),
  )
  assert_true(@strategy.release_captured_effect_inputs(inputs))
  assert_eq(
    @strategy.captured_effect_inputs_row_inventory(inputs, plan.rows),
    None,
  )
  // Revoke the same publication witness after its last original input pin.
  // A permanently true witness correctly keeps the managed snapshot alive.
  output_live.val = false
  for operations in completed_operations {
    (operations.close)()
  }
  @strategy.stop_captured_dag(dag)
  for task in 1..=tasks {
    @strategy.close_captured_task_output(dag, task)
  }
  @strategy.close_captured_task_output(dag, 0)
  retire_installed_source_read(read).unwrap()
  @strategy.refresh_captured_retention(dag)
  // Logical close/stop is not the managed output's physical cleanup ACK.
  // Drive the original bounded disposal before returning the parent holder.
  let mut cleaned = false
  for _ in 0..<10000 {
    let mut stopped = true
    let mut released = true
    for operations in completed_operations {
      let original_stopped = (operations.execution_stopped)()
      let original_released = (operations.cleanup_refresh)()
      stopped = stopped && original_stopped
      released = released && original_released
    }
    @strategy.refresh_captured_retention(dag)
    if stopped && released {
      cleaned = true
      break
    }
  }
  assert_true(cleaned)
  retire_installed_managed_run(owner).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
}

///|
test "planned Effect Compute rejects foreign bound Run and fences same-parent callback reentry" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  let bound = effect_parent_bound_run(prepared)
  let foreign = effect_parent_bound_run(installed_effect_managed_fixture())
  let called = Ref(0)
  let reentry_refused = Ref(false)
  let retirement_pending = Ref(false)
  let armed = Ref(false)
  let selected : Ref[ClientInstalledManagedRun?] = Ref(None)
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
    current=() => {
      if armed.val && selected.val is Some(owner) {
        armed.val = false
        called.val += 1
        reentry_refused.val = open_installed_effect_managed_host(owner, bound, [])
          is Err(AlreadyBound)
        retirement_pending.val = retire_installed_managed_run(owner)
          is Err(CleanupPending)
      }
    },
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  selected.val = Some(owner)
  assert_true(
    open_installed_effect_managed_host(owner, foreign, [])
    is Err(ForeignOriginal),
  )
  assert_true(owner.source_free_captured is None)
  armed.val = true
  let (host, captured, _) = open_installed_effect_managed_host(owner, bound, [])
    .unwrap()
    .unwrap()
  assert_eq(called.val, 1)
  assert_true(reentry_refused.val)
  assert_true(retirement_pending.val)
  assert_true(
    physical_equal(
      owner.source_free_captured.unwrap(),
      @strategy.captured_effect_run_dag(captured),
    ),
  )
  let execution = execute_source_free_values_guarded(host, 64, 10000, () => true).unwrap()
  assert_true(execution.close())
  retire_installed_managed_run(owner).unwrap()
}

///|
extern "js" fn effect_parent_test_require_current(available : Bool) -> Unit =
  #|available => {if (!available) throw new Error('explicit test current loss');}

///|
test "planned Effect callback current loss retains original DAG cleanup and starts no task" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  let bound = effect_parent_bound_run(prepared)
  let available = Ref(true)
  let selected : Ref[ClientInstalledManagedRun?] = Ref(None)
  let armed = Ref(false)
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
    current=() => {
      if armed.val &&
        selected.val is Some(owner) &&
        owner.source_free_captured is Some(_) {
        available.val = false
      }
      effect_parent_test_require_current(available.val)
    },
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  let ledger = require_installed_managed_run(owner).unwrap()
  selected.val = Some(owner)
  armed.val = true
  let outcome = open_installed_effect_managed_host(owner, bound, [])
  assert_false(available.val)
  assert_true(outcome is Err(Resource(Unavailable)))
  assert_false(owner.source_free_opening)
  guard owner.source_free_captured is Some(dag) else {
    fail("failed configuration must retain its original cleanup DAG")
  }
  assert_true(physical_equal(@strategy.captured_dag_ledger(dag), ledger))
  assert_false(@strategy.captured_task_completed(dag, 0))
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  assert_true(
    open_installed_effect_managed_host(owner, bound, []) is Err(AlreadyBound),
  )
  retire_installed_managed_run(owner).unwrap()
  assert_true(owner.source_free_captured is None)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
}

///|
fn effect_parent_temporal_inputs() -> (
  @publication_host.PreparedClientEffectComputation,
  @publication_host.ClientRequestIdentity,
  ClientInstalledSequenceContracts,
) {
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    "sha256:05ee9059ef5f173069a3f3f1896e16ee62d34d0c842d81e9b0f8421db62e67a8",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"planned-effect-query-time","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"},{"from":"seed","derive":{"stamp":"current_timestamp()"},"as":"clock"}],"results":{"rows":{"from":"clock","fields":["id","stamp"]}},"effects":{"save":{"update":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"rows"},"id":"id","set":{"Name":{"field":"id"}}}}}}],"results":{"rows":{"from":{"stage":"main","result":"rows"}}}}
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
    "effect-temporal-parent",
    @publication_host.source_free_caller_input_intent_cid(),
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
test "temporal planned Effect executes the original sampled timestamp on the same quoted sequences and Ledger" {
  let (prepared, request, contracts) = effect_parent_temporal_inputs()
  assert_true(
    @publication_host.prepared_client_effect_requires_query_time(
      prepared, 100000, 100000,
    ).unwrap(),
  )
  let (bound, original) = effect_operation_time_run(
    prepared, request, "2026-10-25T01:02:03.123Z",
  )
  let plan = effect_operation_plan_fixture(
    prepared,
    request,
    contracts,
    query_time=Some(original),
  )
  assert_true(plan.query_time is Some(value) && physical_equal(value, original))
  let context = @publication_host.client_query_time_preparation_context(
    original,
  ).unwrap()
  for sequence in plan.sequences {
    assert_true(
      @execution.generated_sequence_query_time(sequence) is Some(value) &&
      physical_equal(value, context),
    )
  }
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  let ledger = require_installed_managed_run(owner).unwrap()
  let (foreign, other_time) = effect_operation_time_run(
    prepared, request, "2026-10-25T01:02:03.123Z",
  )
  let other_context = @publication_host.client_query_time_preparation_context(
    other_time,
  ).unwrap()
  let original_definition = @publication.query_evaluation_time_definition(
    context,
  )
  let other_definition = @publication.query_evaluation_time_definition(
    other_context,
  )
  assert_eq(
    @publication.publication_contract_identity(original_definition),
    @publication.publication_contract_identity(other_definition),
  )
  assert_false(physical_equal(original_definition, other_definition))
  assert_true(
    open_installed_effect_managed_host(owner, foreign, [])
    is Err(ForeignOriginal),
  )
  assert_true(owner.source_free_captured is None)
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  let (host, captured, sequences) = open_installed_effect_managed_host(
      owner,
      bound,
      [],
    )
    .unwrap()
    .unwrap()
  assert_true(physical_equal(sequences, plan.sequences))
  assert_true(
    physical_equal(
      @strategy.captured_dag_ledger(@strategy.captured_effect_run_dag(captured)),
      ledger,
    ),
  )
  assert_eq(plan.sequences.length(), 1)
  let execution = execute_source_free_values_guarded(host, 64, 10000, () => true).unwrap()
  assert_eq(execution.rows().unwrap(), [
    "{\"id\":1,\"stamp\":\"2026-10-25T01:02:03.123Z\"}",
  ])
  assert_eq(@resources.ledger_usage(ledger).attempts, plan.sequences.length())
  assert_true(execution.close())
  retire_installed_managed_run(owner).unwrap()
  assert_true(owner.preparation is None)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
}

///|
test "temporal plan refuses an unbound context and copied request without a second admission" {
  let (prepared, request, contracts) = effect_parent_temporal_inputs()
  let (_, original) = effect_operation_time_run(
    prepared, request, "2026-10-25T01:02:03.123Z",
  )
  let plan = effect_operation_plan_fixture(
    prepared,
    request,
    contracts,
    query_time=Some(original),
  )
  let unbound = @publication_host.prepare_client_effect_query_time(
    prepared, request, "2026-10-25T01:02:03.123Z",
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
      plan.operations,
      query_time=Some(unbound),
      provider_factory=_ => [],
    )
    is Err(Unsupported),
  )
  let copied_request = @publication_host.prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "effect-temporal-parent",
    @publication_host.source_free_caller_input_intent_cid(),
  ).unwrap()
  assert_true(request == copied_request)
  assert_false(physical_equal(request, copied_request))
  assert_true(
    prepare_installed_effect_managed_plan(
      prepared,
      copied_request,
      [],
      "",
      "",
      [],
      [],
      contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
      plan.operations,
      query_time=Some(original),
      provider_factory=_ => [],
    )
    is Err(Unsupported),
  )
}

///|
extern "js" fn effect_preparation_test_original(
  loader : PublicationTestLoader,
  input : () -> Array[Int],
  quote : FixedArray[Int64],
  current : () -> Unit,
) -> @resources.OriginalNodeManagedRunReference =
  #|(loader,input,quote,current) => loader('../../../../../adapters/host-node/ordinary-node-resource-runtime.cjs').retainOrdinaryManagedRun(input(),{planningWork:Number(quote[0]),attempts:Number(quote[1]),holdings:Number(quote[2]),transferBytes:quote[3],retainedBytes:quote[4],executionBytes:quote[5]},current,()=>false,'local-preparation')

///|
// This supplies actual original resource ports and a checked Effect plan, not
// a physical initial-family backing recipe. Tiny fixture charges deliberately
// prove transfer/borrow accounting only, not complete constructor funding.
fn effect_preparation_test_capacity(
  plan : ClientInstalledEffectManagedPlan,
  quote : Array[Int64],
  max_borrowers? : Int = 3,
  current? : () -> Unit = () => (),
) -> (
  Array[Int],
  @resources.NodePreparationAdmission[Array[Int]],
  @resources.Ledger,
  @resources.PreparationCapacity[Array[Int], ClientInstalledEffectManagedPlan],
) {
  let input = [17]
  let original = effect_preparation_test_original(
    publication_test_loader(publication_test_url()),
    () => input,
    FixedArray::from_array(quote),
    current,
  )
  let initial = @resources.prepare_node_local_preparation_admission(
    original, input,
  ).unwrap()
  let ledger = @resources.start_node_preparation_admission(initial).unwrap()
  let capacity : @resources.PreparationCapacity[
    Array[Int],
    ClientInstalledEffectManagedPlan,
  ] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    10L,
    10L,
    max_borrowers~,
  ).unwrap()
  @resources.complete_preparation_capacity(capacity, input, plan, 10L, 0L).unwrap()
  (input, initial, ledger, capacity)
}

///|
test "staged Effect plan adopts the one initial Ledger and retains its actual dispatch borrow" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  let quote = prepared_installed_effect_managed_requirements(plan)
  quote[4] += 10L
  quote[5] += 10L
  let (input, initial, ledger, capacity) = effect_preparation_test_capacity(
    plan, quote,
  )
  let run = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  assert_true(
    physical_equal(
      installed_effect_managed_operation_plan(run, prepared, request).unwrap(),
      plan,
    ),
  )
  assert_true(
    physical_equal(require_installed_managed_run(run).unwrap(), ledger),
  )
  assert_true(
    @resources.start_node_preparation_admission(initial)
    is Err(@resources.AlreadyConsumed),
  )
  assert_true(
    physical_equal(
      prepare_installed_effect_managed_run_ledger(
        run,
        prepared,
        request,
        [],
        [],
        [],
        contracts,
        source_query_original_values,
        Some(source_query_original_fragment),
        None,
      ).unwrap(),
      ledger,
    ),
  )
  let holder = borrow_installed_effect_dispatch_preparation(run, plan, request)
    .unwrap()
    .unwrap()
  assert_true(
    physical_equal(
      @resources.preparation_body_borrow_value(holder).unwrap(),
      plan,
    ),
  )
  assert_true(
    borrow_installed_effect_dispatch_preparation(run, plan, request)
    is Err(CleanupPending),
  )
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 10L)
  assert_true(installed_preparation_payload_severed(run, request))
  assert_true(
    borrow_installed_effect_dispatch_preparation(run, plan, request) is Err(_),
  )
  assert_true(@resources.return_preparation_body_borrow(holder).unwrap())
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
}

///|
test "staged Effect plan refuses foreign original input plan and request before losing cleanup" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  let copied_plan = effect_operation_plan_fixture(prepared, request, contracts)
  let copied_request = @publication_host.prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "effect-operation-plan",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  let quote = prepared_installed_effect_managed_requirements(plan)
  quote[4] += 10L
  quote[5] += 10L
  let (input, initial, ledger, capacity) = effect_preparation_test_capacity(
    plan, quote,
  )
  assert_true(
    begin_preparation_owned_installed_effect_managed_run(
      initial,
      [17],
      capacity,
      prepared,
      request,
      plan,
    )
    is Err(Resource(@resources.ForeignOriginal)),
  )
  assert_true(
    begin_preparation_owned_installed_effect_managed_run(
      initial, input, capacity, prepared, copied_request, plan,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    begin_preparation_owned_installed_effect_managed_run(
      initial, input, capacity, prepared, request, copied_plan,
    )
    is Err(Resource(@resources.ForeignOriginal)),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 10L)
  let run = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  assert_true(
    borrow_installed_effect_dispatch_preparation(run, copied_plan, request)
    is Err(ForeignOriginal),
  )
  assert_true(
    borrow_installed_effect_dispatch_preparation(run, plan, copied_request)
    is Err(ForeignOriginal),
  )
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
}

///|
test "staged Effect control one-short allocation and insufficient live borrower slots keep original cleanup" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  for field in [4, 5] {
    let quote = prepared_installed_effect_managed_requirements(plan)
    quote[field] = if field == 4 {
      10L +
      @execution.execution_capacity_retained_bytes(
        plan.operation_control_capacity,
      ) -
      1L
    } else {
      @execution.execution_capacity_execution_bytes(
        plan.operation_control_capacity,
      ) -
      1L
    }
    let (input, initial, ledger, capacity) = effect_preparation_test_capacity(
      plan, quote,
    )
    let owner = begin_preparation_owned_installed_effect_managed_run(
      initial, input, capacity, prepared, request, plan,
    ).unwrap()
    let before = @resources.ledger_usage(ledger)
    let refused = begin_installed_effect_operation_controls(
      owner, prepared, request, plan,
    )
    if field == 4 {
      assert_true(refused is Err(Ledger(RetentionLimit)))
    } else {
      assert_true(refused is Err(Ledger(ExecutionLimit)))
    }
    assert_eq(@resources.ledger_usage(ledger), before)
    retire_installed_managed_run(owner).unwrap()
    assert_eq(
      @resources.cleanup_node_preparation_admission(initial),
      Err(@resources.AlreadyConsumed),
    )
    assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  }
  let quote = prepared_installed_effect_managed_requirements(plan)
  let (input, initial, ledger, capacity) = effect_preparation_test_capacity(
    plan,
    quote,
    max_borrowers=1,
  )
  assert_true(
    begin_preparation_owned_installed_effect_managed_run(
      initial, input, capacity, prepared, request, plan,
    )
    is Err(Resource(@resources.Unavailable)),
  )
  assert_true(@resources.retire_preparation_capacity(capacity).unwrap())
  @resources.cleanup_node_preparation_admission(initial).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
}

///|
test "staged Source Effect keeps original captures and final plan on the initial Ledger" {
  let plan = effect_operation_source_plan_fixture(
    provider=Some(@execution.execution_capacity(17L, 19L).unwrap()),
  )
  let quote = prepared_installed_effect_managed_requirements(plan)
  quote[4] += 10L
  quote[5] += 10L
  let (input, initial, ledger, capacity) = effect_preparation_test_capacity(
    plan, quote,
  )
  let run = begin_preparation_owned_installed_effect_managed_run(
    initial,
    input,
    capacity,
    plan.prepared,
    plan.request,
    plan,
  ).unwrap()
  let (read, _, _, capture) = begin_installed_effect_managed_source_read(
    run,
    plan.declarations[0],
    0,
  ).unwrap()
  assert_true(physical_equal(capture, plan.captures[0]))
  assert_true(
    physical_equal(
      prepare_installed_effect_managed_run_ledger(
        run,
        plan.prepared,
        plan.request,
        [capture],
        plan.transport_bytes,
        plan.transport_execution_bytes,
        plan.installed_contracts,
        plan.values_body,
        plan.fragment_body,
        plan.ordered_body,
      ).unwrap(),
      ledger,
    ),
  )
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  retire_installed_source_read(read).unwrap()
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
}

///|
test "pure staged preparation retains its original dispatch and same generic retirement" {
  let prepared = single_source_free_capacity_prepared()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "pure-staged-retirement",
  ).unwrap()
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let source_free = prepare_installed_managed_source_free_with_contracts(
    prepared,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    retained_output=true,
    provider_factory=_ => [],
  ).unwrap()
  let input = [17]
  let quote = prepared_installed_managed_source_free_requirements(source_free)
  quote[4] += 10L
  quote[5] += 10L
  let original = effect_preparation_test_original(
    publication_test_loader(publication_test_url()),
    () => input,
    FixedArray::from_array(quote),
    () => (),
  )
  let initial = @resources.prepare_node_local_preparation_admission(
    original, input,
  ).unwrap()
  let ledger = @resources.start_node_preparation_admission(initial).unwrap()
  let capacity : @resources.PreparationCapacity[
    Array[Int],
    @publication_host.PreparedClientProgram,
  ] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    10L,
    10L,
    max_borrowers=3,
  ).unwrap()
  @resources.complete_preparation_capacity(capacity, input, prepared, 10L, 0L).unwrap()
  let run = begin_preparation_owned_installed_managed_run(
    initial, input, capacity, prepared, request, source_free,
  ).unwrap()
  let holder = borrow_installed_managed_dispatch_preparation(
      run, prepared, request,
    )
    .unwrap()
    .unwrap()
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(@resources.return_preparation_body_borrow(holder).unwrap())
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
}

///|
// Actual fixed purpose/parent ports, with no physical Model/Source supplier.
extern "js" fn effect_model_parent_test_original(
  loader : PublicationTestLoader,
  plan : ClientInstalledEffectManagedPlan,
  quote : FixedArray[Int64],
) -> @resources.OriginalNodeManagedRunReference =
  #|(loader,plan,quote) => loader('../../../../../adapters/host-node/ordinary-node-resource-runtime.cjs').retainOrdinaryManagedRun(plan,{planningWork:Number(quote[0]),attempts:Number(quote[1]),holdings:Number(quote[2]),transferBytes:quote[3],retainedBytes:quote[4],executionBytes:quote[5]},()=>{},()=>false,'local-mock-model')

///|
fn effect_model_parent_test_admission(
  plan : ClientInstalledEffectManagedPlan,
  quote : Array[Int64],
) -> @resources.NodeManagedRunAdmission[ClientInstalledEffectManagedPlan] {
  let original = effect_model_parent_test_original(
    publication_test_loader(publication_test_url()),
    plan,
    FixedArray::from_array(quote),
  )
  @resources.prepare_node_local_mock_model_run_admission(original, plan).unwrap()
}

///|
test "planned Model begins same original Scope before children and retains pending read cleanup" {
  let (prepared, request, contracts, model) = effect_model_plan_inputs()
  let calls = Ref(0)
  let plan = effect_model_plan_fixture(
    prepared, request, contracts, model, calls,
  )
  // Preserve the former ordinary-entry refusal on the new same-initial
  // path. A complete Model Plan still requires its separately selected Scope.
  let quote = prepared_installed_effect_managed_requirements(plan)
  quote[4] += 10L
  quote[5] += 10L
  let (input, initial, _, capacity) = effect_preparation_test_capacity(
    plan, quote,
  )
  assert_true(
    begin_preparation_owned_installed_effect_managed_run(
      initial, input, capacity, prepared, request, plan,
    )
    is Err(Unsupported),
  )
  assert_true(@resources.retire_preparation_capacity(capacity).unwrap())
  @resources.cleanup_node_preparation_admission(initial).unwrap()
  let admission = effect_model_parent_test_admission(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  let (run, scope) = begin_prepared_installed_effect_mock_model_managed_run(
    admission, prepared, request, plan,
  ).unwrap()
  assert_eq(calls.val, 1)
  assert_true(
    physical_equal(
      installed_effect_managed_operation_plan(run, prepared, request).unwrap(),
      plan,
    ),
  )
  assert_true(
    @publication_host.client_model_read_scope_live(
      scope,
      model.compiled,
      model.definition,
      model.graph,
    ),
  )
  let ledger = prepare_installed_effect_managed_run_ledger(
    run,
    prepared,
    request,
    [],
    [],
    [],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  assert_true(
    physical_equal(require_installed_managed_run(run).unwrap(), ledger),
  )
  let read = @publication_host.prepare_client_model_read(scope, 100L, 200L).unwrap()
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 600L)
  assert_true(retire_installed_managed_run(run) is Err(Resource(Unavailable)))
  assert_true(
    @publication_host.settle_client_model_read(read, false)
    is Err(Resource(@resources.CleanupPending)),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 600L)
  @publication_host.settle_client_model_read(read, true).unwrap()
  retire_installed_managed_run(run).unwrap()
  assert_true(
    !@publication_host.client_model_read_scope_live(
      scope,
      model.compiled,
      model.definition,
      model.graph,
    ),
  )
  assert_true(
    begin_prepared_installed_effect_mock_model_managed_run(
      admission, prepared, request, plan,
    )
    is Err(Resource(AlreadyConsumed)),
  )
  assert_eq(calls.val, 1)
}

///|
test "planned Model refuses wrong purpose foreign original and short envelope with original cleanup" {
  let (prepared, request, contracts, model) = effect_model_plan_inputs()
  let calls = Ref(0)
  let plan = effect_model_plan_fixture(
    prepared, request, contracts, model, calls,
  )
  let wrong = effect_wrong_purpose_test_admission(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  assert_true(
    begin_prepared_installed_effect_mock_model_managed_run(
      wrong, prepared, request, plan,
    )
    is Err(Resource(Unavailable)),
  )
  @resources.cleanup_node_managed_run_admission(wrong).unwrap()
  let foreign = effect_model_plan_fixture(
    prepared, request, contracts, model, calls,
  )
  let admitted = effect_model_parent_test_admission(
    plan,
    prepared_installed_effect_managed_requirements(plan),
  )
  assert_true(
    begin_prepared_installed_effect_mock_model_managed_run(
      admitted, prepared, request, foreign,
    )
    is Err(Resource(ForeignOriginal)),
  )
  let (run, _) = begin_prepared_installed_effect_mock_model_managed_run(
    admitted, prepared, request, plan,
  ).unwrap()
  retire_installed_managed_run(run).unwrap()
  for field in [0, 1, 2, 3, 4, 5] {
    let quote = prepared_installed_effect_managed_requirements(plan)
    quote[field] -= 1L
    let short = effect_model_parent_test_admission(plan, quote)
    assert_true(
      begin_prepared_installed_effect_mock_model_managed_run(
        short, prepared, request, plan,
      )
      is Err(InsufficientCapacity),
    )
    @resources.cleanup_node_managed_run_admission(short).unwrap()
  }
  assert_eq(calls.val, 2)
}

///|
test "same original planned parent lookup observes physical current once" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  let calls = Ref(0)
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
    current=() => calls.val += 1,
  )
  let run = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  calls.val = 0
  let ledger = require_installed_managed_run(run).unwrap()
  assert_true(physical_equal(run.ledger.unwrap(), ledger))
  // Count the actual original physical-owner callback, not a Result unwrap,
  // function entry, Plan getter hit or another compilation/capacity quote.
  assert_eq(calls.val, 1)
  retire_installed_managed_run(run).unwrap()
}

///|
test "bound Plan getter checks exact immutable originals and calls current once" {
  let (prepared, request, contracts) = effect_operation_plan_inputs()
  let plan = effect_operation_plan_fixture(prepared, request, contracts)
  let calls = Ref(0)
  let (input, initial, _, capacity) = effect_parent_test_preparation(
    plan,
    prepared_installed_effect_managed_requirements(plan),
    current=() => calls.val += 1,
  )
  let run = begin_preparation_owned_installed_effect_managed_run(
    initial, input, capacity, prepared, request, plan,
  ).unwrap()
  calls.val = 0
  let original = installed_effect_managed_operation_plan(run, prepared, request).unwrap()
  assert_true(physical_equal(original, plan))
  assert_eq(calls.val, 1)
  let copy = { ..run, }
  let equal_request = @publication_host.prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "effect-operation-plan",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  assert_true(equal_request == request)
  calls.val = 0
  assert_true(
    installed_effect_managed_operation_plan(copy, prepared, request)
    is Err(ForeignOriginal),
  )
  assert_true(
    installed_effect_managed_operation_plan(run, prepared, equal_request)
    is Err(ForeignOriginal),
  )
  assert_true(
    installed_effect_managed_operation_plan(
      run,
      installed_effect_managed_fixture(),
      request,
    )
    is Err(ForeignOriginal),
  )
  assert_eq(calls.val, 0)
  retire_installed_managed_run(run).unwrap()
  assert_true(
    installed_effect_managed_operation_plan(run, prepared, request)
    is Err(Unsupported),
  )
}

///|
test "one current callback cannot retire or replace the original planned Run tuple" {
  for replace in [false, true] {
    let (prepared, request, contracts) = effect_operation_plan_inputs()
    let plan = effect_operation_plan_fixture(prepared, request, contracts)
    let foreign_plan = effect_operation_plan_fixture(
      prepared, request, contracts,
    )
    let selected : Ref[ClientInstalledManagedRun?] = Ref(None)
    let original : Ref[ClientInstalledManagedRunOriginal?] = Ref(None)
    let calls = Ref(0)
    let armed = Ref(false)
    let (input, initial, _, capacity) = effect_parent_test_preparation(
      plan,
      prepared_installed_effect_managed_requirements(plan),
      current=() => {
        calls.val += 1
        if armed.val && selected.val is Some(run) {
          armed.val = false
          if replace && original.val is Some(PlannedEffectManaged(a, _)) {
            run.preparation = Some(PlannedEffectManaged(a, foreign_plan))
          } else {
            run.preparation = None
          }
        }
      },
    )
    let run = begin_preparation_owned_installed_effect_managed_run(
      initial, input, capacity, prepared, request, plan,
    ).unwrap()
    selected.val = Some(run)
    original.val = run.preparation
    calls.val = 0
    armed.val = true
    assert_true(
      installed_effect_managed_operation_plan(run, prepared, request)
      is Err(Retired),
    )
    assert_eq(calls.val, 1)
    // Restore only this private test's artificial tuple mutation so the
    // original admission owns its actual normal cleanup; no new Run/owner.
    run.preparation = original.val
    retire_installed_managed_run(run).unwrap()
  }
}

///|
test "cold inventory grows original symbolic member backing without opening or refunding physical work" {
  let original = effect_operation_source_plan_fixture()
  let fixed = @execution.execution_capacity(13L, 17L).unwrap()
  let per_row = @execution.execution_capacity(37L, 61L).unwrap()
  let recovery_extent = prepare_installed_effect_capture_extent(
    "recovery", fixed, per_row,
  ).unwrap()
  let demand = prepare_installed_effect_operation_demand(
    original.prepared,
    original.operations[0].stage_index,
    original.operations[0].effect_id,
    [recovery_extent],
    original.operations[0].row_extents,
  ).unwrap()
  let plan = prepare_installed_effect_managed_plan(
    original.prepared,
    original.request,
    original.declarations,
    original_row_query_contract_fixture,
    original_row_evidence_contract_fixture,
    original.transport_bytes,
    original.transport_execution_bytes,
    original.installed_contracts,
    original.values_body,
    original.fragment_body,
    original.ordered_body,
    [demand],
    provider_factory=_ => [],
  ).unwrap()
  assert_true(plan.closed_rows is None)
  let quote = prepared_installed_effect_managed_requirements(plan)
  let (input, initial, ledger, capacity) = effect_parent_test_preparation(
    plan, quote,
  )
  let owner = begin_preparation_owned_installed_effect_managed_run(
    initial,
    input,
    capacity,
    plan.prepared,
    plan.request,
    plan,
  ).unwrap()
  retain_installed_effect_operation_controls_before_construction(
    owner,
    plan.prepared,
    plan.request,
    plan,
  ).unwrap()
  |> ignore
  let control = owner.effect_operation_controls.unwrap()
  let reservation = control.reservation
  assert_true(owner.source_free_captured is None)
  assert_true(
    retain_installed_effect_operation_construction(
      owner,
      plan.prepared,
      plan.request,
      plan,
      0,
      false,
      0,
      0,
      "recovery",
    )
    is Err(InsufficientCapacity),
  )
  let before = @resources.ledger_usage(ledger)
  let limits = @resources.ledger_limits(ledger)
  let blocker = @resources.reserve_capacity(
    ledger,
    limits.retained_bytes - before.held_bytes - before.reserved_retention_bytes,
    0L,
  ).unwrap()
  let blocked = @resources.ledger_usage(ledger)
  let preparation = owner.preparation.unwrap()
  let admission = match preparation {
    PlannedEffectManaged(admission, _) => admission
    _ => fail("expected original Effect Plan")
  }
  assert_true(
    retain_installed_effect_control_row_inventory(
      owner,
      preparation,
      admission,
      plan,
      ledger,
      control,
      2,
      () => Ok(()),
    )
    is Err(Ledger(RetentionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), blocked)
  assert_true(control.captured_rows is None)
  assert_true(physical_equal(control.reservation, reservation))
  @resources.settle_capacity(ledger, blocker).unwrap()
  retain_installed_effect_control_row_inventory(
    owner,
    preparation,
    admission,
    plan,
    ledger,
    control,
    2,
    () => Ok(()),
  ).unwrap()
  assert_eq(control.captured_rows, Some(2))
  assert_true(physical_equal(control.reservation, reservation))
  let child = retain_installed_effect_operation_construction(
    owner,
    plan.prepared,
    plan.request,
    plan,
    0,
    false,
    0,
    0,
    "recovery",
  ).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(child.extent.unwrap().capacity),
    87L,
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(
      child.extent.unwrap().capacity,
    ),
    139L,
  )
  begin_installed_effect_operation_construction(child).unwrap()
  complete_installed_effect_operation_construction(child).unwrap()
  assert_true(retire_installed_effect_operation(child, true).unwrap())
  assert_eq(@resources.ledger_usage(ledger).attempts, before.attempts)
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    before.transferred_bytes,
  )
  retire_installed_managed_run(owner).unwrap()
}
