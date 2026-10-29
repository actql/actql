///|
/// Attach the completed original binding only after funding its new Source
/// snapshot. The old Source/reader/values are still held by original aliases.
/// Repeated growth retains the SAME selected Source and original quote.
pub fn[I, P] prepare_parameter_binding_source(
  owner : ClientParameterBindingPreparation[I, P],
  source : @stages.Source,
) -> Result[Unit, ClientParameterBindingPreparationIssue] {
  guard !owner.busy &&
    (owner.phase == BindingRetained || owner.phase == BindingSourceQuoted) &&
    owner.input is Some(input) &&
    owner.prepared is Some(Ok(original)) &&
    @parameters.binding_read_phase(original) == @parameters.BindingComplete else {
    return Err(WrongPhase)
  }
  if owner.phase == BindingSourceQuoted &&
    !(owner.source_input is Some(selected) && physical_equal(selected, source)) {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = prepare_parameter_binding_source_owned(
    owner, input, source, original,
  )
  owner.busy = false
  result
}

///|
fn[I, P] prepare_parameter_binding_source_owned(
  owner : ClientParameterBindingPreparation[I, P],
  input : I,
  source : @stages.Source,
  original : @parameters.BindingReadInput,
) -> Result[Unit, ClientParameterBindingPreparationIssue] {
  if owner.phase == BindingRetained {
    guard parameter_source_binding_construction_bytes()
      is Some((returned, temporary)) &&
      @execution.checked_preparation_add_product(owner.body_bytes, returned, 1L)
      is Some(body) &&
      @execution.checked_preparation_add_product(
        owner.body_bytes,
        temporary,
        1L,
      )
      is Some(peak) &&
      @execution.checked_preparation_add_product(
        parameter_binding_initial_bytes, peak, 1L,
      )
      is Some(peak) &&
      @execution.checked_preparation_add_product(owner.base_retained, peak, 1L)
      is Some(r) &&
      @execution.checked_preparation_add_product(owner.base_execution, peak, 1L)
      is Some(e) else {
      return Err(Overflow)
    }
    owner.source_input = Some(source)
    owner.body_bytes = body
    owner.quote = Some((r, e))
    owner.phase = BindingSourceQuoted
  }
  let (r, e) = owner.quote.unwrap()
  match
    @resources.reserve_working_preparation_phase(owner.capacity, input, r, e) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  guard owner.source_input is Some(selected) &&
    physical_equal(selected, source) &&
    @parameters.binding_read_phase(original) == @parameters.BindingComplete else {
    return Err(WrongPhase)
  }
  owner.source = Some(@stages.retain_completed_binding(source, original))
  owner.phase = BindingSourcePrepared
  Ok(())
}

///|
pub fn[I, P] parameter_binding_source_outcome(
  owner : ClientParameterBindingPreparation[I, P],
) -> Result[@stages.Source, @stages.Issue]? {
  if owner.busy || owner.phase == BindingRetired {
    None
  } else {
    owner.source
  }
}

///|
pub fn[I, P] reconcile_parameter_binding_source(
  owner : ClientParameterBindingPreparation[I, P],
) -> Result[Unit, ClientParameterBindingPreparationIssue] {
  guard !owner.busy &&
    owner.work is None &&
    owner.phase == BindingSourcePrepared &&
    owner.input is Some(input) &&
    owner.source is Some(Ok(_)) else {
    return Err(WrongPhase)
  }
  guard @execution.checked_preparation_add_product(
      parameter_binding_initial_bytes,
      owner.body_bytes,
      1L,
    )
    is Some(bytes) &&
    @execution.checked_preparation_add_product(owner.base_retained, bytes, 1L)
    is Some(r) &&
    @execution.checked_preparation_add_product(owner.base_execution, bytes, 1L)
    is Some(e) else {
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
      owner.phase = BindingSourceRetained
      Ok(())
    }
  }
}
