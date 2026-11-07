///|
/// Same adopted publication owner; a validation continuation never exposes its
/// semantic checker or substitutes a second reservation/registry.
pub(all) enum ClientProgramValidationIssue {
  Owner(ClientClosedValuesPreparationIssue)
  Chain(@publication.RunEvidenceChainIssue)
  Commit(@publication.PublicationCommitIssue)
}

///|
struct ClientProgramValidation {
  capture : ClientProgramCapture
  commit_kind : Bool
  mut plan : @publication.PublicationValidationPlan?
  mut chain : @publication.ComputationEvidenceCheck?
  mut commit : @publication.PublicationCommitPreparation?
  mut closed : Bool
}

///|
/// Cancel semantic aliases before allowing the same capture to prepare another
/// serial check. A stale wrapper cannot remove a newer active continuation.
pub fn cancel_program_validation(value : ClientProgramValidation) -> Unit {
  if value.closed {
    return
  }
  if value.plan is Some(plan) {
    @publication.cancel_publication_validation_plan(plan)
  }
  value.plan = None
  if value.chain is Some(checker) {
    checker.cancel()
  }
  value.chain = None
  if value.commit is Some(checker) {
    checker.cancel()
  }
  value.commit = None
  value.closed = true
  if value.capture.validation is Some(current) && physical_equal(current, value) {
    value.capture.validation = None
  }
}

///|
fn validation_original(value : ClientProgramValidation) -> Bool {
  !value.closed &&
  value.capture.validation is Some(current) &&
  physical_equal(current, value) &&
  value.capture.publication.capture is Some(capture) &&
  physical_equal(capture, value.capture) &&
  publication_original_body(value.capture.publication) is Some(_) &&
  value.capture.issuer is Some(_)
}

///|
fn[T] validation_failure(
  value : ClientProgramValidation,
  issue : ClientProgramValidationIssue,
) -> Result[T, ClientProgramValidationIssue] {
  cancel_program_validation(value)
  Err(issue)
}

///|
fn new_program_validation(
  capture : ClientProgramCapture,
  commit_kind : Bool,
) -> Result[ClientProgramValidation, ClientProgramValidationIssue] {
  guard publication_original_body(capture.publication) is Some(_) &&
    capture.publication.capture is Some(original) &&
    physical_equal(original, capture) &&
    capture.issuer is Some(_) else {
    return Err(Owner(ForeignOriginal))
  }
  if capture.validation is Some(_) {
    return Err(Owner(WrongPhase))
  }
  // This fixed six-slot handle and Some are part of the publication owner's
  // pre-admitted continuation control packet, before callback-bearing growth.
  let value : ClientProgramValidation = {
    capture,
    commit_kind,
    plan: None,
    chain: None,
    commit: None,
    closed: false,
  }
  capture.validation = Some(value)
  Ok(value)
}

///|
fn grow_program_validation(
  value : ClientProgramValidation,
  retained : Int64,
  execution : Int64,
) -> Result[Unit, ClientProgramValidationIssue] {
  if !validation_original(value) {
    return Err(Owner(ForeignOriginal))
  }
  let capture = value.capture
  let publication = capture.publication
  guard publication_original_body(capture.publication) is Some(prepared) else {
    return Err(Owner(ForeignOriginal))
  }
  let target = Int64::max(capture.validation_retained, retained)
  let delta = target - capture.validation_retained
  if retained < 0L ||
    execution < 0L ||
    delta > 9223372036854775807L - publication.retained_quote {
    return Err(Owner(Policy))
  }
  let total = publication.retained_quote + delta
  let peak = Int64::max(publication.execution_quote, execution)
  match
    reserve_program_publication_phase(
      capture.publication.holder,
      prepared,
      total,
      peak,
    ) {
    Err(issue) => return Err(Owner(issue))
    Ok(_) => {
      publication.retained_quote = total
      publication.execution_quote = peak
      capture.validation_retained = target
    }
  }
  if !validation_original(value) {
    return Err(Owner(ForeignOriginal))
  }
  Ok(())
}

///|
fn fund_validation_inventory(
  value : ClientProgramValidation,
  slots : Int64,
  arrays : Int,
) -> Result[Unit, ClientProgramValidationIssue] {
  guard program_validation_inventory_layout(slots, arrays) is Some(units) &&
    @execution.preparation_representation_cost(units) is Some(retained) else {
    return Err(Owner(Policy))
  }
  grow_program_validation(value, retained, publication_projection_execution)
}

///|
fn finish_program_validation_plan(
  value : ClientProgramValidation,
  plan : @publication.PublicationValidationPlan,
) -> Result[ClientProgramValidation, ClientProgramValidationIssue] {
  value.plan = Some(plan)
  // This Host recipe owns metadata validation only. An unmatched/stale capture
  // never silently enters the full row-revalidation path under this allowance.
  guard @publication.publication_validation_plan_reuses_capture(plan)
    is Some(true) &&
    @publication.publication_validation_plan_inventory(plan)
    is Some((slots, arrays, _, metadata, _, _, _)) &&
    program_retained_validation_layout(slots, arrays, metadata) is Some(layout) &&
    @execution.preparation_representation_cost(layout.retained) is Some(r) &&
    @execution.preparation_representation_cost(layout.temporary) is Some(e) else {
    return validation_failure(value, Owner(Policy))
  }
  match grow_program_validation(value, r, e) {
    Err(issue) => return validation_failure(value, issue)
    Ok(_) => ()
  }
  guard @publication.publication_validation_plan_reuses_capture(plan)
    is Some(true) else {
    return validation_failure(value, Owner(ForeignOriginal))
  }
  Ok(value)
}

///|
pub fn prepare_program_chain_validation(
  capture : ClientProgramCapture,
  run_definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  artifacts : Array[@publication.PublicationContract],
  manifest : @publication.PublicationContract,
  receipt : @publication.PublicationContract,
  captured_run : @publication.PublicationContract,
) -> Result[ClientProgramValidation, ClientProgramValidationIssue] {
  let value = match new_program_validation(capture, false) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let slots = definitions.length().to_int64() + artifacts.length().to_int64()
  match fund_validation_inventory(value, slots, 2) {
    Err(issue) => return validation_failure(value, issue)
    Ok(_) => ()
  }
  // Imported currentness may mutate caller arrays. Never copy more members
  // than the same original growth just funded. Plan snapshots actual members.
  if definitions.length().to_int64() + artifacts.length().to_int64() > slots {
    return validation_failure(value, Owner(Policy))
  }
  guard capture.issuer is Some(issuer) else {
    return validation_failure(value, Owner(ForeignOriginal))
  }
  guard @publication.prepare_original_effect_free_chain_validation(
      run_definition,
      invocation,
      definitions,
      artifacts,
      manifest,
      receipt,
      captured_run,
      retained=Some(issuer),
    )
    is Some(plan) else {
    return validation_failure(value, Owner(Policy))
  }
  finish_program_validation_plan(value, plan)
}

///|
pub fn prepare_program_commit_validation(
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
) -> Result[ClientProgramValidation, ClientProgramValidationIssue] {
  let value = match new_program_validation(capture, true) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let slots = definitions.length().to_int64() +
    artifacts.length().to_int64() +
    derivations.length().to_int64() +
    orderings.length().to_int64() +
    retentions.length().to_int64() +
    bindings.length().to_int64()
  match fund_validation_inventory(value, slots, 6) {
    Err(issue) => return validation_failure(value, issue)
    Ok(_) => ()
  }
  // Imported currentness may mutate caller arrays. Never copy more members
  // than the same original growth just funded. Plan snapshots actual members.
  if definitions.length().to_int64() +
    artifacts.length().to_int64() +
    derivations.length().to_int64() +
    orderings.length().to_int64() +
    retentions.length().to_int64() +
    bindings.length().to_int64() >
    slots {
    return validation_failure(value, Owner(Policy))
  }
  guard capture.issuer is Some(issuer) else {
    return validation_failure(value, Owner(ForeignOriginal))
  }
  guard @publication.prepare_original_effect_free_commit_validation(
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
      retained=Some(issuer),
    )
    is Some(plan) else {
    return validation_failure(value, Owner(Policy))
  }
  finish_program_validation_plan(value, plan)
}

///|
pub fn start_program_validation(
  value : ClientProgramValidation,
) -> Result[ClientProgramValidation, ClientProgramValidationIssue] {
  if !validation_original(value) {
    return Err(Owner(ForeignOriginal))
  }
  guard value.plan is Some(plan) else { return Err(Owner(WrongPhase)) }
  match
    grow_program_validation(
      value,
      value.capture.validation_retained,
      value.capture.publication.execution_quote,
    ) {
    Err(issue) => return validation_failure(value, issue)
    Ok(_) => ()
  }
  guard @publication.publication_validation_plan_reuses_capture(plan)
    is Some(true) else {
    return validation_failure(value, Owner(ForeignOriginal))
  }
  if value.commit_kind {
    guard @publication.start_planned_commit_validation(plan) is Some(checker) else {
      return validation_failure(value, Owner(WrongPhase))
    }
    value.commit = Some(checker)
  } else {
    guard @publication.start_planned_chain_validation(plan) is Some(checker) else {
      return validation_failure(value, Owner(WrongPhase))
    }
    value.chain = Some(checker)
  }
  value.plan = None
  Ok(value)
}

///|
pub fn advance_program_validation(
  value : ClientProgramValidation,
  quantum : Int,
) -> Result[(Bool, Int), ClientProgramValidationIssue] {
  if !validation_original(value) {
    return Err(Owner(ForeignOriginal))
  }
  match refresh_publication_original(value.capture.publication) {
    Err(issue) => return Err(Owner(issue))
    Ok(_) => ()
  }
  if !validation_original(value) {
    return Err(Owner(ForeignOriginal))
  }
  if value.chain is Some(checker) {
    return checker.advance(quantum).map_err(issue => Chain(issue))
  }
  if value.commit is Some(checker) {
    return checker.advance(quantum).map_err(issue => Commit(issue))
  }
  Err(Owner(WrongPhase))
}

///|
pub fn finish_program_validation(
  value : ClientProgramValidation,
) -> Result[Unit, ClientProgramValidationIssue] {
  if !validation_original(value) {
    return Err(Owner(ForeignOriginal))
  }
  match refresh_publication_original(value.capture.publication) {
    Err(issue) => return Err(Owner(issue))
    Ok(_) => ()
  }
  if !validation_original(value) {
    return Err(Owner(ForeignOriginal))
  }
  let result = if value.chain is Some(checker) {
    checker.finish().map_err(issue => Chain(issue))
  } else if value.commit is Some(checker) {
    checker.finish().map_err(issue => Commit(issue))
  } else {
    Err(Owner(WrongPhase))
  }
  match result {
    Ok(_) => {
      cancel_program_validation(value)
      Ok(())
    }
    Err(issue) => Err(issue)
  }
}

///|
/// Synchronous imported caller of the SAME reserved validation continuation.
/// All original contract associations and current callbacks remain checked;
/// failure always retires its own checker before returning the typed cause.
pub fn check_program_commit_validation(
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
) -> Result[Unit, ClientProgramValidationIssue] {
  let validation = match
    prepare_program_commit_validation(
      capture, run_definition, invocation, definitions, artifacts, derivations, orderings,
      retentions, bindings, manifest, receipt, captured_run, request, attempt, index_entry,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match start_program_validation(validation) {
    Ok(_) => ()
    Err(issue) => {
      cancel_program_validation(validation)
      return Err(issue)
    }
  }
  let mut done = false
  while !done {
    match advance_program_validation(validation, 256) {
      Ok((ready, _)) => done = ready
      Err(issue) => {
        cancel_program_validation(validation)
        return Err(issue)
      }
    }
  }
  match finish_program_validation(validation) {
    Ok(_) => Ok(())
    Err(issue) => {
      cancel_program_validation(validation)
      Err(issue)
    }
  }
}
