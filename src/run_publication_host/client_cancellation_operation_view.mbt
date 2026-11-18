///|
// These are bounded response DATA. Neither encoding an accepted original nor
// echoing an attempt is a physical COMMIT, stop or cleanup acknowledgment.
fn cancellation_response_reference(
  writer : @encode.Writer,
  identity : ClientCancellationIdentity,
  operation : Bool,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "namespaceId")
  @encode.string_value(writer, identity.namespace_id)
  @encode.key(writer, "authorityScopeCid")
  @encode.string_value(writer, identity.authority_scope_cid)
  @encode.key(writer, "runDefinitionCid")
  @encode.string_value(writer, identity.run_definition_cid)
  if operation {
    @encode.key(writer, "cancelId")
    @encode.string_value(writer, identity.cancel_id)
    @encode.key(writer, "expectedRevision")
    @encode.number_value(writer, identity.expected_revision.to_double())
  }
  @encode.end_object(writer)
}

///|
fn cancellation_response_attempt(
  writer : @encode.Writer,
  attempt_id : String,
) -> Unit raise @encode.EncodeFailure {
  @encode.key(writer, "attemptRef")
  @encode.begin_object(writer)
  @encode.key(writer, "operation")
  @encode.string_value(writer, "cancel")
  @encode.key(writer, "attemptId")
  @encode.string_value(writer, attempt_id)
  @encode.end_object(writer)
}

///|
/// Match the existing Host attempt envelope. Replaying an accepted original
/// remains accepted; it never becomes another recorded operation or stop.
pub fn client_cancellation_attempt_wire(
  original : ClientCancellationJournalEncoding,
  attempt_id : String,
) -> String? {
  if !valid_client_cancellation_text(attempt_id) ||
    original.observed_revision < 0L ||
    original.observed_revision > 2147483647L {
    return None
  }
  let requested = prepare_client_cancellation_identity(
    original.namespace_id,
    client_request_authority_scope_cid(original.request),
    original.cancel_id,
    original.definition,
    original.expected_revision,
  ).to_option()
  guard requested is Some(requested) &&
    client_cancellation_identity_relation(requested, original.identity) ==
    SameOperation else {
    return None
  }
  let writer = @encode.writer(8192, 40, 5) catch { _ => return None }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "kind")
    @encode.string_value(
      writer,
      if original.action == AcceptCancellation {
        "accepted"
      } else {
        "already_satisfied"
      },
    )
    cancellation_response_attempt(writer, attempt_id)
    @encode.key(writer, "cancellation")
    @encode.begin_object(writer)
    @encode.key(writer, "ref")
    cancellation_response_reference(writer, original.identity, false)
    @encode.key(writer, "cancelRef")
    cancellation_response_reference(writer, original.identity, true)
    @encode.key(writer, "kind")
    @encode.string_value(
      writer,
      match original.action {
        AcceptCancellation => "accepted"
        AlreadyRequested => "already_requested"
        AlreadyTerminal => "already_terminal"
      },
    )
    @encode.key(writer, "revision")
    @encode.number_value(writer, original.observed_revision.to_double())
    @encode.end_object(writer)
    @encode.end_object(writer)
    Some(@encode.finish(writer))
  } catch {
    _ => None
  }
}

///|
/// Only a known pre-write decision has this closed refusal envelope. An I/O,
/// custody, encoding or COMMIT error is never converted to non-consumption.
pub fn[E] client_cancellation_rejection_wire(
  requested : ClientCancellationIdentity,
  attempt_id : String,
  issue : ClientCancellationJournalOperationIssue[E],
) -> String? {
  if !valid_client_cancellation_text(attempt_id) {
    return None
  }
  let (kind, reason) = match issue {
    CapacityExceeded => ("refused", "admission_capacity")
    AuthorizationDenied | Operation(AuthorizationDenied) =>
      ("refused", "authorization")
    ChangedIntent | Operation(ChangedIntent) | Operation(DifferentOperation) =>
      ("conflict", "intent")
    Operation(RevisionConflict) => ("conflict", "control_revision")
    _ => return None
  }
  let writer = @encode.writer(8192, 32, 4) catch { _ => return None }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "kind")
    @encode.string_value(writer, kind)
    cancellation_response_attempt(writer, attempt_id)
    @encode.key(writer, "reason")
    @encode.string_value(writer, reason)
    if kind == "refused" {
      @encode.key(writer, "guarantee")
      @encode.string_value(writer, "attempt_uncommitted_unconsumed")
    }
    @encode.key(writer, "cancelRef")
    cancellation_response_reference(writer, requested, true)
    @encode.end_object(writer)
    Some(@encode.finish(writer))
  } catch {
    _ => None
  }
}
