///|
/// Fund the complete original fact vector before its one metadata walk.
/// Actual Cursor/default selection is retained by the semantic reader; later
/// steps use those SAME originals, not another lookup or type preparation.
pub fn[I, P] prepare_parameter_binding_inventory(
  owner : ClientParameterBindingPreparation[I, P],
) -> Result[Unit, ClientParameterBindingPreparationIssue] {
  guard !owner.busy &&
    (
      owner.phase == BindingHeaderPrepared ||
      owner.phase == BindingInventoryQuoted
    ) &&
    owner.input is Some(input) &&
    owner.prepared is Some(Ok(original)) &&
    @parameters.binding_read_phase(original) == @parameters.BindingSelection &&
    @parameters.binding_read_construction_work(original) is None else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = prepare_parameter_binding_inventory_owned(owner, input, original)
  owner.busy = false
  result
}

///|
fn[I, P] prepare_parameter_binding_inventory_owned(
  owner : ClientParameterBindingPreparation[I, P],
  input : I,
  original : @parameters.BindingReadInput,
) -> Result[Unit, ClientParameterBindingPreparationIssue] {
  if owner.phase == BindingHeaderPrepared {
    guard parameter_binding_inventory_construction_bytes(original)
      is Some((r, t)) &&
      @parameters.binding_read_construction_maximum_work(original)
      is Some(maximum) &&
      @execution.checked_preparation_add_product(owner.body_bytes, r, 1L)
      is Some(body) &&
      parameter_binding_phase_quote(owner, body, t) is Some(quote) else {
      return Err(Overflow)
    }
    owner.body_bytes = body
    owner.maximum_work = maximum
    owner.quote = Some(quote)
    owner.phase = BindingInventoryQuoted
  }
  let (r, e) = owner.quote.unwrap()
  match
    @resources.reserve_working_preparation_phase(owner.capacity, input, r, e) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  guard @parameters.binding_read_phase(original) == @parameters.BindingSelection &&
    @parameters.binding_read_construction_work(original) is None else {
    return Err(WrongPhase)
  }
  let receipt = match
    @resources.begin_preparation_phase_work64(
      owner.capacity,
      input,
      @resources.ParameterBindingBodyInventory,
      owner.maximum_work,
    ) {
    Err(issue) => return Err(Work(issue))
    Ok(receipt) => receipt
  }
  owner.work = Some(receipt)
  let observed = @parameters.observe_binding_read_construction(original)
  let charged = match observed {
    None => None
    Some(spent) =>
      Some(@resources.spend_preparation_phase_work64(receipt, spent))
  }
  match @resources.finish_preparation_phase_work64(receipt) {
    Err(issue) => return Err(Work(issue))
    Ok(_) => owner.work = None
  }
  match charged {
    None => {
      owner.phase = BindingFailed
      return Err(WrongPhase)
    }
    Some(Err(issue)) => {
      owner.phase = BindingFailed
      return Err(Work(issue))
    }
    Some(Ok(_)) => ()
  }
  owner.phase = BindingInventoryPrepared
  Ok(())
}

///|
/// Only after synchronous original metadata scratch and its work receipt
/// returned. Keep Header/facts/source/outputs; no parent settle or work refund.
pub fn[I, P] reconcile_parameter_binding_inventory(
  owner : ClientParameterBindingPreparation[I, P],
) -> Result[Unit, ClientParameterBindingPreparationIssue] {
  guard !owner.busy &&
    owner.phase == BindingInventoryPrepared &&
    owner.work is None &&
    owner.input is Some(input) else {
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
      // Confirmed scratch retirement changes the live base. Do not regrow an
      // earlier completed inventory peak merely because its quote was retained.
      owner.quote = Some((r, e))
      owner.phase = BindingSteps
      Ok(())
    }
  }
}
