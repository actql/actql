///|
/// Grow the SAME original parent before Source correspondence and Stage copy.
/// A failed resize retains the exact Program, completed reader and quote.
/// No declaration/type/default reader is advanced or repeated by this phase.
pub fn[I, P] prepare_parameter_declaration_source(
  owner : ClientParameterDeclarationPreflight[I, P],
  program : @syntax.Program,
) -> Result[Unit, ClientParameterDeclarationPreflightIssue] {
  guard !owner.busy &&
    (owner.phase == RetainedDeclarations || owner.phase == SourceQuoted) &&
    owner.input is Some(input) &&
    owner.prepared is Some((Ok(original), _, _)) &&
    @parameters.declaration_read_phase(original) ==
    @parameters.DeclarationComplete else {
    return Err(WrongPhase)
  }
  if owner.phase == SourceQuoted &&
    !(owner.program is Some(selected) && physical_equal(selected, program)) {
    return Err(WrongPhase)
  }
  owner.busy = true
  let result = prepare_parameter_declaration_source_owned(
    owner, input, program, original,
  )
  owner.busy = false
  result
}

///|
fn[I, P] prepare_parameter_declaration_source_owned(
  owner : ClientParameterDeclarationPreflight[I, P],
  input : I,
  program : @syntax.Program,
  original : @parameters.DeclarationReadInput,
) -> Result[Unit, ClientParameterDeclarationPreflightIssue] {
  if owner.phase == RetainedDeclarations {
    guard parameter_source_construction_bytes(program)
      is Some((returned, temporary, maximum)) &&
      @execution.checked_preparation_add_product(owner.body_bytes, returned, 1L)
      is Some(body) &&
      @execution.checked_preparation_add_product(
        owner.body_bytes,
        temporary,
        1L,
      )
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
    owner.program = Some(program)
    owner.body_bytes = body
    owner.source_maximum_work = maximum
    owner.quote = Some((r, e))
    owner.phase = SourceQuoted
  }
  let (r, e) = owner.quote.unwrap()
  match
    @resources.reserve_working_preparation_phase(owner.capacity, input, r, e) {
    Err(issue) => return Err(Capacity(issue))
    Ok(_) => ()
  }
  guard owner.program is Some(selected) &&
    physical_equal(selected, program) &&
    @parameters.declaration_read_phase(original) ==
    @parameters.DeclarationComplete else {
    return Err(WrongPhase)
  }
  let receipt = match
    @resources.begin_preparation_phase_work64(
      owner.capacity,
      input,
      @resources.ParameterSourceConstruction,
      owner.source_maximum_work,
    ) {
    Err(issue) => return Err(Work(issue))
    Ok(receipt) => receipt
  }
  owner.work = Some(receipt)
  let (source, spent) = @stages.prepare_from_declaration_read(program, original)
  let charged = @resources.spend_preparation_phase_work64(receipt, spent)
  match @resources.finish_preparation_phase_work64(receipt) {
    Err(issue) => return Err(Work(issue))
    Ok(_) => owner.work = None
  }
  owner.source = Some(source)
  owner.phase = SourcePrepared
  match charged {
    Err(issue) => Err(Work(issue))
    Ok(_) => Ok(())
  }
}

///|
pub fn[I, P] parameter_declaration_source_outcome(
  owner : ClientParameterDeclarationPreflight[I, P],
) -> Result[@stages.Source, @stages.Issue]? {
  if owner.busy || owner.phase == Retired {
    None
  } else {
    owner.source
  }
}

///|
/// Return only synchronous constructor scratch after an actual successful
/// Source result. Original declarations, Program, Source aliases and outside
/// debit remain charged; clear does not settle or refund this reservation.
pub fn[I, P] reconcile_parameter_declaration_source(
  owner : ClientParameterDeclarationPreflight[I, P],
) -> Result[Unit, ClientParameterDeclarationPreflightIssue] {
  guard !owner.busy &&
    owner.work is None &&
    owner.phase == SourcePrepared &&
    owner.input is Some(input) &&
    owner.source is Some(Ok(_)) else {
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
      owner.quote = Some((r, e))
      owner.phase = RetainedSource
      Ok(())
    }
  }
}
