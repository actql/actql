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
  guard owner.effect_limits is None &&
    !owner.busy &&
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
  let work = match
    begin_program_compilation_work(owner, input, checked, data, limits) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let (result, known) = @publication_host.observe_prepare_checked_effect_free_client_program(
    checked,
    limits.lowering,
    max_parameters=limits.max_parameters,
    max_parameter_name_bytes=limits.max_parameter_name_bytes,
    max_tasks=limits.max_tasks,
    max_graph_work=limits.max_graph_work,
    values_max_rows=limits.values_max_rows,
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
fn[I, P] begin_program_compilation_work(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  checked : @checked.CheckedProgram,
  data : @checked.ParsedCheckDataEstimate,
  limits : @publication_host.ClientProgramPreparationLimits,
) -> Result[
  @resources.PreparationPhaseWork64,
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
  Ok(work)
}

///|
fn[T] same_effect_publication(left : T?, right : T?) -> Bool {
  match (left, right) {
    (None, None) => true
    (Some(a), Some(b)) => physical_equal(a, b)
    _ => false
  }
}

///|
/// Original retained Effect candidate to the existing static/lowering/graph
/// body. Declined grows retain all original publication selections and limits.
pub fn[I, P] compile_effect_program_check_preparation(
  owner : ClientProgramCheckPreparation[I, P],
  update_targets? : @update_targets.UpdateTargetPublication? = None,
  store_targets? : @update_targets.StoreTargetPublication? = None,
  command_targets? : @update_targets.CommandTargetPublication? = None,
  source_input? : @publication_host.ClientSourceInput? = None,
) -> Result[
  @publication_host.PreparedClientEffectComputation,
  ClientProgramCheckPreparationIssue,
] {
  guard !owner.busy &&
    (owner.phase == SemanticCheckComplete || owner.phase == CompilationQuoted) &&
    owner.input is Some(input) &&
    owner.effect_candidate is Some(candidate) &&
    owner.effect_limits is Some(limits) &&
    owner.check_data is Some(data) else {
    return Err(WrongPhase)
  }
  if owner.effect_targets is Some((update, store, command, source)) {
    if !same_effect_publication(update, update_targets) ||
      !same_effect_publication(store, store_targets) ||
      !same_effect_publication(command, command_targets) ||
      !same_effect_publication(source, source_input) {
      return Err(ChangedInputs)
    }
  } else {
    owner.effect_targets = Some(
      (update_targets, store_targets, command_targets, source_input),
    )
  }
  owner.busy = true
  let result = compile_effect_program_check_preparation_owned(
    owner, input, candidate, data, limits, update_targets, store_targets, command_targets,
    source_input,
  )
  owner.busy = false
  result
}

///|
fn[I, P] compile_effect_program_check_preparation_owned(
  owner : ClientProgramCheckPreparation[I, P],
  input : I,
  candidate : @checked.EffectComputationCandidate,
  data : @checked.ParsedCheckDataEstimate,
  limits : @publication_host.ClientEffectComputationLimits,
  update_targets : @update_targets.UpdateTargetPublication?,
  store_targets : @update_targets.StoreTargetPublication?,
  command_targets : @update_targets.CommandTargetPublication?,
  source_input : @publication_host.ClientSourceInput?,
) -> Result[
  @publication_host.PreparedClientEffectComputation,
  ClientProgramCheckPreparationIssue,
] {
  let checked = @checked.effect_computation_checked_program(candidate)
  let work = match
    begin_program_compilation_work(owner, input, checked, data, limits.program) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let observed = match source_input {
    None =>
      Ok(
        @publication_host.observe_prepare_checked_client_effect_computation(
          candidate,
          limits,
          update_targets~,
          store_targets~,
          command_targets~,
        ),
      )
    Some(source) =>
      @publication_host.observe_prepare_checked_client_source_effect_computation(
        source,
        candidate,
        limits,
        update_targets~,
        store_targets~,
        command_targets~,
      ).map_err(issue => ClientProgramCheckPreparationIssue::SourceInput(issue))
  }
  let known = match observed {
    Ok((_, known)) => known
    // The original Source association is checked before compiler invocation.
    Err(_) => 0L
  }
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
  let result = match observed {
    Err(issue) => {
      owner.phase = CompilationFailed
      return Err(issue)
    }
    Ok((result, _)) => result
  }
  match result {
    Err(issue) => {
      owner.phase = CompilationFailed
      Err(EffectCompilation(issue))
    }
    Ok(prepared) => {
      owner.compiled_effect = Some(prepared)
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
