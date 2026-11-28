///|
// Original checked Mapping/limits and existing public Resource supplier.
// Empty physical providers are an explicit component port, not ordinary I/O.
fn request_effect_fixture(
  current? : () -> Bool = () => true,
  limits? : @publication_host.ClientEffectComputationLimits? = None,
  automatic? : Bool = false,
  write_input_before_last_step? : Bool = false,
  debug? : Bool = false,
) -> (
  ClientRequestPreparation[Array[Int]],
  ClientProgramCheckPreparation[Array[Int], Unit],
  Array[Int],
  @decode.Cursor,
) raise {
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    "sha256:40c45acbf81bdf192d79b7e8f65a5731ba6065b1d4b8cc7b4cab89ab4ac85c60",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let text =
    #|{"version":"actql/0.1","id":"request-effect-original","params":{"n":{"type":"number","default":7}},"stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"seed"},{"derive":{"amount":"id + $n"},"as":"changed"}],"results":{"rows":{"from":"changed","fields":["id","amount"]}},"effects":{"save":{"update":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"rows"},"id":"id","set":{"Name":{"field":"amount"}}}}}}],"results":{"rows":{"from":{"stage":"main","result":"rows"}}}}
  let text = if write_input_before_last_step {
    text
    .replace(
      old="\"results\":{\"rows\":{\"from\":\"changed\"",
      new="\"results\":{\"seed_rows\":{\"from\":\"seed\",\"fields\":[\"id\"]},\"rows\":{\"from\":\"changed\"",
    )
    .replace(
      old="\"result\":\"rows\"},\"id\"",
      new="\"result\":\"seed_rows\"},\"id\"",
    )
    .replace(
      old="\"Name\":{\"field\":\"amount\"}",
      new="\"Name\":{\"field\":\"id\"}",
    )
  } else {
    text
  }
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
    intent_wire=if debug {
      Some(
        "{\"kind\":\"program\",\"input\":" +
        text +
        ",\"parameters\":{\"n\":9},\"executionProfile\":\"debug\"}",
      )
    } else {
      None
    },
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
fn exercise_installed_effect_debug_map(restored : Bool) -> Unit raise {
  let live = Ref(true)
  let (parent, _, input, _) = request_effect_fixture(
    current=() => live.val,
    automatic=true,
    debug=true,
  )
  finish_request_computation_preparation(parent, input).unwrap()
  let submitted = request_submitted_intent_original(parent, input).unwrap()
  let prepared = parent.compiled_effect.unwrap()
  let (plan, request) = request_effect_plan_fixture(prepared)
  assert_eq(@strategy.graph_task_count(plan.graph), 2)
  let compilation = @publication_host.issue_prepared_client_effect_compilation(
    prepared,
    request_program_module_manifests(),
    @publication_host.client_standard_values_sequence_limits(),
    1000,
    1000,
    65536,
    8192,
    64,
  ).unwrap()
  let allowed = @publication_host.issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2026-11-25T00:00:00.000Z",
  ).unwrap()
  let issue_definition = id => {
    @publication_host.issue_client_effect_run_definition(
      allowed, "scope", id, "2026-11-24T00:00:00.000Z", "2026-11-25T00:00:00.000Z",
    ).unwrap()
  }
  let definition = issue_definition("effect-debug-map")
  let bound = @publication_host.bind_client_effect_compiled_run(
    prepared, allowed, definition,
  ).unwrap()
  let sibling_definition = issue_definition("sibling-effect-debug-map")
  let sibling = @publication_host.bind_client_effect_compiled_run(
    prepared, allowed, sibling_definition,
  ).unwrap()
  let capacity = parent.effect_capacity.unwrap()
  let before_capture = @resources.preparation_capacity_working_extents(
    capacity, input,
  ).unwrap()
  let scope = try_capture_request_effect_run_explanation(
      parent, input, allowed, definition, 65536, 8192, 64, 10000,
    )
    .unwrap()
    .unwrap()
  let captured = @resources.preparation_capacity_working_extents(
    capacity, input,
  ).unwrap()
  let map = scope.original.unwrap().debug_map.unwrap().0
  let cid = @publication.run_evidence_value_identity(map)
  let backing = installed_effect_debug_map_backing(map).unwrap()
  let wire = original_effect_run_explanation_facets(scope, definition).unwrap().plan
  let view = @json.parse(wire)
  guard view is Object(fields) &&
    fields.get("logical_map") is Some(Object(logical)) &&
    logical.get("steps") is Some(Array(steps)) &&
    steps[0] is Object(first) &&
    first.get("step_id") is Some(String(step)) else {
    fail("the original Plan contains the first Step")
  }
  assert_true(logical.get("self_cid") is Some(String(value)) && value == cid)
  reserve_request_effect_plan(parent, input).unwrap()
  complete_request_effect_preparation(parent, input, plan).unwrap()
  let run = begin_request_effect_managed_run(parent, request).unwrap()
  let holder = effect_unit_publication_body(run, plan, request).unwrap()
  let selected_map = if restored {
    // Re-admit the saved bytes. The new path must survive the loss of the
    // original Explanation alias and reserve backing for this new token.
    let wire = @publication.run_evidence_value_json(map)
    discard_original_effect_run_explanation(scope, definition, reclaim=true).unwrap()
    let selected = @publication.admit_run_evidence_value(
      "logical_map", wire, 65536, 8192, 64,
    ).unwrap()
    assert_false(physical_equal(selected, map))
    selected
  } else {
    map
  }
  let before = @resources.preparation_body_borrow_reserved_extents(holder).unwrap()
  let work = 1 +
    12 * steps.length() +
    @strategy.graph_data_count(plan.graph) +
    @strategy.graph_control_count(plan.graph)
  let definition_cid = @publication.publication_contract_identity(definition)
  let select = (bound, max_work) => {
    if restored {
      restore_installed_effect_debug_map(
        run, bound, request, selected_map, definition_cid, cid, step, max_work,
      )
    } else {
      retain_installed_effect_debug_map(
        run, bound, request, submitted, scope, max_work,
      )
    }
  }
  assert_true(select(sibling, work) is Err(ForeignOriginal))
  if restored {
    let foreign = "sha256:" + "f".repeat(64)
    assert_true(
      restore_installed_effect_debug_map(
        run, bound, request, selected_map, definition_cid, foreign, step, work,
      )
      is Err(ForeignOriginal),
    )
    assert_true(
      restore_installed_effect_debug_map(
        run, bound, request, selected_map, definition_cid, cid, foreign, work,
      )
      is Err(ForeignOriginal),
    )
    assert_true(run.effect_debug_map is None)
  }
  let unrelated = @publication_host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":" +
    debug_original_values_document +
    ",\"parameters\":null,\"executionProfile\":\"debug\"}",
    65536,
    8192,
    64,
  ).unwrap()
  if !restored {
    assert_true(
      retain_installed_effect_debug_map(
        run, bound, request, unrelated, scope, work,
      )
      is Err(ForeignOriginal),
    )
  }
  let before_work = @resources.ledger_usage(parent.ledger).planning_work
  assert_true(select(bound, work - 1) is Err(Ledger(PlanningLimit)))
  assert_eq(@resources.ledger_usage(parent.ledger).planning_work, before_work)
  for retention in [true, false] {
    let limits = @resources.ledger_limits(parent.ledger)
    let usage = @resources.ledger_usage(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes -
        usage.held_bytes -
        usage.reserved_retention_bytes -
        backing +
        1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - usage.reserved_execution_bytes - backing + 1L
      },
    ).unwrap()
    let refused = select(bound, work)
    assert_true(
      if retention {
        refused is Err(Preparation(Resource(RetentionLimit)))
      } else {
        refused is Err(Preparation(Resource(ExecutionLimit)))
      },
    )
    assert_true(
      installed_effect_debug_entry(run, bound, request, definition_cid)
      is Err(ForeignOriginal),
    )
    assert_eq(
      @resources.preparation_body_borrow_reserved_extents(holder).unwrap(),
      before,
    )
    assert_eq(@resources.ledger_usage(parent.ledger).attempts, 0)
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
  }
  select(bound, work).unwrap()
  assert_true(select(bound, work) is Err(AlreadyBound))
  assert_true(physical_equal(run.effect_debug_map.unwrap().map, selected_map))
  let returned = if restored {
    (0L, 0L)
  } else {
    discard_original_effect_run_explanation(scope, definition, reclaim=true).unwrap()
    (captured.0 - before_capture.0, captured.1 - before_capture.1)
  }
  assert_eq(
    @resources.preparation_body_borrow_reserved_extents(holder).unwrap(),
    (before.0 + backing - returned.0, before.1 + backing - returned.1),
  )
  assert_eq(
    installed_effect_debug_entry(run, bound, request, definition_cid).unwrap(),
    (step, cid),
  )
  assert_true(
    installed_effect_debug_entry(run, sibling, request, definition_cid)
    is Err(ForeignOriginal),
  )
  assert_true(
    installed_effect_debug_entry(
      run,
      bound,
      request,
      @publication.publication_contract_identity(sibling_definition),
    )
    is Err(ForeignOriginal),
  )
  assert_true(run.source_free_captured is None)
  assert_eq(@resources.ledger_usage(parent.ledger).attempts, 0)
  guard steps[1] is Object(second) &&
    second.get("step_id") is Some(String(next_step)) else {
    fail("the original Plan contains the next Step")
  }
  assert_not_eq(step, next_step)
  let (host, captured_run, _) = open_installed_effect_managed_host(run, bound, [])
    .unwrap()
    .unwrap()
  assert_true(
    installed_effect_debug_entry(run, bound, request, definition_cid)
    is Err(ForeignOriginal),
  )
  let dag = @strategy.captured_effect_run_dag(captured_run)
  let readiness_work = @strategy.graph_task_count(plan.graph) *
    (
      1 +
      @strategy.graph_data_count(plan.graph) +
      @strategy.graph_control_count(plan.graph)
    )
  let pause_work = work + readiness_work
  let command_work = pause_work + readiness_work
  let account = @authorization.admit_account_configuration({
    account_id: "effect-compute-debug",
    entries: [
      {
        entry_id: "original-debug-control",
        outcome: Allow,
        scope: {
          principal: AnyOf(["user"]),
          connection: AnyOf(["local"]),
          resource: AnyOf(["run"]),
          operation: AnyOf(["pause", "resume"]),
        },
        exclusions: [],
      },
    ],
    bootstrap: None,
  }).unwrap()
  assert_eq(
    prepare_installed_effect_debug_control(
      run, sibling, request, captured_run, account, "user", "local",
    ),
    Err(ForeignOwner),
  )
  assert_eq(
    prepare_installed_effect_debug_control(
      run, bound, request, captured_run, account, "foreign", "local",
    ),
    Err(AuthorizationMismatch),
  )
  prepare_installed_effect_debug_control(
    run, bound, request, captured_run, account, "user", "local",
  ).unwrap()
  let hooks = @strategy.captured_task_boundary_hooks(dag).unwrap()
  assert_eq(@strategy.captured_task_control_entry_task(dag, hooks), Some(0))
  assert_eq(@strategy.next_captured_task(dag), None)
  assert_eq(@resources.ledger_usage(parent.ledger).attempts, 0)
  let command = (start, boundary, single) => {
    command_installed_effect_debug_control(
      run, bound, request, captured_run, account, "user", "local", start, boundary,
      single, command_work,
    )
  }
  let runnable = start => {
    installed_effect_debug_control_runnable(
      run, bound, request, captured_run, start,
    )
  }
  assert_eq(command(0, None, true), Err(StaleRevision))
  assert_eq(runnable(4), Err(StaleRevision))
  command(4, None, true).unwrap()
  assert_eq(runnable(4), Ok(true))
  assert_eq(runnable(5), Err(StaleRevision))
  let pause = (revision, max_work) => {
    installed_effect_debug_task_pause(
      run, bound, request, captured_run, revision, max_work,
    )
  }
  let observation = Ref(None)
  let generated = execute_retained_effect_local_tasks_guarded(
    host,
    captured_run,
    64,
    10000,
    () => {
      if observation.val is None &&
        @strategy.captured_task_control_state(dag, hooks) is Ok((2, Paused)) {
        let generation = @strategy.captured_dag_generation(dag)
        let actual = pause(4, pause_work)
        let no_work = pause(4, pause_work - 1)
        let foreign_start = pause(5, pause_work)
        let foreign_next = command(4, Some((2, step, step, generation)), false)
        let parked = runnable(4)
        let unchanged = @strategy.captured_task_control_state(dag, hooks)
        let attempts = @resources.ledger_usage(parent.ledger).attempts
        let continued = command(
          4,
          Some((2, step, next_step, generation)),
          false,
        )
        observation.val = Some(
          (
            generation, actual, no_work, foreign_start, foreign_next, unchanged,
            parked, attempts, continued,
          ),
        )
        return continued is Ok(_)
      }
      true
    },
    require_live=Some(() => true),
  )
  guard observation.val
    is Some(
      (
        generation,
        actual,
        no_work,
        foreign_start,
        foreign_next,
        unchanged,
        parked,
        attempts,
        continued,
      )
    ) else {
    fail("the real first Compute did not reach the next original Step")
  }
  assert_eq(actual, Ok((2, step, next_step, generation)))
  assert_eq(no_work, Err(Resource(PlanningLimit)))
  assert_eq(foreign_start, Err(StaleRevision))
  assert_eq(foreign_next, Err(StaleRevision))
  assert_eq(unchanged, Ok((2, Paused)))
  assert_eq(parked, Ok(false))
  assert_eq(attempts, 1)
  assert_eq(continued, Ok(()))
  let generated = generated.unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).attempts, 2)
  assert_eq(generated.rows().unwrap(), ["{\"amount\":10,\"id\":1}"])
  assert_true(generated.close())
  live.val = false
  assert_true(
    installed_effect_debug_entry(run, bound, request, definition_cid) is Err(_),
  )
  retire_installed_managed_run(run).unwrap()
  assert_true(run.effect_debug_map is None)
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "the adopted Effect Debug Run keeps only the exact funded Map after Journal scratch return" {
  exercise_installed_effect_debug_map(false)
}

///|
test "the resumed Effect Compute adopts the retained original Map and exact first Step" {
  exercise_installed_effect_debug_map(true)
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

///|
test "first Effect Run Explanation borrows its issued compilation and holds all facets on the Request" {
  let live = Ref(true)
  let (parent, input, prepared) = request_effect_compile_fixture(current=() => {
    live.val
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
  let issued = (context : String) => {
    @publication_host.issue_client_effect_allowed_run(
      compiled,
      "sha256:" + context.repeat(64),
      "sha256:" + "b".repeat(64),
      "2026-11-25T00:00:00.000Z",
    ).unwrap()
  }
  let issue_definition = (allowed, id) => {
    @publication_host.issue_client_effect_run_definition(
      allowed, "scope", id, "2026-11-24T00:00:00.000Z", "2026-11-25T00:00:00.000Z",
    ).unwrap()
  }
  let allowed = issued("a")
  let definition = issue_definition(allowed, "first-effect-explanation")
  let foreign = issue_definition(issued("c"), "foreign-effect-explanation")
  let sibling = issue_definition(allowed, "sibling-effect-explanation")
  let holder = borrow_request_effect_plan_input(parent, input).unwrap()
  let capacity = parent.effect_capacity.unwrap()
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let capture = (candidate, run) => {
    capture_request_effect_run_explanation(
      parent, candidate, allowed, run, 65536, 8192, 64, 10000,
    )
  }
  assert_true(
    capture(input.copy(), definition) is Err(Preparation(ForeignOriginal)),
  )
  assert_true(capture(input, foreign) is Err(Preparation(ForeignOriginal)))
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input).unwrap(),
    before,
  )
  let usage = @resources.ledger_usage(parent.ledger)
  let free = @resources.ledger_limits(parent.ledger).retained_bytes -
    usage.held_bytes -
    usage.reserved_retention_bytes
  let unavailable = @resources.reserve_capacity(parent.ledger, free - 1L, 0L).unwrap()
  assert_true(capture(input, definition) is Err(Preparation(Capacity(_))))
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input).unwrap(),
    before,
  )
  assert_true(
    try_capture_request_effect_run_explanation(
      parent, input, allowed, definition, 65536, 8192, 64, 10000,
    )
    is Ok(None),
  )
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input).unwrap(),
    before,
  )
  @resources.settle_capacity(parent.ledger, unavailable).unwrap()
  let limited = 1024
  // Each original key and port fits on its own. The combined map cannot fit.
  assert_true(
    @publication_host.client_effect_static_computation_plan_view(
      prepared, compiled, limited, 8192, 64,
    )
    is Err(Evidence(RunEvidenceInvalidWire)),
  )
  assert_true(
    try_capture_request_effect_run_explanation(
      parent, input, allowed, foreign, limited, 8192, 64, 10000,
    )
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input).unwrap(),
    before,
  )
  assert_true(
    try_capture_request_effect_run_explanation(
      parent, input, allowed, definition, limited, 8192, 64, 10000,
    )
    is Ok(None),
  )
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input).unwrap(),
    before,
  )
  let plan = @publication_host.client_effect_static_computation_plan_view(
    prepared, compiled, 65536, 8192, 64,
  ).unwrap()
  let effect = @publication_host.client_effectful_static_plan_view(
    prepared, compiled, 65536, 8192, 64,
  ).unwrap()
  let plan_bytes = @scalar.admit_utf8_length(plan, 65536).unwrap()
  let effect_bytes = @scalar.admit_utf8_length(effect, 65536).unwrap()
  assert_true(plan_bytes < effect_bytes - 1)
  // Keep the old strict errors and verify each new typed boundary on the
  // same checked compiler. The exact Effectful extent reproduces its wire.
  assert_true(
    @publication_host.client_effect_static_computation_plan_view(
      prepared,
      compiled,
      plan_bytes - 1,
      8192,
      64,
    )
    is Err(Encoding),
  )
  let original_plan = (bytes : Int) => {
    @publication_host.capture_client_static_effect_explanation_original(
      prepared, compiled, bytes, 8192, 64,
    )
  }
  assert_true(
    original_plan(plan_bytes - 1) is Err(Plan(Computation(ConstructionRefused))),
  )
  assert_true(
    @publication_host.client_effectful_static_plan_view(
      prepared,
      compiled,
      effect_bytes - 1,
      8192,
      64,
    )
    is Err(Encoding),
  )
  assert_true(
    original_plan(effect_bytes - 1) is Err(Encoding(@encode.OutputLimit)),
  )
  assert_eq(original_plan(effect_bytes).unwrap().1, effect)
  for bytes in [plan_bytes - 1, effect_bytes - 1] {
    assert_true(
      try_capture_request_effect_run_explanation(
        parent, input, allowed, definition, bytes, 8192, 64, 10000,
      )
      is Ok(None),
    )
    assert_eq(
      @resources.preparation_capacity_working_extents(capacity, input).unwrap(),
      before,
    )
  }
  let journal_scope = try_capture_request_effect_run_explanation(
      parent, input, allowed, definition, 65536, 8192, 64, 10000,
    )
    .unwrap()
    .unwrap()
  assert_true(
    original_effect_run_explanation_facets(journal_scope, definition) is Ok(_),
  )
  discard_original_effect_run_explanation(
    journal_scope,
    definition,
    reclaim=true,
  ).unwrap()
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input).unwrap(),
    before,
  )
  let original = capture(input, definition).unwrap()
  assert_true(
    original_effect_run_explanation_facets(original, sibling)
    is Err(Preparation(ForeignOriginal)),
  )
  let equal_wire = @publication.admit_publication_contract(
    "run_definition",
    @publication.publication_contract_json(definition),
    65536,
    8192,
    64,
  ).unwrap()
  assert_true(
    original_effect_run_explanation_facets(original, equal_wire)
    is Err(Preparation(ForeignOriginal)),
  )
  {
    let selected = original_effect_run_explanation_facets(original, definition).unwrap()
    assert_eq(
      selected.plan,
      @publication_host.client_effect_static_computation_plan_view(
        prepared, compiled, 65536, 8192, 64,
      ).unwrap(),
    )
    let original_plan = @publication_host.client_effect_compilation_compiled_plan(
      compiled,
    )
    assert_eq(
      selected.compiled_plan,
      @publication.publication_contract_json(original_plan),
    )
    let template = @publication_host.client_effect_compilation_template(
      compiled,
    )
    assert_eq(
      selected.invocation_template,
      @publication.run_evidence_value_json(template),
    )
    guard @json.parse(selected.invocation_template) is Object(template_fields) &&
      @json.parse(@publication.publication_contract_json(definition))
      is Object(definition_fields) else {
      fail("the original Template and Run Definition must be objects")
    }
    assert_true(
      definition_fields.get("invocation_template_cid") is Some(String(value)) &&
      value == @publication.run_evidence_value_identity(template),
    )
    assert_true(
      template_fields.get("check_environment_cid") is Some(String(value)) &&
      value ==
      @publication_host.prepared_client_effect_computation_environment_cid(
        prepared,
      ),
    )
    let plan_cid = @publication.publication_contract_identity(original_plan)
    let facts = @publication.parse_interactive_run_control_shape(
      "explanation_facts",
      selected.facts,
      65536,
      8192,
      64,
    ).unwrap()
    let context = @publication.parse_interactive_run_control_shape(
      "explanation_context",
      selected.context,
      65536,
      8192,
      64,
    ).unwrap()
    let binding = @identity.object_field(context, "binding").unwrap()
    assert_true(
      @identity.object_field(binding, "check_environment_cid")
      is Some(@identity.String(value)) &&
      value ==
      @publication_host.prepared_client_effect_computation_environment_cid(
        prepared,
      ),
    )
    for facet in [facts, binding] {
      assert_true(
        @identity.object_field(facet, "compiled_plan_cid")
        is Some(@identity.String(value)) &&
        value == plan_cid,
      )
    }
    guard @identity.object_field(facts, "logical_map_cid")
      is Some(@identity.String(map_cid)) else {
      fail("original map identity is required")
    }
    assert_true(
      @identity.object_field(binding, "logical_map_cid")
      is Some(@identity.String(value)) &&
      value == map_cid,
    )
    assert_true(
      selected.context.contains("\"write_fields\":{\"fields\":[\"Name\"]"),
    )
    let identity = @publication_host.prepared_client_effect_identity(prepared)
    let definition_cid = @publication.publication_contract_identity(definition)
    let read = (run, parameters, context, template, before_binding) => {
      @publication_host.retained_client_run_explanation_context(
        run,
        Some(original_plan),
        identity.program_definition_cid,
        parameters,
        Some(selected.plan),
        Some(selected.facts),
        context,
        template,
        "scope",
        definition_cid,
        65536,
        65536,
        8192,
        64,
        before_binding,
      )
    }
    let same_parameters = identity.parameter_values_cid
    let admit_binding = (_, _) => true
    let retained = read(
        equal_wire,
        same_parameters,
        Some(selected.context),
        Some(selected.invocation_template),
        admit_binding,
      )
      .unwrap()
      .unwrap()
    assert_eq(
      @identity.stringify_value(retained.context, 65536, 8192, 64),
      selected.context,
    )
    assert_eq(
      @identity.stringify_value(retained.facts, 65536, 8192, 64),
      selected.facts,
    )
    assert_eq(
      @identity.stringify_value(retained.plan, 65536, 8192, 64),
      selected.plan,
    )
    let other_cid = "sha256:" + "e".repeat(64)
    let environment = @publication_host.prepared_client_effect_computation_environment_cid(
      prepared,
    )
    let changed_context = selected.context.replace(
      old=environment,
      new=other_cid,
    )
    assert_true(changed_context != selected.context)
    assert_true(
      read(
        equal_wire,
        same_parameters,
        Some(changed_context),
        Some(selected.invocation_template),
        admit_binding,
      )
      is Err(ForeignOriginal),
    )
    template_fields.remove("bound_invocation_template_cid")
    template_fields["check_environment_cid"] = other_cid.to_json()
    let other_template = @publication.seal_run_evidence_value(
      "bound_invocation_template",
      Json::object(template_fields).stringify(),
      65536,
      8192,
      64,
    ).unwrap()
    let other_template_wire = @publication.run_evidence_value_json(
      other_template,
    )
    assert_eq(
      other_template_wire.length(),
      selected.invocation_template.length(),
    )
    assert_true(
      read(
        equal_wire,
        same_parameters,
        Some(changed_context),
        Some(other_template_wire),
        admit_binding,
      )
      is Err(ForeignOriginal),
    )
    assert_true(
      read(
        sibling,
        same_parameters,
        Some(selected.context),
        Some(selected.invocation_template),
        admit_binding,
      )
      is Err(ForeignOriginal),
    )
    assert_true(
      read(
        equal_wire,
        other_cid,
        Some(selected.context),
        Some(selected.invocation_template),
        admit_binding,
      )
      is Err(ForeignOriginal),
    )
    // A cold consumer starts a separate existing Request. Use the exact
    // issued originals above and an independently constructed scalar extent.
    let definition_wire = @publication.publication_contract_json(definition)
    let extent = wire => @scalar.admit_utf8_length(wire, 65536).unwrap()
    let base_extent = 142 +
      extent(definition_wire) +
      extent(selected.compiled_plan) +
      extent(selected.plan) +
      extent(selected.facts)
    let context_extent = extent(selected.context)
    let template_extent = extent(selected.invocation_template)
    for
      (context, template, expected) in [
        (Some(selected.context), Some(selected.invocation_template), 0),
        (Some(changed_context), Some(other_template_wire), 1),
        (Some(selected.context + " "), Some(selected.invocation_template), 2),
        (None, None, 3),
      ] {
      let reader_input = [4]
      let current = Ref(true)
      let reader = begin_request_preparation(
        request_parent_fixture(reader_input, current=() => current.val),
        reader_input,
        client_local_resource_policy(),
      ).unwrap()
      let original_capacity = reader.capacity
      begin_request_explanation_context_read(reader, reader_input).unwrap()
      let (stored, context_bytes, template_bytes) = if expected == 3 {
        (base_extent, 0, 0)
      } else {
        (
          base_extent + context_extent + template_extent + 64,
          context_extent,
          template_extent,
        )
      }
      if expected != 3 {
        assert_true(
          reserve_request_explanation_context_read(
            reader, reader_input, stored, context_bytes, 0, 65536, 8192, 64,
          )
          is Err(Policy),
        )
      }
      reserve_request_explanation_context_read(
        reader, reader_input, stored, context_bytes, template_bytes, 65536, 8192,
        64,
      ).unwrap()
      let read_selected = candidate => {
        read_request_explanation_context(
          reader,
          candidate,
          definition_wire,
          Some(selected.compiled_plan),
          Some(selected.plan),
          Some(selected.facts),
          context,
          template,
          identity.program_definition_cid,
          same_parameters,
          "scope",
          "sha256:" + "a".repeat(64),
          definition_cid,
          stored,
          65536,
          8192,
          64,
        )
      }
      assert_true(
        read_selected(reader_input.copy()) is Err(Preparation(ForeignOriginal)),
      )
      let value = read_selected(reader_input)
      match expected {
        0 => {
          let delivery = @publication.parse_interactive_run_control_shape(
            "run_explanation_context_view",
            value.unwrap(),
            65536,
            8192,
            64,
          ).unwrap()
          let explanation = @identity.object_field(delivery, "explanation").unwrap()
          let view = @identity.object_field(explanation, "view").unwrap()
          for
            (key, wire) in [
              ("context", selected.context),
              ("facts", selected.facts),
              ("plan", selected.plan),
            ] {
            assert_eq(
              @identity.stringify_value(
                @identity.object_field(view, key).unwrap(),
                65536,
                8192,
                64,
              ),
              wire,
            )
          }
        }
        1 => assert_true(value is Err(Projection(ForeignOriginal)))
        2 => assert_true(value is Err(ReadLimit))
        _ => {
          let delivery = @publication.parse_interactive_run_control_shape(
            "run_explanation_context_view",
            value.unwrap(),
            65536,
            8192,
            64,
          ).unwrap()
          let envelope = @identity.object_field(delivery, "explanation").unwrap()
          assert_true(
            @identity.object_field(envelope, "reason")
            is Some(@identity.String(reason)) &&
            reason == "not_retained",
          )
        }
      }
      assert_true(read_selected(reader_input) is Err(Preparation(WrongPhase)))
      assert_true(physical_equal(reader.capacity, original_capacity))
      abort_request_preparation_after_cleanup(reader).unwrap()
      assert_eq(@resources.ledger_usage(reader.ledger).live_reservations, 0)
    }
    assert_true(
      read(equal_wire, same_parameters, None, None, admit_binding) is Ok(None),
    )
    assert_true(
      read(
        equal_wire,
        same_parameters,
        Some(selected.context),
        None,
        admit_binding,
      )
      is Err(ForeignOriginal),
    )
    assert_true(
      read(
        equal_wire,
        same_parameters,
        Some(selected.context),
        Some(selected.invocation_template),
        (_, _) => false,
      )
      is Err(ConstructionUnavailable),
    )
  }
  let after = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  assert_true(after.0 > before.0)
  assert_true(after.1 > before.1)
  assert_true(parent.phase == EffectPlanReserved)
  live.val = false
  assert_true(
    original_effect_run_explanation_facets(original, definition)
    is Err(Preparation(Capacity(_))),
  )
  live.val = true
  discard_original_effect_run_explanation(original, definition).unwrap()
  assert_true(
    original_effect_run_explanation_facets(original, definition)
    is Err(Preparation(WrongPhase)),
  )
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input).unwrap(),
    after,
  )
  @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "static Effect Explanation charges the complete envelope at the per-facet clamp" {
  let bytes = 65536
  let nodes = 64
  let depth = 16
  let wire_bytes = 3 * bytes + 70
  let decoded_nodes = 3L * nodes.to_int64() + 9L
  let extent_nodes = 4L * decoded_nodes + 4L * depth.to_int64() + 64L
  let expected = result_read_data_cost(
    extent_nodes,
    6L * wire_bytes.to_int64(),
    2L * wire_bytes.to_int64(),
  )
  let limits = (bytes, nodes, depth)
  assert_eq(
    static_effect_explanation_delivery_construction(limits, wire_bytes + 1),
    expected,
  )
  assert_eq(
    static_effect_explanation_delivery_construction(limits, wire_bytes),
    expected,
  )
  assert_eq(
    static_effect_explanation_delivery_construction(limits, wire_bytes - 1),
    result_read_data_cost(
      extent_nodes,
      6L * (wire_bytes - 1).to_int64(),
      2L * (wire_bytes - 1).to_int64(),
    ),
  )
}

///|
test "prepared static Effect reader issues one Plan with both structural facets" {
  let (parent, input, _) = request_effect_compile_fixture()
  let (legacy, legacy_input, _) = request_effect_compile_fixture()
  let checks = parent._observed_semantic_check_calls
  let compiles = parent._observed_program_compile_calls
  let manifests = request_program_module_manifests()
  let value = match
    request_prepared_static_effect_explanation(
      parent, input, manifests, 65536, 8192, 64, 10000,
    ) {
    Err(issue) => fail(@debug.to_string(issue))
    Ok(result) => result
  }
  assert_eq(
    value.plan,
    request_prepared_static_plan_view(
      legacy, legacy_input, manifests, 65536, 8192, 64,
    ).unwrap(),
  )
  let parse = (name, wire) => {
    @publication.parse_interactive_run_control_shape(
      name, wire, 65536, 8192, 64,
    ).unwrap()
  }
  let plan = parse("effectful_static_plan_view", value.plan)
  let component = @identity.object_field(plan, "computation").unwrap()
  let view = @identity.object_field(component, "plan_view").unwrap()
  let map = @identity.object_field(view, "logical_map").unwrap()
  let facts = parse("explanation_facts", value.facts)
  let context = parse("explanation_context", value.context)
  let binding = @identity.object_field(context, "binding").unwrap()
  guard @identity.object_field(view, "compiled_plan_cid")
    is Some(@identity.String(plan_cid)) &&
    @identity.object_field(map, "self_cid") is Some(@identity.String(map_cid)) else {
    fail("the original Plan and map identities must be present")
  }
  for facet in [facts, binding] {
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
  assert_true(parent.phase == EffectCompiled)
  assert_true(parent.effect_plan is None)
  assert_true(parent.submitted_intent is None)
  assert_eq(parent._observed_semantic_check_calls, checks)
  assert_eq(parent._observed_program_compile_calls, compiles)
  abort_request_preparation_after_cleanup(legacy).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "prepared static Effect Explanation envelopes enforce the aggregate byte limit" {
  let manifests = request_program_module_manifests()
  let (probe, probe_input, _) = request_effect_compile_fixture()
  let expected = match
    request_prepared_static_effect_explanation_wire(
      probe, probe_input, manifests, 65536, 8192, 64, 10000,
    ) {
    Ok(wire) => wire
    Err(issue) => fail(@debug.to_string(issue))
  }
  let exact = @utf8.encode(expected).length()
  let decoded = @publication.parse_interactive_run_control_shape(
    "static_explanation_view", expected, exact, 8192, 64,
  ).unwrap()
  assert_true(
    @identity.object_field(decoded, "version")
    is Some(@identity.String("actql-static-explanation/0.1")),
  )
  for (limit, exact_limit) in [(exact, true), (exact - 1, false)] {
    let (parent, input, _) = request_effect_compile_fixture()
    let wire = request_prepared_static_effect_explanation_wire(
      parent, input, manifests, limit, 8192, 64, 10000,
    )
    if exact_limit {
      match wire {
        Ok(value) => assert_eq(value, expected)
        Err(issue) => fail(@debug.to_string(issue))
      }
    } else {
      assert_true(wire is Err(Encoding(@encode.OutputLimit)))
    }
    assert_true(parent.phase == EffectCompiled)
    assert_true(parent.submitted_intent is None)
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
  abort_request_preparation_after_cleanup(probe).unwrap()
  assert_eq(@resources.ledger_usage(probe.ledger).live_reservations, 0)
}

///|
test "prepared static Effect Explanation renders the admitted original within its Request" {
  let manifests = request_program_module_manifests()
  for
    (language, result, heading) in [
      (
        @publication_host.English,
        "Declare Result \"rows\"",
        "Logical dependencies",
      ),
      (
        @publication_host.Japanese,
        "結果を宣言 \"rows\"",
        "論理的な依存関係",
      ),
    ] {
    let (parent, input, _) = request_effect_compile_fixture()
    let output = match
      request_prepared_static_effect_explanation_narrative(
        parent, input, manifests, 65536, 8192, 64, 10000, language,
      ) {
      Ok(wire) => wire
      Err(issue) => fail(@debug.to_string(issue))
    }
    assert_true(output.contains(result), msg=output)
    assert_true(output.contains(heading), msg=output)
    assert_true(output.contains("\"connector://crm/account\""))
    assert_true(parent.phase == EffectCompiled)
    assert_true(parent.submitted_intent is None)
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "prepared static Effect Explanation reuses its borrowed singleton or composed Model plans" {
  let mut first_parameters = None
  for
    (plural, parameter) in [
      (false, None),
      (true, None),
      (false, Some("private_original_a")),
      (false, Some("private_original_b")),
    ] {
    let (parent, input, holder) = request_effect_model_material_fixture(
      plural~,
      parameter~,
    )
    let prepared = @resources.preparation_body_borrow_value(holder).unwrap()
    let occurrences = @publication_host.prepared_client_effect_infer_occurrences(
      prepared,
    ).unwrap()
    let model_count = if plural { 2 } else { 1 }
    assert_eq(occurrences.length(), model_count)
    let infers = occurrences.map(occurrence => {
      @publication_host.issue_installed_client_composed_infer_plan_graph(
        occurrence,
        effect_model_plan_execution(occurrence),
        @publication_host.client_standard_values_sequence_limits(),
        65536,
        8192,
        64,
      ).unwrap()
    })
    let value = match
      request_prepared_static_effect_explanation(
        parent,
        input,
        request_program_module_manifests(),
        65536,
        8192,
        64,
        10000,
        infers~,
      ) {
      Ok(output) => output
      Err(issue) => fail(@debug.to_string(issue))
    }
    let context = @publication.parse_interactive_run_control_shape(
      "explanation_context",
      value.context,
      65536,
      8192,
      64,
    ).unwrap()
    guard @identity.object_field(context, "items")
      is Some(@identity.Array(items)) else {
      fail("Context must contain its original item inventory")
    }
    if parameter is Some(original) {
      let binding = @identity.object_field(context, "binding").unwrap()
      let identity = @publication_host.prepared_client_effect_identity(prepared)
      assert_true(
        @identity.object_field(binding, "parameter_values_cid")
        is Some(@identity.String(cid)) &&
        cid == identity.parameter_values_cid,
      )
      assert_false(value.context.contains(original))
      assert_false(value.facts.contains(original))
      assert_false(value.plan.contains(original))
      match first_parameters {
        None => first_parameters = Some(identity.parameter_values_cid)
        Some(prior) => assert_false(prior == identity.parameter_values_cid)
      }
    }
    let mut found = 0
    for index in 0..<@identity.array_count(items) {
      let item = @identity.array_at(items, index).unwrap()
      if @identity.object_field(item, "kind")
        is Some(@identity.String("model_task")) {
        assert_true(
          @identity.object_field(item, "task_id")
          is Some(@identity.String("model-task:risk-score.v1")),
        )
        if parameter is Some(_) {
          guard @identity.object_field(item, "input_bindings")
            is Some(@identity.Array(inputs)) else {
            fail("Model Context must contain checked input bindings")
          }
          let selected = @identity.array_at(inputs, 0).unwrap()
          assert_eq(
            @identity.stringify_value(
              @identity.object_field(selected, "binding").unwrap(),
              100,
              10,
              4,
            ),
            "{\"name\":\"input_text\",\"state\":\"parameter\"}",
          )
          let kind = @identity.object_field(selected, "type").unwrap()
          assert_true(
            @identity.object_field(kind, "kind")
            is Some(@identity.String("string")),
          )
          assert_true(
            @identity.object_field(kind, "nullable")
            is Some(@identity.Bool(false)),
          )
        }
        found += 1
      }
    }
    assert_eq(found, model_count)
    assert_true(parent.phase == EffectPlanReserved)
    assert_true(parent.effect_plan is None)
    assert_true(parent.submitted_intent is None)
    assert_true(
      physical_equal(
        @resources.preparation_body_borrow_value(holder).unwrap(),
        prepared,
      ),
    )
    assert_false(@resources.return_preparation_body_borrow(holder).unwrap())
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "static Effect Plan retains its same borrowed original without constructing a body" {
  let (parent, input, prepared) = request_effect_compile_fixture()
  let checks = parent._observed_semantic_check_calls
  let compiles = parent._observed_program_compile_calls
  let borrow = borrow_request_effect_plan_input(parent, input).unwrap()
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
  let wire = request_prepared_static_plan_view(
    parent,
    input,
    request_program_module_manifests(),
    65536,
    8192,
    64,
  ).unwrap()
  assert_true(wire.contains("actql-effectful-static-plan-view/0.1"))
  assert_true(parent.phase == EffectPlanReserved)
  assert_true(parent.effect_plan is None)
  assert_true(physical_equal(parent.compiled_effect.unwrap(), prepared))
  assert_eq(parent._observed_semantic_check_calls, checks)
  assert_eq(parent._observed_program_compile_calls, compiles)
  @resources.return_preparation_body_borrow(borrow).unwrap() |> ignore
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
