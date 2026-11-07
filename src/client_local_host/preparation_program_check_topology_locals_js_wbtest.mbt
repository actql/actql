///|
test "original reconciled-input constructor retains one returned work receipt on the same Request parent" {
  let (parent, owner, input) = context_entry_parent(2)
  prepare_program_check_source_context_input(owner).unwrap()
  prepare_program_check_source_topology_entry(owner).unwrap()
  reconcile_program_check_source_topology_entry(owner).unwrap()
  let original = owner.source_registration.unwrap()
  let context = @checked.parsed_source_context_input(original).unwrap().unwrap()
  let read = @context.sourceview_context_topology_read(context).unwrap()
  let before = @resources.preparation_capacity_working_extents(
    parent.capacity,
    input,
  ).unwrap()
  assert_eq(advance_program_check_source_topology(owner).unwrap(), Imports)
  assert_true(owner.phase == SourceTopologyBodyReturned && owner.work is None)
  assert_true(
    physical_equal(
      @context.sourceview_context_topology_read(context).unwrap(),
      read,
    ),
  )
  assert_eq(
    @stage_results.local_program_read_constructor_position(read).map(p => p.0),
    Some(0),
  )
  assert_eq(@stage_results.local_program_read_owned_work(read), Some(2L))
  assert_eq(owner.topology_observed_work, 2L)
  // The returned quotation frame341H146R738W covers this constructor too.
  // Original delta-binding controls add four scalar words to the prior frame.
  assert_eq(16L * 341L + 8L * 146L + 8L * 738L, 12528L)
  // After return only live state8H11R4W +original Usage1H3W remains288.
  assert_eq(owner.source_body_quote, Some((12528L, 288L)))
  assert_eq(
    @resources.preparation_capacity_working_extents(parent.capacity, input),
    Ok((before.0 + 12528L, before.1 + 12528L)),
  )
  let work = owner.topology_work.unwrap()
  assert_eq(
    @resources.spend_preparation_phase_work_continuation64(work, 1L),
    Err(WrongPhase),
  )
  assert_true(
    @resources.complete_preparation_capacity(
      parent.capacity,
      input,
      (),
      before.0,
      before.1,
    )
    is Err(WorkActive),
  )
  assert_true(
    @resources.begin_preparation_phase_work64(
      parent.capacity,
      input,
      @resources.SemanticCheck,
      1L,
    )
    is Err(WrongPhase),
  )
  reconcile_program_check_source_topology(owner).unwrap()
  assert_true(owner.phase == SourceTopologyBodyRetained)
  assert_true(physical_equal(owner.topology_work.unwrap(), work))
  assert_eq(
    @resources.preparation_capacity_working_extents(parent.capacity, input),
    Ok((before.0 + 288L, before.1 + 288L)),
  )
  let maximum = @stage_results.local_program_read_work_bound(read).unwrap()
  assert_eq(
    advance_program_check_source_topology(owner).unwrap(),
    InputRegistration,
  )
  assert_true(physical_equal(owner.topology_work.unwrap(), work))
  assert_eq(advance_program_check_source_topology(owner).unwrap(), Pipeline)
  assert_true(physical_equal(owner.topology_work.unwrap(), work))
  assert_eq(@stage_results.local_program_read_owned_work(read), Some(4L))
  assert_eq(owner.topology_observed_work, 4L)
  reconcile_program_check_source_topology(owner).unwrap()
  @resources.resume_preparation_phase_work_continuation64(work).unwrap()
  assert_eq(
    @resources.spend_preparation_phase_work_continuation64(work, maximum),
    Err(WorkLimit),
  )
  @resources.return_preparation_phase_work_continuation64(work).unwrap()
  assert_eq(
    advance_program_check_source_topology(owner).unwrap(),
    PipelineCarriers,
  )
  assert_eq(advance_program_check_source_topology(owner).unwrap(), PipelineKeys)
  assert_true(physical_equal(owner.topology_work.unwrap(), work))
  assert_eq(owner.topology_observed_work, 4L)
  assert_eq(
    advance_program_check_source_topology(owner).unwrap(),
    PipelineRankings,
  )
  assert_eq(advance_program_check_source_topology(owner).unwrap(), PipelineCore)
  assert_true(owner.topology_observed_work > 4L)
  let before_core = owner.topology_observed_work
  assert_eq(
    advance_program_check_source_topology(owner).unwrap(),
    PipelineCoreInputs,
  )
  assert_eq(owner.topology_observed_work, before_core + 2L)
  reconcile_program_check_source_topology(owner).unwrap()
  let mut replaces = 0
  while @stage_results.local_program_read_phase(read) == PipelineCoreInputs {
    let before = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
    advance_program_check_source_topology(owner).unwrap() |> ignore
    let peak = owner.source_body_quote.unwrap().0
    let held = owner.source_body_quote.unwrap().1
    let replaced = owner.topology_replaced_bytes
    let scratch = owner.environment_scratch.unwrap()
    assert_eq(scratch, peak + replaced - held)
    reconcile_program_check_source_topology(owner).unwrap()
    assert_eq(
      @resources.preparation_capacity_working_extents(parent.capacity, input),
      Ok((before.0 + held - replaced, before.1 + held - replaced)),
    )
    assert_true(physical_equal(owner.topology_work.unwrap(), work))
    replaces += 1
  }
  assert_true(replaces > 2)
  assert_eq(
    @stage_results.local_program_read_phase(read),
    PipelineCoreParameters,
  )
  while @stage_results.local_program_read_phase(read) == PipelineCoreParameters {
    advance_program_check_source_topology(owner).unwrap() |> ignore
    reconcile_program_check_source_topology(owner).unwrap()
  }
  assert_eq(
    @stage_results.local_program_read_phase(read),
    PipelineCoreImportedEvidence,
  )
  clear_program_check_preparation(owner).unwrap()
  assert_eq(
    @resources.finish_preparation_phase_work_continuation64(work),
    Err(Closed),
  )
  assert_eq(@stage_results.local_program_read_phase(read), Cleared)
  assert_true(
    @resources.begin_preparation_phase_work_continuation64(
      parent.capacity,
      input,
      @resources.SourceTopologyBody,
      100L,
    )
    is Err(AlreadyClaimed),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_retention_bytes, 0L)
}

///|
test "reconciled-input one-short admission does not claim work or advance the original reader" {
  for retention in [true, false] {
    let (parent, owner, _) = context_entry_parent(0)
    prepare_program_check_source_context_input(owner).unwrap()
    prepare_program_check_source_topology_entry(owner).unwrap()
    reconcile_program_check_source_topology_entry(owner).unwrap()
    let context = @checked.parsed_source_context_input(
        owner.source_registration.unwrap(),
      )
      .unwrap()
      .unwrap()
    let read = @context.sourceview_context_topology_read(context).unwrap()
    let usage = @resources.ledger_usage(parent.ledger)
    let limits = @resources.ledger_limits(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes -
        usage.held_bytes -
        usage.reserved_retention_bytes -
        12528L +
        1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - usage.reserved_execution_bytes - 12528L + 1L
      },
    ).unwrap()
    let refused = advance_program_check_source_topology(owner)
    assert_true(
      if retention {
        refused is Err(Capacity(Resource(RetentionLimit)))
      } else {
        refused is Err(Capacity(Resource(ExecutionLimit)))
      },
    )
    assert_true(
      owner.phase == SourceTopologyBodyInspectionInitial &&
      owner.topology_work is None,
    )
    assert_true(owner.source_body_quote is None)
    assert_eq(@stage_results.local_program_read_phase(read), LocalInputs)
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    assert_eq(advance_program_check_source_topology(owner).unwrap(), Imports)
    assert_eq(owner.source_body_quote.unwrap(), (12528L, 288L))
    clear_program_check_preparation(owner).unwrap()
    abort_request_preparation_after_cleanup(parent).unwrap()
  }
}

///|
test "reconciled-input current reentry and stop cannot start or retire the original work mid-grow" {
  let action : Ref[(() -> Unit)?] = Ref(None)
  let stop = Ref(false)
  let (parent, owner, _) = context_entry_parent(0, current=() => {
    if action.val is Some(run) {
      run()
    }
    !stop.val
  })
  prepare_program_check_source_context_input(owner).unwrap()
  prepare_program_check_source_topology_entry(owner).unwrap()
  reconcile_program_check_source_topology_entry(owner).unwrap()
  let context = @checked.parsed_source_context_input(
      owner.source_registration.unwrap(),
    )
    .unwrap()
    .unwrap()
  let read = @context.sourceview_context_topology_read(context).unwrap()
  let flags = Ref(0)
  action.val = Some(() => {
    if advance_program_check_source_topology(owner) is Err(WrongPhase) {
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
    advance_program_check_source_topology(owner)
    is Err(Capacity(Resource(ClosedReservation))),
  )
  action.val = None
  assert_eq(flags.val, 7)
  assert_true(owner.topology_work is None)
  assert_eq(@stage_results.local_program_read_phase(read), LocalInputs)
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "the original invalid import-counter fixture keeps structural UnknownProducer before topology or work" {
  let text =
    #|{"version":"actql/0.1","id":"deferred","stages":[{"id":"s","inputs":{"a":{"result":{"stage":"missing","result":"out"}},"b":{"result":{"stage":"missing","result":"out"}},"c":{"result":{"stage":"missing","result":"out"}}},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[]},"as":"v"}],"results":{"out":{"from":"v","fields":["id"]}}}],"results":{"out":{"from":{"stage":"s","result":"out"}}}}
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let source = prepare_request_program_json_preparation(
    parent,
    input,
    text,
    @publication_host.client_standard_program_preparation_limits().checking.input,
  ).unwrap()
  for _ in 0..<(text.length() + 1) {
    match advance_program_json_preparation(source, 64).unwrap() {
      @source.JsonSourceContinue(..) => ()
      @source.JsonSourceReady(_, ..) => break
      @source.JsonSourceFailed(_, ..) => fail("original Source refused")
    }
  }
  finish_program_json_preparation(source).unwrap()
  assert_true(
    construct_program_json_preparation(source)
    is Err(Syntax(Structure(UnknownProducer("missing"), ..))),
  )
  clear_program_json_preparation(source).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "original resize current cannot move the read then make this driver execute its next unfunded constructor" {
  let action : Ref[(() -> Unit)?] = Ref(None)
  let (parent, owner, _) = context_entry_parent(2, current=() => {
    if action.val is Some(run) {
      run()
    }
    true
  })
  prepare_program_check_source_context_input(owner).unwrap()
  prepare_program_check_source_topology_entry(owner).unwrap()
  reconcile_program_check_source_topology_entry(owner).unwrap()
  let context = @checked.parsed_source_context_input(
      owner.source_registration.unwrap(),
    )
    .unwrap()
    .unwrap()
  let read = @context.sourceview_context_topology_read(context).unwrap()
  let moved = Ref(0)
  // Adversarial original callback only: no physical IO, new owner or normal
  // caller acceptance. The selected constructor changed during actual resize.
  action.val = Some(() => {
    if @stage_results.local_program_read_phase(read) == LocalInputs {
      @stage_results.advance_local_program_read(read) |> ignore
      moved.val += 1
    }
  })
  assert_true(advance_program_check_source_topology(owner) is Err(WrongPhase))
  action.val = None
  assert_eq(moved.val, 1)
  // The driver must stop before Imports, whose inventory was never selected.
  assert_eq(@stage_results.local_program_read_phase(read), Imports)
  assert_true(owner.topology_work is None)
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "returned quotation storage executes the same small constructor with one original current observation" {
  let calls = Ref(0)
  let (parent, owner, _) = context_entry_parent(0, current=() => {
    calls.val += 1
    true
  })
  prepare_program_check_source_context_input(owner).unwrap()
  prepare_program_check_source_topology_entry(owner).unwrap()
  reconcile_program_check_source_topology_entry(owner).unwrap()
  calls.val = 0
  assert_eq(advance_program_check_source_topology(owner).unwrap(), Imports)
  assert_eq(calls.val, 1)
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "a retained topology quote cannot be moved to a different original constructor" {
  let (parent, owner, _) = context_entry_parent(0)
  prepare_program_check_source_context_input(owner).unwrap()
  prepare_program_check_source_topology_entry(owner).unwrap()
  inspect_program_check_source_topology(owner).unwrap()
  let quote = owner.source_body_quote.unwrap()
  let context = @checked.parsed_source_context_input(
      owner.source_registration.unwrap(),
    )
    .unwrap()
    .unwrap()
  let read = @context.sourceview_context_topology_read(context).unwrap()
  assert_eq(owner.topology_quoted_phase, LocalInputs)
  // Adversarial pure continuation movement after quotation; no IO or public
  // execution is claimed. The caller must not reinterpret the cached quote.
  assert_eq(@stage_results.advance_local_program_read(read), Imports)
  assert_true(advance_program_check_source_topology(owner) is Err(WrongPhase))
  assert_true(physical_equal(owner.source_body_quote.unwrap(), quote))
  assert_true(owner.topology_work is None)
  assert_eq(@stage_results.local_program_read_phase(read), Imports)
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
}

///|
test "256-input registration grows only missing backing and retains its original quote work and read after refusal" {
  for retention in [true, false] {
    let (parent, owner, _) = context_entry_parent(256)
    prepare_program_check_source_context_input(owner).unwrap()
    prepare_program_check_source_topology_entry(owner).unwrap()
    assert_eq(advance_program_check_source_topology(owner).unwrap(), Imports)
    assert_eq(
      advance_program_check_source_topology(owner).unwrap(),
      InputRegistration,
    )
    reconcile_program_check_source_topology(owner).unwrap()
    let context = @checked.parsed_source_context_input(
        owner.source_registration.unwrap(),
      )
      .unwrap()
      .unwrap()
    let read = @context.sourceview_context_topology_read(context).unwrap()
    let work = owner.topology_work.unwrap()
    let prior = @stage_results.local_program_read_owned_work(read).unwrap()
    inspect_program_check_source_topology(owner).unwrap()
    let quote = owner.source_body_quote.unwrap()
    let additional = quote.0 - 12528L
    assert_true(additional > 0L)
    let usage = @resources.ledger_usage(parent.ledger)
    let limits = @resources.ledger_limits(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes -
        usage.held_bytes -
        usage.reserved_retention_bytes -
        additional +
        1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes -
        usage.reserved_execution_bytes -
        additional +
        1L
      },
    ).unwrap()
    let refused = advance_program_check_source_topology(owner)
    assert_true(
      if retention {
        refused is Err(Capacity(Resource(RetentionLimit)))
      } else {
        refused is Err(Capacity(Resource(ExecutionLimit)))
      },
    )
    assert_true(owner.phase == SourceTopologyBodyQuoted)
    assert_true(physical_equal(owner.source_body_quote.unwrap(), quote))
    assert_true(physical_equal(owner.topology_work.unwrap(), work))
    assert_eq(@stage_results.local_program_read_phase(read), InputRegistration)
    assert_eq(@stage_results.local_program_read_owned_work(read), Some(prior))
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    assert_eq(advance_program_check_source_topology(owner).unwrap(), Pipeline)
    assert_eq(
      @stage_results.local_program_read_owned_work(read),
      Some(prior + 256L),
    )
    assert_true(physical_equal(owner.topology_work.unwrap(), work))
    clear_program_check_preparation(owner).unwrap()
    abort_request_preparation_after_cleanup(parent).unwrap()
  }
}
