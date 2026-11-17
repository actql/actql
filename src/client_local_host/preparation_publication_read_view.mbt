///|
/// Lend the same completed metadata checker only inside its actual caller
/// Read. Native observation may finish its view and original Store checks in
/// this call; no validator survives the visitor. A returned DATA value grants
/// no publication, Account, Store-current or future Read permission.
pub fn[T, E] with_program_commit_validation_view_in_read(
  capture : ClientProgramCapture,
  run_definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  artifacts : Array[@publication.PublicationContract],
  derivations : Array[@publication.PublicationContract],
  orderings : Array[@publication.PublicationContract],
  retentions : Array[@publication.PublicationContract],
  bindings : Array[@publication.PublicationContract],
  manifest : @publication.PublicationContract,
  receipt : @publication.PublicationContract,
  captured_run : @publication.PublicationContract,
  request : @publication.PublicationContract,
  attempt : @publication.PublicationContract,
  index_entry : @publication.PublicationContract,
  max_workspace : Int,
  quantum : Int,
  max_rounds : Int,
  fund_read : (ClientProgramValidationReadDemand) -> Result[
    Unit,
    ClientProgramValidationIssue,
  ],
  consume : (ClientProgramValidation, @publication.PublicationCommitPreparation) -> Result[
    T,
    E,
  ],
) -> Result[Result[T, E]?, ClientProgramValidationIssue] {
  guard publication_original_body(capture.publication) is Some(_) &&
    capture.publication.capture is Some(original) &&
    physical_equal(original, capture) &&
    capture.issuer is Some(_) else {
    return Err(Owner(ForeignOriginal))
  }
  if capture.validation is Some(_) {
    return Err(Owner(WrongPhase))
  }
  if max_workspace < 1 || quantum < 1 || max_rounds < 1 {
    return Err(Owner(Policy))
  }
  match
    fund_read({
      retained_bytes: 0L,
      execution_bytes: publication_projection_execution,
      copied_slots: 0,
      copied_arrays: 0,
      metadata_nodes: 0,
      phase: Scaffold,
    }) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let value = match
    prepare_program_commit_validation_funded(
      capture,
      run_definition,
      invocation,
      definitions,
      artifacts,
      derivations,
      orderings,
      retentions,
      bindings,
      manifest,
      receipt,
      captured_run,
      request,
      attempt,
      index_entry,
      Some(fund_read),
    ) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  defer cancel_program_validation(value)
  match fence_program_validation_read(value, Some(fund_read)) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match
    start_program_validation_prequoted(value, max_workspace=Some(max_workspace)) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let mut done = false
  for _ in 0..<max_rounds {
    match advance_program_validation_funded(value, quantum, Some(fund_read)) {
      Err(issue) => return Err(issue)
      Ok((ready, _)) =>
        if ready {
          done = true
          break
        }
    }
  }
  // Preserve the observer's existing bounded-progress refusal independently
  // of semantic/owner errors. No unfinished checker reaches the visitor.
  if !done {
    return Ok(None)
  }
  guard borrow_program_commit_validation(value) is Some(checker) else {
    return Err(Owner(ForeignOriginal))
  }
  let result = consume(value, checker)
  // A consumer error is primary. Only success may escape, after the original
  // Run callback and the SAME physical caller Read have both been rechecked.
  if result is Ok(_) {
    match refresh_publication_original(capture.publication) {
      Err(issue) => return Err(Owner(issue))
      Ok(_) => ()
    }
    match fence_program_validation_read(value, Some(fund_read)) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  Ok(Some(result))
}
