///|
// Original JSON/check/compiler and installed Model/module DATA. Initial and
// physical frames here are explicit component ports, not C's normal supplier
// recipe, Source/Model IO or a public acceptance/performance claim.
fn request_model_input_fixture(
  captured? : Bool = false,
  single_capture? : Bool = false,
  with_query_time? : Bool = false,
  with_serialization? : Bool = false,
  current? : () -> Bool = () => true,
  declaration? : @row_source_host.RowDeclaration? = None,
) -> (
  ClientRequestPreparation[Array[Int]],
  Array[Int],
  @publication_host.PreparedClientProgram,
) raise {
  let (environment, _) = effect_model_plan_source(declaration~)
  let document = if single_capture {
    assert_false(captured)
    (
      #|{"version":"actql/0.1","id":"request-model-one-capture","stages":[{"id":"source","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id >= 0"},{"select":["id","amount"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","amount"]}}},{"id":"classify","inputs":{"rows":{"result":{"stage":"source","result":"rows"}}},"steps":[{"from":"rows","derive":{"text":{"literal":"hello"}}},{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"classified"}],"results":{"rows":{"from":"classified","fields":["id","outcome","value"]}}}],"results":{"rows":{"from":{"stage":"classify","result":"rows"}}}}
    )
  } else if captured {
    (
      #|{"version":"actql/0.1","id":"request-model-captures","stages":[{"id":"left","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id >= 0"},{"select":["id","amount"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","amount"]}}},{"id":"right","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id >= 0"},{"select":["id","amount"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","amount"]}}},{"id":"classify","inputs":{"left":{"result":{"stage":"left","result":"rows"}},"right":{"result":{"stage":"right","result":"rows"}}},"steps":[{"from":"left","join":{"with":"right","kind":"inner","on":[{"left":"id","right":"id"}],"select":{"id":"left.id"}}},{"derive":{"text":{"literal":"hello"}}},{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"classified"}],"results":{"rows":{"from":"classified","fields":["id","outcome","value"]}}}],"results":{"rows":{"from":{"stage":"classify","result":"rows"}}}}
    )
  } else {
    (
      #|{"version":"actql/0.1","id":"request-model-values","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"text":{"type":"string","nullable":true}},"rows":[{"id":1,"text":"hello"}]},"as":"seed"},{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"classified"}],"results":{"rows":{"from":"classified","fields":["id","outcome","value"]}}}],"results":{"rows":{"from":{"stage":"main","result":"rows"}}}}
    )
  }
  let document = if with_serialization {
    assert_false(captured)
    assert_false(with_query_time)
    document
    .replace(
      old="{\"assert_rows\":{\"unique_by\":[\"id\"]}},{\"infer\":",
      new="{\"assert_rows\":{\"unique_by\":[\"id\"]}},{\"serialize\":{\"format\":\"jsonl\",\"fields\":[\"id\",\"text\"],\"name\":\"out.jsonl\",\"preserve_order\":true,\"bounds\":{\"max_rows\":1,\"max_bytes\":128}},\"as\":\"attachment\"},{\"assert_rows\":{\"unique_by\":[\"name\"]}},{\"infer\":",
    )
    .replace(
      old="\"key\":\"id\",\"input\":{\"text\":{\"field\":\"text\"}}",
      new="\"key\":\"name\",\"input\":{\"text\":{\"field\":\"name\"}}",
    )
    .replace(
      old="\"fields\":[\"id\",\"outcome\",\"value\"]",
      new="\"fields\":[\"name\",\"outcome\",\"value\"]",
    )
  } else {
    document
  }
  let document = match declaration {
    Some(original) =>
      document.replace_all(
        old="\"connector\":\"crm/main\"",
        new="\"connector\":\"" + original.connector_id + "\"",
      )
    None => document
  }
  let document = if with_query_time {
    assert_false(captured)
    let selected = document.replace(
      old="\"as\":\"seed\"},{\"assert_rows\"",
      new="\"as\":\"seed\"},{\"filter\":\"current_timestamp() = current_timestamp()\"},{\"assert_rows\"",
    )
    assert_true(selected != document)
    selected
  } else {
    document
  }
  let ordinary = client_local_preparation_initial_limits(
    client_local_resource_policy(),
  ).unwrap()
  // Selected component supplier reserves the existing installed module's full
  // policy envelope in addition to the initial input and finite Model DATA.
  // This logical test port supplies no complete physical Model frame proof.
  let domain = {
    ..effect_model_plan_limits,
    retained_bytes: ordinary.retained_bytes,
    execution_bytes: ordinary.execution_bytes,
  }
  let initial_limits = @resources.add_ledger_limits(ordinary, domain).unwrap()
  let (parent, child, _, input) = registration_parent_fixture(
    current~,
    text=document,
    environment=Some(environment),
    initial_limits=Some(initial_limits),
  )
  finish_program_check_preparation(child).unwrap() |> ignore
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
  (parent, input, prepared)
}

///|
fn request_model_graph_fixture(
  prepared : @publication_host.PreparedClientProgram,
) -> (
  @publication_host.ClientInferOccurrence,
  @publication_host.ClientInferPlanGraph,
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
  let graph = @publication_host.issue_installed_client_composed_infer_plan_graph(
    occurrence,
    execution,
    @publication_host.client_standard_values_sequence_limits(),
    1000000,
    100000,
    100,
  ).unwrap()
  (occurrence, graph)
}

///|
fn request_model_fixture(
  captured? : Bool = false,
  model_input? : Bool = true,
  current? : () -> Bool = () => true,
) -> (
  ClientRequestPreparation[Array[Int]],
  Array[Int],
  ClientInstalledManagedModelPlan,
  @resources.PreparationBodyBorrow[@publication_host.PreparedClientProgram],
) raise {
  let declaration = request_model_module_declaration()
  let (parent, input, prepared) = request_model_input_fixture(
    captured~,
    current~,
    declaration=if model_input && captured { Some(declaration) } else { None },
  )
  let construction = if model_input {
    borrow_request_model_plan_input(parent, input).unwrap()
  } else {
    borrow_request_program_plan_input(parent, input).unwrap()
  }
  let capacity = parent.program_capacity.unwrap()
  let previous = @resources.begin_preparation_io(capacity, input, 2L).unwrap()
  @resources.charge_preparation_io(previous, 1L).unwrap()
  @resources.finish_preparation_io_after_cleanup(previous).unwrap()
  @resources.configure_quantities(parent.ledger, {
    tokens: 128L,
    cost_units: 0L,
    duration_ms: 1000L,
  }).unwrap()
  let contracts = request_program_module_contracts()
  let manifests = request_program_module_manifests()
  let compilation_limits = @publication_host.client_standard_pure_compilation_limits()
  let (occurrence, graph) = if model_input {
    let (occurrence, execution) = request_model_graph_inputs(prepared)
    (
      occurrence,
      prepare_request_model_graph(
        parent,
        input,
        occurrence,
        execution,
        contracts,
        manifests~,
        compilation_limits~,
      ).unwrap(),
    )
  } else {
    request_model_graph_fixture(prepared)
  }
  let compilation = if model_input {
    prepare_request_model_compilation(
      parent,
      input,
      graph,
      contracts,
      manifests~,
      compilation_limits~,
    ).unwrap()
  } else {
    @publication_host.issue_prepared_client_multi_infer_compilation(
      prepared,
      [graph],
      request_program_module_manifests(),
      @publication_host.client_standard_values_sequence_limits(),
      1000,
      10000,
      1000000,
      100000,
      100,
    ).unwrap()
  }
  let compiled = @publication_host.issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "request-model", "same-original", "2026-10-31T00:00:00.000Z", "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "request-model",
  ).unwrap()
  let assets = @publication_host.client_local_product_assets()
  let factory_calls = Ref(0)
  let factory = (_ : @execution.ExecutionCapacity) => {
    factory_calls.val += 1
    []
  }
  let plan = if captured {
    let original = if model_input {
      prepare_request_model_capture_module(
        parent,
        input,
        request,
        compiled,
        definition,
        compilation,
        [declaration, declaration],
        original_row_query_contract_fixture,
        original_row_evidence_contract_fixture,
        [4096L, 4096L],
        [2048L, 2048L],
        contracts,
        true,
        0,
        factory,
      ).unwrap()
    } else {
      let captures = Array::makei(2, index => {
        let requirement = prepare_local_query_requirement(
          prepared,
          index,
          0,
          contracts,
          assets.values,
          Some(assets.fragment),
          assets.ordered,
        ).unwrap()
        installed_row_capture_capacity(
          original_row_acquisition_fixture(requirement),
        ).unwrap()
      })
      prepare_installed_mock_model_capture_plan(
        prepared,
        request,
        compilation,
        captures,
        [4096L, 4096L],
        [2048L, 2048L],
        contracts,
        assets.values,
        Some(assets.fragment),
        assets.ordered,
        retained_output=true,
        provider_factory=factory,
      ).unwrap()
    }
    prepare_installed_mock_model_capture_plan_binding(
      original, compiled, definition, occurrence, graph, effect_model_plan_limits,
      500L, 700L, 20, 20, 20,
    ).unwrap()
  } else {
    let original = if model_input {
      prepare_request_model_source_free_module(
        parent, input, request, compiled, definition, compilation, contracts, true,
        0, factory,
      ).unwrap()
    } else {
      prepare_installed_mock_model_source_free_with_contracts(
        prepared,
        compilation,
        contracts,
        assets.values,
        Some(assets.fragment),
        assets.ordered,
        retained_output=true,
        provider_factory=factory,
      ).unwrap()
    }
    prepare_installed_mock_model_source_free_plan(
      original, request, compiled, definition, occurrence, graph, effect_model_plan_limits,
      500L, 700L, 20, 20, 20,
    ).unwrap()
  }
  assert_eq(factory_calls.val, 1)
  // These same-Request constructors retain actual Graph/module backing.
  // Runtime reservations and Scope/census still keep their separate duties;
  // the fixture's installation/Resource admission is not ordinary IO.
  (parent, input, plan, construction)
}

///|
test "Pure Scope funds its new origin and original census before binding for source-free and captured Plans" {
  for captured in [false, true] {
    let (parent, input, plan, construction) = request_model_fixture(captured~)
    let capacity = parent.program_capacity.unwrap()
    let before = @resources.preparation_capacity_working_extents(
      capacity, input,
    ).unwrap()
    let increment = expected_request_model_scope_controls(
      plan.max_reservations,
      plan.max_holdings,
      plan.max_delegations,
    )
    let scope = prepare_request_model_read_scope(parent, input, plan).unwrap()
    assert_eq(
      @resources.preparation_capacity_working_extents(capacity, input),
      Ok((before.0 + increment, before.1 + increment)),
    )
    complete_request_model_preparation(parent, input, plan).unwrap()
    @resources.return_preparation_body_borrow(construction).unwrap() |> ignore
    let run = begin_request_model_managed_run(parent, plan.request, scope).unwrap()
    assert_true(
      @publication_host.finish_client_model_read_scope(
        scope,
        plan.compiled,
        plan.definition,
        plan.graph,
        true,
      ).unwrap(),
    )
    retire_installed_managed_run(run).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "Pure Scope one-short keeps its original absolute quote and cannot complete another Plan" {
  for captured in [false, true] {
    let (parent, input, plan, construction) = request_model_fixture(captured~)
    let capacity = parent.program_capacity.unwrap()
    let before = @resources.preparation_capacity_working_extents(
      capacity, input,
    ).unwrap()
    let increment = expected_request_model_scope_controls(
      plan.max_reservations,
      plan.max_holdings,
      plan.max_delegations,
    )
    let limits = @resources.ledger_limits(parent.ledger)
    let block = @resources.reserve_capacity(
      parent.ledger,
      0L,
      limits.execution_bytes - before.1 - increment + 1L,
    ).unwrap()
    assert_true(
      prepare_request_model_read_scope(parent, input, plan)
      is Err(Preparation(Resource(_))),
    )
    assert_true(parent.phase == ModelScopeQuoted)
    assert_eq(
      parent.program_domain_quote,
      Some((before.0 + increment, before.1 + increment)),
    )
    assert_true(
      complete_request_model_preparation(parent, input, plan)
      is Err(ForeignOriginal),
    )
    let copied = { ..plan, max_holdings: plan.max_holdings, }
    assert_true(
      prepare_request_model_read_scope(parent, input, copied)
      is Err(ForeignOriginal),
    )
    @resources.settle_capacity(parent.ledger, block).unwrap()
    let scope = prepare_request_model_read_scope(parent, input, plan).unwrap()
    assert_eq(
      @resources.preparation_capacity_working_extents(capacity, input),
      Ok((before.0 + increment, before.1 + increment)),
    )
    assert_true(parent.program_domain_quote is None)
    complete_request_model_preparation(parent, input, plan).unwrap()
    @resources.return_preparation_body_borrow(construction).unwrap() |> ignore
    let run = begin_request_model_managed_run(parent, plan.request, scope).unwrap()
    assert_true(
      @publication_host.finish_client_model_read_scope(
        scope,
        plan.compiled,
        plan.definition,
        plan.graph,
        true,
      ).unwrap(),
    )
    retire_installed_managed_run(run).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "Model Scope cannot adopt a Plan built without selecting its original construction input" {
  let (parent, input, plan, construction) = request_model_fixture(
    model_input=false,
  )
  assert_true(
    prepare_request_model_read_scope(parent, input, plan)
    is Err(ForeignOriginal),
  )
  assert_true(parent.program_model is None)
  // Returning a borrow does not retire the still-active original capacity.
  assert_false(@resources.return_preparation_body_borrow(construction).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "Model construction input preserves grown Program backing and funds its actual record once before allocation" {
  let calls = Ref(0)
  let (parent, input, prepared) = request_model_input_fixture(current=() => {
    calls.val += 1
    true
  })
  let program = borrow_request_program_plan_input(parent, input).unwrap()
  let capacity = parent.program_capacity.unwrap()
  let (r, e) = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  @resources.reserve_working_preparation_phase(
    capacity,
    input,
    r + 129L,
    e + 257L,
  ).unwrap()
  let before = calls.val
  let model = borrow_request_model_plan_input(parent, input).unwrap()
  assert_eq(calls.val, before + 1)
  // Independent record inventory: header16 + nine references72 + three words24.
  // No Model Plan, compilation, Scope, provider or IO is constructed here.
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((r + 129L + 112L, e + 257L + 112L)),
  )
  assert_true(parent.phase == ModelPlanReserved)
  assert_true(parent.program_model is None)
  assert_true(
    @resources.preparation_body_borrow_value(model) is Some(original) &&
    physical_equal(original, prepared),
  )
  assert_false(@resources.return_preparation_body_borrow(program).unwrap())
  let charged = request_preparation_accounting(parent)
  let second = borrow_request_model_plan_input(parent, input).unwrap()
  assert_eq(request_preparation_accounting(parent), charged)
  assert_true(
    borrow_request_program_plan_input(parent, input) is Err(WrongPhase),
  )
  assert_true(
    borrow_request_content_plan_input(parent, input) is Err(WrongPhase),
  )
  assert_true(
    abort_request_preparation_after_cleanup(parent) is Err(WrongPhase),
  )
  assert_false(@resources.return_preparation_body_borrow(model).unwrap())
  assert_true(@resources.return_preparation_body_borrow(second).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Model construction input foreign and one-byte-short refusal preserves the original Program borrow" {
  let calls = Ref(0)
  let (parent, input, prepared) = request_model_input_fixture(current=() => {
    calls.val += 1
    true
  })
  let program = borrow_request_program_plan_input(parent, input).unwrap()
  let capacity = parent.program_capacity.unwrap()
  let (_, e) = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let r = @resources.ledger_limits(parent.ledger).retained_bytes - 111L
  @resources.reserve_working_preparation_phase(capacity, input, r, e).unwrap()
  let charged = request_preparation_accounting(parent)
  let observed = calls.val
  assert_true(
    borrow_request_model_plan_input(parent, [1]) is Err(ForeignOriginal),
  )
  assert_eq(calls.val, observed)
  assert_true(
    borrow_request_model_plan_input(parent, input)
    is Err(Capacity(Resource(RetentionLimit))),
  )
  assert_eq(calls.val, observed + 1)
  assert_true(parent.phase == ProgramPlanReserved)
  assert_eq(request_preparation_accounting(parent), charged)
  assert_true(
    @resources.preparation_body_borrow_value(program) is Some(original) &&
    physical_equal(original, prepared),
  )
  assert_true(
    abort_request_preparation_after_cleanup(parent) is Err(WrongPhase),
  )
  assert_true(@resources.return_preparation_body_borrow(program).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "source-free and captured Model retain one Request census through actual Scope adoption and cleanup" {
  for captured in [false, true] {
    let (parent, input, plan, construction) = request_model_fixture(captured~)
    let ledger = parent.ledger
    let capacity = parent.program_capacity.unwrap()
    let attempts = @resources.ledger_usage(ledger).attempts
    let scope = prepare_request_model_read_scope(parent, input, plan).unwrap()
    assert_true(
      @publication_host.client_model_read_scope_original_inventory(
        scope,
        ledger,
        @resources.preparation_capacity_inventory_original(capacity, input).unwrap(),
      ),
    )
    complete_request_model_preparation(parent, input, plan).unwrap()
    @resources.return_preparation_body_borrow(construction).unwrap() |> ignore
    let held = borrow_request_program_preparation(parent).unwrap()
    assert_true(
      if captured {
        begin_request_capture_managed_run(parent, plan.request)
        is Err(Unsupported)
      } else {
        begin_request_program_managed_run(parent, plan.request)
        is Err(Unsupported)
      },
    )
    let run = begin_request_model_managed_run(parent, plan.request, scope).unwrap()
    assert_true(physical_equal(run.ledger.unwrap(), ledger))
    assert_true(parent.program_model is None && parent.phase == Selected)
    let compilation = installed_managed_run_compilation_original(
      run,
      plan.prepared,
    ).unwrap()
    assert_true(
      match compilation {
        @publication_host.Tasks(original) =>
          @publication_host.client_compiled_run_matches_tasks(
            plan.compiled,
            plan.prepared,
            original,
          )
        _ => false
      },
    )
    assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
    assert_false(
      @publication_host.finish_client_model_read_scope(
        scope,
        plan.compiled,
        plan.definition,
        plan.graph,
        false,
      ).unwrap(),
    )
    assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
    assert_true(
      @publication_host.finish_client_model_read_scope(
        scope,
        plan.compiled,
        plan.definition,
        plan.graph,
        true,
      ).unwrap(),
    )
    assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
    @resources.return_preparation_body_borrow(held).unwrap() |> ignore
    retire_installed_managed_run(run).unwrap()
    assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
    assert_eq(@resources.ledger_usage(ledger).attempts, attempts)
  }
}

///|
test "Model Plan and Scope originals cannot be replaced at completion or adoption" {
  let (parent, input, plan, construction) = request_model_fixture()
  let (other, other_input, other_plan, other_construction) = request_model_fixture()
  assert_true(
    prepare_request_model_read_scope(parent, input, other_plan)
    is Err(ForeignOriginal),
  )
  let scope = prepare_request_model_read_scope(parent, input, plan).unwrap()
  let other_scope = prepare_request_model_read_scope(
    other, other_input, other_plan,
  ).unwrap()
  assert_true(
    complete_request_model_preparation(parent, input, other_plan)
    is Err(ForeignOriginal),
  )
  complete_request_model_preparation(parent, input, plan).unwrap()
  @resources.return_preparation_body_borrow(construction).unwrap() |> ignore
  let before = @resources.ledger_usage(parent.ledger)
  assert_true(
    begin_request_model_managed_run(parent, plan.request, other_scope)
    is Err(ForeignOriginal),
  )
  assert_true(
    begin_request_model_managed_run(parent, other_plan.request, scope)
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  assert_true(parent.phase == ProgramBodyReady && parent.input is Some(_))
  @publication_host.finish_client_model_read_scope(
    scope,
    plan.compiled,
    plan.definition,
    plan.graph,
    true,
  ).unwrap()
  |> ignore
  abort_request_preparation_after_cleanup(parent).unwrap()
  @resources.return_preparation_body_borrow(other_construction).unwrap()
  |> ignore
  @publication_host.finish_client_model_read_scope(
    other_scope,
    other_plan.compiled,
    other_plan.definition,
    other_plan.graph,
    true,
  ).unwrap()
  |> ignore
  abort_request_preparation_after_cleanup(other).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  assert_eq(@resources.ledger_usage(other.ledger).live_reservations, 0)
}

///|
test "Model Scope closing in adoption current keeps the original Request cleanup owner" {
  let armed = Ref(false)
  let closed = Ref(false)
  let original : Ref[
    (@publication_host.ClientModelReadScope, ClientInstalledManagedModelPlan)?,
  ] = Ref(None)
  let (parent, input, plan, construction) = request_model_fixture(current=() => {
    if armed.val {
      armed.val = false
      let (scope, plan) = original.val.unwrap()
      closed.val = @publication_host.finish_client_model_read_scope(
        scope,
        plan.compiled,
        plan.definition,
        plan.graph,
        true,
      ).unwrap()
    }
    true
  })
  let scope = prepare_request_model_read_scope(parent, input, plan).unwrap()
  original.val = Some((scope, plan))
  complete_request_model_preparation(parent, input, plan).unwrap()
  @resources.return_preparation_body_borrow(construction).unwrap() |> ignore
  let before = @resources.ledger_usage(parent.ledger)
  armed.val = true
  assert_true(
    begin_request_model_managed_run(parent, plan.request, scope)
    is Err(
      Resource(
        @resources.ImportedChildLedgerIssue::Resource(
          @resources.ClosedReservation
        )
      )
    ),
  )
  assert_true(closed.val)
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  assert_true(parent.phase == ProgramBodyReady && parent.input is Some(_))
  assert_true(
    @resources.check_node_preparation_input(parent.initial, input) is Ok(_),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
fn request_model_ordinary_entry_refusal(captured : Bool) -> Unit raise {
  let (parent, input, plan, construction) = request_model_fixture(captured~)
  let scope = prepare_request_model_read_scope(parent, input, plan).unwrap()
  let before = @resources.ledger_usage(parent.ledger)
  if captured {
    let factories = Ref(0)
    assert_true(
      prepare_request_capture_module_body(
        parent,
        input,
        plan.captured.unwrap(),
        manifests=request_program_module_manifests(),
        compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
        provider_factory=_ => {
          factories.val += 1
          []
        },
      )
      is Err(Preparation(WrongPhase)),
    )
    assert_eq(factories.val, 0)
    assert_true(parent.program_artifact_inputs is None)
  } else {
    assert_true(
      complete_request_program_preparation(
        parent,
        input,
        plan.source_free.unwrap(),
      )
      is Err(WrongPhase),
    )
    assert_true(parent.program_source_free is None)
  }
  assert_true(parent.phase == ModelPlanReserved)
  assert_true(
    parent.program_model is Some(original) && physical_equal(original, plan),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  complete_request_model_preparation(parent, input, plan).unwrap()
  @resources.return_preparation_body_borrow(construction).unwrap() |> ignore
  @publication_host.finish_client_model_read_scope(
    scope,
    plan.compiled,
    plan.definition,
    plan.graph,
    true,
  ).unwrap()
  |> ignore
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "ordinary completion cannot replace the selected original Model module" {
  request_model_ordinary_entry_refusal(false)
}

///|
test "ordinary module compiler cannot consume the selected original Model capture Plan" {
  request_model_ordinary_entry_refusal(true)
}

///|
test "actual source-free and captured Model compiler spends the same Request Plan writer work" {
  for captured in [false, true] {
    let (parent, input, plan, construction) = request_model_fixture(captured~)
    assert_true(parent.program_artifact_work_spent > 0L)
    assert_eq(
      parent.program_artifact_work_spent,
      parent.program_artifact_plan_encoding_nodes.val,
    )
    let before = parent.program_artifact_work_spent
    let scope = prepare_request_model_read_scope(parent, input, plan).unwrap()
    complete_request_model_preparation(parent, input, plan).unwrap()
    assert_eq(parent.program_artifact_work_spent, before)
    @resources.return_preparation_body_borrow(construction).unwrap() |> ignore
    let run = begin_request_model_managed_run(parent, plan.request, scope).unwrap()
    assert_true(
      @publication_host.finish_client_model_read_scope(
        scope,
        plan.compiled,
        plan.definition,
        plan.graph,
        true,
      ).unwrap(),
    )
    retire_installed_managed_run(run).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "Model compiler measurement and artifact one-short growth retain the same original without recompile" {
  for retention in [true, false] {
    let (parent, input, prepared) = request_model_input_fixture()
    let holder = borrow_request_model_plan_input(parent, input).unwrap()
    let (_, graph) = request_model_graph_fixture(prepared)
    let contracts = request_program_module_contracts()
    let manifests = request_program_module_manifests()
    let compilation_limits = @publication_host.client_standard_pure_compilation_limits()
    let capacity = parent.program_capacity.unwrap()
    let limits = @resources.ledger_limits(parent.ledger)
    let base = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
    let storage = @execution.preparation_representation_cost(
      @publication_host.prepared_client_model_measurement_storage(
        prepared,
        [graph],
        compilation_limits,
      ).unwrap(),
    ).unwrap()
    let measurement = (base.0 + storage, base.1 + storage)
    let block = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - measurement.0 + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - measurement.1 + 1L
      },
    ).unwrap()
    assert_true(
      prepare_request_model_compilation(
        parent,
        input,
        graph,
        contracts,
        manifests~,
        compilation_limits~,
      )
      is Err(Preparation(Capacity(_))),
    )
    assert_true(
      parent.phase == ModelPlanReserved &&
      parent.program_artifact_geometry is None,
    )
    assert_eq(parent.program_artifact_work_spent, 0L)
    assert_eq(parent.program_artifact_plan_encoding_nodes.val, 0L)
    @resources.settle_capacity(parent.ledger, block).unwrap()
    let block = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - measurement.0
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - measurement.1
      },
    ).unwrap()
    assert_true(
      prepare_request_model_compilation(
        parent,
        input,
        graph,
        contracts,
        manifests~,
        compilation_limits~,
      )
      is Err(Preparation(Capacity(_))),
    )
    let geometry = parent.program_artifact_geometry.unwrap()
    let quote = parent.program_artifact_quote.unwrap()
    assert_true(geometry.borrowed_inputs.length() == 1)
    assert_true(parent.program_compilation is None)
    @resources.settle_capacity(parent.ledger, block).unwrap()
    let short = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - quote.0 + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - quote.1 + 1L
      },
    ).unwrap()
    assert_true(
      prepare_request_model_compilation(
        parent,
        input,
        graph,
        contracts,
        manifests~,
        compilation_limits~,
      )
      is Err(Preparation(Capacity(_))),
    )
    assert_true(
      physical_equal(parent.program_artifact_geometry.unwrap(), geometry),
    )
    assert_eq(parent.program_artifact_plan_encoding_nodes.val, 0L)
    @resources.settle_capacity(parent.ledger, short).unwrap()
    let artifact = prepare_request_model_compilation(
      parent,
      input,
      graph,
      contracts,
      manifests~,
      compilation_limits~,
    ).unwrap()
    assert_true(
      parent.program_compilation is Some(@publication_host.Tasks(original)) &&
      physical_equal(original, artifact),
    )
    let spent = parent.program_artifact_work_spent
    assert_true(spent > 0L)
    assert_true(
      prepare_request_model_compilation(
        parent,
        input,
        graph,
        contracts,
        manifests~,
        compilation_limits~,
      )
      is Err(Preparation(ForeignOriginal)),
    )
    assert_eq(parent.program_artifact_work_spent, spent)
    assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "Model compiler original input and current reentry cannot switch a selected constructor" {
  let active : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
  let reentered = Ref(0)
  let (parent, input, prepared) = request_model_input_fixture(current=() => {
    if active.val is Some(parent) &&
      parent.phase == Selecting &&
      parent.program_domain_compilation_inputs
      is Some(
        RequestModelCompilation(manifests, compilation_limits, contracts, graph)
      ) {
      assert_true(
        prepare_request_model_compilation(
          parent,
          parent.input.unwrap(),
          graph,
          contracts,
          manifests~,
          compilation_limits~,
        )
        is Err(Preparation(ForeignOriginal)),
      ) catch {
        _ => return false
      }
      assert_true(
        abort_request_preparation_after_cleanup(parent) is Err(WrongPhase),
      ) catch {
        _ => return false
      }
      reentered.val += 1
    }
    true
  })
  let holder = borrow_request_model_plan_input(parent, input).unwrap()
  let (_, graph) = request_model_graph_fixture(prepared)
  let (other, other_input, other_prepared) = request_model_input_fixture()
  let (_, foreign) = request_model_graph_fixture(other_prepared)
  let contracts = request_program_module_contracts()
  let manifests = request_program_module_manifests()
  let compilation_limits = @publication_host.client_standard_pure_compilation_limits()
  let before = request_preparation_accounting(parent)
  assert_true(
    prepare_request_model_compilation(
      parent,
      [1],
      graph,
      contracts,
      manifests~,
      compilation_limits~,
    )
    is Err(Preparation(ForeignOriginal)),
  )
  assert_true(
    prepare_request_model_compilation(
      parent,
      input,
      foreign,
      contracts,
      manifests~,
      compilation_limits~,
    )
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(request_preparation_accounting(parent), before)
  active.val = Some(parent)
  prepare_request_model_compilation(
    parent,
    input,
    graph,
    contracts,
    manifests~,
    compilation_limits~,
  ).unwrap()
  |> ignore
  assert_true(reentered.val > 0)
  active.val = None
  assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
  abort_request_preparation_after_cleanup(parent).unwrap()
  abort_request_preparation_after_cleanup(other).unwrap()
  assert_true(other_input.length() > 0)
}

///|
test "Model Scope refuses an independently compiled equivalent instead of replacing its parent artifact" {
  let (parent, input, plan, construction) = request_model_fixture()
  guard parent.program_compilation is Some(@publication_host.Tasks(original)) else {
    fail("Expected the original Task compilation")
  }
  let independent = @publication_host.issue_prepared_client_multi_infer_compilation(
    plan.prepared,
    [plan.graph],
    request_program_module_manifests(),
    @publication_host.client_standard_values_sequence_limits(),
    1000,
    10000,
    1000000,
    100000,
    100,
  ).unwrap()
  assert_false(physical_equal(original, independent))
  assert_eq(
    @publication_host.client_task_executable_plan_wire(original.plan),
    @publication_host.client_task_executable_plan_wire(independent.plan),
  )
  let compiled = @publication_host.issue_client_task_compiled_run(
    plan.prepared,
    independent,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_compiled_run_definition(
    compiled, "request-model", "same-original", "2026-10-31T00:00:00.000Z", "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let foreign = { ..plan, compiled, definition, }
  assert_true(
    prepare_request_model_read_scope(parent, input, foreign)
    is Err(ForeignOriginal),
  )
  assert_true(
    parent.program_model is None &&
    parent.program_compilation is Some(@publication_host.Tasks(actual)) &&
    physical_equal(actual, original),
  )
  let scope = prepare_request_model_read_scope(parent, input, plan).unwrap()
  complete_request_model_preparation(parent, input, plan).unwrap()
  assert_true(
    parent.program_compilation is None &&
    parent.program_domain_compilation_inputs is None &&
    parent.program_artifact_geometry is None,
  )
  @resources.return_preparation_body_borrow(construction).unwrap() |> ignore
  let run = begin_request_model_managed_run(parent, plan.request, scope).unwrap()
  assert_true(
    @publication_host.finish_client_model_read_scope(
      scope,
      plan.compiled,
      plan.definition,
      plan.graph,
      true,
    ).unwrap(),
  )
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
