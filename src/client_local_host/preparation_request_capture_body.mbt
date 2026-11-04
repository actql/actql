///|
/// Complete the actual captured Plan on the existing Pure prepared capacity.
/// The Run fields/manager borrow own its Plan dependency until actual cleanup.
fn[I] complete_request_capture_preparation(
  owner : ClientRequestPreparation[I],
  input : I,
  plan : ClientInstalledManagedCapturePlan,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard owner.phase == ProgramPlanReserved &&
    owner.program_capacity is Some(capacity) &&
    owner.compiled_program is Some(prepared) &&
    physical_equal(plan.prepared, prepared) else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  let (r, e) = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  owner.program_captured = Some(plan)
  owner.program_body_attempted = true
  owner.phase = Selecting
  let result = @resources.complete_preparation_capacity(
    capacity, input, prepared, r, e,
  )
  owner.phase = if result is Ok(_) {
    ProgramBodyReady
  } else {
    ProgramBodyFailed
  }
  result.map_err(issue => Capacity(issue))
}

///|
pub fn[I] begin_request_capture_managed_run(
  owner : ClientRequestPreparation[I],
  request : @publication_host.ClientRequestIdentity,
) -> Result[ClientInstalledManagedRun, ClientInstalledManagedRunIssue] {
  guard owner.phase == ProgramBodyReady &&
    owner.input is Some(input) &&
    owner.program_capacity is Some(capacity) &&
    owner.compiled_program is Some(prepared) &&
    owner.program_captured is Some(plan) else {
    return Err(ForeignOriginal)
  }
  owner.phase = Selecting
  let result = begin_preparation_owned_installed_capture_run_original(
    owner.initial,
    input,
    capacity,
    prepared,
    request,
    plan,
  )
  match result {
    Err(issue) => {
      owner.phase = ProgramBodyReady
      Err(issue)
    }
    Ok(run) => {
      owner.program_capacity = None
      owner.compiled_program = None
      owner.program_data = None
      owner.program_plan_quote = None
      owner.program_captured = None
      owner.program_model_direct = None
      owner.native_parameters = None
      owner.native_query_declarations = None
      owner.native_parameters_ready = false
      owner.held_program = None
      clear_request_source_input(owner)
      owner.submitted_intent = None
      owner.intent_base = None
      owner.intent_peak_live = false
      owner.input = None
      owner.query_syntax = None
      owner.phase = Selected
      Ok(run)
    }
  }
}
