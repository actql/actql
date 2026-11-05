///|
// The real Effect compiler/borrower precedes Model Graph construction. No
// Graph, Model Plan or Scope is constructed to manufacture these inputs.
fn request_effect_model_graph_inputs(
  current? : () -> Bool = () => true,
) -> (
  ClientRequestPreparation[Array[Int]],
  Array[Int],
  @publication_host.PreparedClientEffectComputation,
  @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientEffectComputation,
  ],
  @publication_host.ClientInferOccurrence,
  @environment.ModelExecutionContract,
) raise {
  let (environment, document) = effect_model_plan_source()
  let initial = @resources.add_ledger_limits(
    client_local_preparation_initial_limits(client_local_resource_policy()).unwrap(),
    effect_model_plan_limits,
  ).unwrap()
  let (parent, child, _, input) = registration_parent_fixture(
    current~,
    text=document,
    environment=Some(environment),
    effect_limits=Some(
      @publication_host.client_standard_effect_computation_limits(),
    ),
    initial_limits=Some(initial),
  )
  finish_effect_program_check_preparation(child).unwrap() |> ignore
  let prepared = compile_effect_program_check_preparation(child).unwrap()
  assert_true(
    physical_equal(
      continue_request_effect_preparation(parent, input).unwrap(),
      prepared,
    ),
  )
  let holder = borrow_request_effect_plan_input(parent, input).unwrap()
  let occurrence = @publication_host.prepared_client_effect_infer_occurrence(
    prepared,
  ).unwrap()
  let wire =
    #|{"backoff_contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","default_publication":"outcomes","max_attempts_per_slot":2,"max_total_attempts":4,"max_total_cost_units":0,"max_total_duration_ms":1000,"max_total_token_reservation":128,"max_total_wire_bytes":2048,"media_input_contracts":{},"model_task_contract_cid":"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560","retry_classification_contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","self_cid":"sha256:564c77f8cde8da49fda0b61b072ddce8ee598116eada536c71d27457f1b478da","version":"actql-model-execution-contract/0.1"}
  let execution = @publication_host.read_client_infer_occurrence_model_execution(
    occurrence,
    @utf8.encode(wire),
    "sha256:564c77f8cde8da49fda0b61b072ddce8ee598116eada536c71d27457f1b478da",
    { max_bytes: 10000, max_nodes: 1000, max_depth: 30, max_members: 1000, },
    100000,
  ).unwrap()
  (parent, input, prepared, holder, occurrence, execution)
}

///|
test "Effect Model Graph grows its same Request before measuring and issuing the original component" {
  let (parent, input, prepared, holder, occurrence, execution) = request_effect_model_graph_inputs()
  let capacity = parent.effect_capacity.unwrap()
  let ledger = parent.ledger
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let graph = prepare_request_model_graph(
    parent,
    input,
    occurrence,
    execution,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
  ).unwrap()
  let after = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  assert_true(after.0 > before.0 && after.1 > before.1)
  assert_true(physical_equal(parent.effect_capacity.unwrap(), capacity))
  assert_true(physical_equal(parent.ledger, ledger))
  assert_true(physical_equal(parent.compiled_effect.unwrap(), prepared))
  assert_true(
    parent.compiled_program is None && parent.program_capacity is None,
  )
  assert_true(parent.phase == EffectPlanReserved)
  assert_true(
    @publication_host.client_infer_occurrence_matches_plan(occurrence, graph),
  )
  assert_true(
    parent.program_domain_compilation_inputs
    is Some(RequestModelGraph(_, _, _, original)) &&
    physical_equal(original, graph),
  )
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
test "Effect Model Graph refuses current loss before each constructor and retains the same failed child" {
  for denied in [1, 2] {
    let armed = Ref(false)
    let calls = Ref(0)
    let (parent, input, _, holder, occurrence, execution) = request_effect_model_graph_inputs(current=() => {
        if !armed.val {
          return true
        }
        calls.val += 1
        calls.val != denied
      },
    )
    let capacity = parent.effect_capacity.unwrap()
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
    assert_true(parent.phase == EffectBodyFailed)
    assert_true(physical_equal(parent.effect_capacity.unwrap(), capacity))
    assert_true(parent.program_domain_quote is Some(_))
    if denied == 1 {
      assert_true(parent.program_domain_compilation_inputs is None)
    } else {
      assert_true(
        parent.program_domain_compilation_inputs
        is Some(RequestModelGraphConstruction(_, _, _, _)),
      )
    }
    armed.val = false
    assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_true(parent.program_domain_compilation_inputs is None)
    assert_eq(@resources.ledger_usage(parent.ledger).held_bytes, 0L)
  }
}

///|
test "Effect Model Graph refuses another original occurrence without debiting its Request" {
  let (parent, input, _, holder, _, _) = request_effect_model_graph_inputs()
  let (foreign, _, _, foreign_holder, occurrence, execution) = request_effect_model_graph_inputs()
  let before = request_preparation_accounting(parent)
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
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(request_preparation_accounting(parent), before)
  assert_true(parent.program_domain_compilation_inputs is None)
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_false(
    @resources.return_preparation_body_borrow(foreign_holder).unwrap(),
  )
  abort_request_preparation_after_cleanup(foreign).unwrap()
}

///|
test "Effect Model Graph transfers its same component to Scope and clears only the adopted Request alias" {
  let (parent, input, prepared, holder, occurrence, execution) = request_effect_model_graph_inputs()
  let graph = prepare_request_model_graph(
    parent,
    input,
    occurrence,
    execution,
    request_program_module_contracts(),
    manifests=request_program_module_manifests(),
    compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
  ).unwrap()
  let compilation = @publication_host.issue_prepared_client_effect_compilation(
    prepared,
    request_program_module_manifests(),
    @publication_host.client_standard_values_sequence_limits(),
    1000,
    10000,
    1000000,
    100000,
    100,
    infer=Some(graph),
  ).unwrap()
  let allowed = @publication_host.issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_effect_run_definition(
    allowed, "Model-plan", "same-original", "2026-10-26T00:00:00.000Z", "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let compiled = @publication_host.client_effect_allowed_infer_run_with_policy_body(
    allowed,
    Some(
      "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563",
    ),
    Some(
      "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}",
    ),
    10000,
    1000,
    20,
  ).unwrap()
  let model = prepare_installed_effect_model_demand(
    prepared, compiled, compilation, definition, occurrence, graph, effect_model_plan_limits,
    500L, 700L, 20, 20, 20,
  ).unwrap()
  let request = @publication_host.prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "effect-graph-original",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  let plan = effect_model_plan_fixture(
    prepared,
    request,
    request_program_module_contracts(),
    model,
    Ref(0),
  )
  let scope = prepare_request_effect_model_read_scope(parent, input, plan).unwrap()
  assert_true(
    parent.program_domain_compilation_inputs
    is Some(RequestModelGraph(_, _, _, original)) &&
    physical_equal(original, graph),
  )
  complete_request_effect_preparation(parent, input, plan).unwrap()
  @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
  let run = begin_request_effect_model_managed_run(parent, request, scope).unwrap()
  assert_true(parent.program_domain_compilation_inputs is None)
  assert_true(parent.program_domain_quote is None)
  assert_true(physical_equal(plan.model.unwrap().graph, graph))
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope, compiled, definition, graph, true,
    ).unwrap(),
  )
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  assert_eq(@resources.ledger_usage(parent.ledger).held_bytes, 0L)
}

///|
// Reuse the existing independent execution-contract vector, without issuing
// a Graph before the Request's new construction reservation.
fn request_model_graph_inputs(
  prepared : @publication_host.PreparedClientProgram,
  selected? : @publication_host.ClientInferOccurrence? = None,
) -> (
  @publication_host.ClientInferOccurrence,
  @environment.ModelExecutionContract,
) {
  let occurrence = match selected {
    Some(original) => original
    None =>
      @publication_host.prepared_client_composed_infer_occurrence(prepared).unwrap()
  }
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
  two_captures? : Bool = false,
  serialized? : Bool = true,
  nonterminal? : Bool = false,
  authored? : String? = None,
) -> RequestSerializedModelFixture raise {
  let declaration = if single_capture || two_captures {
    Some(request_model_module_declaration())
  } else {
    None
  }
  let (parent, input, prepared) = request_model_input_fixture(
    with_serialization=serialized,
    authored~,
    captured=two_captures,
    single_capture~,
    nonterminal~,
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
  let component = if !serialized {
    None
  } else if single_capture {
    Some(
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
      ).unwrap(),
    )
  } else {
    Some(
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
      ).unwrap(),
    )
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
    serialization=component,
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
test "single generic acquired Model binds original Request module and Scope without a Node layout" {
  let f = request_serialized_model_fixture(
    single_capture=true,
    serialized=false,
  )
  let provider = @execution.execution_capacity(7L, 9L).unwrap()
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
    _ => [],
    providers=Some([Some(provider)]),
  ).unwrap()
  let before = @resources.ledger_usage(f.parent.ledger)
  assert_true(
    prepare_request_model_capture_plan(
      f.parent,
      f.input.copy(),
      original,
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
  assert_eq(@resources.ledger_usage(f.parent.ledger), before)
  let plan = prepare_request_model_capture_plan(
    f.parent,
    f.input,
    original,
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
  assert_true(plan.content_prefix is None)
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
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
}

///|
test "single native Model retains original Request Query capacity without a Row declaration" {
  let f = request_serialized_model_fixture(
    single_capture=true,
    serialized=false,
  )
  let loader = publication_test_loader(publication_test_url())
  let source_ref = f.declaration.unwrap().views[0].source_ref
  let capacity = f.parent.program_capacity.unwrap()
  let before = @resources.preparation_capacity_working_extents(
    capacity,
    f.input,
  ).unwrap()
  let original = prepare_request_model_capture_module(
    f.parent,
    f.input,
    f.request,
    f.compiled,
    f.definition,
    f.compilation,
    [],
    capture_parent_contract(loader, "actql-query-acquisition.json"),
    capture_parent_contract(loader, "actql-query-process-evidence.json"),
    [4096L],
    [2048L],
    f.contracts,
    true,
    0,
    _ => [],
    native_source_ref=Some(source_ref),
    native_database_schema=Some("main"),
    native_table=Some("records"),
    native_receipt_body=Some(
      capture_parent_contract(loader, "actql-query-two-receipt.json"),
    ),
  ).unwrap()
  let after = @resources.preparation_capacity_working_extents(capacity, f.input).unwrap()
  let legacy = request_model_material_body_bytes(3, index => {
    capture_parent_contract(
      loader,
      if index == 0 {
        "actql-query-acquisition.json"
      } else if index == 1 {
        "actql-query-process-evidence.json"
      } else {
        "actql-query-two-receipt.json"
      },
    )
  }).unwrap()
  // These actual protocols contain long schema Strings. Preserve the old
  // live Request debit, without adding a hypothetical node per wire byte.
  assert_true(after.0 > before.0 && after.1 > before.1)
  assert_true(after.0 - before.0 < legacy)
  assert_true(after.1 - before.1 < legacy)
  let query_peak = request_local_query_construction_bytes().unwrap()
  // Finished Query writers and native protocol parse frames are absent from
  // the returned module. The original Query/documents and earlier debit live.
  assert_true(after.0 - before.0 < query_peak)
  assert_true(after.1 - before.1 < query_peak)
  assert_eq(original.captures.length(), 1)
  let capture = original.captures[0]
  assert_false(capture.original_input)
  assert_true(capture.acquisition is None && capture.provider is None)
  assert_eq(
    @planning.query_requirement_source(capture.requirement).0,
    source_ref,
  )
  let plan = prepare_request_model_capture_plan(
    f.parent,
    f.input,
    original,
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
  assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
  let run = begin_request_model_managed_run(f.parent, f.request, scope).unwrap()
  let (requirement, same_capture) = installed_managed_duckdb_capture(
    run,
    f.prepared,
    f.request,
    0,
  ).unwrap()
  assert_true(physical_equal(capture, same_capture))
  assert_true(physical_equal(capture.requirement, requirement))
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope,
      f.compiled,
      f.definition,
      f.graph,
      true,
    ).unwrap(),
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
  _source : @row_source_host.RowRun
  capture : @row_source_host.RowSourceCapture
  verify_hook : Ref[(() -> Unit)?]
}

///|
fn request_acquired_model_capture_fixture(
  current? : () -> Bool = () => true,
  provider? : @execution.ExecutionCapacity? = None,
  provider_stopped? : () -> Bool = () => true,
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
    providers=provider.map(value => [Some(value)]),
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
  let verify = _ => {
    if verify_hook.val is Some(hook) {
      hook()
    }
    true
  }
  let started = match provider {
    None =>
      start_installed_source_read_rows(
        read, acquisition, "same-request-acquired-model", verify, 4096L, 2048L,
      )
    Some(value) =>
      start_installed_source_read_provider_rows(
        read,
        acquisition,
        Some(value),
        "same-request-acquired-model",
        verify,
        4096L,
        2048L,
      )
  }
  let source = match started {
    Ok(value) => value
    Err(Acquisition(@row_source_host.Physical(issue))) =>
      fail("same Request managed Source physical: " + @debug.to_string(issue))
    Err(Resource(issue)) =>
      fail("same Request managed Source Resource: " + @debug.to_string(issue))
    Err(_) => fail("same Request managed Source non-physical refusal")
  }
  @row_source_host.begin_row_run(source, 128, 1, 1).unwrap()
  if provider is Some(_) {
    let responses = @row_source_host.borrow_row_run_responses(
      source, acquisition,
    ).unwrap()
    @row_source_host.bind_row_run_response_borrow_cleanup(
      responses, provider_stopped,
    ).unwrap()
  }
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
  let quantities = @resources.quantity_usage(f.parent.ledger)
  assert_eq(quantities.consumed.tokens, 0L)
  assert_eq(quantities.consumed.cost_units, 0L)
  assert_eq(quantities.consumed.duration_ms, 0L)
  assert_eq(quantities.reserved.tokens, 0L)
  assert_eq(quantities.uncertain.tokens, 0L)
  {
    original: f,
    prefix,
    module_plan,
    scope,
    run,
    read,
    _source: source,
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
    "{\"amount\":7,\"id\":1,\"text\":\"hello\"}",
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

///|
test "Request acquired Node Model binds original provider and physical Plan on the same parent before Scope" {
  let f = request_serialized_model_fixture(single_capture=true)
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
  let provider = @execution.execution_capacity(7L, 9L).unwrap()
  let calls = Ref(0)
  // A missing original provider cannot enter any Query/module constructor.
  assert_true(
    prepare_request_model_capture_module(
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
      providers=Some([None]),
    )
    is Err(Installed(Unsupported)),
  )
  assert_eq(calls.val, 0)
  assert_true(f.parent.program_captured is None)
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
    providers=Some([Some(provider)]),
  ).unwrap()
  assert_eq(calls.val, 1)
  let capture = original.captures[0]
  assert_true(
    installed_provider_row_capture_capacity_matches(
      capture,
      capture.acquisition.unwrap(),
      provider,
    ),
  )
  let layout = request_node_model_layout_declaration(f.graph)
  let installation = request_node_model_layout_installation()
  assert_true(
    prepare_request_node_model_capture_plan(
      f.parent,
      f.input,
      original,
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
  let plan = prepare_request_node_model_capture_plan(
    f.parent,
    f.input,
    original,
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
  assert_true(plan.content_prefix is Some(same) && physical_equal(same, prefix))
  let scope = prepare_request_model_read_scope(f.parent, f.input, plan).unwrap()
  complete_request_model_preparation(f.parent, f.input, plan).unwrap()
  assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
  let run = begin_request_model_managed_run(f.parent, f.request, scope).unwrap()
  assert_eq(
    installed_managed_source_input_kind(run, f.prepared, f.request).unwrap(),
    "query",
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
// Real checked one-Source occurrence, compiler, provider capacity and shared
// Scope. Resource admission/physical transport are explicit component ports;
// no normal Account, Model send, Store operation or ACK is issued here.
fn request_plain_captured_model_case(
  authored? : String? = None,
  consume_input? : Bool = false,
) -> Unit raise {
  let f = request_serialized_model_fixture(
    single_capture=true,
    serialized=false,
    authored~,
  )
  assert_true(f.graph.serialization is None)
  assert_true(
    @publication_host.client_task_compilation_serialization(f.compilation)
    is None,
  )
  let before = @resources.preparation_capacity_working_extents(
    f.parent.program_capacity.unwrap(),
    f.input,
  ).unwrap()
  let provider = @execution.execution_capacity(7L, 9L).unwrap()
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
    _ => [],
    providers=Some([Some(provider)]),
  ).unwrap()
  let after = @resources.preparation_capacity_working_extents(
    f.parent.program_capacity.unwrap(),
    f.input,
  ).unwrap()
  assert_true(after.0 > before.0 && after.1 > before.1)
  assert_true(
    installed_provider_row_capture_capacity_matches(
      original.captures[0],
      original.captures[0].acquisition.unwrap(),
      provider,
    ),
  )
  let layout = request_node_model_layout_declaration(f.graph)
  let plan = prepare_request_node_model_capture_plan(
    f.parent,
    f.input,
    original,
    f.request,
    f.compiled,
    f.definition,
    f.occurrence,
    f.graph,
    effect_model_plan_limits,
    Some(layout),
    request_node_model_layout_installation(),
    layout.runtime_artifact_cid,
    layout.layout_artifact_cid,
    None,
    20,
    20,
    20,
  ).unwrap()
  assert_true(plan.content_prefix is None)
  let scope = prepare_request_model_read_scope(f.parent, f.input, plan).unwrap()
  complete_request_model_preparation(f.parent, f.input, plan).unwrap()
  assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
  let run = begin_request_model_managed_run(f.parent, f.request, scope).unwrap()
  let (read, requirement, acquisition, capacity) = begin_installed_managed_capture_source_read(
    run,
    f.prepared,
    f.request,
    f.declaration.unwrap(),
    0,
  ).unwrap()
  assert_true(
    physical_equal(acquisition, original.captures[0].acquisition.unwrap()),
  )
  assert_true(physical_equal(requirement, original.captures[0].requirement))
  assert_true(
    prepare_installed_managed_run_ledger(
      run,
      f.prepared,
      f.request,
      [{ ..capacity, }],
      [4096L],
      [2048L],
      f.contracts,
      f.contracts.original.values_body,
      f.contracts.original.fragment_body,
      f.contracts.original.ordered_body,
    )
    is Err(ForeignOriginal),
  )
  let ledger = prepare_installed_managed_run_ledger(
    run,
    f.prepared,
    f.request,
    [capacity],
    [4096L],
    [2048L],
    f.contracts,
    f.contracts.original.values_body,
    f.contracts.original.fragment_body,
    f.contracts.original.ordered_body,
  ).unwrap()
  assert_true(physical_equal(ledger, f.parent.ledger))
  if consume_input {
    let source = start_installed_source_read_rows(
      read,
      acquisition,
      "same-unit-model-input",
      _ => true,
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
    let mut captured = false
    for _ in 0..<10000 {
      if @row_source_host.advance_row_capture(source, 7).unwrap().0 {
        captured = true
        break
      }
    }
    assert_true(captured)
    let original_source = @row_source_host.row_capture_source(
      @row_source_host.capture_row_run(source).unwrap(),
    ).unwrap()
    let prefix = installed_managed_run_model_input_prefix(run, f.prepared).unwrap()
    let (_, execution, measurement) = client_local_execution_limits(max_rows=1)
    let mapping : @execution.InferPreparationLimits = {
      max_items: 1,
      max_work: 100000,
      max_frames: 100,
      max_workspace_slots: 10000,
      values: { max_nodes: 10000, max_depth: 100, max_text_bytes: 10000, },
      logical: {
        max_input_rows: 1L,
        max_value_bytes: 10000L,
        max_live_value_bytes: 100000L,
        max_work: 100000L,
      },
    }
    let before = @resources.ledger_usage(ledger)
    // The old whole-prefix/empty-input route keeps its exact refusal.
    assert_true(
      start_client_composed_infer_input(
        f.occurrence,
        prefix,
        [],
        execution,
        measurement,
        mapping,
      )
      is Err(Local(@connector.Execution(@execution.InputSet))),
    )
    let child = start_client_composed_infer_input(
      f.occurrence,
      prefix,
      [],
      execution,
      measurement,
      mapping,
      captured=Some((f.prepared, original_source)),
    ).unwrap()
    assert_true(
      physical_equal(
        @execution.generated_sequence_owner(child.sequence.unwrap()),
        @execution.generated_sequence_owner(prefix),
      ),
    )
    assert_true(
      physical_equal(
        @execution.generated_prepared_sequence(child.sequence.unwrap()),
        @execution.generated_prepared_sequence(prefix),
      ),
    )
    assert_eq(@resources.ledger_usage(ledger), before)
    let mut mapped = None
    for _ in 0..<10000 {
      match advance_client_infer_input(child, 1).unwrap() {
        Continue(..) => ()
        Complete(rows, ..) => {
          mapped = Some(rows)
          break
        }
        _ =>
          abort(
            "the retained capture must reach Model rows without scan replay",
          )
      }
    }
    let rows = mapped.unwrap()
    assert_eq(@execution.prepared_infer_rows_count(rows), 1)
    assert_true(
      @execution.prepared_infer_rows_value(rows, 0, 0).unwrap().value
      is @admitted.Text("hello"),
    )
    assert_eq(@resources.ledger_usage(ledger), before)
    assert_true(cleanup_client_infer_input(child).unwrap())
    assert_true(@query.captured_source_statistics(original_source) is Some(_))
    @row_source_host.close_accounted_row_run(source).unwrap()
    assert_true(
      start_client_composed_infer_input(
        f.occurrence,
        prefix,
        [],
        execution,
        measurement,
        mapping,
        captured=Some((f.prepared, original_source)),
      )
      is Err(Capture(@query.Unavailable)),
    )
  }
  retire_installed_source_read(read).unwrap()
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope,
      f.compiled,
      f.definition,
      f.graph,
      true,
    ).unwrap(),
  )
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
}

///|
test "plain acquired Model constructs its original Graph module and Source reader on one Request without Content" {
  request_plain_captured_model_case()
}

///|
test "same Unit captured Model consumes its original generated prefix without replaying Source" {
  let document =
    #|{"version":"actql/0.1","id":"same-unit-captured-model","stages":[{"id":"main","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id >= 0"},{"select":["id","amount"],"as":"selected"},{"derive":{"text":{"literal":"hello"}}},{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"classified"}],"results":{"rows":{"from":"classified","fields":["id","outcome","value"]}}}],"results":{"rows":{"from":{"stage":"main","result":"rows"}}}}
  request_plain_captured_model_case(authored=Some(document), consume_input=true)
}

///|
test "plain acquired Model original occurrence gate does not widen ordinary purpose or accept another Prepared" {
  let declaration = request_model_module_declaration()
  let (parent, input, prepared) = request_model_input_fixture(
    single_capture=true,
    declaration=Some(declaration),
  )
  let holder = borrow_request_model_plan_input(parent, input).unwrap()
  let (foreign, foreign_input, foreign_prepared) = request_model_input_fixture()
  let foreign_holder = borrow_request_model_plan_input(foreign, foreign_input).unwrap()
  let (occurrence, execution) = request_model_graph_inputs(prepared)
  let (other, _) = request_model_graph_inputs(foreign_prepared)
  assert_false(installed_managed_run_shape_supported(prepared, false))
  assert_false(installed_managed_run_shape_supported(prepared, true))
  assert_true(
    installed_managed_owner_shape_supported(
      Pure(prepared),
      true,
      model_occurrence=Some(occurrence),
    ),
  )
  assert_false(
    installed_managed_owner_shape_supported(
      Pure(prepared),
      true,
      model_occurrence=Some(other),
    ),
  )
  let before = request_preparation_accounting(parent)
  assert_true(
    prepare_request_model_graph(
      parent,
      input,
      other,
      execution,
      request_program_module_contracts(),
      manifests=request_program_module_manifests(),
      compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
    )
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(request_preparation_accounting(parent), before)
  assert_true(parent.program_domain_compilation_inputs is None)
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  assert_false(
    @resources.return_preparation_body_borrow(foreign_holder).unwrap(),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  abort_request_preparation_after_cleanup(foreign).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  assert_eq(@resources.ledger_usage(foreign.ledger).live_reservations, 0)
}

///|
test "plain Node Model input lowering is backed on the same Request before module provider factory" {
  let f = request_serialized_model_fixture(
    single_capture=true,
    serialized=false,
  )
  let before = @resources.preparation_capacity_working_extents(
    f.parent.program_capacity.unwrap(),
    f.input,
  ).unwrap()
  let provider = @execution.execution_capacity(7L, 9L).unwrap()
  let containers = request_model_module_container_bytes(
    @strategy.graph_task_count(
      @publication_host.prepared_client_graph(f.prepared),
    ),
    1,
    0,
    provider_captures=1,
  ).unwrap()
  let protocols = request_model_material_body_bytes(2, index => {
    if index == 0 {
      original_row_query_contract_fixture
    } else {
      original_row_evidence_contract_fixture
    }
  }).unwrap()
  let query = request_local_query_construction_bytes().unwrap()
  let input = program_check_data_extent_cost(f.parent.program_data.unwrap()).unwrap()
  // One real pre-INFER lowering; this fixture's original occurrence is terminal.
  assert_true(@publication_host.client_infer_occurrence_terminal(f.occurrence))
  let required = containers + protocols + query + input
  let observed = Ref(false)
  prepare_request_model_capture_module(
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
      let current = @resources.preparation_capacity_working_extents(
        f.parent.program_capacity.unwrap(),
        f.input,
      ).unwrap()
      observed.val = current.0 >= before.0 + required &&
        current.1 >= before.1 + required
      []
    },
    providers=Some([Some(provider)]),
  ).unwrap()
  |> ignore
  assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
  abort_request_preparation_after_cleanup(f.parent).unwrap()
  assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
  assert_true(observed.val)
}

///|
test "plain Model module retains its original input segments without getters preparing again" {
  for nonterminal in [false, true] {
    let ticks = Ref(0)
    let f = request_serialized_model_fixture(
      single_capture=true,
      serialized=false,
      nonterminal~,
      current=() => {
        ticks.val += 1
        true
      },
    )
    let provider = @execution.execution_capacity(7L, 9L).unwrap()
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
      _ => [],
      providers=Some([Some(provider)]),
    ).unwrap()
    let before = @resources.preparation_capacity_working_extents(
      f.parent.program_capacity.unwrap(),
      f.input,
    ).unwrap()
    let calls = ticks.val
    let prefix = prepared_request_model_input_prefix(original).unwrap()
    assert_true(
      original.model_input_prefix is Some(same) && physical_equal(prefix, same),
    )
    assert_true(
      physical_equal(
        prefix,
        prepared_request_model_input_prefix(original).unwrap(),
      ),
    )
    let suffix = prepared_request_model_input_suffix(original).unwrap()
    assert_eq(suffix is Some(_), nonterminal)
    assert_true(
      match (suffix, original.model_input_suffix) {
        (None, None) => true
        (Some(a), Some(b)) => physical_equal(a, b)
        _ => false
      },
    )
    assert_eq(ticks.val, calls)
    assert_eq(
      @resources.preparation_capacity_working_extents(
        f.parent.program_capacity.unwrap(),
        f.input,
      ).unwrap(),
      before,
    )
    assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
    abort_request_preparation_after_cleanup(f.parent).unwrap()
    assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
  }
}

///|
test "plain Model refused input construction keeps the same parent and enters no provider factory" {
  let armed = Ref(false)
  let selected : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
  let threshold = Ref(0L)
  let observed = Ref(false)
  let f = request_serialized_model_fixture(
    single_capture=true,
    serialized=false,
    current=() => {
      if armed.val &&
        selected.val is Some(owner) &&
        owner.program_domain_quote is Some((r, _)) &&
        r >= threshold.val {
        observed.val = true
        false
      } else {
        true
      }
    },
  )
  selected.val = Some(f.parent)
  let before = @resources.preparation_capacity_working_extents(
    f.parent.program_capacity.unwrap(),
    f.input,
  ).unwrap()
  let variable = program_check_data_extent_cost(f.parent.program_data.unwrap()).unwrap()
  let controls = request_model_module_container_bytes(
    @strategy.graph_task_count(
      @publication_host.prepared_client_graph(f.prepared),
    ),
    1,
    0,
    provider_captures=1,
    input_segments=1,
  ).unwrap()
  threshold.val = before.0 + controls + variable
  let factories = Ref(0)
  armed.val = true
  assert_true(
    prepare_request_model_capture_module(
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
        factories.val += 1
        []
      },
      providers=Some([Some(@execution.execution_capacity(7L, 9L).unwrap())]),
    )
    is Err(Preparation(Capacity(_))),
  )
  armed.val = false
  assert_true(observed.val)
  assert_eq(factories.val, 0)
  assert_true(f.parent.program_captured is None)
  assert_true(f.parent.phase == ProgramBodyFailed)
  assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
  abort_request_preparation_after_cleanup(f.parent).unwrap()
  assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
}

///|
// The component is an explicit pure constructor port, not a physical Model
// supplier or egress grant. The actual parent debit and prefix are native.
test "plain Model component factory receives the already backed original input before module configuration" {
  let f = request_serialized_model_fixture(
    single_capture=true,
    serialized=false,
  )
  let calls = Ref(0)
  let captured : Ref[@execution.GeneratedSequence?] = Ref(None)
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
    1,
    _ => [],
    providers=Some([Some(@execution.execution_capacity(7L, 9L).unwrap())]),
    component_factory=Some((capacity, prefix, suffix) => {
      calls.val += 1
      captured.val = Some(prefix)
      // No physical execution can be started by this fixture component.
      @local.managed_provider(_ => suffix is None, _ => Some(capacity), (
        _,
        _,
        _,
        _,
        _,
      ) => Err(@connector.ComputeUnsupported))
    }),
  ).unwrap()
  assert_eq(calls.val, 1)
  assert_true(
    captured.val is Some(prefix) &&
    physical_equal(
      prefix,
      prepared_request_model_input_prefix(original).unwrap(),
    ),
  )
  assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
  abort_request_preparation_after_cleanup(f.parent).unwrap()
  assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
}

///|
test "two Source singleton Model component keeps its backed original prefix and suffix before configuration" {
  for nonterminal in [false, true] {
    let f = request_serialized_model_fixture(
      two_captures=true,
      serialized=false,
      nonterminal~,
    )
    let before = @resources.preparation_capacity_working_extents(
      f.parent.program_capacity.unwrap(),
      f.input,
    ).unwrap()
    let segments = if nonterminal { 2 } else { 1 }
    let containers = request_model_module_container_bytes(
      @strategy.graph_task_count(
        @publication_host.prepared_client_graph(f.prepared),
      ),
      2,
      1,
      input_segments=segments,
      model_components=1,
    ).unwrap()
    let protocols = request_model_material_body_bytes(2, index => {
      if index == 0 {
        original_row_query_contract_fixture
      } else {
        original_row_evidence_contract_fixture
      }
    }).unwrap()
    let queries = request_local_query_construction_bytes().unwrap() * 2L
    let inputs = program_check_data_extent_cost(f.parent.program_data.unwrap()).unwrap() *
      segments.to_int64()
    let required = containers + protocols + queries + inputs
    let calls = Ref(0)
    let backed = Ref(false)
    let prefix : Ref[@execution.GeneratedSequence?] = Ref(None)
    let suffix : Ref[@execution.GeneratedSequence?] = Ref(None)
    let original = prepare_request_model_capture_module(
      f.parent,
      f.input,
      f.request,
      f.compiled,
      f.definition,
      f.compilation,
      [f.declaration.unwrap(), f.declaration.unwrap()],
      original_row_query_contract_fixture,
      original_row_evidence_contract_fixture,
      [4096L, 4096L],
      [2048L, 2048L],
      f.contracts,
      true,
      1,
      _ => [],
      component_factory=Some((capacity, original_prefix, original_suffix) => {
        let current = @resources.preparation_capacity_working_extents(
          f.parent.program_capacity.unwrap(),
          f.input,
        ).unwrap()
        backed.val = current.0 >= before.0 + required &&
          current.1 >= before.1 + required
        calls.val += 1
        prefix.val = Some(original_prefix)
        suffix.val = original_suffix
        @local.managed_provider(_ => false, _ => Some(capacity), (_, _, _, _, _) => {
          Err(@connector.ComputeUnsupported)
        })
      }),
    ).unwrap()
    assert_eq(calls.val, 1)
    assert_true(backed.val)
    assert_eq(original.captures.length(), 2)
    assert_true(physical_equal(f.parent.program_captured.unwrap(), original))
    assert_true(
      prefix.val is Some(value) &&
      physical_equal(value, original.model_input_prefix.unwrap()),
    )
    if nonterminal {
      assert_true(
        suffix.val is Some(value) &&
        physical_equal(value, original.model_input_suffix.unwrap()),
      )
    } else {
      assert_true(suffix.val is None && original.model_input_suffix is None)
    }
    assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
    abort_request_preparation_after_cleanup(f.parent).unwrap()
    assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
    assert_eq(@resources.ledger_usage(f.parent.ledger).held_bytes, 0L)
  }
}

///|
test "two Source singleton Model component refuses original current loss before its constructor" {
  let current = Ref(true)
  let f = request_serialized_model_fixture(
    two_captures=true,
    serialized=false,
    current=() => current.val,
  )
  let calls = Ref(0)
  current.val = false
  assert_true(
    prepare_request_model_capture_module(
      f.parent,
      f.input,
      f.request,
      f.compiled,
      f.definition,
      f.compilation,
      [f.declaration.unwrap(), f.declaration.unwrap()],
      original_row_query_contract_fixture,
      original_row_evidence_contract_fixture,
      [4096L, 4096L],
      [2048L, 2048L],
      f.contracts,
      true,
      1,
      _ => [],
      component_factory=Some((capacity, _, _) => {
        calls.val += 1
        @local.managed_provider(_ => false, _ => Some(capacity), (_, _, _, _, _) => {
          Err(@connector.ComputeUnsupported)
        })
      }),
    )
    is Err(Preparation(Capacity(_))),
  )
  assert_eq(calls.val, 0)
  assert_true(f.parent.program_captured is None)
  current.val = true
  assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
  abort_request_preparation_after_cleanup(f.parent).unwrap()
  assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
  assert_eq(@resources.ledger_usage(f.parent.ledger).held_bytes, 0L)
}

///|
test "same Request acquired Model prefix keeps live provider backing until original Source cleanup" {
  let stopped = Ref(false)
  let f = request_acquired_model_capture_fixture(
    provider=Some(@execution.execution_capacity(7L, 9L).unwrap()),
    provider_stopped=() => stopped.val,
  )
  let original = f.original
  let ledger = original.parent.ledger
  let before = @resources.ledger_usage(ledger)
  // The captured provider still owns its original scratch/cleanup allowance.
  // Prefix borrowing is neither physical retirement nor a released byte grant.
  assert_true(before.reserved_execution_bytes > 0L)
  let prefix = start_installed_managed_acquired_serialization_prefix(
    f.run,
    original.prepared,
    f.prefix,
    f.capture,
  ).unwrap()
  assert_true(physical_equal(prefix.ledger, ledger))
  assert_true(
    @resources.ledger_usage(ledger).reserved_execution_bytes >=
    before.reserved_execution_bytes,
  )
  let mut complete = false
  for _ in 0..<1000 {
    match advance_client_serialization_prefix(prefix, 1).unwrap() {
      @local.Complete(value, ..) => {
        assert_eq(@execution.completed_row_count(value), 1)
        complete = true
        break
      }
      @local.Continue(..) | @local.Waiting(..) | @local.Settling(_, ..) => ()
      _ => fail("retained provider prefix did not complete")
    }
  }
  assert_true(complete)
  assert_true(
    cleanup_installed_managed_serialization_prefix(f.run, f.prefix).unwrap(),
  )
  assert_true(@row_source_host.row_capture_source(f.capture) is Ok(_))
  assert_true(retire_installed_source_read(f.read) is Err(_))
  assert_true(@resources.ledger_usage(ledger).live_reservations > 0)
  assert_false(stopped.val)
  stopped.val = true
  request_acquired_model_capture_close(f)
}

///|
// Actual checked Program, native graph constructors and one Request compiler.
// Synthetic component initial allowances are not an installed Host/provider
// recipe or normal runtime/physical qualification.

///|
fn request_two_model_document() -> String {
  (
    #|{"version":"actql/0.1","id":"request-two-models","stages":[{"id":"input","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"text":{"type":"string","nullable":true}},"rows":[{"id":"a","text":"hello"}]},"as":"items"}],"results":{"rows":{"from":"items","fields":["id","text"]}}},{"id":"first","inputs":{"rows":{"result":{"stage":"input","result":"rows"}}},"steps":[{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"assessment"}],"results":{"rows":{"from":"assessment","fields":["id","outcome","value"]}}},{"id":"second","inputs":{"rows":{"result":{"stage":"input","result":"rows"}}},"steps":[{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"assessment"}],"results":{"rows":{"from":"assessment","fields":["id","outcome","value"]}}}],"results":{"first":{"from":{"stage":"first","result":"rows"}},"second":{"from":{"stage":"second","result":"rows"}}}}
  )
}

///|
test "multiple Model graphs retain complete original order on one Request compiler" {
  let document = request_two_model_document()
  let (parent, input, prepared) = request_model_input_fixture(
    authored=Some(document),
  )
  let holder = borrow_request_model_plan_input(parent, input).unwrap()
  let occurrences = @publication_host.prepared_client_composed_infer_occurrences(
    prepared,
  ).unwrap()
  assert_eq(occurrences.length(), 2)
  let contracts = request_program_module_contracts()
  let manifests = request_program_module_manifests()
  let limits = @publication_host.client_standard_pure_compilation_limits()
  let graphs : Array[@publication_host.ClientInferPlanGraph] = []
  for occurrence in occurrences {
    let (_, execution) = request_model_graph_inputs(
      prepared,
      selected=Some(occurrence),
    )
    graphs.push(
      prepare_request_model_graph(
        parent,
        input,
        occurrence,
        execution,
        contracts,
        manifests~,
        compilation_limits=limits,
      ).unwrap(),
    )
  }
  guard parent.program_domain_compilation_inputs
    is Some(RequestModelGraphs(_, _, _, originals)) else {
    fail("complete Request-owned graph vector")
  }
  assert_eq(originals.length(), 2)
  assert_true(physical_equal(originals[0], graphs[0]))
  assert_true(physical_equal(originals[1], graphs[1]))
  let capacity = parent.program_capacity.unwrap()
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  assert_true(
    prepare_request_models_compilation(
      parent,
      input,
      [graphs[1], graphs[0]],
      contracts,
      manifests~,
      compilation_limits=limits,
    )
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input).unwrap(),
    before,
  )
  let compiled = prepare_request_models_compilation(
    parent,
    input,
    graphs,
    contracts,
    manifests~,
    compilation_limits=limits,
  ).unwrap()
  assert_eq(compiled.infers.length(), 2)
  assert_true(physical_equal(compiled.infers[0], graphs[0]))
  assert_true(physical_equal(compiled.infers[1], graphs[1]))
  assert_true(physical_equal(parent.program_capacity.unwrap(), capacity))
  let compiled_run = @publication_host.issue_client_task_compiled_run(
    prepared,
    compiled,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled_run, "two-model-original-module", "same-original", "2026-10-31T00:00:00.000Z",
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "two-model-original-module",
  ).unwrap()
  let entries : Array[Int] = []
  let backed = Ref(true)
  let before_module = @resources.preparation_capacity_working_extents(
    capacity, input,
  ).unwrap()
  let original_module_value = prepare_request_model_source_free_module(
    parent,
    input,
    request,
    compiled_run,
    definition,
    compiled,
    contracts,
    true,
    0,
    _ => [],
    components_factory=Some((index, extent, _, _) => {
      let during = @resources.preparation_capacity_working_extents(
        capacity, input,
      ).unwrap()
      backed.val = backed.val &&
        during.0 > before_module.0 &&
        during.1 > before_module.1
      entries.push(index)
      @local.managed_provider(_ => false, _ => Some(extent), (_, _, _, _, _) => {
        Err(@connector.ComputeUnsupported)
      })
    }),
  ).unwrap()
  assert_eq(entries, [0, 1])
  assert_true(backed.val)
  assert_true(
    parent.program_source_free is Some(original_module) &&
    physical_equal(original_module, original_module_value),
  )
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
// Actual shared Request/check/compiler/module/Plan/Scope/adoption/retirement.
// The two physical providers remain explicit ports, not ordinary Model IO.

///|
priv struct RequestTwoModelPlanFixture {
  parent : ClientRequestPreparation[Array[Int]]
  input : Array[Int]
  prepared : @publication_host.PreparedClientProgram
  holder : @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientProgram,
  ]
  occurrences : Array[@publication_host.ClientInferOccurrence]
  graphs : Array[@publication_host.ClientInferPlanGraph]
  compiled : @publication_host.ClientCompiledRun
  definition : @publication.PublicationContract
  request : @publication_host.ClientRequestIdentity
  selected_module : ClientInstalledManagedSourceFreePreparation
  module_entries : Array[Int]
}

///|
fn request_two_model_plan_fixture(
  current? : () -> Bool = () => true,
) -> RequestTwoModelPlanFixture raise {
  let (parent, input, prepared) = request_model_input_fixture(
    authored=Some(request_two_model_document()),
    model_copies=2,
    current~,
  )
  let holder = borrow_request_model_plan_input(parent, input).unwrap()
  let occurrences = @publication_host.prepared_client_composed_infer_occurrences(
    prepared,
  ).unwrap()
  let contracts = request_program_module_contracts()
  let manifests = request_program_module_manifests()
  let limits = @publication_host.client_standard_pure_compilation_limits()
  let graphs : Array[@publication_host.ClientInferPlanGraph] = []
  for occurrence in occurrences {
    let (_, execution) = request_model_graph_inputs(
      prepared,
      selected=Some(occurrence),
    )
    graphs.push(
      prepare_request_model_graph(
        parent,
        input,
        occurrence,
        execution,
        contracts,
        manifests~,
        compilation_limits=limits,
      ).unwrap(),
    )
  }
  let compilation = prepare_request_models_compilation(
    parent,
    input,
    graphs,
    contracts,
    manifests~,
    compilation_limits=limits,
  ).unwrap()
  let compiled = @publication_host.issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "two-model-aggregate", "original", "2026-11-04T00:00:00.000Z", "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "two-model-aggregate",
  ).unwrap()
  let module_entries : Array[Int] = []
  let selected_module = prepare_request_model_source_free_module(
    parent,
    input,
    request,
    compiled,
    definition,
    compilation,
    contracts,
    true,
    0,
    _ => [],
    components_factory=Some((index, extent, _, _) => {
      module_entries.push(index)
      @local.managed_provider(_ => false, _ => Some(extent), (_, _, _, _, _) => {
        Err(@connector.ComputeUnsupported)
      })
    }),
  ).unwrap()
  {
    parent,
    input,
    prepared,
    holder,
    occurrences,
    graphs,
    compiled,
    definition,
    request,
    selected_module,
    module_entries,
  }
}

///|
test "two Model Request adopts one module and all original scopes with one aggregate demand and child first retirement" {
  let f = request_two_model_plan_fixture()
  let {
    parent,
    input,
    prepared: _,
    holder,
    occurrences,
    graphs,
    compiled,
    definition,
    request,
    selected_module,
    module_entries,
  } = f
  let ledger = parent.ledger
  let before_plan = @resources.preparation_capacity_working_extents(
    parent.program_capacity.unwrap(),
    input,
  ).unwrap()
  let plan = prepare_request_models_source_free_plan(
    parent,
    input,
    selected_module,
    request,
    compiled,
    definition,
    occurrences,
    graphs,
    [effect_model_plan_limits, effect_model_plan_limits],
    [7L, 9L],
    [5L, 6L],
    40,
    40,
    40,
    bootstrap=Some((31L, 37L)),
  ).unwrap()
  assert_eq(module_entries, [0, 1])
  // One original module demand, two Model demands, total read partitions,
  // and the independent same-parent bootstrap exactly once.
  assert_eq(
    plan.limits.planning_work,
    selected_module.limits.planning_work + 34,
  )
  assert_eq(plan.limits.attempts, selected_module.limits.attempts + 8)
  assert_eq(
    plan.limits.retained_bytes,
    selected_module.limits.retained_bytes + 2000L + 16L + 31L,
  )
  assert_eq(
    plan.limits.execution_bytes,
    selected_module.limits.execution_bytes + 4000L + 11L + 37L,
  )
  let after_plan = @resources.preparation_capacity_working_extents(
    parent.program_capacity.unwrap(),
    input,
  ).unwrap()
  assert_true(after_plan.0 > before_plan.0 && after_plan.1 > before_plan.1)
  assert_true(physical_equal(parent.ledger, ledger))
  assert_true(
    prepare_request_model_read_scope(parent, input, plan)
    is Err(ForeignOriginal),
  )
  let scopes = prepare_request_models_read_scopes(parent, input, plan).unwrap()
  assert_eq(scopes.length(), 2)
  complete_request_model_preparation(parent, input, plan).unwrap()
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  // Another group order cannot adopt the first Scope as a proxy for all.
  assert_true(
    begin_request_model_managed_run(
      parent,
      request,
      scopes[0],
      scopes=Some([scopes[1], scopes[0]]),
    )
    is Err(ForeignOriginal),
  )
  let run = begin_request_model_managed_run(
    parent,
    request,
    scopes[0],
    scopes=Some(scopes),
  ).unwrap()
  assert_true(physical_equal(run.ledger.unwrap(), ledger))
  let second = @publication_host.prepare_client_model_read(scopes[1], 9L, 6L).unwrap()
  let first = @publication_host.prepare_client_model_read(scopes[0], 7L, 5L).unwrap()
  @publication_host.settle_client_model_read(first, true).unwrap()
  assert_false(
    @publication_host.finish_client_model_read_scope(
      scopes[0],
      compiled,
      definition,
      graphs[0],
      true,
    ).unwrap(),
  )
  assert_true(
    @publication_host.settle_client_model_read(second, false)
    is Err(@publication_host.Resource(@resources.CleanupPending)),
  )
  @publication_host.settle_client_model_read(second, true).unwrap()
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scopes[1],
      compiled,
      definition,
      graphs[1],
      true,
    ).unwrap(),
  )
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  assert_eq(@resources.ledger_usage(ledger).held_bytes, 0L)
}

///|
test "two Model Plan current mutation refuses changed original read partition and preserves its failed construction for abort" {
  let armed = Ref(false)
  let retained = [7L, 9L]
  let f = request_two_model_plan_fixture(current=() => {
    if armed.val {
      retained[0] = -1L
    }
    true
  })
  let capacity = f.parent.program_capacity.unwrap()
  let ledger = f.parent.ledger
  armed.val = true
  assert_true(
    prepare_request_models_source_free_plan(
      f.parent,
      f.input,
      f.selected_module,
      f.request,
      f.compiled,
      f.definition,
      f.occurrences,
      f.graphs,
      [effect_model_plan_limits, effect_model_plan_limits],
      retained,
      [5L, 6L],
      40,
      40,
      40,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    f.parent.phase == ProgramBodyFailed && f.parent.program_model is None,
  )
  assert_true(physical_equal(f.parent.program_capacity.unwrap(), capacity))
  assert_true(@resources.ledger_usage(ledger).live_reservations > 0)
  armed.val = false
  assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
  abort_request_preparation_after_cleanup(f.parent).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
// Same Request and actual two Source/Model compiler graph. Providers below
// are explicit pure component ports; no physical read or normal ABI is claimed.
fn request_captured_models_original_case(native : Bool) -> Unit raise {
  let row_document =
    #|{"version":"actql/0.1","id":"request-two-captured-models","stages":[{"id":"left","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id >= 0"},{"select":["id","amount"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","amount"]}}},{"id":"right","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id >= 0"},{"select":["id","amount"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","amount"]}}},{"id":"classify","inputs":{"left":{"result":{"stage":"left","result":"rows"}},"right":{"result":{"stage":"right","result":"rows"}}},"steps":[{"from":"left","join":{"with":"right","kind":"inner","on":[{"left":"id","right":"id"}],"select":{"id":"left.id"}}},{"derive":{"text":{"literal":"hello"}}},{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"classified"}],"results":{"rows":{"from":"classified","fields":["id","outcome","value"]}}},{"id":"classify-second","inputs":{"left":{"result":{"stage":"left","result":"rows"}},"right":{"result":{"stage":"right","result":"rows"}}},"steps":[{"from":"left","join":{"with":"right","kind":"inner","on":[{"left":"id","right":"id"}],"select":{"id":"left.id"}}},{"derive":{"text":{"literal":"hello"}}},{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"classified"}],"results":{"rows":{"from":"classified","fields":["id","outcome","value"]}}}],"results":{"first":{"from":{"stage":"classify","result":"rows"}},"second":{"from":{"stage":"classify-second","result":"rows"}}}}
  let native_document =
    #|{"version":"actql/0.1","id":"request-native-source-two-models","stages":[{"id":"input","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id >= 0"},{"select":["id","amount"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","amount"]}}},{"id":"first","inputs":{"rows":{"result":{"stage":"input","result":"rows"}}},"steps":[{"from":"rows","derive":{"text":{"literal":"hello"}}},{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"classified"}],"results":{"rows":{"from":"classified","fields":["id","outcome","value"]}}},{"id":"second","inputs":{"rows":{"result":{"stage":"input","result":"rows"}}},"steps":[{"from":"rows","derive":{"text":{"literal":"hello"}}},{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"classified"}],"results":{"rows":{"from":"classified","fields":["id","outcome","value"]}}}],"results":{"first":{"from":{"stage":"first","result":"rows"}},"second":{"from":{"stage":"second","result":"rows"}}}}
  let document = if native { native_document } else { row_document }
  let declaration = request_model_module_declaration()
  let (parent, input, prepared) = request_model_input_fixture(
    authored=Some(document),
    declaration=Some(declaration),
    model_copies=2,
  )
  let holder = borrow_request_model_plan_input(parent, input).unwrap()
  let occurrences = @publication_host.prepared_client_composed_infer_occurrences(
    prepared,
  ).unwrap()
  let contracts = request_program_module_contracts()
  let manifests = request_program_module_manifests()
  let limits = @publication_host.client_standard_pure_compilation_limits()
  let graphs : Array[@publication_host.ClientInferPlanGraph] = []
  for occurrence in occurrences {
    let (_, execution) = request_model_graph_inputs(
      prepared,
      selected=Some(occurrence),
    )
    graphs.push(
      prepare_request_model_graph(
        parent,
        input,
        occurrence,
        execution,
        contracts,
        manifests~,
        compilation_limits=limits,
      ).unwrap(),
    )
  }
  let compilation = prepare_request_models_compilation(
    parent,
    input,
    graphs,
    contracts,
    manifests~,
    compilation_limits=limits,
  ).unwrap()
  let compiled = @publication_host.issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "two-model-captured", "original", "2026-11-04T00:00:00.000Z", "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "two-model-captured",
  ).unwrap()
  let direct = request_model_direct_occurrences(parent, input).unwrap()
  assert_eq(
    @publication_host.client_direct_acquisition_occurrence_count(direct),
    if native {
      1
    } else {
      2
    },
  )
  let loader = publication_test_loader(publication_test_url())
  let entries : Array[Int] = []
  let selected = prepare_request_model_capture_module(
    parent,
    input,
    request,
    compiled,
    definition,
    compilation,
    if native {
      []
    } else {
      [declaration, declaration]
    },
    if native {
      capture_parent_contract(loader, "actql-query-acquisition.json")
    } else {
      original_row_query_contract_fixture
    },
    if native {
      capture_parent_contract(loader, "actql-query-process-evidence.json")
    } else {
      original_row_evidence_contract_fixture
    },
    if native {
      [4096L]
    } else {
      [4096L, 4096L]
    },
    if native {
      [2048L]
    } else {
      [2048L, 2048L]
    },
    contracts,
    true,
    0,
    _ => [],
    native_source_ref=if native {
      Some(declaration.views[0].source_ref)
    } else {
      None
    },
    native_database_schema=if native { Some("main") } else { None },
    native_table=if native { Some("records") } else { None },
    native_receipt_body=if native {
      Some(capture_parent_contract(loader, "actql-query-two-receipt.json"))
    } else {
      None
    },
    components_factory=Some((index, extent, _, _) => {
      entries.push(index)
      @local.managed_provider(_ => false, _ => Some(extent), (_, _, _, _, _) => {
        Err(@connector.ComputeUnsupported)
      })
    }),
  ).unwrap()
  assert_eq(entries, [0, 1])
  assert_true(
    selected.direct_occurrences is Some(original) &&
    physical_equal(original, direct),
  )
  assert_true(
    physical_equal(
      request_model_direct_occurrences(parent, input).unwrap(),
      direct,
    ),
  )
  let prior_work = @resources.ledger_usage(parent.ledger).planning_work
  if native {
    @resources.charge_planning(parent.ledger, 7).unwrap()
  }
  let plan = prepare_request_models_capture_plan(
    parent,
    input,
    selected,
    request,
    compiled,
    definition,
    occurrences,
    graphs,
    [effect_model_plan_limits, effect_model_plan_limits],
    [7L, 9L],
    [5L, 6L],
    40,
    40,
    40,
  ).unwrap()
  assert_true(
    plan.captured is Some(original) && physical_equal(original, selected),
  )
  assert_true(plan.source_free is None)
  assert_eq(plan.limits.attempts, selected.limits.attempts + 8)
  if native {
    let initial = client_local_preparation_initial_limits(
      client_local_resource_policy(),
    ).unwrap()
    // The same finite Local charge path must serve a complete Model group;
    // its whole-Run policy ceiling is not a per-binding work requirement.
    assert_true(plan.limits.planning_work <= initial.planning_work)
  }
  let scopes = prepare_request_models_read_scopes(parent, input, plan).unwrap()
  complete_request_model_preparation(parent, input, plan).unwrap()
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  let run = begin_request_model_managed_run(
    parent,
    request,
    scopes[0],
    scopes=Some(scopes),
  ).unwrap()
  assert_true(physical_equal(run.ledger.unwrap(), parent.ledger))
  for index, scope in scopes {
    @publication_host.finish_client_model_read_scope(
      scope,
      compiled,
      definition,
      graphs[index],
      true,
    ).unwrap()
    |> ignore
  }
  for index, scope in scopes {
    assert_true(
      @publication_host.finish_client_model_read_scope(
        scope,
        compiled,
        definition,
        graphs[index],
        true,
      ).unwrap(),
    )
  }
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  if native {
    assert_eq(
      @resources.ledger_usage(parent.ledger).planning_work,
      prior_work + 7,
    )
  }
}

///|
test "two captured Model Request keeps original Direct inventory and all scopes on its one aggregate Plan" {
  request_captured_models_original_case(false)
}

///|
test "native captured Model Request keeps one original Query and both ordered scopes on its aggregate Plan" {
  request_captured_models_original_case(true)
}

///|
// Real Request/Model Scope, two accounted captures and original dispatch Plan.
// The provider is an explicit nonexecuting component; no permission or IO ACK.
test "captured reusable inputs retain one owner and fund only missing import copies" {
  let f = request_serialized_model_fixture(two_captures=true, serialized=false)
  let starts = Ref(0)
  let original = prepare_request_model_capture_module(
    f.parent,
    f.input,
    f.request,
    f.compiled,
    f.definition,
    f.compilation,
    [f.declaration.unwrap(), f.declaration.unwrap()],
    original_row_query_contract_fixture,
    original_row_evidence_contract_fixture,
    [4096L, 4096L],
    [2048L, 2048L],
    f.contracts,
    false,
    1,
    _ => [],
    component_factory=Some((capacity, _, _) => {
      @local.managed_provider(_ => true, _ => Some(capacity), (_, _, _, _, _) => {
        starts.val += 1
        Err(@connector.ComputeUnsupported)
      })
    }),
  ).unwrap()
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
  ).unwrap()
  let scope = prepare_request_model_read_scope(f.parent, f.input, plan).unwrap()
  complete_request_model_preparation(f.parent, f.input, plan).unwrap()
  assert_true(@resources.preparation_body_borrow_value(f.holder) is Some(_))
  let run = begin_request_model_managed_run(f.parent, f.request, scope).unwrap()
  let reads = Array::makei(2, index => {
    begin_installed_managed_capture_read(run, index).unwrap()
  })
  let ledger = request_capture_ledger_fixture(run, original).unwrap()
  assert_true(physical_equal(ledger, f.parent.ledger))
  let sources = []
  for index in 0..<2 {
    let rows = start_installed_source_read_rows(
      reads[index],
      original.captures[index].acquisition.unwrap(),
      "same-original-two-inputs",
      _ => true,
      4096L,
      2048L,
    ).unwrap()
    @row_source_host.begin_row_run(rows, 2048, 2, 2).unwrap()
    let wire = @utf8.encode("[{\"id\":3,\"amount\":7}]")
    let charged = @row_source_host.charge_row_run_page(rows, wire).unwrap()
    assert_eq(
      @row_source_host.accept_charged_row_run_page(rows, charged, wire).unwrap(),
      1,
    )
    @row_source_host.finish_row_run(rows).unwrap()
    @row_source_host.begin_row_capture(rows).unwrap()
    let mut completed = false
    for _ in 0..<10000 {
      if @row_source_host.advance_row_capture(rows, 256).unwrap().0 {
        completed = true
        break
      }
    }
    assert_true(completed)
    sources.push(
      @row_source_host.row_capture_source(
        @row_source_host.capture_row_run(rows).unwrap(),
      ).unwrap(),
    )
  }
  let task = @strategy.graph_captured_prefix(original.graph)
  let planned = @local_driver.local_dispatch_preparation_task_capacity(
    original.configuration.dispatch,
    task,
  ).unwrap()
  let usage = @resources.ledger_usage(ledger)
  let available = @resources.ledger_admission_limits(ledger).execution_bytes -
    usage.reserved_execution_bytes
  assert_true(available >= planned.execution_bytes)
  // Preserve the unchanged full Ledger. A real reservation leaves one byte
  // less than the future-input quote, while these original reads need no copy.
  let other = @resources.reserve_capacity(
    ledger,
    0L,
    available - planned.execution_bytes + 1L,
  ).unwrap()
  let (host, dag, _) = open_installed_managed_capture_host(
    run,
    f.prepared,
    f.request,
    sources,
  ).unwrap()
  assert_true(physical_equal(@strategy.captured_dag_ledger(dag), ledger))
  for index in 0..<2 {
    let read = @strategy.captured_task_input(
      dag,
      task,
      10000,
      10000,
      input_index=index,
    ).unwrap()
    assert_true(@execution.producer_read_has_cell_access(read))
    assert_true(
      physical_equal(
        read,
        @strategy.captured_task_input(
          dag,
          task,
          10000,
          10000,
          input_index=index,
        ).unwrap(),
      ),
    )
  }
  assert_eq(@strategy.strategy_report_count(dag), 1)
  assert_true(@strategy.strategy_report_at(dag, 0).unwrap().rejection is None)
  let installed = @builtin.configured_local_module(
    @builtin.configured_host_modules(host),
  ).unwrap()
  let setup : @local_driver.LocalManagedDispatchConfiguration[Int] = @local_driver.prepare_local_managed_dispatch_with_outputs(
      installed,
      [
        @local_driver.local_managed_captured_relation_input(),
        @local_driver.local_managed_captured_relation_input(),
      ],
      @execution.process_managed_obligations(
        @strategy.graph_task_owner(original.graph, task).unwrap(),
      ),
      0L,
    )
    .unwrap()
    .unwrap()
  let (_, execution) = @local_driver.local_managed_dispatch_site_capacity(setup).unwrap()
  assert_true(execution < planned.execution_bytes)
  assert_eq(starts.val, 0)
  assert_eq(@resources.ledger_usage(ledger).attempts, usage.attempts)
  @resources.settle_capacity(ledger, other).unwrap()
  ignore(reject_client_local_run(dag))
  for read in reads {
    retire_installed_source_read(read).unwrap()
  }
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
  @resources.return_preparation_body_borrow(f.holder).unwrap() |> ignore
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
test "captured unavailable originals receive no missing-copy credit or provider start" {
  let f = request_serialized_model_fixture(two_captures=true, serialized=false)
  let starts = Ref(0)
  let original = prepare_request_model_capture_module(
    f.parent,
    f.input,
    f.request,
    f.compiled,
    f.definition,
    f.compilation,
    [f.declaration.unwrap(), f.declaration.unwrap()],
    original_row_query_contract_fixture,
    original_row_evidence_contract_fixture,
    [4096L, 4096L],
    [2048L, 2048L],
    f.contracts,
    false,
    1,
    _ => [],
    component_factory=Some((capacity, _, _) => {
      @local.managed_provider(_ => true, _ => Some(capacity), (_, _, _, _, _) => {
        starts.val += 1
        Err(@connector.ComputeUnsupported)
      })
    }),
  ).unwrap()
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
  ).unwrap()
  let scope = prepare_request_model_read_scope(f.parent, f.input, plan).unwrap()
  complete_request_model_preparation(f.parent, f.input, plan).unwrap()
  assert_true(@resources.preparation_body_borrow_value(f.holder) is Some(_))
  let run = begin_request_model_managed_run(f.parent, f.request, scope).unwrap()
  let reads = Array::makei(2, index => {
    begin_installed_managed_capture_read(run, index).unwrap()
  })
  let ledger = request_capture_ledger_fixture(run, original).unwrap()
  assert_true(physical_equal(ledger, f.parent.ledger))
  let sources = []
  for index in 0..<2 {
    let rows = start_installed_source_read_rows(
      reads[index],
      original.captures[index].acquisition.unwrap(),
      "same-original-two-inputs",
      _ => true,
      4096L,
      2048L,
    ).unwrap()
    @row_source_host.begin_row_run(rows, 2048, 2, 2).unwrap()
    let wire = @utf8.encode("[{\"id\":3,\"amount\":7}]")
    let charged = @row_source_host.charge_row_run_page(rows, wire).unwrap()
    assert_eq(
      @row_source_host.accept_charged_row_run_page(rows, charged, wire).unwrap(),
      1,
    )
    @row_source_host.finish_row_run(rows).unwrap()
    @row_source_host.begin_row_capture(rows).unwrap()
    let mut completed = false
    for _ in 0..<10000 {
      if @row_source_host.advance_row_capture(rows, 256).unwrap().0 {
        completed = true
        break
      }
    }
    assert_true(completed)
    sources.push(
      @row_source_host.row_capture_source(
        @row_source_host.capture_row_run(rows).unwrap(),
      ).unwrap(),
    )
  }
  let task = @strategy.graph_captured_prefix(original.graph)
  let planned = @local_driver.local_dispatch_preparation_task_capacity(
    original.configuration.dispatch,
    task,
  ).unwrap()
  retire_installed_source_read(reads[0]).unwrap()
  assert_false(@query.captured_source_available(sources[0]))
  assert_true(
    open_installed_managed_capture_host(run, f.prepared, f.request, sources)
    is Err(_),
  )
  assert_true(run.source_free_captured is None)
  assert_eq(
    @local_driver.local_dispatch_preparation_task_capacity(
      original.configuration.dispatch,
      task,
    ),
    Some(planned),
  )
  assert_eq(starts.val, 0)
  retire_installed_source_read(reads[1]).unwrap()
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
  @resources.return_preparation_body_borrow(f.holder).unwrap() |> ignore
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
test "native protocol preflight sizes a long String as one node and retains old refusal fallback" {
  let wire = "\"" + "x".repeat(12000) + "\""
  let geometry = request_model_material_source_geometry(wire).unwrap()
  assert_eq(geometry.0, 12002)
  assert_eq(geometry.1, 1)
  let actual = request_model_material_body_bytes(
    1,
    _ => wire,
    source_geometry=true,
  ).unwrap()
  let legacy = request_model_material_body_bytes(1, _ => wire).unwrap()
  assert_true(actual < legacy / 10L)
  let malformed = String::from_array([(0xd800).unsafe_to_char()])
  for refused in ["", malformed] {
    assert_true(request_model_material_source_geometry(refused) is None)
    assert_eq(
      request_model_material_body_bytes(1, _ => refused, source_geometry=true),
      request_model_material_body_bytes(1, _ => refused),
    )
  }
}

///|
// Real Request/module/Plan/adoption originals, explicit Resource/provider
// component ports. This getter proves no normal physical capacity or IO.
test "adopted captured Model reads only its retained original prefix before payload retirement" {
  let ticks = Ref(0)
  let f = request_serialized_model_fixture(
    single_capture=true,
    serialized=false,
    current=() => {
      ticks.val += 1
      true
    },
  )
  let provider = @execution.execution_capacity(7L, 9L).unwrap()
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
    _ => [],
    providers=Some([Some(provider)]),
  ).unwrap()
  let expected = prepared_request_model_input_prefix(original).unwrap()
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
  ).unwrap()
  let scope = prepare_request_model_read_scope(f.parent, f.input, plan).unwrap()
  complete_request_model_preparation(f.parent, f.input, plan).unwrap()
  assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
  let run = begin_request_model_managed_run(f.parent, f.request, scope).unwrap()
  assert_true(physical_equal(run.captured_preparation.unwrap(), original))
  let work = @resources.ledger_usage(f.parent.ledger)
  let quantities = @resources.quantity_usage(f.parent.ledger)
  let calls = ticks.val
  for _ in 0..<2 {
    assert_true(
      physical_equal(
        installed_managed_run_model_input_prefix(run, f.prepared).unwrap(),
        expected,
      ),
    )
  }
  assert_eq(ticks.val, calls)
  assert_eq(@resources.ledger_usage(f.parent.ledger), work)
  assert_eq(@resources.quantity_usage(f.parent.ledger), quantities)
  let other = request_serialized_model_fixture(
    single_capture=true,
    serialized=false,
  )
  assert_true(
    installed_managed_run_model_input_prefix(run, other.prepared)
    is Err(ForeignOriginal),
  )
  // Equal-looking DATA cannot change this adopted Run's Request association.
  let copied_request = @publication_host.prepare_source_free_client_request_identity(
    f.prepared,
    "sha256:" + "a".repeat(64),
    "copied-model-prefix-request",
  ).unwrap()
  run.captured_preparation = Some({ ..original, request: copied_request, })
  assert_true(
    installed_managed_run_model_input_prefix(run, f.prepared)
    is Err(ForeignOriginal),
  )
  run.captured_preparation = Some(original)
  assert_true(
    physical_equal(
      installed_managed_run_model_input_prefix(run, f.prepared).unwrap(),
      expected,
    ),
  )
  assert_false(@resources.return_preparation_body_borrow(other.holder).unwrap())
  abort_request_preparation_after_cleanup(other.parent).unwrap()
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope,
      f.compiled,
      f.definition,
      f.graph,
      true,
    ).unwrap(),
  )
  retire_installed_managed_run(run).unwrap()
  assert_true(
    installed_managed_run_model_input_prefix(run, f.prepared)
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
}
