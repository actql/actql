///|
fn saved_run_reference_locator_key(
  namespace_id : String,
  authority_scope_cid : String,
  definition_cid : String,
) -> String {
  @sha.hex(
    @utf8.encode(
      namespace_id +
      "\u{0000}" +
      authority_scope_cid +
      "\u{0000}" +
      definition_cid,
    ),
  )
}

///|
/// Subordinate Journal locator DATA. The physical caller writes this in the
/// same admission transaction, preserves ambiguity between distinct originals,
/// and authenticates epoch/current separately. No Run or permission is issued.
pub fn client_saved_run_reference_locator(
  reference : ClientSubmissionReferenceRecord,
  request : ClientRequestIdentity,
  definition : @publication.PublicationContract,
) -> Result[(String, Bytes), ClientJournalEncodingIssue] {
  if !client_submission_reference_matches_request(reference, request) ||
    @publication.publication_contract_name(definition) != "run_definition" {
    return Err(Encoding)
  }
  guard @publication.run_definition_namespace(definition) is Some(namespace_id) else {
    return Err(Encoding)
  }
  Ok(
    (
      saved_run_reference_locator_key(
        namespace_id,
        client_request_authority_scope_cid(request),
        @publication.publication_contract_identity(definition),
      ),
      @utf8.encode(client_submission_reference_record_wire(reference)),
    ),
  )
}

///|
/// Targeted saved-original selection through a same-snapshot locator. Missing
/// coverage, ambiguity and corruption refuse; None cannot imply fresh work.
/// The original nested Run validator remains mandatory. Explicit integrity
/// inspection and legacy indexing stay outside ordinary read/open.
pub fn[E] read_client_saved_run_reference(
  namespace_id : String,
  authority_scope_cid : String,
  definition_cid : String,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  validate_run : (ClientJournalPhysicalRow) -> Result[
    ClientRunJournalInspection,
    E,
  ],
  custody_lost : E,
) -> Result[ClientSavedSubmissionSnapshot, E] {
  let key = saved_run_reference_locator_key(
    namespace_id, authority_scope_cid, definition_cid,
  )
  let locator = match read("client_run_reference_index", key) {
    Ok(Some(value)) if value.key == key && value.revision >= 0L => value
    Err(issue) => return Err(issue)
    _ => return Err(custody_lost)
  }
  let wire = @utf8.decode(locator.body) catch { _ => return Err(custody_lost) }
  let reference = match admit_client_submission_reference_record(wire) {
    Ok(value) => value
    Err(_) => return Err(custody_lost)
  }
  let snapshot = match
    read_client_saved_submission(reference, read, validate_run, custody_lost) {
    Ok(Some(value)) => value
    Err(issue) => return Err(issue)
    _ => return Err(custody_lost)
  }
  guard snapshot.inspection is Some(run) else { return Err(custody_lost) }
  if client_request_authority_scope_cid(run.request) != authority_scope_cid ||
    @publication.publication_contract_identity(run.definition) != definition_cid ||
    @publication.run_definition_namespace(run.definition) != Some(namespace_id) {
    return Err(custody_lost)
  }
  Ok(snapshot)
}
