///|
test "same original Request backs the core initializer and its nonzero work without a new receipt or checker" {
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
      PipelineRankings,
      PipelineCore,
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
  let before = owner.topology_observed_work
  inspect_program_check_source_topology(owner).unwrap()
  let quote = owner.source_body_quote.unwrap()
  let missing = quote.0 - program_topology_quotation_bytes
  assert_true(missing > 0L)
  let usage = @resources.ledger_usage(parent.ledger)
  let limits = @resources.ledger_limits(parent.ledger)
  let blocker = @resources.reserve_capacity(
    parent.ledger,
    limits.retained_bytes -
    usage.held_bytes -
    usage.reserved_retention_bytes -
    missing +
    1L,
    0L,
  ).unwrap()
  assert_true(
    advance_program_check_source_topology(owner)
    is Err(Capacity(Resource(RetentionLimit))),
  )
  assert_eq(@stage_results.local_program_read_phase(read), PipelineCore)
  assert_eq(owner.topology_observed_work, before)
  assert_eq(owner.source_body_quote, Some(quote))
  assert_true(physical_equal(owner.topology_work.unwrap(), work))
  @resources.settle_capacity(parent.ledger, blocker).unwrap()
  assert_eq(
    advance_program_check_source_topology(owner).unwrap(),
    PipelineCoreInputs,
  )
  assert_eq(owner.topology_observed_work, before + 128L)
  assert_eq(
    @stage_results.local_program_read_owned_work(read),
    Some(before + 128L),
  )
  assert_true(physical_equal(owner.topology_work.unwrap(), work))
  assert_true(
    @resources.complete_preparation_capacity(parent.capacity, input, (), 0L, 0L)
    is Err(WorkActive),
  )
  clear_program_check_preparation(owner).unwrap()
  assert_eq(@stage_results.local_program_read_phase(read), Cleared)
  assert_eq(
    @resources.finish_preparation_phase_work_continuation64(work),
    Err(Closed),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_retention_bytes, 0L)
}
