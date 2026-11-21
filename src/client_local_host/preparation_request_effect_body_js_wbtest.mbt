///|
// Original checked Mapping/limits and existing public Resource supplier.
// Empty physical providers are an explicit component port, not ordinary I/O.
fn request_effect_fixture(
  current? : () -> Bool = () => true,
  limits? : @publication_host.ClientEffectComputationLimits? = None,
  automatic? : Bool = false,
) -> (
  ClientRequestPreparation[Array[Int]],
  ClientProgramCheckPreparation[Array[Int], Unit],
  Array[Int],
  @decode.Cursor,
) raise {
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    "sha256:05ee9059ef5f173069a3f3f1896e16ee62d34d0c842d81e9b0f8421db62e67a8",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let text =
    #|{"version":"actql/0.1","id":"request-effect-original","params":{"n":{"type":"number","default":7}},"stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"},{"derive":{"amount":"id + $n"},"as":"changed"}],"results":{"rows":{"from":"changed","fields":["id","amount"]}},"effects":{"save":{"update":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"rows"},"id":"id","set":{"Name":{"field":"amount"}}}}}}],"results":{"rows":{"from":{"stage":"main","result":"rows"}}}}
  let supplied = @decode.admit_raw_json(
    @json.parse("{\"n\":9}"),
    {
      start_byte: 0,
      end_byte: 7,
      start_line: 1,
      start_column: 1,
      end_line: 1,
      end_column: 8,
      source_path: "<original-effect-parameters>",
    },
    {
      max_nodes: 10,
      max_depth: 4,
      max_string_bytes: 16,
      max_total_string_bytes: 64,
    },
  ).unwrap()
  let (parent, child, _, input) = registration_parent_fixture(
    current~,
    text~,
    environment=Some(environment),
    effect_limits=Some(
      limits.unwrap_or(
        @publication_host.client_standard_effect_computation_limits(),
      ),
    ),
    supplied=Some(supplied),
    computation_limits=if automatic {
      Some(
        (
          @publication_host.client_standard_program_preparation_limits(),
          limits.unwrap_or(
            @publication_host.client_standard_effect_computation_limits(),
          ),
        ),
      )
    } else {
      None
    },
  )
  (parent, child, input, supplied)
}

///|
fn request_effect_compile_fixture(
  current? : () -> Bool = () => true,
) -> (
  ClientRequestPreparation[Array[Int]],
  Array[Int],
  @publication_host.PreparedClientEffectComputation,
) raise {
  let (parent, child, input, _) = request_effect_fixture(current~)
  finish_effect_program_check_preparation(child).unwrap() |> ignore
  let prepared = compile_effect_program_check_preparation(child).unwrap()
  assert_true(
    physical_equal(
      continue_request_effect_preparation(parent, input).unwrap(),
      prepared,
    ),
  )
  (parent, input, prepared)
}

///|
fn request_effect_plan_fixture(
  prepared : @publication_host.PreparedClientEffectComputation,
) -> (ClientInstalledEffectManagedPlan, @publication_host.ClientRequestIdentity) {
  let request = @publication_host.prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "effect-operation-plan",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  (effect_operation_plan_fixture(prepared, request, contracts), request)
}

///|
test "actual Effect Request keeps original headers Parameters checked Program and compiler before typed continuation" {
  let (parent, child, input, supplied) = request_effect_fixture()
  let program = parent.held_program.unwrap()
  let registry = child.check_registry.unwrap()
  assert_eq(@syntax.program_preparation_data(program).effect_members, 1)
  assert_true(finish_program_check_preparation(child) is Err(WrongPhase))
  let candidate = finish_effect_program_check_preparation(child).unwrap()
  assert_true(
    @checked.finish_parsed_effect_check_registry(registry)
    is Err(Phase(AlreadyConsumed)),
  )
  let checked = @checked.effect_computation_checked_program(candidate)
  assert_true(physical_equal(@checked.checked_source_program(checked), program))
  assert_true(
    physical_equal(
      @checked.effect_computation_supplied(candidate).unwrap(),
      supplied,
    ),
  )
  assert_true(finish_effect_program_check_preparation(child) is Err(WrongPhase))
  let prepared = compile_effect_program_check_preparation(child).unwrap()
  let static_candidate = @publication_host.prepared_client_effect_computation_candidate(
    prepared,
  )
  assert_true(
    physical_equal(
      @checked.effect_program_static_checked_computation(static_candidate),
      checked,
    ),
  )
  assert_true(
    physical_equal(
      @publication_host.prepared_client_effect_computation_source(prepared),
      program,
    ),
  )
  let graph = @strategy.checked_effect_computation_graph(
    @publication_host.prepared_client_effect_computation_graph(prepared),
  )
  let task = @strategy.graph_task_owner(graph, 0).unwrap()
  assert_eq(
    @admitted.canonical_scalar_text(
      @lower.parameter_value(task, "n").unwrap(),
      32,
    ),
    Some("9"),
  )
  assert_true(child.compilation_known_work > 0L)
  assert_true(
    compile_effect_program_check_preparation(child) is Err(WrongPhase),
  )
  let old = parent.capacity
  let before = @resources.ledger_usage(parent.ledger)
  assert_true(
    physical_equal(
      continue_request_effect_preparation(parent, input).unwrap(),
      prepared,
    ),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  assert_true(
    child.phase == Transferred &&
    parent.program_check is None &&
    parent.program_json is None,
  )
  assert_true(
    @resources.abort_preparation_capacity_after_cleanup(old, input)
    is Err(ForeignOriginal),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "actual Effect Request refuses an independently prepared equal Plan before consuming its original" {
  let (parent, input, prepared) = request_effect_compile_fixture()
  reserve_request_effect_plan(parent, input).unwrap()
  let (other, other_input, foreign) = request_effect_compile_fixture()
  reserve_request_effect_plan(other, other_input).unwrap()
  let (foreign_plan, _) = request_effect_plan_fixture(foreign)
  assert_true(
    complete_request_effect_preparation(parent, input, foreign_plan)
    is Err(WrongPhase),
  )
  assert_true(parent.effect_plan is None && !parent.program_body_attempted)
  let (plan, _) = request_effect_plan_fixture(prepared)
  complete_request_effect_preparation(parent, input, plan).unwrap()
  abort_request_preparation_after_cleanup(other).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "actual Effect Request adopts the same initial Plan and body while manager custody delays retirement" {
  let (parent, input, prepared) = request_effect_compile_fixture()
  reserve_request_effect_plan(parent, input).unwrap()
  let (plan, request) = request_effect_plan_fixture(prepared)
  complete_request_effect_preparation(parent, input, plan).unwrap()
  let holder = borrow_request_effect_preparation(parent).unwrap()
  assert_true(
    physical_equal(
      @resources.preparation_body_borrow_value(holder).unwrap(),
      plan,
    ),
  )
  let copied = @publication_host.prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "effect-operation-plan",
    "sha256:" + "b".repeat(64),
  ).unwrap()
  assert_true(
    begin_request_effect_managed_run(parent, copied) is Err(ForeignOriginal),
  )
  let run = begin_request_effect_managed_run(parent, request).unwrap()
  assert_true(
    parent.phase == Selected &&
    parent.effect_capacity is None &&
    parent.effect_plan is None &&
    parent.compiled_effect is None,
  )
  assert_true(
    abort_request_preparation_after_cleanup(parent) is Err(WrongPhase),
  )
  assert_true(
    physical_equal(
      installed_effect_managed_operation_plan(run, prepared, request).unwrap(),
      plan,
    ),
  )
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(@resources.preparation_body_retirement_started(holder))
  assert_true(@resources.return_preparation_body_borrow(holder).unwrap())
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_execution_bytes, 0L)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "one actual Effect Request Run handoff observes original external current once" {
  let calls = Ref(0)
  let (parent, input, prepared) = request_effect_compile_fixture(current=() => {
    calls.val += 1
    true
  })
  reserve_request_effect_plan(parent, input).unwrap()
  let (plan, request) = request_effect_plan_fixture(prepared)
  complete_request_effect_preparation(parent, input, plan).unwrap()
  let before = calls.val
  let run = begin_request_effect_managed_run(parent, request).unwrap()
  let observed = calls.val - before
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  assert_eq(observed, 1)
}

///|
test "Effect Request Plan grow keeps the same compiled original and quote at both one-byte-short boundaries" {
  for retention in [true, false] {
    let (parent, input, prepared) = request_effect_compile_fixture()
    let capacity = parent.effect_capacity.unwrap()
    let before = @resources.preparation_capacity_working_extents(
      capacity, input,
    ).unwrap()
    let bytes = program_check_data_extent_cost(parent.program_data.unwrap()).unwrap()
    let providers = @local.local_module_provider_field_inventory(
      @strategy.graph_task_count(
        @strategy.checked_effect_computation_graph(
          @publication_host.prepared_client_effect_computation_graph(prepared),
        ),
      ),
    ).unwrap()
    let phase = installed_effect_control_phase_quote_capacity()
    // The existing generic Plan constructor also backs its checked-node proof
    // before entry. The previous data-only fixture omitted those live frames.
    let proof_retained = client_local_value_node_proof_retained_bytes().unwrap()
    let proof_scratch = client_local_value_node_proof_scratch_bytes().unwrap()
    // The empty Direct selection retains its original Plan reference even
    // though this Effect fixture captures no Source or coordinate arrays.
    let direct_selector_field = @execution.preparation_representation_cost({
      record_headers: 0L,
      reference_slots: 1L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }).unwrap()
    let (member_retained, member_execution) = installed_effect_member_selection_layout(
      1,
    ).unwrap()
    // The same no-Model Plan still retains its empty selection field,
    // early publication receipt and keyed-plan field before constructor entry.
    let (model_retained, model_execution) = installed_model_selection_layout(0).unwrap()
    let receipt = installed_effect_early_publication_receipt_capacity()
    let keyed_field = installed_effect_keyed_plan_field_bytes()
    let retained = bytes +
      providers.retained_bytes +
      2L * 8L +
      proof_retained +
      direct_selector_field +
      member_retained +
      model_retained +
      @execution.execution_capacity_retained_bytes(receipt) +
      keyed_field +
      @execution.execution_capacity_retained_bytes(phase)
    let execution = bytes +
      providers.execution_bytes +
      4L * 8L +
      proof_retained +
      proof_scratch +
      direct_selector_field +
      member_execution +
      model_execution +
      @execution.execution_capacity_execution_bytes(receipt) +
      keyed_field +
      @execution.execution_capacity_execution_bytes(phase)
    let limits = @resources.ledger_limits(parent.ledger)
    let block = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - before.0 - retained + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - before.1 - execution + 1L
      },
    ).unwrap()
    let result = reserve_request_effect_plan(parent, input)
    assert_true(
      if retention {
        result is Err(Capacity(Resource(RetentionLimit)))
      } else {
        result is Err(Capacity(Resource(ExecutionLimit)))
      },
    )
    assert_eq(
      parent.program_plan_quote,
      Some((before.0 + retained, before.1 + execution)),
    )
    assert_true(
      parent.phase == EffectPlanQuoted &&
      physical_equal(parent.compiled_effect.unwrap(), prepared),
    )
    assert_eq(
      @resources.preparation_capacity_working_extents(capacity, input),
      Ok(before),
    )
    @resources.settle_capacity(parent.ledger, block).unwrap()
    reserve_request_effect_plan(parent, input).unwrap()
    assert_true(parent.phase == EffectPlanReserved)
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "Effect Request immutable limits DATA does not observe current while the real Run boundary fences reentry" {
  let action : Ref[(() -> Unit)?] = Ref(None)
  let calls = Ref(0)
  let flags = Ref(0)
  let (parent, input, prepared) = request_effect_compile_fixture(current=() => {
    calls.val += 1
    if action.val is Some(run) {
      run()
    }
    true
  })
  reserve_request_effect_plan(parent, input).unwrap()
  let (plan, request) = request_effect_plan_fixture(prepared)
  complete_request_effect_preparation(parent, input, plan).unwrap()
  let before = calls.val
  let limits = preparation_initial_limits(parent.initial, input).unwrap()
  assert_true(physical_equal(limits, @resources.ledger_limits(parent.ledger)))
  assert_true(
    preparation_initial_limits(parent.initial, [1]) is Err(ForeignOriginal),
  )
  assert_eq(calls.val, before)
  action.val = Some(() => {
    if begin_request_effect_managed_run(parent, request) is Err(ForeignOriginal) {
      flags.val += 1
    }
    if borrow_request_effect_preparation(parent) is Err(WrongPhase) {
      flags.val += 2
    }
    if abort_request_preparation_after_cleanup(parent) is Err(WrongPhase) {
      flags.val += 4
    }
  })
  let run = begin_request_effect_managed_run(parent, request).unwrap()
  action.val = None
  assert_eq(calls.val - before, 1)
  assert_eq(flags.val, 7)
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Effect Request retains typed original lowering refusal and its claimed work phase through abort" {
  let original = @publication_host.client_standard_effect_computation_limits()
  let limited = {
    ..original,
    program: {
      ..original.program,
      lowering: { ..original.program.lowering, max_work: 0, },
    },
  }
  let (parent, child, input, _) = request_effect_fixture(limits=Some(limited))
  finish_effect_program_check_preparation(child).unwrap() |> ignore
  assert_true(
    compile_effect_program_check_preparation(child)
    is Err(EffectCompilation(Stage(Lowering(_)))),
  )
  assert_true(
    child.phase == CompilationFailed &&
    child.compiled_effect is None &&
    child.work is None,
  )
  // Preparation receipts are their original finite semantic meter, not the
  // dispatch Ledger.planning_work counter. This failed lowering reports only
  // its known completed-pass prefix; it cannot claim/refill the phase again.
  assert_eq(child.compilation_known_work, 0L)
  assert_true(
    @resources.begin_preparation_phase_work64(
      parent.capacity,
      input,
      @resources.LowerAndGraph,
      0L,
    )
    is Err(AlreadyClaimed),
  )
  assert_true(parent.effect_capacity is None)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "static Effect Request Plan uses the same checked compiler without body Run or recheck" {
  let action : Ref[(() -> Unit)?] = Ref(None)
  let reentry = Ref(0)
  let (parent, input, prepared) = request_effect_compile_fixture(current=() => {
    if action.val is Some(run) {
      run()
    }
    true
  })
  let checks = parent._observed_semantic_check_calls
  let compiles = parent._observed_program_compile_calls
  action.val = Some(() => {
    if request_prepared_static_plan_view(
        parent,
        input,
        request_program_module_manifests(),
        65536,
        8192,
        64,
      )
      is Err(Preparation(WrongPhase)) {
      reentry.val += 1
    }
  })
  let wire = request_prepared_static_plan_view(
    parent,
    input,
    request_program_module_manifests(),
    65536,
    8192,
    64,
  ).unwrap()
  action.val = None
  assert_true(reentry.val > 0)
  assert_true(wire.contains("actql-effectful-static-plan-view/0.1"), msg=wire)
  assert_true(wire.contains("\"provider_io\":0"), msg=wire)
  assert_true(wire.contains("\"reason\":\"not_sealed\""), msg=wire)
  assert_true(wire.contains("\"state\":\"unknown\""), msg=wire)
  assert_true(!wire.contains("run_ref"))
  assert_true(parent.phase == EffectCompiled)
  assert_true(parent.submitted_intent is None)
  assert_true(physical_equal(parent.compiled_effect.unwrap(), prepared))
  assert_eq(parent._observed_semantic_check_calls, checks)
  assert_eq(parent._observed_program_compile_calls, compiles)
  assert_true(
    request_prepared_static_plan_view(
      parent,
      input,
      request_program_module_manifests(),
      16,
      8192,
      64,
    )
    is Err(Preparation(Policy)),
  )
  assert_true(parent.phase == EffectCompiled)
  assert_true(physical_equal(parent.compiled_effect.unwrap(), prepared))
  assert_eq(parent._observed_program_compile_calls, compiles)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "static Effect Request Plan refuses foreign or noncurrent originals before projection" {
  let current = Ref(true)
  let (parent, input, prepared) = request_effect_compile_fixture(current=() => {
    current.val
  })
  let before = @resources.ledger_usage(parent.ledger)
  assert_true(
    request_prepared_static_plan_view(
      parent,
      input.copy(),
      request_program_module_manifests(),
      65536,
      8192,
      64,
    )
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), before)
  current.val = false
  assert_true(
    request_prepared_static_plan_view(
      parent,
      input,
      request_program_module_manifests(),
      65536,
      8192,
      64,
    )
    is Err(Preparation(Capacity(_))),
  )
  assert_true(parent.phase == EffectCompiled)
  assert_true(physical_equal(parent.compiled_effect.unwrap(), prepared))
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "static Effect Context measures and emits on the original working Request" {
  let current = Ref(true)
  let (parent, input, prepared) = request_effect_compile_fixture(current=() => {
    current.val
  })
  let manifests = request_program_module_manifests()
  let compiled = @publication_host.issue_prepared_client_effect_compilation(
    prepared,
    manifests,
    @publication_host.client_standard_values_sequence_limits(),
    1000,
    1000,
    65536,
    8192,
    64,
  ).unwrap()
  let (original, _) = @publication_host.capture_client_static_effect_explanation_original(
    prepared, compiled, 65536, 8192, 64,
  ).unwrap()
  let build = (candidate, bytes) => {
    construct_request_static_effect_context(
      parent, candidate, original, compiled, bytes, 8192, 64, 10000,
    )
  }
  let capacity = parent.effect_capacity.unwrap()
  let extents = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let usage = @resources.ledger_usage(parent.ledger)
  let entry = static_context_measurement_bytes +
    client_static_plan_quote_construction_bytes()
  let free = @resources.ledger_limits(parent.ledger).retained_bytes -
    usage.held_bytes -
    usage.reserved_retention_bytes
  assert_true(free >= entry)
  let blocker = @resources.reserve_capacity(
    parent.ledger,
    free - entry + 1L,
    0L,
  ).unwrap()
  assert_true(build(input, 65536) is Err(Preparation(Capacity(_))))
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input).unwrap(),
    extents,
  )
  @resources.settle_capacity(parent.ledger, blocker).unwrap()
  assert_true(build(input.copy(), 65536) is Err(Preparation(ForeignOriginal)))
  let wire = match build(input, 65536) {
    Ok(value) => value
    Err(issue) => fail(@debug.to_string(issue))
  }
  assert_true(wire.contains("actql-explanation-context/0.1"))
  assert_true(wire.contains("\"write_fields\":{\"fields\":[\"Name\"]"))
  assert_true(wire.contains("\"name\":\"rows\""))
  assert_true(!wire.contains("run_ref"))
  let completed = @resources.preparation_capacity_working_extents(
    capacity, input,
  ).unwrap()
  assert_true(completed.0 > extents.0 + entry)
  assert_true(completed.1 > extents.1 + entry)
  assert_true(parent.phase == EffectCompiled)
  assert_true(physical_equal(parent.effect_capacity.unwrap(), capacity))
  current.val = false
  assert_true(build(input, 65536) is Err(Preparation(Capacity(_))))
  current.val = true
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "static Effect Explanation pairs Facts and Context with one Plan and final current fence" {
  let calls = Ref(0)
  let refuse_at : Ref[Int?] = Ref(None)
  let (parent, input, prepared) = request_effect_compile_fixture(current=() => {
    calls.val += 1
    refuse_at.val != Some(calls.val)
  })
  let compiled = @publication_host.issue_prepared_client_effect_compilation(
    prepared,
    request_program_module_manifests(),
    @publication_host.client_standard_values_sequence_limits(),
    1000,
    1000,
    65536,
    8192,
    64,
  ).unwrap()
  let (original, plan) = @publication_host.capture_client_static_effect_explanation_original(
    prepared, compiled, 65536, 8192, 64,
  ).unwrap()
  let read_pair = () => {
    construct_request_static_effect_explanation(
      parent, input, original, compiled, 65536, 8192, 64, 10000,
    )
  }
  let before = calls.val
  let (facts, context) = match read_pair() {
    Ok(value) => value
    Err(issue) => fail(@debug.to_string(issue))
  }
  let checks = calls.val - before
  assert_true(checks > 1)
  let parse = (name, wire) => {
    @publication.parse_interactive_run_control_shape(
      name, wire, 65536, 8192, 64,
    ).unwrap()
  }
  let plan = parse("effectful_static_plan_view", plan)
  let base_view = @identity.object_field(
    @identity.object_field(plan, "computation").unwrap(),
    "plan_view",
  ).unwrap()
  let plan_map = @identity.object_field(base_view, "logical_map").unwrap()
  let facts = parse("explanation_facts", facts)
  let context_binding = @identity.object_field(
    parse("explanation_context", context),
    "binding",
  ).unwrap()
  guard @identity.object_field(plan_map, "self_cid")
    is Some(@identity.String(map_cid)) &&
    @identity.object_field(base_view, "compiled_plan_cid")
    is Some(@identity.String(plan_cid)) else {
    fail("original static Plan binding is required")
  }
  for facet in [facts, context_binding] {
    assert_true(
      @identity.object_field(facet, "compiled_plan_cid")
      is Some(@identity.String(value)) &&
      value == plan_cid,
    )
    assert_true(
      @identity.object_field(facet, "logical_map_cid")
      is Some(@identity.String(value)) &&
      value == map_cid,
    )
  }
  // Observe the same synchronous sequence and revoke just its last current
  // check. Both admitted outputs are then withheld from the caller together.
  refuse_at.val = Some(calls.val + checks)
  assert_true(read_pair() is Err(Preparation(Capacity(_))))
  assert_eq(Some(calls.val), refuse_at.val)
  assert_true(parent.phase == EffectCompiled)
  refuse_at.val = None
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
