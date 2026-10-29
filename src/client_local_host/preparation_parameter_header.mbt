///|
/// Fund the SAME original Header before open_object, names, sorting or reader
/// construction. Successful preflight scratch must already have returned and
/// reconciled. Type/default/metadata remain unconstructed and need later funding.
pub fn[I, P] prepare_parameter_declaration_header(
  owner : ClientParameterDeclarationPreflight[I, P],
) -> Result[Unit, ClientParameterDeclarationPreflightIssue] {
  guard !owner.busy &&
    (owner.phase == RetainedPreflight || owner.phase == HeaderQuoted) &&
    owner.input is Some(input) &&
    owner.prepared is Some((Ok(original), _, _)) &&
    @parameters.declaration_read_phase(original) ==
    @parameters.DeclarationHeader else {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = prepare_parameter_declaration_header_owned(
    owner, input, original,
  )
  owner.busy = false
  result
}

///|
fn[I, P] prepare_parameter_declaration_header_owned(
  owner : ClientParameterDeclarationPreflight[I, P],
  input : I,
  original : @parameters.DeclarationReadInput,
) -> Result[Unit, ClientParameterDeclarationPreflightIssue] {
  if owner.phase == RetainedPreflight {
    guard parameter_header_construction_split(
        owner.root,
        owner.depth,
        owner.limits,
      )
      is Some((retained, bytes)) &&
      @execution.checked_preparation_add_product(
        parameter_preflight_initial_bytes, bytes, 1L,
      )
      is Some(total) &&
      @execution.checked_preparation_add_product(owner.base_retained, total, 1L)
      is Some(r) &&
      @execution.checked_preparation_add_product(
        owner.base_execution,
        total,
        1L,
      )
      is Some(e) else {
      return Err(Overflow)
    }
    owner.body_bytes = retained
    owner.quote = Some((r, e))
    owner.phase = HeaderQuoted
  }
  let (r, e) = owner.quote.unwrap()
  match
    @resources.reserve_working_preparation_phase(owner.capacity, input, r, e) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  // Actual Resource currentness can call out/reenter. The SAME semantic reader
  // must still be at Header after that boundary; do not advance a changed phase
  // into type/default work merely because the byte growth succeeded.
  guard @parameters.declaration_read_phase(original) ==
    @parameters.DeclarationHeader else {
    return Err(WrongPhase)
  }
  @parameters.advance_declaration_read(original)
  owner.phase = HeaderPrepared
  Ok(())
}
