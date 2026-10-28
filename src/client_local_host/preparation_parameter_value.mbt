///|
/// Grow the SAME reservation before metadata/Value/constraints/final-entry
/// construction. A resource success retains the original semantic outcome;
/// it does not turn a typed refusal into successful declarations.
pub fn[I, P] prepare_parameter_declaration_value(
  owner : ClientParameterDeclarationPreflight[I, P],
) -> Result[Unit, ClientParameterDeclarationPreflightIssue] {
  guard !owner.busy &&
    (owner.phase == TypePrepared || owner.phase == ValueQuoted) &&
    owner.input is Some(input) &&
    owner.prepared is Some((Ok(original), _, _)) &&
    @parameters.declaration_read_phase(original) == @parameters.DeclarationValue else {
    return Err(WrongPhase)
  }
  let syntax = @parameters.declaration_read_pending_syntax(original)
  let facts = @parameters.declaration_read_current_construction(original)
  guard syntax is Some(_) && facts is Some(_) else { return Err(WrongPhase) }
  if owner.phase == TypePrepared {
    guard physical_equal(owner.current_type_facts, facts) else {
      return Err(WrongPhase)
    }
    owner.current_syntax = syntax
  } else if !physical_equal(owner.current_syntax, syntax) ||
    !physical_equal(owner.current_type_facts, facts) {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = prepare_parameter_declaration_value_owned(owner, input, original)
  owner.busy = false
  result
}

///|
fn[I, P] prepare_parameter_declaration_value_owned(
  owner : ClientParameterDeclarationPreflight[I, P],
  input : I,
  original : @parameters.DeclarationReadInput,
) -> Result[Unit, ClientParameterDeclarationPreflightIssue] {
  if owner.phase == TypePrepared {
    guard parameter_value_construction_bytes(original, owner.depth)
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
    let (r, e) = match owner.quote {
      None => (r, e)
      Some((prior_r, prior_e)) =>
        (Int64::max(r, prior_r), Int64::max(e, prior_e))
    }
    owner.body_bytes = body
    owner.quote = Some((r, e))
    owner.phase = ValueQuoted
  }
  let (r, e) = owner.quote.unwrap()
  match
    @resources.reserve_working_preparation_phase(owner.capacity, input, r, e) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  guard @parameters.declaration_read_phase(original) ==
    @parameters.DeclarationValue &&
    physical_equal(
      owner.current_syntax,
      @parameters.declaration_read_pending_syntax(original),
    ) &&
    physical_equal(
      owner.current_type_facts,
      @parameters.declaration_read_current_construction(original),
    ) else {
    return Err(WrongPhase)
  }
  @parameters.advance_declaration_read(original)
  owner.phase = ValuePrepared
  Ok(())
}

///|
/// Reconcile only after the original complete successful semantic reader and
/// all its synchronous scratch returned. Refusals keep full location backing.
/// Source/output aliases stay funded; no parent settlement or work refund.
pub fn[I, P] reconcile_parameter_declarations(
  owner : ClientParameterDeclarationPreflight[I, P],
) -> Result[Unit, ClientParameterDeclarationPreflightIssue] {
  guard !owner.busy &&
    (owner.phase == ValuePrepared || owner.phase == HeaderPrepared) &&
    owner.input is Some(input) &&
    owner.prepared is Some((Ok(original), _, _)) &&
    @parameters.declaration_read_phase(original) ==
    @parameters.DeclarationComplete &&
    @parameters.finish_declaration_read(original) is Ok(_) else {
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
      owner.phase = RetainedDeclarations
      Ok(())
    }
  }
}
