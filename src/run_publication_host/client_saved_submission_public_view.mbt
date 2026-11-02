///|
pub(all) enum ClientSavedSubmissionViewIssue {
  NotAdmitted
  CustodyLost
  UnrepresentableRevision
  Encoding
} derive(Eq, Debug)

///|
/// Project the original saved admission after the existing retained-Run
/// validator has accepted the same physical snapshot. This does no I/O and
/// grants no current authority, dispatch, retry or publication permission.
/// The trusted durable Host authenticates epoch/scope and rechecks current
/// authority around transfer; this view is not a physical COMMIT ACK.
pub fn client_saved_submission_admission_wire(
  value : ClientSavedSubmissionSnapshot,
) -> Result[String, ClientSavedSubmissionViewIssue] {
  guard value.record.run_admission is Some(admission) else {
    return Err(NotAdmitted)
  }
  guard value.run is Some(retained) && value.inspection is Some(run) else {
    return Err(CustodyLost)
  }
  if validate_client_submitted_retained_run(
      value.record.reference,
      admission,
      run.request,
      run.definition,
      retained.revision,
    )
    is Err(_) {
    return Err(CustodyLost)
  }
  // The journal keeps the full Int64. The public JSON value domain cannot
  // carry an unsafe integer; never round it or substitute a later revision.
  if admission.2 < 0L || admission.2 > 9007199254740991L {
    return Err(UnrepresentableRevision)
  }
  guard @publication.run_definition_namespace(run.definition)
    is Some(run_namespace) else {
    return Err(CustodyLost)
  }
  if run_namespace.length() == 0 || run_namespace.length() > 256 {
    return Err(Encoding)
  }
  for character in run_namespace.iter() {
    if character.to_int() < 32 || character.to_int() == 127 {
      return Err(Encoding)
    }
  }
  try {
    let writer = @encode.writer(4096, 16, 3)
    @encode.begin_object(writer)
    @encode.key(writer, "ref")
    @encode.begin_object(writer)
    @encode.key(writer, "namespaceId")
    @encode.string_value(writer, run_namespace)
    @encode.key(writer, "authorityScopeCid")
    @encode.string_value(
      writer,
      client_request_authority_scope_cid(run.request),
    )
    @encode.key(writer, "runDefinitionCid")
    @encode.string_value(
      writer,
      @publication.publication_contract_identity(run.definition),
    )
    @encode.end_object(writer)
    @encode.key(writer, "durability")
    @encode.string_value(writer, "durable")
    @encode.key(writer, "revision")
    @encode.decimal_number_value(writer, admission.2.to_string())
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(Encoding)
  }
}

///|
/// Candidate bytes for the SAME accepted original after a known preparation
/// failure. This neither writes nor acknowledges a transaction. A terminal
/// outcome, foreign intent or existing Run cannot be rewritten by this view.
pub fn client_saved_submission_preparation_failure_body(
  value : ClientSavedSubmissionSnapshot,
  intent : ClientSubmittedIntent,
  problem : (String, String),
) -> Result[Bytes, ClientSavedSubmissionViewIssue] {
  let original = value.record
  guard original.run_admission is None &&
    original.preparation_problem is None &&
    client_submitted_intent_wire(original.intent) ==
    client_submitted_intent_wire(intent) &&
    client_submitted_intent_cid(original.intent) ==
    client_submitted_intent_cid(intent) &&
    client_submitted_intent_transition("preparing", "preparation_failed") else {
    return Err(CustodyLost)
  }
  client_submitted_intent_journal_row_body(
    client_submission_reference_record_wire(original.reference),
    original.intent,
    preparation_problem=Some(problem),
  ).map_err(_ => Encoding)
}
