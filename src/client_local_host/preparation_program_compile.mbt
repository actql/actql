///|
/// Continue the SAME retained check/capacity, without a parse or check fallback.
/// The original variable-data envelope covers coexisting lowering/graph data;
/// fixed controller frames remain trusted Host overhead. Limits are the
/// original installed compiler configuration, never a second resource grant.
pub fn[I, P] compile_program_check_preparation(
  owner : ClientProgramCheckPreparation[I, P],
  limits : @publication_host.ClientProgramPreparationLimits,
) -> Result[
  @publication_host.PreparedClientProgram,
  ClientProgramCheckPreparationIssue,
] {
  guard !owner.busy &&
    (owner.phase == SemanticCheckComplete || owner.phase == CompilationQuoted) &&
    owner.input is Some(input) &&
    owner.check_outcome is Some(@checked.Checked(checked)) &&
    owner.check_data is Some(data) else {
    return Err(WrongPhase)
  }
  // Same original installed configuration on a declined-grow retry. An equal
  // replacement cannot alter the attempted compiler or its typed precedence.
  if owner.compilation_limits is Some(original) &&
    !physical_equal(original, limits) {
    return Err(ChangedInputs)
  }
  owner.busy = true
  let result = compile_program_check_preparation_owned(
    owner, input, checked, data, limits,
  )
  owner.busy = false
  result
}

///|
fn[I, P] compile_program_check_preparation_owned(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  checked : @checked.CheckedProgram,
  data : @checked.ParsedCheckDataEstimate,
  limits : @publication_host.ClientProgramPreparationLimits,
) -> Result[
  @publication_host.PreparedClientProgram,
  ClientProgramCheckPreparationIssue,
] {
  if owner.phase == SemanticCheckComplete {
    guard program_check_data_extent_cost(data) is Some(bytes) else {
      return Err(Overflow)
    }
    let (r, e) = match
      @resources.preparation_capacity_working_extents(owner.capacity, input) {
      Err(issue) => return Err(Capacity(issue))
      Ok(value) => value
    }
    guard @execution.checked_preparation_add_product(r, bytes, 1L) is Some(r) &&
      @execution.checked_preparation_add_product(e, bytes, 1L) is Some(e) else {
      return Err(Overflow)
    }
    owner.compilation_limits = Some(limits)
    owner.compilation_quote = Some((r, e))
    owner.phase = CompilationQuoted
  }
  let (r, e) = owner.compilation_quote.unwrap()
  match
    @resources.reserve_working_preparation_phase(owner.capacity, input, r, e) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  // Bounded by the SAME original lowering limits in every Stage. Binding and
  // graph retain their existing separate finite limits; their unavailable
  // consumed-work observation is not invented from a configured maximum.
  let stages = @checked.unit_count(checked).to_int64()
  let maximum = if limits.lowering.max_work < 0 {
    0L
  } else {
    stages * limits.lowering.max_work.to_int64()
  }
  let work = match
    @resources.begin_preparation_phase_work64(
      owner.capacity,
      input,
      @resources.LowerAndGraph,
      maximum,
    ) {
    Err(issue) => return Err(Work(issue))
    Ok(value) => value
  }
  owner.work = Some(work)
  let (result, known) = @publication_host.observe_prepare_checked_effect_free_client_program(
    checked,
    limits.lowering,
    max_parameters=limits.max_parameters,
    max_parameter_name_bytes=limits.max_parameter_name_bytes,
    max_tasks=limits.max_tasks,
    max_graph_work=limits.max_graph_work,
  )
  owner.compilation_known_work = known
  let charged = @resources.spend_preparation_phase_work64(work, known)
  match @resources.finish_preparation_phase_work64(work) {
    Err(issue) => {
      owner.phase = CompilationFailed
      return Err(Work(issue))
    }
    Ok(_) => owner.work = None
  }
  match charged {
    Err(issue) => {
      owner.phase = CompilationFailed
      return Err(Work(issue))
    }
    Ok(_) => ()
  }
  match result {
    Err(issue) => {
      owner.phase = CompilationFailed
      Err(Compilation(issue))
    }
    Ok(prepared) => {
      owner.compiled_program = Some(prepared)
      owner.phase = CompilationComplete
      Ok(prepared)
    }
  }
}

///|
/// Same synchronous DATA handoff, no repeated compiler/current or early refund.
/// The known count covers completed lowering passes only, not complete work.
pub fn[I, P] take_program_compilation_preparation(
  owner : ClientProgramCheckPreparation[I, P],
) -> Result[
  (@publication_host.PreparedClientProgram, Int64),
  ClientProgramCheckPreparationIssue,
] {
  guard !owner.busy &&
    owner.phase == CompilationComplete &&
    owner.compiled_program is Some(prepared) else {
    return Err(WrongPhase)
  }
  let known = owner.compilation_known_work
  transfer_program_check_input(owner)
  Ok((prepared, known))
}
