///|
/// Facts projected by the same original Run validator, not current permission.
pub(all) struct ClientCancellationRunOperationFacts {
  request : ClientRequestIdentity
  definition : @publication.PublicationContract
  revision : Int64
  cancellation_requested : Bool
  publication_binding : String?
}

///|
pub(all) enum ClientCancellationJournalOperationIssue[E] {
  Observation(E)
  CustodyLost
  Encoding
  CapacityExceeded
  AuthorizationDenied
  ChangedIntent
  Identity(ClientCancellationIdentityIssue)
  Operation(ClientCancellationOperationIssue)
}

///|
/// A bounded write candidate, retained by the caller's existing transaction or
/// prepared-output Owner. Neither this plan nor its rows acknowledge a write.
struct ClientCancellationJournalAppend[R] {
  run : R
  record : ClientCancellationJournalEncoding
  key : String
  issued : Int
  issued_revision : Int64
}

///|
pub(all) enum ClientCancellationJournalAppendPlan[R] {
  RetainedCancellation(ClientCancellationJournalEncoding)
  AppendCancellation(ClientCancellationJournalAppend[R])
}

///|
pub(all) enum ClientCancellationJournalLookup {
  UnresolvedCancellationHistory
  OriginalCancellation(ClientCancellationJournalEncoding)
}

///|
// These ports remain inside the original current/fenced physical transaction.
// census is the complete Common inventory over that same reader; retained
// invokes the backend's full original Run/nested metadata validation. No
// caller-supplied scope or row digest replaces either observation.
fn[R, E] cancellation_journal_operation_originals(
  request : ClientRequestIdentity,
  namespace_id : String,
  cancel_id : String,
  expected_revision : Int,
  census : () -> Result[(Int, Int64), E],
  retained : () -> Result[R?, E],
  facts : (R) -> ClientCancellationRunOperationFacts,
  read_original : (String) -> Result[ClientCancellationJournalEncoding?, E],
) -> Result[
  (
    R,
    ClientCancellationRunOperationFacts,
    ClientCancellationIdentity,
    String,
    ClientCancellationJournalEncoding?,
    Int,
    Int64,
  ),
  ClientCancellationJournalOperationIssue[E],
] {
  let (issued, issued_revision) = match census() {
    Ok(value) => value
    Err(issue) => return Err(Observation(issue))
  }
  let run = match retained() {
    Ok(Some(value)) => value
    Ok(None) => return Err(CustodyLost)
    Err(issue) => return Err(Observation(issue))
  }
  let original = facts(run)
  if client_request_identity_relation(request, original.request) != SameRequest {
    return Err(CustodyLost)
  }
  let identity = match
    prepare_client_cancellation_identity(
      namespace_id,
      client_request_authority_scope_cid(request),
      cancel_id,
      original.definition,
      expected_revision,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Identity(issue))
  }
  let key = match
    client_cancellation_journal_index(
      namespace_id,
      client_request_authority_scope_cid(request),
      cancel_id,
    ) {
    Some(value) => value
    None => return Err(Encoding)
  }
  let retained_cancellation = match read_original(key) {
    Ok(value) => value
    Err(issue) => return Err(Observation(issue))
  }
  Ok(
    (
      run, original, identity, key, retained_cancellation, issued, issued_revision,
    ),
  )
}

///|
/// Reuse the existing cancellation decision without writing, refreshing a
/// revision or deriving an old operation's result from today's Run flags.
pub fn[R, E] prepare_client_cancellation_journal_append(
  request : ClientRequestIdentity,
  namespace_id : String,
  cancel_id : String,
  expected_revision : Int,
  max_records : Int,
  publication_binding : String?,
  census : () -> Result[(Int, Int64), E],
  retained : () -> Result[R?, E],
  facts : (R) -> ClientCancellationRunOperationFacts,
  read_original : (String) -> Result[ClientCancellationJournalEncoding?, E],
  observe_terminal : (R) -> Result[Bool, E],
  current : () -> Bool,
) -> Result[
  ClientCancellationJournalAppendPlan[R],
  ClientCancellationJournalOperationIssue[E],
] {
  let (run, original_run, identity, key, original, issued, issued_revision) = match
    cancellation_journal_operation_originals(
      request, namespace_id, cancel_id, expected_revision, census, retained, facts,
      read_original,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if original is None && original_run.publication_binding != publication_binding {
    return Err(ChangedIntent)
  }
  // The physical publication observer is called only for a new operation,
  // while the same original Store/Run binding is still held by the caller.
  let terminal = if original is Some(_) {
    false
  } else {
    match observe_terminal(run) {
      Ok(value) => value
      Err(issue) => return Err(Observation(issue))
    }
  }
  if original_run.revision > 2147483647L {
    return Err(CapacityExceeded)
  }
  let action = match
    prepare_client_cancellation_operation(
      identity,
      original.map(value => value.identity),
      original_run.definition,
      original_run.revision.to_int(),
      true,
      terminal,
      original_run.cancellation_requested,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Operation(issue))
  }
  if !current() {
    return Err(AuthorizationDenied)
  }
  match action {
    ReplayOriginalCancellation => Ok(RetainedCancellation(original.unwrap()))
    RecordCancellation(action) => {
      if issued >= max_records {
        return Err(CapacityExceeded)
      }
      let record : ClientCancellationJournalEncoding = {
        namespace_id,
        cancel_id,
        expected_revision,
        request,
        definition: original_run.definition,
        identity,
        action,
        observed_revision: original_run.revision +
        (if action == AcceptCancellation { 1L } else { 0L }),
      }
      Ok(AppendCancellation({ run, record, key, issued, issued_revision, }))
    }
  }
}

///|
pub fn[R] client_cancellation_append_original(
  plan : ClientCancellationJournalAppend[R],
) -> R {
  plan.run
}

///|
pub fn[R] client_cancellation_append_record(
  plan : ClientCancellationJournalAppend[R],
) -> ClientCancellationJournalEncoding {
  plan.record
}

///|
/// Produce exact existing row/witness/CAS DATA. The caller still owns the
/// actual Run update, all atomic writes, COMMIT/Unknown and current checks.
pub fn[R] client_cancellation_append_rows(
  plan : ClientCancellationJournalAppend[R],
) -> (String, Bytes, Bytes, Int64, Bytes)? {
  client_cancellation_journal_row_body(plan.record).map(body => {
    (
      plan.key,
      body,
      @utf8.encode(@sha.hex(body)),
      plan.issued_revision,
      @utf8.encode((plan.issued + 1).to_string()),
    )
  })
}

///|
/// Read the immutable original only. Missing history is unresolved; it cannot
/// request a new cancellation, observe physical stop or manufacture success.
pub fn[R, E] lookup_client_cancellation_journal_original(
  request : ClientRequestIdentity,
  namespace_id : String,
  cancel_id : String,
  expected_revision : Int,
  census : () -> Result[(Int, Int64), E],
  retained : () -> Result[R?, E],
  facts : (R) -> ClientCancellationRunOperationFacts,
  read_original : (String) -> Result[ClientCancellationJournalEncoding?, E],
  current : () -> Bool,
) -> Result[
  ClientCancellationJournalLookup,
  ClientCancellationJournalOperationIssue[E],
] {
  let (_, _, identity, _, original, _, _) = match
    cancellation_journal_operation_originals(
      request, namespace_id, cancel_id, expected_revision, census, retained, facts,
      read_original,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !current() {
    return Err(AuthorizationDenied)
  }
  match original {
    None => Ok(UnresolvedCancellationHistory)
    Some(value) =>
      match client_cancellation_identity_relation(identity, value.identity) {
        SameOperation => Ok(OriginalCancellation(value))
        ChangedIntent => Err(Operation(ChangedIntent))
        DifferentOperation => Err(Operation(DifferentOperation))
      }
  }
}
