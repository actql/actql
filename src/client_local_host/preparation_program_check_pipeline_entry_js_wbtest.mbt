///|
test "same Request pipeline entry one-short preserves original reader receipt and carrier backing" {
  for retention in [true, false] {
    let (parent, owner, input) = context_entry_parent(2)
    prepare_program_check_source_context_input(owner).unwrap()
    prepare_program_check_source_topology_entry(owner).unwrap()
    assert_eq(advance_program_check_source_topology(owner).unwrap(), Imports)
    assert_eq(
      advance_program_check_source_topology(owner).unwrap(),
      InputRegistration,
    )
    assert_eq(advance_program_check_source_topology(owner).unwrap(), Pipeline)
    reconcile_program_check_source_topology(owner).unwrap()
    let original = @checked.parsed_source_context_input(
        owner.source_registration.unwrap(),
      )
      .unwrap()
      .unwrap()
    let read = @context.sourceview_context_topology_read(original).unwrap()
    let work = owner.topology_work.unwrap()
    let before = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
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
    let result = advance_program_check_source_topology(owner)
    assert_true(
      if retention {
        result is Err(Capacity(Resource(RetentionLimit)))
      } else {
        result is Err(Capacity(Resource(ExecutionLimit)))
      },
    )
    assert_eq(@stage_results.local_program_read_phase(read), Pipeline)
    assert_true(physical_equal(owner.topology_work.unwrap(), work))
    assert_eq(owner.topology_observed_work, 4L)
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    assert_eq(
      advance_program_check_source_topology(owner).unwrap(),
      PipelineCarriers,
    )
    let entry_held = owner.source_body_quote.unwrap().1
    assert_true(entry_held > 0L)
    reconcile_program_check_source_topology(owner).unwrap()
    assert_eq(
      @resources.preparation_capacity_working_extents(parent.capacity, input),
      Ok((before.0 + entry_held, before.1 + entry_held)),
    )
    assert_eq(
      advance_program_check_source_topology(owner).unwrap(),
      PipelineKeys,
    )
    let carrier_held = owner.source_body_quote.unwrap().1
    assert_true(carrier_held > 0L)
    reconcile_program_check_source_topology(owner).unwrap()
    assert_eq(
      @resources.preparation_capacity_working_extents(parent.capacity, input),
      Ok(
        (
          before.0 + entry_held + carrier_held,
          before.1 + entry_held + carrier_held,
        ),
      ),
    )
    assert_true(physical_equal(owner.topology_work.unwrap(), work))
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
  }
}
