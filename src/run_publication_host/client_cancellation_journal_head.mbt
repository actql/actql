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
    head,
    namespace_id,
    run.request,
    run.definition,
    run.revision,
    read,
    custody_lost,
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
    client_request_identity_relation(original.request, request) == SameRequest &&
    @publication.publication_contract_identity(original.definition) ==
    @publication.publication_contract_identity(definition) else {
    return Err(custody_lost)
  }
  Ok(original)
}

///|
priv struct ClientLegacyAcceptedCancellation {
  scope_cid : String
  intent_cid : String
  definition_cid : String
  head : ClientAcceptedCancellationHead
}

///|
/// Temporary locator inventory within one actual Journal Read. Its entries
/// come only from authenticated accepted operations in the old format's
/// existing cancellation table and immutable witness table.
struct ClientLegacyCancellationHeads {
  accepted : Array[ClientLegacyAcceptedCancellation]
}

///|
pub fn[E] read_client_legacy_cancellation_heads(
  max_records : Int,
  scan : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  fund : (Int64, Int64, Int64) -> Result[Unit, E],
  custody_lost : E,
  capacity_exceeded : E,
) -> Result[ClientLegacyCancellationHeads, E] {
  let (count, _) = match
    read_client_cancellation_journal_issuance(
      max_records, scan, read, custody_lost,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let count_units = count.to_int64()
  // The array can grow while retaining the compact CID and head records.
  // Include a second reference vector for ordering before construction.
  guard @execution.preparation_array_representation(2L, count_units, true)
    is Some(vectors) &&
    @execution.preparation_representation_cost({
      record_headers: vectors.record_headers + 5L * count_units,
      reference_slots: vectors.reference_slots + 5L * count_units,
      scalar_words: vectors.scalar_words + count_units,
      owned_utf16_units: (3L * 71L + 64L) * count_units,
      owned_wire_bytes: 0L,
    })
    is Some(retained) else {
    return Err(capacity_exceeded)
  }
  match fund(retained, retained, 0L) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let accepted = []
  let mut key = ""
  for _ in 0..<count {
    let row = match scan("client_cancellations", key) {
      Ok(Some(value)) if value.key > key => value
      Ok(_) => return Err(custody_lost)
      Err(issue) => return Err(issue)
    }
    key = row.key
    guard row.revision == 0L &&
      client_cancellation_journal_scan_workspace(row.body.length())
      is Some(workspace) else {
      return Err(custody_lost)
    }
    match fund(0L, workspace, row.body.length().to_int64()) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    let original = match
      read_client_cancellation_row_with_witness(row, read, custody_lost) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if original.action is AcceptCancellation {
      guard @publication.run_definition_namespace(original.definition) ==
        Some(original.namespace_id) &&
        original.observed_revision > 0L &&
        original.observed_revision <= 2147483647L else {
        return Err(custody_lost)
      }
      accepted.push({
        scope_cid: client_request_scope_cid(original.request),
        intent_cid: client_request_intent_cid(original.request),
        definition_cid: @publication.publication_contract_identity(
          original.definition,
        ),
        head: {
          record_key: key,
          observed_revision: original.observed_revision,
        },
      })
    }
  }
  match scan("client_cancellations", key) {
    Ok(None) => ()
    Ok(Some(_)) => return Err(custody_lost)
    Err(issue) => return Err(issue)
  }
  accepted.sort_by((left, right) => left.scope_cid.compare(right.scope_cid))
  for index in 1..<accepted.length() {
    if accepted[index - 1].scope_cid == accepted[index].scope_cid {
      return Err(custody_lost)
    }
  }
  Ok({ accepted, })
}

///|
pub fn ClientLegacyCancellationHeads::select(
  self : Self,
  request : ClientRequestIdentity,
  definition : @publication.PublicationContract,
  revision : Int64,
) -> ClientAcceptedCancellationHead? {
  let scope = client_request_scope_cid(request)
  let mut low = 0
  let mut high = self.accepted.length()
  while low < high {
    let index = low + (high - low) / 2
    let original = self.accepted[index]
    let order = original.scope_cid.compare(scope)
    if order < 0 {
      low = index + 1
    } else if order > 0 {
      high = index
    } else {
      return if original.intent_cid == client_request_intent_cid(request) &&
        original.definition_cid ==
        @publication.publication_contract_identity(definition) &&
        original.head.observed_revision <= revision {
        Some(original.head)
      } else {
        None
      }
    }
  }
  None
}
