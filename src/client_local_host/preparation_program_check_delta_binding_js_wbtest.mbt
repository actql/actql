///|
fn funded_original_delta_binding_parent() -> (
  ClientRequestPreparation[Array[Int]],
  ClientProgramCheckPreparation[Array[Int], Unit],
  Array[Int],
  @stage_results.LocalProgramRead,
) raise {
  let (parent, owner, input, read) = funded_original_imported_parent()
  while @stage_results.local_program_read_phase(read) ==
        PipelineCoreImportedEvidence {
    advance_program_check_source_topology(owner).unwrap() |> ignore
    reconcile_program_check_source_topology(owner).unwrap()
  }
  (parent, owner, input, read)
}

///|
test "same Request advances original empty explicit-binding table into operations without renewing work or owners" {
  let (parent, owner, input, read) = funded_original_delta_binding_parent()
  let receipt = owner.topology_work.unwrap()
  let work = owner.topology_observed_work
  let mut steps = 0
  while @stage_results.local_program_read_phase(read) ==
        PipelineCoreDeltaContracts {
    let before = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
    advance_program_check_source_topology(owner).unwrap() |> ignore
    let (peak, held) = owner.source_body_quote.unwrap()
    let old = owner.topology_replaced_bytes
    assert_eq(owner.environment_scratch, Some(peak + old - held))
    reconcile_program_check_source_topology(owner).unwrap()
    assert_eq(
      @resources.preparation_capacity_working_extents(parent.capacity, input),
      Ok((before.0 + held - old, before.1 + held - old)),
    )
    assert_true(physical_equal(owner.topology_work.unwrap(), receipt))
    assert_eq(owner.topology_observed_work, work)
    steps += 1
  }
  assert_eq(steps, 1)
  assert_eq(@stage_results.local_program_read_phase(read), PipelineCoreSteps)
  assert_true(advance_program_check_source_topology(owner) is Err(WrongPhase))
  clear_program_check_preparation(owner).unwrap()
  assert_eq(@stage_results.local_program_read_phase(read), Cleared)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_retention_bytes, 0L)
}

///|
test "explicit-binding one-short metadata admission preserves original phase and work before any constructor" {
  for retention in [true, false] {
    let (parent, owner, _, read) = funded_original_delta_binding_parent()
    let position = @stage_results.local_program_read_constructor_position(read)
    let work = owner.topology_observed_work
    let usage = @resources.ledger_usage(parent.ledger)
    let limits = @resources.ledger_limits(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes -
        usage.held_bytes -
        usage.reserved_retention_bytes -
        program_topology_quotation_bytes +
        1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes -
        usage.reserved_execution_bytes -
        program_topology_quotation_bytes +
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
    assert_eq(
      @stage_results.local_program_read_constructor_position(read),
      position,
    )
    assert_eq(owner.topology_observed_work, work)
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    assert_eq(
      advance_program_check_source_topology(owner).unwrap(),
      PipelineCoreSteps,
    )
    assert_eq(owner.topology_observed_work, work)
    clear_program_check_preparation(owner).unwrap()
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(
      @resources.ledger_usage(parent.ledger).reserved_retention_bytes,
      0L,
    )
  }
}
