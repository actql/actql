///|
// Same three authored operations as the strict ordinary timed Values caller.
// This component checks original preparation/ports, not runtime time/rows,
// installed observations, permission, durable ACK or Saved acceptance.
let debug_original_values_document : String =
  #|{"version":"actql/0.1","id":"timed-values-read","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"label":{"type":"string","nullable":false}},"rows":[{"id":2,"label":"東京"},{"id":1,"label":"é"}]},"as":"input"},{"from":"input","sort":[{"field":"id","dir":"asc","nulls":"first"}],"as":"ordered"},{"from":"ordered","derive":{"observed":{"current_timestamp":[]}},"as":"timed"}],"results":{"rows":{"from":"timed","fields":["id","label","observed"]}}}],"results":{"rows":{"from":{"stage":"main","result":"rows"}}}}

///|
test "explicit Debug original Values graph is reserved at exact and one-short before its single compiler call" {
  // Independent quotation46H/11R/85W, staged receipt15H/23R/19W,
  // caller Some/Debug phase2H/1R/3W =>63H/35R/107W. For S1/T3/I2/R1,
  // collection peak is (169+Q)H/(615+8Q)R/288W. Q is the SAME original
  // checked obligation inventory, not an emitted graph or product quote.
  assert_eq(
    @publication_host.client_debug_graph_quotation_control_bytes(),
    2144L,
  )
  for retention in [true, false] {
    for short in [true, false] {
      let (parent, owner, _, input) = registration_parent_fixture(
        text=debug_original_values_document,
      )
      guard finish_program_check_preparation(owner).unwrap()
        is @checked.Checked(checked) else {
        fail("original timed Values check must complete")
      }
      let original_calls = owner._observed_semantic_check_calls
      let q = @context.operation_closure_count(
        @context.stage_requirement_operations(@checked.requirements(checked)),
      ).to_int64()
      let debug_bytes = 2144L + 9928L + 80L * q
      let (r, e) = @resources.preparation_capacity_working_extents(
        owner.capacity,
        input,
      ).unwrap()
      let data = program_check_data_extent_cost(owner.check_data.unwrap()).unwrap() +
        32L
      let expected = (r + data + debug_bytes, e + data + debug_bytes)
      let limits = @publication_host.client_standard_program_preparation_limits()
      let policy = @resources.ledger_limits(parent.ledger)
      let blocker = @resources.reserve_capacity(
        parent.ledger,
        if retention {
          policy.retained_bytes - expected.0 + (if short { 1L } else { 0L })
        } else {
          0L
        },
        if retention {
          0L
        } else {
          policy.execution_bytes - expected.1 + (if short { 1L } else { 0L })
        },
      ).unwrap()
      let result = compile_program_check_preparation(
        owner,
        limits,
        execution_profile=Debug,
      )
      match result {
        Err(Work(issue)) =>
          fail("Debug did not reach geometry: " + @debug.to_string(issue))
        _ => ()
      }
      assert_eq(owner.compilation_quote, Some(expected))
      assert_eq(owner._observed_semantic_check_calls, original_calls)
      if short {
        assert_true(
          if retention {
            result is Err(Capacity(Resource(RetentionLimit)))
          } else {
            result is Err(Capacity(Resource(ExecutionLimit)))
          },
        )
        assert_true(owner.compiled_program is None && owner.work is None)
        assert_true(owner.topology_work is Some(_))
        assert_eq(owner._observed_program_compile_calls, 0L)
        assert_true(owner.compilation_known_work > 0L)
        assert_true(
          compile_program_check_preparation(owner, limits) is Err(ChangedInputs),
        )
        @resources.settle_capacity(parent.ledger, blocker).unwrap()
        assert_true(
          compile_program_check_preparation(
            owner,
            limits,
            execution_profile=Debug,
          )
          is Ok(_),
        )
      } else {
        assert_true(result is Ok(_))
        @resources.settle_capacity(parent.ledger, blocker).unwrap()
      }
      assert_eq(owner._observed_program_compile_calls, 1L)
      let program = owner.compiled_program.unwrap()
      let graph = @publication_host.prepared_client_graph(program)
      assert_eq(@strategy.graph_task_count(graph), 3)
      assert_true(physical_equal(@strategy.graph_program(graph), checked))
      for step in 0..<3 {
        assert_true(
          physical_equal(
            @lower.pipeline(
              @lower.bound_preparation(
                @strategy.graph_task_owner(graph, step).unwrap(),
              ),
            ),
            @checked.unit_pipeline(checked, 0).unwrap(),
          ),
        )
        assert_eq(@strategy.graph_task_selected_step(graph, step), Some(step))
        assert_eq(
          @strategy.graph_stage_operation_task(graph, 0, step),
          Some(step),
        )
      }
      assert_eq(@publication_host.prepared_client_result_count(program), 1)
      let incoming = @context.incoming_links_requirements(
        @context.program_incoming_gates_owner(@checked.incoming_gates(checked)),
      )
      let exported = @stage_results.export_at(
        @context.program_incoming_wiring(incoming),
        0,
      ).unwrap()
      assert_true(
        physical_equal(
          @execution.managed_result_occurrence_port(
            @strategy.graph_result_occurrence(graph, 0).unwrap(),
          ),
          @stage_results.export_port(exported),
        ),
      )
      assert_eq(owner._observed_semantic_check_calls, original_calls)
      assert_true(owner.work is None && owner.topology_work is None)
      clear_program_check_preparation(owner).unwrap()
      abort_request_preparation_after_cleanup(parent).unwrap()
      assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
    }
  }
}

///|
test "explicit Debug geometry exhaustion stays before compiler without pretending Normal success" {
  for work in [false, true] {
    let (parent, owner, _, _) = registration_parent_fixture(
      text=debug_original_values_document,
    )
    assert_true(
      finish_program_check_preparation(owner).unwrap() is @checked.Checked(_),
    )
    let original = @publication_host.client_standard_program_preparation_limits()
    let limits = if work {
      { ..original, max_graph_work: 0, }
    } else {
      { ..original, max_tasks: 2, }
    }
    let result = compile_program_check_preparation(
      owner,
      limits,
      execution_profile=Debug,
    )
    match result {
      Err(Work(issue)) =>
        fail(
          "Debug limit control did not reach geometry: " +
          @debug.to_string(issue),
        )
      _ => ()
    }
    assert_true(
      if work {
        result is Err(Compilation(Graph(WorkLimit)))
      } else {
        result is Err(Compilation(Graph(TaskLimit)))
      },
    )
    assert_eq(owner._observed_program_compile_calls, 0L)
    assert_true(owner.compiled_program is None && owner.work is None)
    clear_program_check_preparation(owner).unwrap()
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "explicit Debug returned topology work survives declined grow until actual owner clear" {
  let (parent, owner, _, input) = registration_parent_fixture(
    text=debug_original_values_document,
  )
  guard finish_program_check_preparation(owner).unwrap()
    is @checked.Checked(checked) else {
    fail("original checked input required")
  }
  let q = @context.operation_closure_count(
    @context.stage_requirement_operations(@checked.requirements(checked)),
  ).to_int64()
  let (r, _) = @resources.preparation_capacity_working_extents(
    owner.capacity,
    input,
  ).unwrap()
  let required = r +
    program_check_data_extent_cost(owner.check_data.unwrap()).unwrap() +
    32L +
    2144L +
    9928L +
    80L * q
  let policy = @resources.ledger_limits(parent.ledger)
  let blocker = @resources.reserve_capacity(
    parent.ledger,
    policy.retained_bytes - required + 1L,
    0L,
  ).unwrap()
  assert_true(
    compile_program_check_preparation(
      owner,
      @publication_host.client_standard_program_preparation_limits(),
      execution_profile=Debug,
    )
    is Err(Capacity(Resource(RetentionLimit))),
  )
  let original_work = owner.topology_work.unwrap()
  assert_true(
    @resources.remaining_preparation_phase_work_continuation64(original_work)
    is Err(WrongPhase),
  )
  assert_eq(owner._observed_program_compile_calls, 0L)
  @resources.settle_capacity(parent.ledger, blocker).unwrap()
  // No selected graph, lowered owner or Run was constructed. Clear returns
  // the SAME pending continuation and existing parent, without a new phase.
  clear_program_check_preparation(owner).unwrap()
  assert_true(owner.topology_work is None)
  assert_true(
    @resources.remaining_preparation_phase_work_continuation64(original_work)
    is Err(Closed),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "explicit Debug selected graph grow fences callback reentry on the same original compiler" {
  let action : Ref[(() -> Unit)?] = Ref(None)
  let flags = Ref(0)
  let (parent, owner, _, _) = registration_parent_fixture(
    text=debug_original_values_document,
    current=() => {
      if action.val is Some(invoke) {
        invoke()
      }
      true
    },
  )
  assert_true(
    finish_program_check_preparation(owner).unwrap() is @checked.Checked(_),
  )
  let limits = @publication_host.client_standard_program_preparation_limits()
  action.val = Some(() => {
    if owner.phase is DebugCompilationQuoted(_) {
      action.val = None
      if compile_program_check_preparation(
          owner,
          limits,
          execution_profile=Debug,
        )
        is Err(WrongPhase) {
        flags.val += 1
      }
      if clear_program_check_preparation(owner) is Err(WrongPhase) {
        flags.val += 2
      }
      if take_program_compilation_preparation(owner) is Err(WrongPhase) {
        flags.val += 4
      }
    }
  })
  assert_true(
    compile_program_check_preparation(owner, limits, execution_profile=Debug)
    is Ok(_),
  )
  action.val = None
  assert_eq(flags.val, 7)
  assert_eq(owner._observed_program_compile_calls, 1L)
  assert_true(owner.topology_work is None)
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "same Effect compiler backs bounded typed selections before constructor at both capacity boundaries" {
  assert_eq(program_effect_selection_extent_cost(0), Some(0L))
  assert_eq(program_effect_selection_extent_cost(-1), None)
  // One 1H/7R/1W record, one original holder reference, and the existing
  // collection owner's Array construction envelope; no copied String backing.
  assert_eq(program_effect_selection_extent_cost(1), Some(280L))
  // Two scalars on both the pipeline demand and aggregate: 4W before entry.
  assert_eq(sequence_demand_scalar_delta_bytes, 8L * 4L)
  for retention in [true, false] {
    let (parent, owner, input, _) = request_effect_fixture()
    finish_effect_program_check_preparation(owner).unwrap() |> ignore
    let before = @resources.preparation_capacity_working_extents(
      owner.capacity,
      input,
    ).unwrap()
    let data = program_check_data_extent_cost(owner.check_data.unwrap()).unwrap()
    let limits = @resources.ledger_limits(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes -
        before.0 -
        data -
        sequence_demand_scalar_delta_bytes -
        279L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes -
        before.1 -
        data -
        sequence_demand_scalar_delta_bytes -
        279L
      },
    ).unwrap()
    let result = compile_effect_program_check_preparation(owner)
    assert_true(
      if retention {
        result is Err(Capacity(Resource(RetentionLimit)))
      } else {
        result is Err(Capacity(Resource(ExecutionLimit)))
      },
    )
    assert_true(
      owner.compiled_effect is None && owner.compilation_known_work == 0L,
    )
    let quote = owner.compilation_quote
    assert_eq(
      quote,
      Some(
        (
          before.0 + data + sequence_demand_scalar_delta_bytes + 280L,
          before.1 + data + sequence_demand_scalar_delta_bytes + 280L,
        ),
      ),
    )
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    assert_true(compile_effect_program_check_preparation(owner) is Ok(_))
    assert_eq(owner.compilation_quote, quote)
    clear_program_check_preparation(owner).unwrap()
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "same Request compiles its retained check and declared Results without a second check or current callback per Stage" {
  let calls = Ref(0)
  let action : Ref[(() -> Unit)?] = Ref(None)
  let flags = Ref(0)
  let (parent, owner, _, input) = registration_parent_fixture(current=() => {
    calls.val += 1
    if action.val is Some(run) {
      run()
    }
    true
  })
  guard finish_program_check_preparation(owner).unwrap()
    is @checked.Checked(checked) else {
    fail("original complete check expected")
  }
  let original_program = parent.held_program.unwrap()
  let limits = @publication_host.client_standard_program_preparation_limits()
  action.val = Some(() => {
    if compile_program_check_preparation(owner, limits) is Err(WrongPhase) {
      flags.val += 1
    }
    if take_program_check_preparation_outcome(owner) is Err(WrongPhase) {
      flags.val += 2
    }
    if clear_program_check_preparation(owner) is Err(WrongPhase) {
      flags.val += 4
    }
  })
  let before = calls.val
  let prepared = compile_program_check_preparation(owner, limits).unwrap()
  action.val = None
  assert_eq(calls.val - before, 1)
  assert_eq(flags.val, 7)
  assert_true(owner.phase == CompilationComplete && owner.work is None)
  assert_true(
    physical_equal(
      @publication_host.prepared_client_graph(prepared)
      |> @strategy.graph_program,
      checked,
    ),
  )
  assert_true(
    physical_equal(@checked.checked_source_program(checked), original_program),
  )
  assert_eq(@publication_host.prepared_client_result_count(prepared), 1)
  assert_eq(
    @strategy.graph_task_count(
      @publication_host.prepared_client_graph(prepared),
    ),
    2,
  )
  assert_true(owner.compilation_known_work > 0L)
  assert_true(
    compile_program_check_preparation(owner, limits) is Err(WrongPhase),
  )
  let held = @resources.preparation_capacity_working_extents(
    parent.capacity,
    input,
  ).unwrap()
  let (taken, known) = take_program_compilation_preparation(owner).unwrap()
  assert_true(physical_equal(prepared, taken) && known > 0L)
  assert_eq(calls.val - before, 1)
  assert_true(
    abort_request_preparation_after_cleanup(parent) is Err(WrongPhase),
  )
  assert_eq(
    @resources.preparation_capacity_working_extents(parent.capacity, input),
    Ok(held),
  )
  // The fixture's next consumer has relinquished the returned DATA.
  assert_true(
    @resources.abort_preparation_capacity_after_cleanup(parent.capacity, input).unwrap(),
  )
  preparation_initial_cleanup(parent.initial).unwrap()
}

///|
test "same compiler quote preserves original configuration and checked Program across declined admission" {
  let (parent, owner, _, input) = registration_parent_fixture()
  assert_true(
    finish_program_check_preparation(owner).unwrap() is @checked.Checked(_),
  )
  let original = owner.check_outcome.unwrap()
  let before = @resources.preparation_capacity_working_extents(
    parent.capacity,
    input,
  ).unwrap()
  let policy = @resources.ledger_limits(parent.ledger)
  let blocker = @resources.reserve_capacity(
    parent.ledger,
    policy.retained_bytes - before.0,
    0L,
  ).unwrap()
  let limits = @publication_host.client_standard_program_preparation_limits()
  assert_true(
    compile_program_check_preparation(owner, limits)
    is Err(Capacity(Resource(RetentionLimit))),
  )
  let quote = owner.compilation_quote
  assert_true(
    owner.compiled_program is None && owner.compilation_known_work == 0L,
  )
  assert_true(physical_equal(owner.check_outcome.unwrap(), original))
  assert_true(
    compile_program_check_preparation(owner, { ..limits, max_tasks: 0, })
    is Err(ChangedInputs),
  )
  assert_eq(owner.compilation_quote, quote)
  @resources.settle_capacity(parent.ledger, blocker).unwrap()
  assert_true(compile_program_check_preparation(owner, limits) is Ok(_))
  assert_eq(owner.compilation_quote, quote)
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "same retained compiler preserves original lower and graph typed refusals without rechecking or success substitution" {
  for graph in [false, true] {
    let (parent, owner, _, _) = registration_parent_fixture()
    let outcome = finish_program_check_preparation(owner).unwrap()
    let original = @publication_host.client_standard_program_preparation_limits()
    let limits = if graph {
      { ..original, max_tasks: 0, }
    } else {
      { ..original, lowering: { ..original.lowering, max_work: 0, }, }
    }
    let result = compile_program_check_preparation(owner, limits)
    assert_true(
      if graph {
        result is Err(Compilation(Graph(TaskLimit)))
      } else {
        result is Err(Compilation(Lowering(_)))
      },
    )
    assert_true(physical_equal(owner.check_outcome.unwrap(), outcome))
    assert_true(
      owner.phase == CompilationFailed &&
      owner.compiled_program is None &&
      owner.work is None,
    )
    assert_true(
      compile_program_check_preparation(owner, original) is Err(WrongPhase),
    )
    clear_program_check_preparation(owner).unwrap()
    abort_request_preparation_after_cleanup(parent).unwrap()
  }
}

///|
test "same Request compiler retains original default Parameter binding and Unicode output through Result import" {
  let text = request_check_wire
    .replace(
      old="\"stages\":[",
      new="\"params\":{\"n\":{\"type\":\"number\",\"default\":7}},\"stages\":[",
    )
    .replace(
      old="\"as\":\"v\"}]",
      new="\"as\":\"v\"},{\"derive\":{\"値\":\"id + $n\"},\"as\":\"calculated\"}]",
    )
    .replace(
      old="\"from\":\"v\",\"fields\":[\"id\"]",
      new="\"from\":\"calculated\",\"fields\":[\"id\",\"値\"]",
    )
    .replace(
      old="\"from\":\"t\",\"fields\":[\"id\"]",
      new="\"from\":\"t\",\"fields\":[\"id\",\"値\"]",
    )
  let (parent, owner, _, _) = registration_parent_fixture(text~)
  guard finish_program_check_preparation(owner).unwrap()
    is @checked.Checked(checked) else {
    fail("original default Parameter and Unicode Program must finish check")
  }
  let prepared = compile_program_check_preparation(
    owner,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  let graph = @publication_host.prepared_client_graph(prepared)
  assert_true(physical_equal(@strategy.graph_program(graph), checked))
  let first = @strategy.graph_task_owner(graph, 0).unwrap()
  assert_eq(
    @admitted.canonical_scalar_text(
      @lower.parameter_value(first, "n").unwrap(),
      32,
    ),
    Some("7"),
  )
  let imported = @checked.unit_result_import_at(checked, 1, 0).unwrap()
  assert_eq(imported.producer_node_id, "a")
  assert_eq(imported.result_name, "r")
  assert_eq(@publication_host.prepared_client_result_count(prepared), 1)
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "Effect Debug refuses a one-short selected graph grow before compiling and retries the same quote" {
  let (parent, owner, input, _) = request_effect_fixture()
  finish_effect_program_check_preparation(owner).unwrap() |> ignore
  let candidate = owner.effect_candidate.unwrap()
  let checked = @checked.effect_computation_checked_program(candidate)
  let limits = owner.effect_limits.unwrap().program
  let observed = Ref(0L)
  let (bytes, remaining) = @publication_host.measure_client_debug_graph_construction(
    checked,
    limits.max_tasks,
    limits.max_graph_work,
    observed,
    effect=Some(candidate),
  ).unwrap()
  assert_true(bytes > 0L && observed.val > 0L)
  let original = @resources.preparation_capacity_working_extents(
    owner.capacity,
    input,
  ).unwrap()
  let required = original.0 +
    program_check_data_extent_cost(owner.check_data.unwrap()).unwrap() +
    sequence_demand_scalar_delta_bytes +
    280L +
    @publication_host.client_debug_graph_quotation_control_bytes() +
    bytes
  let budget = @resources.ledger_limits(parent.ledger)
  let blocker = @resources.reserve_capacity(
    parent.ledger,
    budget.retained_bytes - required + 1L,
    0L,
  ).unwrap()
  assert_true(
    compile_effect_program_check_preparation(owner, execution_profile=Debug)
    is Err(Capacity(Resource(RetentionLimit))),
  )
  assert_true(owner.compiled_effect is None)
  assert_eq(owner.compilation_known_work, observed.val)
  guard owner.phase is DebugCompilationQuoted(quoted_work) else {
    fail("the failed growth keeps the original measured phase")
  }
  assert_eq(quoted_work, remaining)
  let quote = owner.compilation_quote.unwrap()
  assert_eq(quote.0, required)
  let original_work = owner.topology_work.unwrap()
  assert_true(
    @resources.remaining_preparation_phase_work_continuation64(original_work)
    is Err(WrongPhase),
  )
  assert_true(
    compile_effect_program_check_preparation(owner) is Err(ChangedInputs),
  )
  @resources.settle_capacity(parent.ledger, blocker).unwrap()
  let compiled = match
    compile_effect_program_check_preparation(owner, execution_profile=Debug) {
    Ok(value) => value
    Err(EffectCompilation(Graph(issue))) =>
      fail("Funded same-request Debug graph: " + @debug.to_string(issue))
    Err(_) => fail("Funded Debug request failed before graph construction")
  }
  assert_eq(owner.compilation_quote, Some(quote))
  assert_true(owner.topology_work is None)
  let graph = @strategy.checked_effect_computation_graph(
    @publication_host.prepared_client_effect_computation_graph(compiled),
  )
  assert_true(physical_equal(@strategy.graph_program(graph), checked))
  assert_eq(@strategy.graph_task_count(graph), 2)
  assert_eq(@resources.ledger_usage(parent.ledger).attempts, 0)
  assert_eq(@strategy.checked_task_control_operation_task(graph, 0, 0), Some(0))
  assert_eq(@strategy.checked_task_control_operation_task(graph, 0, 1), Some(1))
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Effect Debug remaps the private write input and keeps the public Result on its original Step" {
  let (parent, owner, _, _) = request_effect_fixture(
    write_input_before_last_step=true,
  )
  finish_effect_program_check_preparation(owner).unwrap() |> ignore
  let prepared = match
    compile_effect_program_check_preparation(owner, execution_profile=Debug) {
    Ok(value) => value
    Err(EffectCompilation(Graph(issue))) =>
      fail(
        "Debug graph with distinct private Result: " + @debug.to_string(issue),
      )
    Err(_) =>
      fail(
        "Debug request with distinct private Result failed before graph construction",
      )
  }
  let checked = @publication_host.prepared_client_effect_computation_graph(
    prepared,
  )
  let graph = @strategy.checked_effect_computation_graph(checked)
  assert_eq(@strategy.graph_task_count(graph), 2)
  assert_eq(@strategy.graph_result_count(graph), 1)
  assert_eq(@strategy.graph_result_name(graph, 0), Some("rows"))
  assert_eq(@strategy.graph_result_task(graph, 0), Some(1))
  let private_source = @strategy.checked_effect_source_at(checked, 0).unwrap()
  assert_eq(@strategy.checked_effect_source_task(private_source), 0)
  assert_eq(@strategy.graph_task_target(graph, 0), Some(@pipeline.Step(0)))
  let private_occurrence = @strategy.checked_effect_source_occurrence(
    private_source,
  )
  assert_eq(
    @execution.managed_result_occurrence_name(private_occurrence),
    "seed_rows",
  )
  let public_port = @execution.managed_result_occurrence_port(
    @strategy.graph_result_occurrence(graph, 0).unwrap(),
  )
  let private_port = @execution.managed_result_occurrence_port(
    private_occurrence,
  )
  assert_false(physical_equal(public_port, private_port))
  assert_eq(@resources.ledger_usage(parent.ledger).attempts, 0)
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "Normal Effect keeps its fused original when Debug has not been selected" {
  let (parent, owner, _, _) = request_effect_fixture()
  finish_effect_program_check_preparation(owner).unwrap() |> ignore
  let prepared = compile_effect_program_check_preparation(owner).unwrap()
  let checked = @publication_host.prepared_client_effect_computation_graph(
    prepared,
  )
  let graph = @strategy.checked_effect_computation_graph(checked)
  assert_eq(@strategy.graph_task_count(graph), 1)
  assert_eq(@strategy.checked_task_control_operation_task(graph, 0, 0), None)
  assert_eq(@strategy.checked_task_control_operation_task(graph, 0, 1), None)
  assert_true(owner.topology_work is None)
  assert_eq(@resources.ledger_usage(parent.ledger).attempts, 0)
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "static Effect Debug uses the same original lowered owner with bounded work and scratch" {
  let (parent, input, prepared) = request_effect_compile_fixture()
  let capacity = parent.effect_capacity.unwrap()
  let original = @publication_host.prepared_client_effect_computation_graph(
    prepared,
  )
  let graph = @strategy.checked_effect_computation_graph(original)
  let base = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let work = 4096
  let observed = Ref(0L)
  let (bytes, remaining) = @publication_host.measure_client_static_effect_debug_graph_construction(
    prepared,
    8192,
    work / 2,
    observed,
  ).unwrap()
  assert_true(bytes > 0L && observed.val > 0L)
  assert_true(
    @publication_host.measure_client_static_effect_debug_graph_construction(
      prepared,
      8192,
      observed.val.to_int() - 1,
      Ref(0L),
    )
    is Err(Graph(WorkLimit)),
  )
  let split = match
    @publication_host.prepare_client_static_effect_debug_graph(
      prepared,
      8192,
      remaining - (7L * observed.val + 1L).to_int(),
    ) {
    Ok(graph) => graph
    Err(issue) => fail("Original static split: " + @debug.to_string(issue))
  }
  assert_eq(@strategy.graph_task_count(split), 2)
  assert_true(@strategy.graph_source_free_inputs_complete(split))
  assert_true(@strategy.checked_source_free_effect_control_has_entry(split))
  assert_eq(@strategy.checked_task_control_operation_task(split, 0, 0), Some(0))
  assert_eq(@strategy.checked_task_control_operation_task(split, 0, 1), Some(1))
  assert_true(
    @publication_host.prepared_client_effect_requires_query_time(
      prepared,
      work / 2,
      work / 2,
    )
    is Ok(false),
  )
  let limits = @resources.ledger_limits(parent.ledger)
  let controls = @publication_host.client_debug_graph_quotation_control_bytes()
  // One byte short of even the quoted graph before the extra entry frame.
  let unavailable = @resources.reserve_capacity(
    parent.ledger,
    limits.retained_bytes - base.0 - controls - bytes + 1L,
    0L,
  ).unwrap()
  assert_true(
    static_effect_debug_entry_probe(capacity, input, prepared, 8192, work).unwrap().0 ==
    false,
  )
  @resources.settle_capacity(parent.ledger, unavailable).unwrap()
  assert_true(
    static_effect_debug_entry_probe(capacity, input, prepared, 8192, 15).unwrap() ==
    (false, 0),
  )
  assert_false(
    static_effect_debug_entry_probe(capacity, input, prepared, 1, work).unwrap().0,
  )
  assert_true(
    static_effect_debug_entry_probe(capacity, input, prepared, 8192, work).unwrap() ==
    (true, work),
  )
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input).unwrap(),
    base,
  )
  assert_eq(@strategy.graph_task_count(graph), 1)
  assert_true(
    physical_equal(
      original,
      @publication_host.prepared_client_effect_computation_graph(prepared),
    ),
  )
  assert_eq(@resources.ledger_usage(parent.ledger).attempts, 0)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
