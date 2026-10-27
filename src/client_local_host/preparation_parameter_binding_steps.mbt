///|
pub fn[I, P] prepare_parameter_binding_selection(
  owner : ClientParameterBindingPreparation[I, P],
) -> Result[Unit, ClientParameterBindingPreparationIssue] {
  prepare_parameter_binding_step(owner, @parameters.BindingSelection)
}

///|
pub fn[I, P] prepare_parameter_binding_preflight(
  owner : ClientParameterBindingPreparation[I, P],
) -> Result[Unit, ClientParameterBindingPreparationIssue] {
  prepare_parameter_binding_step(owner, @parameters.BindingPreflight)
}

///|
pub fn[I, P] prepare_parameter_binding_value(
  owner : ClientParameterBindingPreparation[I, P],
) -> Result[Unit, ClientParameterBindingPreparationIssue] {
  prepare_parameter_binding_step(owner, @parameters.BindingValue)
}

///|
fn[I, P] prepare_parameter_binding_step(
  owner : ClientParameterBindingPreparation[I, P],
  step : @parameters.BindingReadPhase,
) -> Result[Unit, ClientParameterBindingPreparationIssue] {
  guard !owner.busy &&
    (owner.phase == BindingSteps || owner.phase == BindingStepQuoted) &&
    owner.input is Some(input) &&
    owner.prepared is Some(Ok(original)) &&
    @parameters.binding_read_phase(original) == step else {
    return Err(WrongPhase)
  }
  let current = @parameters.binding_read_current_construction(original)
  guard current is Some(_) else { return Err(WrongPhase) }
  if owner.phase == BindingStepQuoted {
    guard owner.step == step && physical_equal(owner.current, current) else {
      return Err(WrongPhase)
    }
  } else {
    owner.step = step
    owner.current = current
  }
  owner.busy = true
  let result = prepare_parameter_binding_step_owned(owner, input, original)
  owner.busy = false
  result
}

///|
fn[I, P] prepare_parameter_binding_step_owned(
  owner : ClientParameterBindingPreparation[I, P],
  input : I,
  original : @parameters.BindingReadInput,
) -> Result[Unit, ClientParameterBindingPreparationIssue] {
  if owner.phase == BindingSteps {
    guard parameter_binding_step_construction_bytes(original, owner.step)
      is Some((returned, temporary)) &&
      @execution.checked_preparation_add_product(owner.body_bytes, returned, 1L)
      is Some(body) &&
      parameter_binding_phase_quote(owner, body, temporary) is Some(quote) else {
      return Err(Overflow)
    }
    owner.body_bytes = body
    owner.quote = Some(quote)
    owner.phase = BindingStepQuoted
  }
  let (r, e) = owner.quote.unwrap()
  match
    @resources.reserve_working_preparation_phase(owner.capacity, input, r, e) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  // Original currentness may reenter. Same phase alone cannot identify an
  // entry after a complete raw-reader cycle; retain the SAME original fact.
  guard @parameters.binding_read_phase(original) == owner.step &&
    physical_equal(
      owner.current,
      @parameters.binding_read_current_construction(original),
    ) else {
    return Err(WrongPhase)
  }
  @parameters.advance_binding_read(original)
  owner.phase = BindingSteps
  Ok(())
}

///|
/// Only the original cached Complete Ok can return synchronous scratch. Both
/// Ready and NeedsBindings retain their original declarations/usage; no partial
/// BoundValues or failed-location backing is released as a successful result.
pub fn[I, P] reconcile_parameter_bindings(
  owner : ClientParameterBindingPreparation[I, P],
) -> Result[Unit, ClientParameterBindingPreparationIssue] {
  guard !owner.busy &&
    owner.work is None &&
    (owner.phase == BindingSteps || owner.phase == BindingHeaderPrepared) &&
    owner.input is Some(input) &&
    owner.prepared is Some(Ok(original)) &&
    @parameters.binding_read_phase(original) == @parameters.BindingComplete &&
    @parameters.finish_binding_read(original) is Ok(_) else {
    return Err(WrongPhase)
  }
  guard parameter_binding_retained_quote(owner) is Some((r, e)) else {
    return Err(Overflow)
  }
  owner.busy = true
  let result = @resources.reconcile_working_preparation_phase(
    owner.capacity,
    input,
    r,
    e,
  )
  owner.busy = false
  match result {
    Err(issue) => Err(Capacity(issue))
    Ok(_) => {
      owner.quote = Some((r, e))
      owner.phase = BindingRetained
      Ok(())
    }
  }
}
