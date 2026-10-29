///|
/// Grow SAME original reservation before the actual ParameterSyntax builder.
/// Metadata observations are retained, never repeated; the resulting original
/// ParameterType stays in the reader for the later separately funded default.
pub fn[I, P] prepare_parameter_declaration_type(
  owner : ClientParameterDeclarationPreflight[I, P],
) -> Result[Unit, ClientParameterDeclarationPreflightIssue] {
  guard !owner.busy &&
    (
      owner.phase == RetainedInventory ||
      owner.phase == ValuePrepared ||
      owner.phase == TypeQuoted
    ) &&
    owner.input is Some(input) &&
    owner.prepared is Some((Ok(original), _, _)) &&
    @parameters.declaration_read_phase(original) == @parameters.DeclarationType else {
    return Err(WrongPhase)
  }
  let cursor = @parameters.declaration_read_type_cursor(original)
  let facts = @parameters.declaration_read_current_construction(original)
  guard cursor is Some(_) && facts is Some(_) else { return Err(WrongPhase) }
  if owner.phase == RetainedInventory || owner.phase == ValuePrepared {
    owner.current_syntax = None
    owner.current_type = cursor
    owner.current_type_facts = facts
  } else if !physical_equal(owner.current_type, cursor) ||
    !physical_equal(owner.current_type_facts, facts) {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = prepare_parameter_declaration_type_owned(owner, input, original)
  owner.busy = false
  result
}

///|
fn[I, P] prepare_parameter_declaration_type_owned(
  owner : ClientParameterDeclarationPreflight[I, P],
  input : I,
  original : @parameters.DeclarationReadInput,
) -> Result[Unit, ClientParameterDeclarationPreflightIssue] {
  if owner.phase == RetainedInventory || owner.phase == ValuePrepared {
    guard parameter_type_construction_bytes(original, owner.depth)
      is Some((returned, temporary)) &&
      @execution.checked_preparation_add_product(owner.body_bytes, returned, 1L)
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
    // Prior synchronous constructors returned, but their original reservation
    // is not silently shrunk. Fund this independently derived peak and retain
    // the larger charged peak until final successful reconciliation.
    let (r, e) = match owner.quote {
      None => (r, e)
      Some((prior_r, prior_e)) =>
        (Int64::max(r, prior_r), Int64::max(e, prior_e))
    }
    owner.body_bytes = body
    owner.quote = Some((r, e))
    owner.phase = TypeQuoted
  }
  let (r, e) = owner.quote.unwrap()
  match
    @resources.reserve_working_preparation_phase(owner.capacity, input, r, e) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  // Currentness may reenter and even move a raw reader through another entry.
  // Phase alone is insufficient: both original cursor and facts must survive.
  guard @parameters.declaration_read_phase(original) ==
    @parameters.DeclarationType &&
    physical_equal(
      owner.current_type,
      @parameters.declaration_read_type_cursor(original),
    ) &&
    physical_equal(
      owner.current_type_facts,
      @parameters.declaration_read_current_construction(original),
    ) else {
    return Err(WrongPhase)
  }
  @parameters.advance_declaration_read(original)
  owner.phase = TypePrepared
  Ok(())
}
