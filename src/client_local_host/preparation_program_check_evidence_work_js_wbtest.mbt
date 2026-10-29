///|
test "key quotation one-short retains the same metadata debit receipt and actual typed original" {
  for retention in [true, false] {
    let (parent, owner, input) = context_entry_parent(128)
    prepare_program_check_source_context_input(owner).unwrap()
    prepare_program_check_source_topology_entry(owner).unwrap()
    for
      expected in [
        @stage_results.Imports,
        InputRegistration,
        Pipeline,
        PipelineCarriers,
        PipelineKeys,
      ] {
      assert_eq(advance_program_check_source_topology(owner).unwrap(), expected)
    }
    reconcile_program_check_source_topology(owner).unwrap()
    let context = @checked.parsed_source_context_input(
        owner.source_registration.unwrap(),
      )
      .unwrap()
      .unwrap()
    let read = @context.sourceview_context_topology_read(context).unwrap()
    let work = owner.topology_work.unwrap()
    let before = @stage_results.local_program_read_owned_work(read).unwrap()
    inspect_program_check_source_topology(owner).unwrap()
    let observed = @stage_results.local_program_read_owned_work(read).unwrap()
    assert_eq(observed - before, 128L)
    assert_eq(owner.topology_observed_work, observed)
    let quote = owner.source_body_quote.unwrap()
    let missing = quote.0 - program_topology_quotation_bytes
    assert_true(missing > 0L)
    let usage = @resources.ledger_usage(parent.ledger)
    let limits = @resources.ledger_limits(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes -
        usage.held_bytes -
        usage.reserved_retention_bytes -
        missing +
        1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - usage.reserved_execution_bytes - missing + 1L
      },
    ).unwrap()
    let result = advance_program_check_source_topology(owner)
    assert_true(
      if retention {
        result is Err(Capacity(Resource(RetentionLimit)))
      } else {
        result is Err(Capacity(Resource(ExecutionLimit)))
      },
    )
    assert_eq(owner.source_body_quote, Some(quote))
    assert_eq(
      @stage_results.local_program_read_owned_work(read),
      Some(observed),
    )
    assert_eq(owner.topology_observed_work, observed)
    assert_true(physical_equal(owner.topology_work.unwrap(), work))
    assert_eq(@stage_results.local_program_read_phase(read), PipelineKeys)
    assert_eq(
      @resources.spend_preparation_phase_work_continuation64(work, 1L),
      Err(WrongPhase),
    )
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    assert_eq(
      advance_program_check_source_topology(owner).unwrap(),
      PipelineRankings,
    )
    assert_true(
      @stage_results.local_program_read_owned_work(read).unwrap() > observed,
    )
    assert_eq(
      owner.topology_observed_work,
      @stage_results.local_program_read_owned_work(read).unwrap(),
    )
    assert_true(physical_equal(owner.topology_work.unwrap(), work))
    assert_eq(
      advance_program_check_source_topology(owner).unwrap(),
      PipelineCore,
    )
    clear_program_check_preparation(owner).unwrap()
    assert_eq(@stage_results.local_program_read_phase(read), Cleared)
    assert_eq(
      @resources.finish_preparation_phase_work_continuation64(work),
      Err(Closed),
    )
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(
      @resources.ledger_usage(parent.ledger).reserved_retention_bytes,
      0L,
    )
    let _ = input
  }
}

///|
test "key constructor cancellation after metadata return cannot consume or retire its same original receipt during current" {
  let stop = Ref(false)
  let action : Ref[(() -> Unit)?] = Ref(None)
  let (parent, owner, _) = context_entry_parent(128, current=() => {
    if action.val is Some(run) {
      run()
    }
    !stop.val
  })
  prepare_program_check_source_context_input(owner).unwrap()
  prepare_program_check_source_topology_entry(owner).unwrap()
  for
    expected in [
      @stage_results.Imports,
      InputRegistration,
      Pipeline,
      PipelineCarriers,
      PipelineKeys,
    ] {
    assert_eq(advance_program_check_source_topology(owner).unwrap(), expected)
  }
  reconcile_program_check_source_topology(owner).unwrap()
  inspect_program_check_source_topology(owner).unwrap()
  let context = @checked.parsed_source_context_input(
      owner.source_registration.unwrap(),
    )
    .unwrap()
    .unwrap()
  let read = @context.sourceview_context_topology_read(context).unwrap()
  let work = owner.topology_work.unwrap()
  let observed = owner.topology_observed_work
  let quote = owner.source_body_quote.unwrap()
  assert_true(quote.0 > program_topology_quotation_bytes)
  let refused = Ref(0)
  action.val = Some(() => {
    if advance_program_check_source_topology(owner) is Err(WrongPhase) {
      refused.val += 1
    }
    if clear_program_check_preparation(owner) is Err(WrongPhase) {
      refused.val += 2
    }
    if @resources.finish_preparation_phase_work_continuation64(work)
      is Err(WrongPhase) {
      refused.val += 4
    }
  })
  stop.val = true
  assert_true(
    advance_program_check_source_topology(owner)
    is Err(Capacity(Resource(ClosedReservation))),
  )
  action.val = None
  assert_eq(refused.val, 7)
  assert_true(physical_equal(owner.topology_work.unwrap(), work))
  assert_eq(owner.topology_observed_work, observed)
  assert_eq(@stage_results.local_program_read_owned_work(read), Some(observed))
  assert_eq(@stage_results.local_program_read_phase(read), PipelineKeys)
  clear_program_check_preparation(owner).unwrap()
  assert_eq(@stage_results.local_program_read_phase(read), Cleared)
  assert_eq(
    @resources.finish_preparation_phase_work_continuation64(work),
    Err(Closed),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
}
