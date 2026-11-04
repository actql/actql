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
    let retained = bytes +
      proof_retained +
      direct_selector_field +
      @execution.execution_capacity_retained_bytes(phase)
    let execution = bytes +
      proof_retained +
      proof_scratch +
      direct_selector_field +
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
