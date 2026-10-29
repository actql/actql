///|
/// Grow SAME original reservation before the complete quantity stack/vector.
/// One existing work phase covers all declarations, not one allowance per
/// field/default. Header/Source and outside debits remain owned throughout.
pub fn[I, P] prepare_parameter_declaration_inventory(
  owner : ClientParameterDeclarationPreflight[I, P],
) -> Result[Unit, ClientParameterDeclarationPreflightIssue] {
  guard !owner.busy &&
    (owner.phase == HeaderPrepared || owner.phase == InventoryQuoted) &&
    owner.input is Some(input) &&
    owner.root is Some(root) &&
    owner.geometry is Some(geometry) &&
    owner.prepared is Some((Ok(original), _, _)) &&
    @parameters.declaration_read_phase(original) == @parameters.DeclarationType &&
    @parameters.declaration_read_construction_work(original) is None else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = prepare_parameter_declaration_inventory_owned(
    owner, input, root, geometry, original,
  )
  owner.busy = false
  result
}

///|
fn[I, P] prepare_parameter_declaration_inventory_owned(
  owner : ClientParameterDeclarationPreflight[I, P],
  input : I,
  root : @decode.Cursor,
  geometry : @decode.SubtreeConstructionGeometry,
  original : @parameters.DeclarationReadInput,
) -> Result[Unit, ClientParameterDeclarationPreflightIssue] {
  if owner.phase == HeaderPrepared {
    guard @decode.object_length(root) is Some(count) &&
      parameter_inventory_construction_bytes(geometry.nodes, count)
      is Some((retained, temporary)) &&
      @execution.checked_preparation_add_product(owner.body_bytes, retained, 1L)
      is Some(body) &&
      @execution.checked_preparation_add_product(body, temporary, 1L)
      is Some(peak) &&
      @execution.checked_preparation_add_product(
        parameter_preflight_initial_bytes, peak, 1L,
      )
      is Some(peak) &&
      @execution.checked_preparation_add_product(owner.base_retained, peak, 1L)
      is Some(r) &&
      @execution.checked_preparation_add_product(owner.base_execution, peak, 1L)
      is Some(e) else {
      return Err(Overflow)
    }
    owner.body_bytes = body
    owner.quote = Some((r, e))
    owner.phase = InventoryQuoted
  }
  let (r, e) = owner.quote.unwrap()
  match
    @resources.reserve_working_preparation_phase(owner.capacity, input, r, e) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  guard @parameters.declaration_read_phase(original) ==
    @parameters.DeclarationType &&
    @parameters.declaration_read_construction_work(original) is None else {
    return Err(WrongPhase)
  }
  // Per selected source node: <=6 type/control visits, <=12 field metadata
  // visits, <=3 default-tree visits plus name/metadata observations.32N bounds
  // the SAME original quantity walk; it is not CPU or validation-call count.
  let work = match
    @resources.begin_preparation_phase_work64(
      owner.capacity,
      input,
      @resources.ParameterDeclarationBodyInventory,
      32L * geometry.nodes.to_int64(),
    ) {
    Err(issue) => return Err(Work(issue))
    Ok(value) => value
  }
  owner.work = Some(work)
  let observed = @parameters.observe_declaration_read_construction(original)
  let spent = match observed {
    None => None
    Some(used) => Some(@resources.spend_preparation_phase_work64(work, used))
  }
  match @resources.finish_preparation_phase_work64(work) {
    Err(issue) => return Err(Work(issue))
    Ok(_) => owner.work = None
  }
  match spent {
    None => {
      owner.phase = Failed
      return Err(WrongPhase)
    }
    Some(Err(issue)) => {
      owner.phase = Failed
      return Err(Work(issue))
    }
    Some(Ok(_)) => ()
  }
  owner.phase = InventoryPrepared
  Ok(())
}

///|
/// Only after the synchronous walk and original receipt returned. Retain its
/// SAME facts/Header/source; retire only the returned Cursor-stack scratch.
/// No parent settlement, physical stop or work refund occurs here.
pub fn[I, P] reconcile_parameter_declaration_inventory(
  owner : ClientParameterDeclarationPreflight[I, P],
) -> Result[Unit, ClientParameterDeclarationPreflightIssue] {
  guard !owner.busy &&
    owner.phase == InventoryPrepared &&
    owner.input is Some(input) else {
    return Err(WrongPhase)
  }
  guard @execution.checked_preparation_add_product(
      parameter_preflight_initial_bytes,
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
      owner.phase = RetainedInventory
      Ok(())
    }
  }
}
