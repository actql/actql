///|
test "operation orchestration rejects missing and foreign profile material at its owning phase" {
  let cells = lexical_cells(lexical_host(), true)
  let identity = core_profile_identity(cells)
  let limits : OperationResolutionLimits = {
    max_work: 10000000,
    max_requirements: 1000,
    max_resolutions: 1000,
  }
  assert_true(
    resolve_program_operations(identity, limits)
    is Err(Lexical(MissingArtifact)),
  )
  let profile = lexical_artifact(cells)
  let resolved = resolve_program_operations(
    identity,
    limits,
    text_rank=Some(profile),
  ).unwrap()
  assert_true(operation_resolution_count(resolved) > 0)
  let other = lexical_cells(lexical_host(), true)
  assert_true(
    resolve_program_operations(
      core_profile_identity(other),
      limits,
      text_rank=Some(profile),
    )
    is Err(Lexical(ForeignEnvironment)),
  )
  let lexical = calendar_program(program_calendar_host())
  let calendar_identity = core_profile_identity(
    operation_lexical_cells(lexical),
  )
  assert_true(
    resolve_program_operations(calendar_identity, limits)
    is Err(Calendar(MissingArtifact)),
  )
  assert_true(
    resolve_program_operations(
      calendar_identity,
      limits,
      calendar=Some(program_calendar_artifact(lexical)),
    )
    is Ok(_),
  )
  for
    cap in [
      { ..limits, max_work: -1, },
      { ..limits, max_requirements: -1, },
      { ..limits, max_resolutions: -1, },
    ] {
    assert_true(resolve_program_operations(identity, cap) is Err(InvalidLimits))
  }
}
