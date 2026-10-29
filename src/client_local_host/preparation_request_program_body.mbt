///|
/// Select the actual completed compiler output on the SAME Request parent.
/// The original initial admission, input, reservation and work history survive.
/// Only fixed continuation controls are constructed; no wrapper census or new
/// allowance is introduced. The capacity never escapes as a mutable Ledger.
pub fn[I] continue_request_program_preparation(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[
  @publication_host.PreparedClientProgram,
  ClientRequestPreparationIssue,
] {
  guard owner.phase == ProgramCheck &&
    owner.program_capacity is None &&
    owner.program_check is Some(child) &&
    !child.busy &&
    child.phase == CompilationComplete &&
    child.compiled_program is Some(prepared) &&
    child.check_data is Some(data) else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  // Return the already transferred Source controller's local aliases before
  // selecting the final body. Its output is retained by this exact compiler.
  if owner.program_json is Some(source) {
    match clear_program_json_preparation(source) {
      Err(issue) => return Err(ProgramJson(issue))
      Ok(_) => ()
    }
  }
  owner.phase = Selecting
  child.busy = true
  let next : @resources.PreparationCapacity[
    I,
    @publication_host.PreparedClientProgram,
  ] = match @resources.continue_preparation_capacity(owner.capacity, input) {
    Err(issue) => {
      child.busy = false
      owner.phase = ProgramCheck
      return Err(Capacity(issue))
    }
    Ok(value) => value
  }
  // Retain the same successor before cutting the original child aliases.
  owner.program_capacity = Some(next)
  owner.compiled_program = Some(prepared)
  owner.program_data = Some(data)
  transfer_program_check_input(child)
  child.busy = false
  owner.program_check = None
  owner.program_json = None
  owner.phase = ProgramCompiled
  Ok(prepared)
}

///|
/// Fund the selected Plan/module constructor before the existing caller enters
/// it. These new arrays/sequence/Plan data coexist with the retained compiler;
/// reuse its original dimensions once, not another parse/check or Plan quote.
pub fn[I] reserve_request_program_plan(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard (owner.phase == ProgramCompiled || owner.phase == ProgramPlanQuoted) &&
    owner.program_capacity is Some(capacity) &&
    owner.program_data is Some(data) else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  if owner.phase == ProgramCompiled {
    let (r, e) = match
      original_request_plan_construction_quote(capacity, input, data) {
      Err(issue) => return Err(issue)
      Ok(value) => value
    }
    owner.program_plan_quote = Some((r, e))
    owner.phase = ProgramPlanQuoted
  }
  let (r, e) = owner.program_plan_quote.unwrap()
  owner.phase = Selecting
  let result = @resources.reserve_working_preparation_phase(
    capacity, input, r, e,
  )
  owner.phase = if result is Ok(_) {
    ProgramPlanReserved
  } else {
    ProgramPlanQuoted
  }
  result.map_err(issue => Capacity(issue))
}

///|
/// Bind the actual same-owner installed Plan/configuration after its funded
/// constructor returns. No body or Plan is reconstructed. Retain the full peak
/// across this handoff; retired scratch is not guessed from a returned value.
pub fn[I] complete_request_program_preparation(
  owner : ClientRequestPreparation[I],
  input : I,
  plan : ClientInstalledManagedSourceFreePreparation,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard owner.phase == ProgramPlanReserved &&
    owner.program_capacity is Some(capacity) &&
    owner.compiled_program is Some(prepared) &&
    plan.owner is Pure(original_prepared) &&
    physical_equal(original_prepared, prepared) &&
    plan.configuration is Some(_) else {
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
  owner.program_source_free = Some(plan)
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
/// Existing original body token for the fixed manager. Live borrowers keep the
/// reservation during retirement. This neither admits a Run nor proves stop.
pub fn[I] borrow_request_program_preparation(
  owner : ClientRequestPreparation[I],
) -> Result[
  @resources.PreparationBodyBorrow[@publication_host.PreparedClientProgram],
  ClientRequestPreparationIssue,
] {
  guard owner.phase == ProgramBodyReady &&
    owner.program_capacity is Some(capacity) else {
    return Err(WrongPhase)
  }
  owner.phase = Selecting
  let result = @resources.borrow_preparation_body(capacity)
  owner.phase = ProgramBodyReady
  result.map_err(issue => Capacity(issue))
}

///|
/// Adopt this SAME initial admission/capacity/installed Plan into the existing
/// preparation-owned source-free Run. Captured Source and Effect consumers
/// retain their separate original Plan contracts; there is no None fallback.
pub fn[I] begin_request_program_managed_run(
  owner : ClientRequestPreparation[I],
  request : @publication_host.ClientRequestIdentity,
) -> Result[ClientInstalledManagedRun, ClientInstalledManagedRunIssue] {
  guard owner.phase == ProgramBodyReady &&
    owner.input is Some(input) &&
    owner.program_capacity is Some(capacity) &&
    owner.compiled_program is Some(prepared) &&
    owner.program_source_free is Some(plan) else {
    return Err(ForeignOriginal)
  }
  owner.phase = Selecting
  let result = begin_preparation_owned_installed_managed_run(
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
      // The Run has retained its original cleanup custody and body holders.
      // No callback occurs while cutting this consumed parent's heavy aliases.
      owner.program_capacity = None
      owner.compiled_program = None
      owner.program_data = None
      owner.program_plan_quote = None
      owner.program_source_free = None
      owner.native_parameters = None
      owner.native_parameters_ready = false
      owner.held_program = None
      owner.input = None
      owner.query_syntax = None
      owner.phase = Selected
      Ok(run)
    }
  }
}

///|
// One shared original sequence/Plan data envelope for both typed body choices.
// This prices DATA only; the caller retains the same capacity and phase guard.
fn[I, P] original_request_plan_construction_quote(
  capacity : @resources.PreparationCapacity[I, P],
  input : I,
  data : @checked.ParsedCheckDataEstimate,
) -> Result[(Int64, Int64), ClientRequestPreparationIssue] {
  guard program_check_data_extent_cost(data) is Some(bytes) else {
    return Err(Policy)
  }
  let (r, e) = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Err(issue) => return Err(Capacity(issue))
    Ok(value) => value
  }
  guard @execution.checked_preparation_add_product(r, bytes, 1L) is Some(r) &&
    @execution.checked_preparation_add_product(e, bytes, 1L) is Some(e) else {
    return Err(Policy)
  }
  Ok((r, e))
}
