///|
fn funded_original_input_parent() -> (
  ClientRequestPreparation[Array[Int]],
  ClientProgramCheckPreparation[Array[Int], Unit],
  Array[Int],
  @stage_results.LocalProgramRead,
) raise {
  let (parent, owner, input) = context_entry_parent(2)
  prepare_program_check_source_context_input(owner).unwrap()
  prepare_program_check_source_topology_entry(owner).unwrap()
  while true {
    let phase = advance_program_check_source_topology(owner).unwrap()
    reconcile_program_check_source_topology(owner).unwrap()
    if phase == PipelineCoreInputs {
      break
    }
  }
  let context = @checked.parsed_source_context_input(
      owner.source_registration.unwrap(),
    )
    .unwrap()
    .unwrap()
  (
    parent,
    owner,
    input,
    @context.sourceview_context_topology_read(context).unwrap(),
  )
}

///|
test "original input one-short grow keeps the same quote position and work until actual admission" {
  for retention in [true, false] {
    let (parent, owner, _input, read) = funded_original_input_parent()
    inspect_program_check_source_topology(owner).unwrap()
    let quote = owner.source_body_quote.unwrap()
    let position = @stage_results.local_program_read_constructor_position(read)
    let observed = owner.topology_observed_work
    let replaced = owner.topology_replaced_bytes
    let additional = quote.0 - program_topology_quotation_bytes
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
    assert_true(physical_equal(owner.source_body_quote.unwrap(), quote))
    assert_eq(owner.topology_replaced_bytes, replaced)
    assert_eq(
      @stage_results.local_program_read_constructor_position(read),
      position,
    )
    assert_eq(owner.topology_observed_work, observed)
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    assert_eq(
      advance_program_check_source_topology(owner).unwrap(),
      PipelineCoreInputs,
    )
    assert_eq(
      @stage_results.local_program_read_constructor_position(read).unwrap().1,
      position.unwrap().1 + 1L,
    )
    clear_program_check_preparation(owner).unwrap()
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(
      @resources.ledger_usage(parent.ledger).reserved_retention_bytes,
      0L,
    )
  }
}

///|
test "same Stage and same input phase cannot upgrade a quote after its original constructor moved" {
  let (parent, owner, _, read) = funded_original_input_parent()
  inspect_program_check_source_topology(owner).unwrap()
  let position = @stage_results.local_program_read_constructor_position(read).unwrap()
  let observed = owner.topology_observed_work
  // Adversarial pure read movement only; the production driver must refuse to
  // reinterpret its old quote, even though Stage and phase remain unchanged.
  assert_eq(@stage_results.advance_local_program_read(read), PipelineCoreInputs)
  let moved = @stage_results.local_program_read_constructor_position(read).unwrap()
  assert_eq(moved.0, position.0)
  assert_eq(moved.1, position.1 + 1L)
  assert_true(advance_program_check_source_topology(owner) is Err(WrongPhase))
  assert_eq(
    @stage_results.local_program_read_constructor_position(read),
    Some(moved),
  )
  assert_eq(owner.topology_observed_work, observed)
  clear_program_check_preparation(owner).unwrap()
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_retention_bytes, 0L)
}
