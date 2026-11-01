///|
// Reuse the existing independent execution-contract vector, without issuing
// a Graph before the Request's new construction reservation.
fn request_model_graph_inputs(
  prepared : @publication_host.PreparedClientProgram,
) -> (
  @publication_host.ClientInferOccurrence,
  @environment.ModelExecutionContract,
) {
  let occurrence = @publication_host.prepared_client_composed_infer_occurrence(
    prepared,
  ).unwrap()
  let execution_wire =
    #|{"backoff_contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","default_publication":"outcomes","max_attempts_per_slot":2,"max_total_attempts":4,"max_total_cost_units":0,"max_total_duration_ms":1000,"max_total_token_reservation":128,"max_total_wire_bytes":2048,"media_input_contracts":{},"model_task_contract_cid":"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560","retry_classification_contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","self_cid":"sha256:564c77f8cde8da49fda0b61b072ddce8ee598116eada536c71d27457f1b478da","version":"actql-model-execution-contract/0.1"}
  let execution = @publication_host.read_client_infer_occurrence_model_execution(
    occurrence,
    @utf8.encode(execution_wire),
    "sha256:564c77f8cde8da49fda0b61b072ddce8ee598116eada536c71d27457f1b478da",
    { max_bytes: 10000, max_nodes: 1000, max_depth: 30, max_members: 1000, },
    100000,
  ).unwrap()
  (occurrence, execution)
}

///|
test "Model Graph keeps the same Request capacity and original through sourcefree or two-capture compilation" {
  for captured in [false, true] {
    let (parent, input, prepared) = request_model_input_fixture(captured~)
    let holder = borrow_request_model_plan_input(parent, input).unwrap()
    let (occurrence, execution) = request_model_graph_inputs(prepared)
    let contracts = request_program_module_contracts()
    let manifests = request_program_module_manifests()
    let limits = @publication_host.client_standard_pure_compilation_limits()
    let capacity = parent.program_capacity.unwrap()
    let before = @resources.preparation_capacity_working_extents(
      capacity, input,
    ).unwrap()
    let graph = prepare_request_model_graph(
      parent,
      input,
      occurrence,
      execution,
      contracts,
      manifests~,
      compilation_limits=limits,
    ).unwrap()
    assert_true(
      @publication_host.client_infer_occurrence_matches_plan(occurrence, graph),
    )
    let after = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
    assert_true(after.0 > before.0 && after.1 > before.1)
    assert_true(
      parent.program_domain_compilation_inputs
      is Some(RequestModelGraph(_, _, _, original)) &&
      physical_equal(original, graph),
    )
    assert_true(
      prepare_request_model_graph(
        parent,
        input,
        occurrence,
        execution,
        contracts,
        manifests~,
        compilation_limits=limits,
      )
      is Err(Preparation(ForeignOriginal)),
    )
    assert_eq(
      @resources.preparation_capacity_working_extents(capacity, input).unwrap(),
      after,
    )
    let compilation = prepare_request_model_compilation(
      parent,
      input,
      graph,
      contracts,
      manifests~,
      compilation_limits=limits,
    ).unwrap()
    let components = @publication_host.client_task_compilation_infers(
      compilation,
    )
    assert_eq(components.length(), 1)
    assert_true(physical_equal(components[0], graph))
    assert_true(physical_equal(parent.program_capacity.unwrap(), capacity))
    assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "Model Graph original-current refusal leaves no component and retains same Request cleanup" {
  let armed = Ref(false)
  let calls = Ref(0)
  let (parent, input, prepared) = request_model_input_fixture(current=() => {
    if armed.val {
      calls.val += 1
      false
    } else {
      true
    }
  })
  let holder = borrow_request_model_plan_input(parent, input).unwrap()
  let (occurrence, execution) = request_model_graph_inputs(prepared)
  let contracts = request_program_module_contracts()
  let before = request_preparation_accounting(parent)
  armed.val = true
  assert_true(
    prepare_request_model_graph(
      parent,
      input,
      occurrence,
      execution,
      contracts,
      manifests=request_program_module_manifests(),
      compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    )
    is Err(Preparation(Capacity(_))),
  )
  armed.val = false
  assert_true(
    calls.val > 0 &&
    parent.phase == ProgramBodyFailed &&
    parent.program_domain_compilation_inputs is None &&
    parent.program_compilation is None,
  )
  assert_eq(request_preparation_accounting(parent), before)
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Model Graph retains its already backed original preparation through refused issuer reservation on the same Request" {
  let armed = Ref(false)
  let selected : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
  let (parent, input, prepared) = request_model_input_fixture(current=() => {
    if armed.val &&
      selected.val is Some(owner) &&
      owner.program_domain_compilation_inputs
      is Some(RequestModelGraphConstruction(_, _, _, _)) {
      false
    } else {
      true
    }
  })
  selected.val = Some(parent)
  let holder = borrow_request_model_plan_input(parent, input).unwrap()
  let (occurrence, execution) = request_model_graph_inputs(prepared)
  let before = @resources.preparation_capacity_working_extents(
    parent.program_capacity.unwrap(),
    input,
  ).unwrap()
  armed.val = true
  assert_true(
    prepare_request_model_graph(
      parent,
      input,
      occurrence,
      execution,
      request_program_module_contracts(),
      manifests=request_program_module_manifests(),
      compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    )
    is Err(Preparation(Capacity(_))),
  )
  armed.val = false
  assert_true(
    parent.phase == ProgramBodyFailed &&
    parent.program_domain_compilation_inputs
    is Some(RequestModelGraphConstruction(_, _, _, _)) &&
    parent.program_compilation is None,
  )
  let after = @resources.preparation_capacity_working_extents(
    parent.program_capacity.unwrap(),
    input,
  ).unwrap()
  assert_true(after.0 > before.0 && after.1 > before.1)
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(parent.program_domain_compilation_inputs is None)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "same Request retains Content component before the original serialized Model Graph constructor" {
  let (parent, input, prepared) = request_model_input_fixture(
    with_serialization=true,
  )
  let holder = borrow_request_model_plan_input(parent, input).unwrap()
  let contracts = request_program_module_contracts()
  let manifests = request_program_module_manifests()
  let compilation_limits = @publication_host.client_standard_pure_compilation_limits()
  let capacity = parent.program_capacity.unwrap()
  let component = prepare_request_serialization_graph(
    parent,
    input,
    0,
    2,
    request_graph_policy_cid,
    request_graph_policy_wire,
    1,
    128,
    false,
    contracts,
    manifests~,
    compilation_limits~,
  ).unwrap()
  assert_true(parent.phase == ModelPlanReserved)
  let (occurrence, execution) = request_model_graph_inputs(prepared)
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let graph = prepare_request_model_graph(
    parent,
    input,
    occurrence,
    execution,
    contracts,
    manifests~,
    compilation_limits~,
    serialization=Some(component),
  ).unwrap()
  let after = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  assert_true(after.0 > before.0 && after.1 > before.1)
  assert_true(physical_equal(graph.serialization.unwrap(), component))
  assert_true(
    parent.program_domain_compilation_inputs
    is Some(RequestModelGraph(_, _, _, original)) &&
    physical_equal(original, graph),
  )
  let compilation = prepare_request_model_compilation(
    parent,
    input,
    graph,
    contracts,
    manifests~,
    compilation_limits~,
  ).unwrap()
  assert_true(
    physical_equal(
      @publication_host.client_task_compilation_infers(compilation)[0],
      graph,
    ),
  )
  assert_true(
    physical_equal(
      @publication_host.client_task_compilation_serialization(compilation).unwrap(),
      component,
    ),
  )
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "same Request serialized Model Graph current refusal retains its original Content construction for abort" {
  let armed = Ref(false)
  let selected : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
  let (parent, input, prepared) = request_model_input_fixture(
    with_serialization=true,
    current=() => {
      !armed.val ||
      !(selected.val is Some(owner) &&
      owner.program_domain_compilation_inputs
      is Some(RequestModelGraphConstruction(_, _, _, _)))
    },
  )
  selected.val = Some(parent)
  let holder = borrow_request_model_plan_input(parent, input).unwrap()
  let contracts = request_program_module_contracts()
  let manifests = request_program_module_manifests()
  let compilation_limits = @publication_host.client_standard_pure_compilation_limits()
  let component = prepare_request_serialization_graph(
    parent,
    input,
    0,
    2,
    request_graph_policy_cid,
    request_graph_policy_wire,
    1,
    128,
    false,
    contracts,
    manifests~,
    compilation_limits~,
  ).unwrap()
  let (occurrence, execution) = request_model_graph_inputs(prepared)
  armed.val = true
  assert_true(
    prepare_request_model_graph(
      parent,
      input,
      occurrence,
      execution,
      contracts,
      manifests~,
      compilation_limits~,
      serialization=Some(component),
    )
    is Err(Preparation(Capacity(_))),
  )
  armed.val = false
  assert_true(
    parent.phase == ProgramBodyFailed &&
    parent.program_domain_compilation_inputs
    is Some(RequestModelGraphConstruction(_, _, _, _)),
  )
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_true(parent.program_domain_compilation_inputs is None)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
// Real Request/Graph/compiler/Scope/prefix owners. Resource admission and the
// module factory remain explicit component ports, not a physical Model call.
priv struct RequestSerializedModelFixture {
  parent : ClientRequestPreparation[Array[Int]]
  input : Array[Int]
  prepared : @publication_host.PreparedClientProgram
  holder : @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientProgram,
  ]
  contracts : ClientInstalledSequenceContracts
  occurrence : @publication_host.ClientInferOccurrence
  graph : @publication_host.ClientInferPlanGraph
  compilation : @publication_host.ClientTaskCompilation
  compiled : @publication_host.ClientCompiledRun
  definition : @publication.PublicationContract
  request : @publication_host.ClientRequestIdentity
  declaration : @row_source_host.RowDeclaration?
}

///|
fn request_serialized_model_fixture(
  current? : () -> Bool = () => true,
  single_capture? : Bool = false,
) -> RequestSerializedModelFixture raise {
  let declaration = if single_capture {
    Some(request_model_module_declaration())
  } else {
    None
  }
  let (parent, input, prepared) = request_model_input_fixture(
    with_serialization=true,
    single_capture~,
    current~,
    declaration~,
  )
  let holder = borrow_request_model_plan_input(parent, input).unwrap()
  @resources.configure_quantities(parent.ledger, {
    tokens: 128L,
    cost_units: 0L,
    duration_ms: 1000L,
  }).unwrap()
  let contracts = request_program_module_contracts()
  let manifests = request_program_module_manifests()
  let compilation_limits = @publication_host.client_standard_pure_compilation_limits()
  let component = if single_capture {
    prepare_request_acquired_serialization_graph(
      parent,
      input,
      1,
      2,
      1,
      128,
      false,
      contracts,
      manifests~,
      compilation_limits~,
    ).unwrap()
  } else {
    prepare_request_serialization_graph(
      parent,
      input,
      0,
      2,
      request_graph_policy_cid,
      request_graph_policy_wire,
      1,
      128,
      false,
      contracts,
      manifests~,
      compilation_limits~,
    ).unwrap()
  }
  let (occurrence, execution) = request_model_graph_inputs(prepared)
  let graph = prepare_request_model_graph(
    parent,
    input,
    occurrence,
    execution,
    contracts,
    manifests~,
    compilation_limits~,
    serialization=Some(component),
  ).unwrap()
  let compilation = prepare_request_model_compilation(
    parent,
    input,
    graph,
    contracts,
    manifests~,
    compilation_limits~,
  ).unwrap()
  let compiled = @publication_host.issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "serialized-model", "same-original", "2026-10-31T00:00:00.000Z", "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "serialized-model",
  ).unwrap()
  {
    parent,
    input,
    prepared,
    holder,
    contracts,
    occurrence,
    graph,
    compilation,
    compiled,
    definition,
    request,
    declaration,
  }
}

///|
test "one acquired serialized Model retains its original Query module and prefix before same Request Scope" {
  let f = request_serialized_model_fixture(single_capture=true)
  assert_eq(@publication_host.prepared_client_acquisition_count(f.prepared), 1)
  assert_eq(
    @strategy.graph_captured_prefix(
      @publication_host.prepared_client_graph(f.prepared),
    ),
    1,
  )
  let (_, execution, measurement) = client_local_execution_limits(max_rows=1)
  let prefix = prepare_request_model_serialization_plan(
    f.parent,
    f.input,
    f.request,
    f.compiled,
    f.definition,
    execution,
    measurement,
    None,
    None,
  ).unwrap()
  let calls = Ref(0)
  let original = prepare_request_model_capture_module(
    f.parent,
    f.input,
    f.request,
    f.compiled,
    f.definition,
    f.compilation,
    [f.declaration.unwrap()],
    original_row_query_contract_fixture,
    original_row_evidence_contract_fixture,
    [4096L],
    [2048L],
    f.contracts,
    true,
    0,
    _ => {
      calls.val += 1
      []
    },
  ).unwrap()
  assert_eq(calls.val, 1)
  assert_eq(original.captures.length(), 1)
  let capture = original.captures[0]
  let acquisition = capture.acquisition.unwrap()
  assert_true(
    physical_equal(
      capture.requirement,
      @row_source_host.row_acquisition_requirement(acquisition),
    ),
  )
  assert_true(
    @publication_host.client_query_requirement_matches_program(
      f.prepared,
      0,
      0,
      capture.requirement,
    ),
  )
  let plan = prepare_installed_mock_model_capture_plan_binding(
    original,
    f.compiled,
    f.definition,
    f.occurrence,
    f.graph,
    effect_model_plan_limits,
    500L,
    700L,
    20,
    20,
    20,
    content_prefix=Some(prefix),
  ).unwrap()
  let scope = prepare_request_model_read_scope(f.parent, f.input, plan).unwrap()
  complete_request_model_preparation(f.parent, f.input, plan).unwrap()
  assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
  let run = begin_request_model_managed_run(f.parent, f.request, scope).unwrap()
  assert_true(
    run.captured_preparation is Some(same) && physical_equal(same, original),
  )
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope,
      f.compiled,
      f.definition,
      f.graph,
      true,
    ).unwrap(),
  )
  assert_true(
    cleanup_installed_managed_serialization_prefix(run, prefix).unwrap(),
  )
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
}

///|
// Actual accounted RowRun/capture on the SAME Request Model Scope. The
// installation/profile/Resource and transport verifier remain explicit test
// ports; these tests issue no normal Account grant, Model send or physical IO.
priv struct RequestAcquiredModelCaptureFixture {
  original : RequestSerializedModelFixture
  prefix : ClientInstalledManagedSerializationPreparation
  module_plan : ClientInstalledManagedCapturePlan
  scope : @publication_host.ClientModelReadScope
  run : ClientInstalledManagedRun
  read : ClientInstalledSourceRead
  source : @row_source_host.RowRun
  capture : @row_source_host.RowSourceCapture
  verify_hook : Ref[(() -> Unit)?]
}

///|
fn request_acquired_model_capture_fixture(
  current? : () -> Bool = () => true,
) -> RequestAcquiredModelCaptureFixture raise {
  let f = request_serialized_model_fixture(single_capture=true, current~)
  let (_, execution, measurement) = client_local_execution_limits(max_rows=1)
  let prefix = prepare_request_model_serialization_plan(
    f.parent,
    f.input,
    f.request,
    f.compiled,
    f.definition,
    execution,
    measurement,
    None,
    None,
  ).unwrap()
  let module_plan = prepare_request_model_capture_module(
    f.parent,
    f.input,
    f.request,
    f.compiled,
    f.definition,
    f.compilation,
    [f.declaration.unwrap()],
    original_row_query_contract_fixture,
    original_row_evidence_contract_fixture,
    [4096L],
    [2048L],
    f.contracts,
    true,
    0,
    _ => [],
  ).unwrap()
  let plan = prepare_installed_mock_model_capture_plan_binding(
    module_plan,
    f.compiled,
    f.definition,
    f.occurrence,
    f.graph,
    effect_model_plan_limits,
    500L,
    700L,
    20,
    20,
    20,
    content_prefix=Some(prefix),
  ).unwrap()
  let scope = prepare_request_model_read_scope(f.parent, f.input, plan).unwrap()
  complete_request_model_preparation(f.parent, f.input, plan).unwrap()
  assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
  let run = begin_request_model_managed_run(f.parent, f.request, scope).unwrap()
  let verify_hook : Ref[(() -> Unit)?] = Ref(None)
  let (read, requirement, acquisition, capacity) = begin_installed_managed_capture_source_read(
    run,
    f.prepared,
    f.request,
    f.declaration.unwrap(),
    0,
  ).unwrap()
  assert_true(physical_equal(requirement, module_plan.captures[0].requirement))
  let ledger = prepare_installed_managed_run_ledger(
    run,
    f.prepared,
    f.request,
    [capacity],
    [4096L],
    [2048L],
    f.contracts,
    module_plan.values_body,
    module_plan.fragment_body,
    module_plan.ordered_body,
  ).unwrap()
  assert_true(physical_equal(ledger, f.parent.ledger))
  let source = start_installed_source_read_rows(
    read,
    acquisition,
    "same-request-acquired-model",
    _ => {
      if verify_hook.val is Some(hook) {
        hook()
      }
      true
    },
    4096L,
    2048L,
  ).unwrap()
  @row_source_host.begin_row_run(source, 128, 1, 1).unwrap()
  assert_eq(
    @row_source_host.accept_row_run_page(
      source,
      @utf8.encode("[{\"id\":1,\"amount\":7}]"),
    ).unwrap(),
    1,
  )
  @row_source_host.finish_row_run(source).unwrap()
  @row_source_host.begin_row_capture(source).unwrap()
  let mut complete = false
  for _ in 0..<10000 {
    if @row_source_host.advance_row_capture(source, 7).unwrap().0 {
      complete = true
      break
    }
  }
  assert_true(complete)
  let capture = @row_source_host.capture_row_run(source).unwrap()
  {
    original: f,
    prefix,
    module_plan,
    scope,
    run,
    read,
    source,
    capture,
    verify_hook,
  }
}

///|
fn request_acquired_model_capture_close(
  f : RequestAcquiredModelCaptureFixture,
) -> Unit raise {
  f.verify_hook.val = None
  assert_true(
    cleanup_installed_managed_serialization_prefix(f.run, f.prefix).unwrap(),
  )
  retire_installed_source_read(f.read).unwrap()
  let original = f.original
  assert_true(
    @publication_host.finish_client_model_read_scope(
      f.scope,
      original.compiled,
      original.definition,
      original.graph,
      true,
    ).unwrap(),
  )
  retire_installed_managed_run(f.run).unwrap()
  assert_eq(
    @resources.ledger_usage(original.parent.ledger).live_reservations,
    0,
  )
}

///|
test "same Request acquired Model prefix binds the retained original Query and keeps Source until child cleanup" {
  let f = request_acquired_model_capture_fixture()
  let original = f.original
  let ledger = original.parent.ledger
  let before = @resources.ledger_usage(ledger)
  // Empty-input entry cannot consume an acquired prefix or reserve its slot.
  assert_true(
    start_installed_managed_serialization_prefix(
      f.run,
      original.prepared,
      f.prefix,
    )
    is Err(ForeignOriginal),
  )
  assert_true(f.run.serialization_prefix is None)
  let prefix = start_installed_managed_acquired_serialization_prefix(
    f.run,
    original.prepared,
    f.prefix,
    f.capture,
  ).unwrap()
  assert_true(physical_equal(prefix.ledger, ledger))
  assert_true(
    f.run.serialization_prefix is Some(same) && physical_equal(same, prefix),
  )
  assert_true(
    f.run.captured_preparation is Some(same) &&
    physical_equal(same, f.module_plan),
  )
  let mut output : @execution.CompletedOutput? = None
  for _ in 0..<1000 {
    match advance_client_serialization_prefix(prefix, 1).unwrap() {
      @local.Complete(value, ..) => {
        output = Some(value)
        break
      }
      @local.Continue(..) | @local.Waiting(..) | @local.Settling(_, ..) => ()
      _ =>
        fail("same Request original acquired prefix failed before completion")
    }
  }
  assert_eq(@execution.completed_row_count(output.unwrap()), 1)
  assert_eq(
    @execution.completed_output_row_wire(output.unwrap(), 0, 10000, 1000, 100).unwrap(),
    "{\"id\":1,\"text\":\"hello\"}",
  )
  assert_eq(
    @resources.ledger_usage(ledger).transferred_bytes,
    before.transferred_bytes,
  )
  assert_eq(@resources.ledger_usage(ledger).holdings, before.holdings)
  assert_true(
    cleanup_installed_managed_serialization_prefix(f.run, f.prefix).unwrap(),
  )
  assert_eq(
    @query.captured_source_row_count(
      @row_source_host.row_capture_source(f.capture).unwrap(),
    ),
    Some(1),
  )
  request_acquired_model_capture_close(f)
}

///|
test "same Request acquired Model prefix refuses foreign live capture before reserving its original child" {
  let f = request_acquired_model_capture_fixture()
  let foreign = request_acquired_model_capture_fixture()
  let before = @resources.ledger_usage(f.original.parent.ledger)
  assert_true(
    start_installed_managed_acquired_serialization_prefix(
      f.run,
      f.original.prepared,
      f.prefix,
      foreign.capture,
    )
    is Err(ForeignOriginal),
  )
  assert_true(f.run.serialization_prefix is None)
  assert_eq(@resources.ledger_usage(f.original.parent.ledger), before)
  request_acquired_model_capture_close(foreign)
  request_acquired_model_capture_close(f)
}

///|
test "same Request acquired Model prefix retains its reserved child through input current refusal" {
  let current = Ref(true)
  let f = request_acquired_model_capture_fixture(current=() => current.val)
  let observed = Ref(false)
  let callback_facts = Ref(true)
  f.verify_hook.val = Some(() => {
    if f.run.serialization_prefix is Some(prefix) {
      observed.val = true
      callback_facts.val = callback_facts.val &&
        prefix.child is None &&
        cleanup_installed_managed_serialization_prefix(f.run, f.prefix)
        is Ok(false)
      current.val = false
    }
  })
  assert_true(
    start_installed_managed_acquired_serialization_prefix(
      f.run,
      f.original.prepared,
      f.prefix,
      f.capture,
    )
    is Err(_),
  )
  assert_true(observed.val)
  assert_true(callback_facts.val)
  assert_true(
    f.run.serialization_prefix is Some(prefix) &&
    prefix.child is None &&
    prefix.child_cleaned,
  )
  current.val = true
  request_acquired_model_capture_close(f)
}

///|
test "serialized Model adopts the same Request Content prefix and retains both original cleanup duties" {
  let f = request_serialized_model_fixture()
  let (_, execution, measurement) = client_local_execution_limits(max_rows=1)
  let calls = Ref(0)
  // The actual module cannot allocate providers before its prefix constructor.
  assert_true(
    prepare_request_model_source_free_module(
      f.parent,
      f.input,
      f.request,
      f.compiled,
      f.definition,
      f.compilation,
      f.contracts,
      true,
      0,
      _ => {
        calls.val += 1
        []
      },
    )
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(calls.val, 0)
  let prefix = prepare_request_model_serialization_plan(
    f.parent,
    f.input,
    f.request,
    f.compiled,
    f.definition,
    execution,
    measurement,
    None,
    None,
  ).unwrap()
  let selected_module = prepare_request_model_source_free_module(
    f.parent,
    f.input,
    f.request,
    f.compiled,
    f.definition,
    f.compilation,
    f.contracts,
    true,
    0,
    _ => {
      calls.val += 1
      []
    },
  ).unwrap()
  assert_eq(calls.val, 1)
  // An old module-only Plan cannot discard the still-live Content component.
  assert_true(
    prepare_installed_mock_model_source_free_plan(
      selected_module,
      f.request,
      f.compiled,
      f.definition,
      f.occurrence,
      f.graph,
      effect_model_plan_limits,
      500L,
      700L,
      20,
      20,
      20,
    )
    is Err(ForeignOriginal),
  )
  let plan = prepare_request_model_source_free_plan(
    f.parent,
    f.input,
    selected_module,
    f.request,
    f.compiled,
    f.definition,
    f.occurrence,
    f.graph,
    effect_model_plan_limits,
    500L,
    700L,
    20,
    20,
    20,
  ).unwrap()
  let scope = prepare_request_model_read_scope(f.parent, f.input, plan).unwrap()
  complete_request_model_preparation(f.parent, f.input, plan).unwrap()
  let run = begin_request_model_managed_run(f.parent, f.request, scope).unwrap()
  assert_true(f.parent.program_content is NoContent)
  assert_true(
    run.content is SerializationContent(original) &&
    physical_equal(original, prefix),
  )
  let quantities_before_prefix = @resources.quantity_usage(f.parent.ledger)
  let child = match
    start_installed_managed_serialization_prefix(run, f.prepared, prefix) {
    Ok(child) => child
    Err(Resource(issue)) =>
      fail("original prefix Resource: " + @debug.to_string(issue))
    Err(SerializationPrefix(Physical(issue))) =>
      fail("original prefix physical: " + @debug.to_string(issue))
    Err(SerializationPrefix(Provider(_))) =>
      fail("original prefix provider constructor")
    Err(SerializationPrefix(_)) => fail("original prefix selected child")
    Err(ForeignOriginal) => fail("original prefix tuple")
    _ => fail("original prefix lifetime")
  }
  assert_true(physical_equal(child.ledger, f.parent.ledger))
  assert_eq(
    @resources.quantity_usage(f.parent.ledger),
    quantities_before_prefix,
  )
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  let mut output = None
  for _ in 0..<1000 {
    match advance_client_serialization_prefix(child, 1).unwrap() {
      @local.Complete(value, ..) => {
        output = Some(value)
        break
      }
      @local.Continue(..) | @local.Waiting(..) | @local.Settling(_, ..) => ()
      _ => fail("original serialized Model prefix")
    }
  }
  let output = output.unwrap()
  assert_eq(@execution.completed_row_count(output), 1)
  assert_eq(
    @execution.completed_output_row_wire(output, 0, 10000, 1000, 100).unwrap(),
    "{\"id\":1,\"text\":\"hello\"}",
  )
  assert_true(
    cleanup_installed_managed_serialization_prefix(run, prefix).unwrap(),
  )
  assert_eq(
    @resources.quantity_usage(f.parent.ledger),
    quantities_before_prefix,
  )
  // Prefix ACK does not release the Model Scope or the Request borrower.
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope,
      f.compiled,
      f.definition,
      f.graph,
      true,
    ).unwrap(),
  )
  // Earlier retirement may already have returned its own durable holders.
  // The original return reports whether THIS last borrower completed cleanup;
  // either result consumes the same token and cannot be replayed.
  @resources.return_preparation_body_borrow(f.holder).unwrap() |> ignore
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
  assert_true(
    start_installed_managed_serialization_prefix(run, f.prepared, prefix)
    is Err(ForeignOriginal),
  )
}

///|
test "serialized Model prefix refusal retains original compiler and Request cleanup before any module" {
  let armed = Ref(false)
  let f = request_serialized_model_fixture(current=() => !armed.val)
  let (_, execution, measurement) = client_local_execution_limits(max_rows=1)
  armed.val = true
  assert_true(
    prepare_request_model_serialization_plan(
      f.parent,
      f.input,
      f.request,
      f.compiled,
      f.definition,
      execution,
      measurement,
      None,
      None,
    )
    is Err(Preparation(_)),
  )
  assert_true(f.parent.program_content is NoContent)
  assert_true(f.parent.program_source_free is None)
  assert_true(
    f.parent.program_compilation is Some(@publication_host.Tasks(original)) &&
    physical_equal(original, f.compilation),
  )
  assert_true(f.parent.program_domain_quote is Some(_))
  armed.val = false
  assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
  abort_request_preparation_after_cleanup(f.parent).unwrap()
  assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
}

///|
fn request_node_model_layout_profile() -> @environment.ModelResponseProfile {
  // Fixed, independently sealed vector already owned by the response-profile
  // reader tests. Its 4096/2048 declarations are SUPPORT bounds, not a normal
  // Node layout policy. No expected value is generated by the supplier.
  let wire =
    #|{"adapter":{"build_artifact_cid":"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2","builder_id":"fixture/http-builder","builder_revision":"1","codec_id":"fixture/chat-one","codec_revision":"1","port_abi":"model-physical-port/1","sdk":null},"completion":{"basis":"generation_finish","endpoint_envelope":true,"output_contract":true,"transport_eof":true,"validator_artifact_cid":"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd","validator_id":"fixture/chat-envelope","validator_revision":"1"},"controls":{"cache":false,"fallback":false,"hedging":false,"media_fetch":false,"model_requests":1,"redirect":false,"repair":false,"retry":false,"sdk_telemetry":false,"tools":false,"workflow_restore":false},"limits":{"active_slots":4,"adapter_holding_bytes":4096,"adapter_workspace_bytes":2048,"chunk_bytes":512,"chunks":16,"header_bytes":256,"metadata_bytes":128,"metadata_depth":4,"metadata_nodes":16,"parse_depth":16,"parse_nodes":256,"parse_work":8192,"request_bytes":1024,"response_bytes":2048,"unsettled_slots":4},"observations":["provider_request_id","provider_reported_model_id","finish_reason","input_tokens","output_tokens","provider_metadata"],"operation":{"endpoint":"https://fixture.invalid/v1/chat/completions","method":"POST","streaming":false},"probability":null,"self_cid":"sha256:e5d56780055a27fdfc4c522d9afb38403887afeae671fb93c4ebee8a872f7d86","task":{"contract_cid":"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560","input_schema_cid":"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7","kind":"structured_generate","output_schema_cid":"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3"},"version":"actql-model-response-profile/0.1"}
  @environment.read_model_response_profile(
    @utf8.encode(wire),
    "sha256:e5d56780055a27fdfc4c522d9afb38403887afeae671fb93c4ebee8a872f7d86",
    { max_bytes: 10000, max_nodes: 1000, max_depth: 30, max_members: 1000, },
    100000,
  ).unwrap()
}

///|
fn request_node_model_layout_installation() -> @environment.ModelResponseProfileInstallation {
  {
    builder_id: "fixture/http-builder",
    builder_revision: "1",
    codec_id: "fixture/chat-one",
    codec_revision: "1",
    build_artifact_cid: "sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2",
    sdk: None,
    endpoint: "https://fixture.invalid/v1/chat/completions",
    http_method: "POST",
    streaming: false,
    validator_id: "fixture/chat-envelope",
    validator_revision: "1",
    validator_artifact_cid: "sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd",
    completion_basis: "generation_finish",
  }
}

///|
fn request_node_model_layout_declaration(
  plan : @publication_host.ClientInferPlanGraph,
) -> @publication_host.ClientNodeModelPreparationLayout {
  // Synthetic positive envelopes exercise ownership predicates only. No byte
  // coefficient, installed runtime, physical proof or public grant is adopted.
  {
    response_profile: request_node_model_layout_profile(),
    runtime_artifact_cid: "sha256:" + "d".repeat(64),
    layout_artifact_cid: "sha256:" + "e".repeat(64),
    program_definition_cid: @publication_host.prepared_client_identity(
      plan.owner,
    ).program_definition_cid,
    parameter_values_cid: @publication_host.prepared_client_identity(plan.owner).parameter_values_cid,
    barrier_cid: plan.barrier_cid,
    prepared_rows: 2L,
    retained_bytes: 7000L,
    execution_bytes: 3000L,
  }
}

///|
fn request_node_model_plan_inputs() -> (
  RequestSerializedModelFixture,
  ClientInstalledManagedSourceFreePreparation,
  ClientInstalledManagedSerializationPreparation,
) raise {
  let f = request_serialized_model_fixture()
  let (_, execution, measurement) = client_local_execution_limits(max_rows=1)
  let prefix = prepare_request_model_serialization_plan(
    f.parent,
    f.input,
    f.request,
    f.compiled,
    f.definition,
    execution,
    measurement,
    None,
    None,
  ).unwrap()
  let selected_module = prepare_request_model_source_free_module(
    f.parent,
    f.input,
    f.request,
    f.compiled,
    f.definition,
    f.compilation,
    f.contracts,
    true,
    0,
    _ => [],
  ).unwrap()
  (f, selected_module, prefix)
}

///|
test "Request Node Model Plan retains actual layout extent before Scope read and shared prefix retirement" {
  let (f, selected_module, prefix) = request_node_model_plan_inputs()
  let layout = request_node_model_layout_declaration(f.graph)
  let installation = request_node_model_layout_installation()
  let plan = prepare_request_node_model_source_free_plan(
    f.parent,
    f.input,
    selected_module,
    f.request,
    f.compiled,
    f.definition,
    f.occurrence,
    f.graph,
    effect_model_plan_limits,
    Some(layout),
    installation,
    layout.runtime_artifact_cid,
    layout.layout_artifact_cid,
    None,
    20,
    20,
    20,
  ).unwrap()
  let scope = prepare_request_model_read_scope(f.parent, f.input, plan).unwrap()
  complete_request_model_preparation(f.parent, f.input, plan).unwrap()
  let run = begin_request_model_managed_run(f.parent, f.request, scope).unwrap()
  request_node_model_complete_prefix(run, f, prefix)
  let before = @resources.ledger_usage(f.parent.ledger)
  let read = @publication_host.prepare_client_node_model_read_layout(
    scope,
    f.compiled,
    f.definition,
    f.graph,
    Some(layout),
    installation,
    layout.runtime_artifact_cid,
    layout.layout_artifact_cid,
    None,
  ).unwrap()
  let after = @resources.ledger_usage(f.parent.ledger)
  assert_eq(
    after.reserved_retention_bytes - before.reserved_retention_bytes,
    7000L,
  )
  assert_eq(
    after.reserved_execution_bytes - before.reserved_execution_bytes,
    3000L,
  )
  let consumer = @publication_host.claim_client_node_model_preparation_layout(
    read,
    f.compiled,
    f.definition,
    f.graph,
    Some(layout),
    installation,
    layout.runtime_artifact_cid,
    layout.layout_artifact_cid,
    None,
  ).unwrap()
  @publication_host.enter_client_model_read_consumer(
    consumer,
    f.compiled,
    f.definition,
    f.graph,
    7000L,
    3000L,
  ).unwrap()
  assert_true(physical_equal(run.ledger.unwrap(), f.parent.ledger))
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  @publication_host.stop_client_model_read(read).unwrap()
  @publication_host.settle_client_model_read(read, true).unwrap()
  assert_true(
    cleanup_installed_managed_serialization_prefix(run, prefix).unwrap(),
  )
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope,
      f.compiled,
      f.definition,
      f.graph,
      true,
    ).unwrap(),
  )
  @resources.return_preparation_body_borrow(f.holder).unwrap() |> ignore
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
}

///|
test "Request Node Model Plan keeps original layout refusal before Scope and leaves same parent cleanup" {
  let (f, selected_module, _) = request_node_model_plan_inputs()
  let layout = request_node_model_layout_declaration(f.graph)
  let installation = request_node_model_layout_installation()
  let before = @resources.ledger_usage(f.parent.ledger)
  assert_true(
    prepare_request_node_model_source_free_plan(
      f.parent,
      f.input,
      selected_module,
      f.request,
      f.compiled,
      f.definition,
      f.occurrence,
      f.graph,
      effect_model_plan_limits,
      Some({ ..layout, parameter_values_cid: "sha256:" + "f".repeat(64), }),
      installation,
      layout.runtime_artifact_cid,
      layout.layout_artifact_cid,
      None,
      20,
      20,
      20,
    )
    is Err(ModelLayout(@publication_host.PreparationMismatch)),
  )
  assert_true(f.parent.program_model is None)
  assert_eq(@resources.ledger_usage(f.parent.ledger), before)
  @resources.return_preparation_body_borrow(f.holder).unwrap() |> ignore
  abort_request_preparation_after_cleanup(f.parent).unwrap()
  assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
}

///|
fn request_node_model_complete_prefix(
  run : ClientInstalledManagedRun,
  f : RequestSerializedModelFixture,
  prefix : ClientInstalledManagedSerializationPreparation,
) -> Unit raise {
  let child = start_installed_managed_serialization_prefix(
    run,
    f.prepared,
    prefix,
  ).unwrap()
  let mut complete = false
  for _ in 0..<1000 {
    match advance_client_serialization_prefix(child, 1).unwrap() {
      @local.Complete(output, ..) => {
        assert_eq(@execution.completed_row_count(output), 1)
        complete = true
        break
      }
      @local.Continue(..) | @local.Waiting(..) | @local.Settling(_, ..) => ()
      _ => fail("same original Request Model prefix")
    }
  }
  assert_true(complete)
}

///|
test "Request Node Model read issued before prefix cannot refresh or claim the changed original Ledger" {
  let (f, selected_module, prefix) = request_node_model_plan_inputs()
  let layout = request_node_model_layout_declaration(f.graph)
  let installation = request_node_model_layout_installation()
  let plan = prepare_request_node_model_source_free_plan(
    f.parent,
    f.input,
    selected_module,
    f.request,
    f.compiled,
    f.definition,
    f.occurrence,
    f.graph,
    effect_model_plan_limits,
    Some(layout),
    installation,
    layout.runtime_artifact_cid,
    layout.layout_artifact_cid,
    None,
    20,
    20,
    20,
  ).unwrap()
  let scope = prepare_request_model_read_scope(f.parent, f.input, plan).unwrap()
  complete_request_model_preparation(f.parent, f.input, plan).unwrap()
  let run = begin_request_model_managed_run(f.parent, f.request, scope).unwrap()
  let early_read = @publication_host.prepare_client_node_model_read_layout(
    scope,
    f.compiled,
    f.definition,
    f.graph,
    Some(layout),
    installation,
    layout.runtime_artifact_cid,
    layout.layout_artifact_cid,
    None,
  ).unwrap()
  request_node_model_complete_prefix(run, f, prefix)
  assert_true(
    @publication_host.claim_client_node_model_preparation_layout(
      early_read,
      f.compiled,
      f.definition,
      f.graph,
      Some(layout),
      installation,
      layout.runtime_artifact_cid,
      layout.layout_artifact_cid,
      None,
    )
    is Err(Read(Resource(@resources.ChangedOriginalState))),
  )
  // Retire this failed original; never issue a replacement read in its Scope.
  @publication_host.stop_client_model_read(early_read).unwrap()
  @publication_host.settle_client_model_read(early_read, true).unwrap()
  assert_true(
    cleanup_installed_managed_serialization_prefix(run, prefix).unwrap(),
  )
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope,
      f.compiled,
      f.definition,
      f.graph,
      true,
    ).unwrap(),
  )
  @resources.return_preparation_body_borrow(f.holder).unwrap() |> ignore
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
}
