///|
/// Continue the SAME Request reservation to its actual Effect Plan body type.
/// The already completed original compiler/candidate is retained, never redone.
pub fn[I] continue_request_effect_preparation(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[
  @publication_host.PreparedClientEffectComputation,
  ClientRequestPreparationIssue,
] {
  guard owner.phase == ProgramCheck &&
    owner.effect_capacity is None &&
    owner.program_capacity is None &&
    owner.program_check is Some(child) &&
    !child.busy &&
    child.phase == CompilationComplete &&
    child.compiled_effect is Some(prepared) &&
    child.check_data is Some(data) else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  clear_request_parameter_source(owner)
  if owner.program_json is Some(source) {
    match clear_program_json_preparation(source) {
      Err(issue) => return Err(ProgramJson(issue))
      Ok(_) => ()
    }
  }
  owner.phase = Selecting
  child.busy = true
  let next : @resources.PreparationCapacity[I, ClientInstalledEffectManagedPlan] = match
    @resources.continue_preparation_capacity(owner.capacity, input) {
    Err(issue) => {
      child.busy = false
      owner.phase = ProgramCheck
      return Err(Capacity(issue))
    }
    Ok(value) => value
  }
  owner.effect_capacity = Some(next)
  owner.compiled_effect = Some(prepared)
  owner.program_data = Some(data)
  transfer_program_check_input(child)
  child.busy = false
  owner.program_check = None
  owner.computation_limits = None
  owner.program_json = None
  owner.phase = EffectCompiled
  Ok(prepared)
}

///|
/// Fund the Core sequence/Plan construction coexistence before the actual
/// constructor. Selected provider/request/response backing remains the normal
/// Host's independent domain on this same parent, never a connector knob.
fn[I] request_effect_plan_quote(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[(Int64, Int64), ClientRequestPreparationIssue] {
  guard (
      owner.phase == EffectCompiled ||
      owner.phase == EffectPlanQuoted ||
      owner.phase == EffectPlanReserved
    ) &&
    owner.effect_capacity is Some(capacity) &&
    owner.program_data is Some(data) else {
    return Err(WrongPhase)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  if owner.phase == EffectCompiled {
    let (r, e) = match
      original_request_plan_construction_quote(capacity, input, data) {
      Err(issue) => return Err(issue)
      Ok(value) => value
    }
    owner.program_plan_quote = Some((r, e))
    owner.phase = EffectPlanQuoted
  }
  Ok(owner.program_plan_quote.unwrap())
}

///|
pub fn[I] reserve_request_effect_plan(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[Unit, ClientRequestPreparationIssue] {
  if owner.phase != EffectCompiled && owner.phase != EffectPlanQuoted {
    return Err(WrongPhase)
  }
  let (r, e) = match request_effect_plan_quote(owner, input) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let capacity = owner.effect_capacity.unwrap()
  owner.phase = Selecting
  let result = @resources.reserve_working_preparation_phase(
    capacity, input, r, e,
  )
  owner.phase = if result is Ok(_) {
    EffectPlanReserved
  } else {
    EffectPlanQuoted
  }
  result.map_err(issue => Capacity(issue))
}

///|
/// Same Effect compiler DATA borrowed for its original Plan constructor. The
/// final body type remains the actual Effect Plan; this token cannot invent it.
pub fn[I] borrow_request_effect_plan_input(
  owner : ClientRequestPreparation[I],
  input : I,
) -> Result[
  @resources.PreparationBodyBorrow[
    @publication_host.PreparedClientEffectComputation,
  ],
  ClientRequestPreparationIssue,
] {
  let (r, e) = match request_effect_plan_quote(owner, input) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let capacity = owner.effect_capacity.unwrap()
  let prepared = owner.compiled_effect.unwrap()
  let reserved = owner.phase == EffectPlanReserved
  let (r, e) = if reserved {
    match @resources.preparation_capacity_working_extents(capacity, input) {
      Err(issue) => return Err(Capacity(issue))
      Ok(value) => value
    }
  } else {
    (r, e)
  }
  owner.phase = Selecting
  let result = @resources.reserve_preparation_construction_input(
    capacity, input, prepared, r, e,
  )
  owner.phase = if result is Ok(_) || reserved {
    EffectPlanReserved
  } else {
    EffectPlanQuoted
  }
  result.map_err(issue => Capacity(issue))
}

///|
/// Complete with the actual original selected Plan. No independently rebuilt
/// plan, request, configuration or prepared computation can stand in for it.
pub fn[I] complete_request_effect_preparation(
  owner : ClientRequestPreparation[I],
  input : I,
  plan : ClientInstalledEffectManagedPlan,
) -> Result[Unit, ClientRequestPreparationIssue] {
  guard owner.phase == EffectPlanReserved &&
    owner.effect_capacity is Some(capacity) &&
    owner.compiled_effect is Some(prepared) &&
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
  owner.effect_plan = Some(plan)
  owner.program_body_attempted = true
  owner.phase = Selecting
  let result = @resources.complete_preparation_capacity(
    capacity, input, plan, r, e,
  )
  owner.phase = if result is Ok(_) { EffectBodyReady } else { EffectBodyFailed }
  result.map_err(issue => Capacity(issue))
}

///|
pub fn[I] borrow_request_effect_preparation(
  owner : ClientRequestPreparation[I],
) -> Result[
  @resources.PreparationBodyBorrow[ClientInstalledEffectManagedPlan],
  ClientRequestPreparationIssue,
] {
  guard owner.phase == EffectBodyReady &&
    owner.effect_capacity is Some(capacity) else {
    return Err(WrongPhase)
  }
  owner.phase = Selecting
  let result = @resources.borrow_preparation_body(capacity)
  owner.phase = EffectBodyReady
  result.map_err(issue => Capacity(issue))
}

///|
/// The existing Effect Run adopts this SAME initial admission and original
/// Plan body. Existing current permission, dispatch and retirement duties stay.
pub fn[I] begin_request_effect_managed_run(
  owner : ClientRequestPreparation[I],
  request : @publication_host.ClientRequestIdentity,
) -> Result[ClientInstalledManagedRun, ClientInstalledManagedRunIssue] {
  guard owner.phase == EffectBodyReady &&
    owner.input is Some(input) &&
    owner.effect_capacity is Some(capacity) &&
    owner.compiled_effect is Some(prepared) &&
    owner.effect_plan is Some(plan) else {
    return Err(ForeignOriginal)
  }
  owner.phase = Selecting
  let result = begin_preparation_owned_installed_effect_managed_run(
    owner.initial,
    input,
    capacity,
    prepared,
    request,
    plan,
  )
  match result {
    Err(issue) => {
      owner.phase = EffectBodyReady
      Err(issue)
    }
    Ok(run) => {
      owner.effect_capacity = None
      owner.compiled_effect = None
      owner.effect_plan = None
      owner.program_data = None
      owner.program_plan_quote = None
      owner.native_parameters = None
      owner.native_query_declarations = None
      owner.native_parameters_ready = false
      owner.held_program = None
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
