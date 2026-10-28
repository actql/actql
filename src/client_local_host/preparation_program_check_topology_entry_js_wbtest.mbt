///|
test "same Request parent backs original topology entrance once and retirement clears its exact pending reader" {
  for count in [0, 2] {
    let (parent, owner, input) = context_entry_parent(count)
    prepare_program_check_source_context_input(owner).unwrap()
    let original = owner.source_registration.unwrap()
    let context = @checked.parsed_source_context_input(original)
      .unwrap()
      .unwrap()
    assert_true(@context.sourceview_context_topology_read(context) is None)
    prepare_program_check_source_topology_entry(owner).unwrap()
    assert_true(
      owner.phase == SourceTopologyEntryPrepared && owner.work is None,
    )
    let read = @context.sourceview_context_topology_read(context).unwrap()
    assert_eq(@stage_results.local_program_read_phase(read), LocalInputs)
    assert_eq(@stage_results.local_program_read_stage_index(read), Some(0))
    assert_eq(@stage_results.local_program_read_owned_work(read), Some(2))
    assert_true(
      physical_equal(
        @context.begin_sourceview_context_topology_read(context).unwrap(),
        read,
      ),
    )
    assert_true(
      @resources.begin_preparation_phase_work64(
        parent.capacity,
        input,
        @resources.SourceTopologyEntry,
        2L,
      )
      is Err(AlreadyClaimed),
    )
    reconcile_program_check_source_topology_entry(owner).unwrap()
    assert_true(owner.phase == SourceTopologyEntryComplete)
    assert_true(
      prepare_program_check_source_topology_entry(owner) is Err(WrongPhase),
    )
    clear_program_check_preparation(owner).unwrap()
    assert_eq(@stage_results.local_program_read_phase(read), Cleared)
    assert_eq(@stage_results.advance_local_program_read(read), Cleared)
    assert_true(
      @context.begin_sourceview_context_topology_read(context)
      is Err(Program(Unavailable)),
    )
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(
      @resources.ledger_usage(parent.ledger).reserved_retention_bytes,
      0L,
    )
  }
}

///|
test "topology entry one-short retention or execution does not construct or spend the original read" {
  for retention in [true, false] {
    let (parent, owner, _) = context_entry_parent(2)
    prepare_program_check_source_context_input(owner).unwrap()
    reconcile_program_check_source_context_input(owner).unwrap()
    let context = @checked.parsed_source_context_input(
        owner.source_registration.unwrap(),
      )
      .unwrap()
      .unwrap()
    let usage = @resources.ledger_usage(parent.ledger)
    let limits = @resources.ledger_limits(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes -
        usage.held_bytes -
        usage.reserved_retention_bytes -
        program_topology_entry_peak_bytes +
        1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes -
        usage.reserved_execution_bytes -
        program_topology_entry_peak_bytes +
        1L
      },
    ).unwrap()
    let refused = prepare_program_check_source_topology_entry(owner)
    assert_true(
      if retention {
        refused is Err(Capacity(Resource(RetentionLimit)))
      } else {
        refused is Err(Capacity(Resource(ExecutionLimit)))
      },
    )
    assert_true(owner.phase == SourceTopologyEntryInitial && owner.work is None)
    assert_true(@context.sourceview_context_topology_read(context) is None)
    assert_eq(
      @context.sourceview_context_topology_entry_work_bound(context),
      Some(2),
    )
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    prepare_program_check_source_topology_entry(owner).unwrap()
    assert_true(@context.sourceview_context_topology_read(context) is Some(_))
    clear_program_check_preparation(owner).unwrap()
    abort_request_preparation_after_cleanup(parent).unwrap()
  }
}

///|
test "topology entrance current reentry and cancellation precede reader construction and preserve the original Context" {
  let action : Ref[(() -> Unit)?] = Ref(None)
  let stop = Ref(false)
  let (parent, owner, _) = context_entry_parent(0, current=() => {
    if action.val is Some(run) {
      run()
    }
    !stop.val
  })
  prepare_program_check_source_context_input(owner).unwrap()
  reconcile_program_check_source_context_input(owner).unwrap()
  let original = owner.source_registration.unwrap()
  let context = @checked.parsed_source_context_input(original).unwrap().unwrap()
  let flags = Ref(0)
  action.val = Some(() => {
    if prepare_program_check_source_topology_entry(owner) is Err(WrongPhase) {
      flags.val += 1
    }
    if clear_program_check_preparation(owner) is Err(WrongPhase) {
      flags.val += 2
    }
    if take_program_check_source_registration(owner) is Err(WrongPhase) {
      flags.val += 4
    }
  })
  stop.val = true
  assert_true(
    prepare_program_check_source_topology_entry(owner)
    is Err(Capacity(Resource(ClosedReservation))),
  )
  action.val = None
  assert_eq(flags.val, 7)
  assert_true(@context.sourceview_context_topology_read(context) is None)
  assert_true(
    physical_equal(
      @checked.parsed_source_context_input(original).unwrap().unwrap(),
      context,
    ),
  )
  assert_true(owner.work is None)
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}
