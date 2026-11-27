///|
/// Locator and revision of a single accepted cancellation in the original
/// Journal. A candidate head carries neither a commit acknowledgement nor a
/// current Run permission.
pub struct ClientAcceptedCancellationHead {
  record_key : String
  observed_revision : Int64
} derive(Eq, Debug)

///|
fn decode_client_accepted_cancellation_head(
  cursor : @decode.Cursor,
) -> ClientAcceptedCancellationHead? {
  guard @decode.closed_object(cursor, ["observed_revision", "record_key"])
    is Ok(object) &&
    cancellation_journal_text(object, "record_key") is Some(record_key) &&
    valid_sha256_hex_from(record_key, 0) &&
    @decode.lookup(object, "observed_revision") is Some(revision) &&
    @decode.decimal_int64(revision) is Ok(observed_revision) &&
    observed_revision > 0L &&
    observed_revision <= 2147483647L else {
    return None
  }
  Some({ record_key, observed_revision, })
}

///|
/// Verify the operation and its immutable witness using one original reader.
/// The physical read error and the order of receipt and witness checks matter.
fn[E] read_client_cancellation_row_with_witness(
  row : ClientJournalPhysicalRow,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  custody_lost : E,
) -> Result[ClientCancellationJournalEncoding, E] {
  let original = match decode_client_cancellation_journal_row(row) {
    Ok(value) => value
    Err(_) => return Err(custody_lost)
  }
  let witness = match read("client_cancel_originals", row.key) {
    Ok(Some(value)) => value
    Ok(None) => return Err(custody_lost)
    Err(issue) => return Err(issue)
  }
  guard witness.key == row.key &&
    witness.revision == 0L &&
    witness.body == @utf8.encode(@sha.hex(row.body)) &&
    client_cancellation_journal_index(
      original.namespace_id,
      client_request_authority_scope_cid(original.request),
      original.cancel_id,
    ) ==
    Some(row.key) else {
    return Err(custody_lost)
  }
  Ok(original)
}

///|
/// Observe only the accepted operation named by the head from the checked Run
/// row. The caller supplies the original scoped reader and remains responsible
/// for current authorization, the lease, and the Run transition.
pub fn[E] observe_client_accepted_cancellation_head(
  head : ClientAcceptedCancellationHead,
  namespace_id : String,
  run : ClientCancellationRunOperationFacts,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  custody_lost : E,
) -> Result[ClientCancellationJournalEncoding, E] {
  observe_client_accepted_cancellation_original(
    head, namespace_id, run.request, run.definition, run.revision, read, custody_lost,
  )
}

///|
fn[E] observe_client_accepted_cancellation_original(
  head : ClientAcceptedCancellationHead,
  namespace_id : String,
  request : ClientRequestIdentity,
  definition : @publication.PublicationContract,
  revision : Int64,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  custody_lost : E,
) -> Result[ClientCancellationJournalEncoding, E] {
  let row = match read("client_cancellations", head.record_key) {
    Ok(Some(value)) if value.key == head.record_key => value
    Ok(_) => return Err(custody_lost)
    Err(issue) => return Err(issue)
  }
  let original = match
    read_client_cancellation_row_with_witness(row, read, custody_lost) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard original.namespace_id == namespace_id &&
    original.action == AcceptCancellation &&
    original.observed_revision == head.observed_revision &&
    original.observed_revision <= revision &&
    client_request_identity_relation(original.request, request) ==
    SameRequest &&
    @publication.publication_contract_identity(original.definition) ==
    @publication.publication_contract_identity(definition) else {
    return Err(custody_lost)
  }
  Ok(original)
}
