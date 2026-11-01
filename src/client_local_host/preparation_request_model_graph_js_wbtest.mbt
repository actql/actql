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
}

///|
fn request_serialized_model_fixture(
  current? : () -> Bool = () => true,
) -> RequestSerializedModelFixture raise {
  let (parent, input, prepared) = request_model_input_fixture(
    with_serialization=true,
    current~,
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
  }
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
  assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
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
