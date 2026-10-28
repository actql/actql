///|
fn funded_original_parameter_parent() -> (
  ClientRequestPreparation[Array[Int]],
  ClientProgramCheckPreparation[Array[Int], Unit],
  Array[Int],
  @stage_results.LocalProgramRead,
) raise {
  let (parent, owner, input) = context_entry_parent(
    2,
    params=Some(
      "{\"p\":{\"type\":\"array\",\"items\":{\"type\":\"object\",\"fields\":{\"v\":{\"type\":\"number\"}}},\"default\":[{\"v\":1}]},\"zz\":{\"type\":\"string\",\"nullable\":true,\"default\":\"x\"}}",
    ),
  )
  prepare_program_check_source_context_input(owner).unwrap()
  prepare_program_check_source_topology_entry(owner).unwrap()
  let context = @checked.parsed_source_context_input(
      owner.source_registration.unwrap(),
    )
    .unwrap()
    .unwrap()
  let read = @context.sourceview_context_topology_read(context).unwrap()
  while @stage_results.local_program_read_phase(read) != PipelineCoreParameters {
    advance_program_check_source_topology(owner).unwrap() |> ignore
    reconcile_program_check_source_topology(owner).unwrap()
  }
  (parent, owner, input, read)
}

///|
test "same Request retains original composite declarations and funds Parameter stack and next arrays without new ownership" {
  let (parent, owner, input, read) = funded_original_parameter_parent()
  let context = @checked.parsed_source_context_input(
      owner.source_registration.unwrap(),
    )
    .unwrap()
    .unwrap()
  let source = @context.sourceview_context_input_source(context)
  let declarations = @stages.declarations(source)
  assert_eq(@parameters.declaration_count(declarations), 2)
  assert_true(
    @parameters.has_default(
      @parameters.declaration_at(declarations, 0).unwrap(),
    ),
  )
  let receipt = owner.topology_work.unwrap()
  let before_work = owner.topology_observed_work
  let mut steps = 0
  while @stage_results.local_program_read_phase(read) == PipelineCoreParameters {
    let before = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
    let _ = advance_program_check_source_topology(owner).unwrap()
    let (peak, held) = owner.source_body_quote.unwrap()
    let replaced = owner.topology_replaced_bytes
    assert_eq(owner.environment_scratch, Some(peak + replaced - held))
    reconcile_program_check_source_topology(owner).unwrap()
    assert_eq(
      @resources.preparation_capacity_working_extents(parent.capacity, input),
      Ok((before.0 + held - replaced, before.1 + held - replaced)),
    )
    assert_true(physical_equal(owner.topology_work.unwrap(), receipt))
    assert_true(
      physical_equal(
        @stages.declarations(@context.sourceview_context_input_source(context)),
        declarations,
      ),
    )
    steps += 1
  }
  assert_true(steps > 8)
  assert_eq(owner.topology_observed_work - before_work, 7L)
  assert_eq(
    @stage_results.local_program_read_phase(read),
    PipelineCoreImportedEvidence,
  )
  assert_true(advance_program_check_source_topology(owner) is Err(WrongPhase))
  clear_program_check_preparation(owner).unwrap()
  assert_eq(@stage_results.local_program_read_phase(read), Cleared)
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_retention_bytes, 0L)
}

///|
test "Parameter one-short admission retains original declaration position and consumed work until the same parent can grow" {
  for retention in [true, false] {
    let (parent, owner, _, read) = funded_original_parameter_parent()
    let original = @stage_results.local_program_read_constructor_position(read)
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
      original,
    )
    assert_eq(owner.topology_observed_work, work)
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    assert_eq(
      advance_program_check_source_topology(owner).unwrap(),
      PipelineCoreParameters,
    )
    assert_eq(owner.topology_observed_work, work + 2L)
    clear_program_check_preparation(owner).unwrap()
    abort_request_preparation_after_cleanup(parent).unwrap()
  }
}

///|
test "unknown initial selector preserves original Source refusal before Parameter topology" {
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  let declaration = "\"rows\":{\"carrier\":\"relation\",\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"primary_key\":[\"id\"]}"
  let text = "{\"version\":\"actql/0.1\",\"id\":\"early-selector\",\"params\":{\"p\":{\"type\":\"number\",\"default\":1}},\"stages\":[{\"id\":\"s\",\"inputs\":{" +
    declaration +
    "},\"from\":\"missing\",\"steps\":[],\"results\":{\"out\":{}}}],\"results\":{\"out\":{\"from\":{\"stage\":\"s\",\"result\":\"out\"}}}}"
  let source = prepare_request_program_json_preparation(
    parent,
    input,
    text,
    @publication_host.client_standard_program_preparation_limits().checking.input,
  ).unwrap()
  while true {
    match advance_program_json_preparation(source, 64).unwrap() {
      @source.JsonSourceContinue(..) => ()
      @source.JsonSourceReady(_, ..) => break
      @source.JsonSourceFailed(_, ..) =>
        fail("authored JSON must reach original structure constructor")
    }
  }
  finish_program_json_preparation(source).unwrap()
  assert_true(
    construct_program_json_preparation(source)
    is Err(Syntax(Structure(UnknownInput("missing"), ..))),
  )
  assert_true(source.program is None)
  assert_true(parent.program_check is None)
  assert_true(
    @resources.ledger_usage(parent.ledger).reserved_retention_bytes > 0L,
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).reserved_retention_bytes, 0L)
}
