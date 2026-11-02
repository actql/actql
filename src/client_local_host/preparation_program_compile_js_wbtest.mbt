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
