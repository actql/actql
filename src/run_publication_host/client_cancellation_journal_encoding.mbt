///|
/// Exact serialization DATA of the existing immutable cancellation row. This
/// supplies neither Journal provenance, current authority nor physical stop.
pub(all) struct ClientCancellationJournalEncoding {
  namespace_id : String
  cancel_id : String
  expected_revision : Int
  request : ClientRequestIdentity
  definition : @publication.PublicationContract
  identity : ClientCancellationIdentity
  action : ClientRunCancellationAction
  observed_revision : Int64
}

///|
fn cancellation_journal_cursor(body : Bytes) -> @decode.Cursor? {
  @source.parse_json_bytes_preserving(body, {
    max_input_bytes: 262144,
    max_nodes: 4096,
    max_depth: 64,
  })
  .to_option()
  .bind(source => {
    @decode.admit(source, {
      max_nodes: 4096,
      max_depth: 64,
      max_string_bytes: 262144,
      max_total_string_bytes: 262144,
    }).to_option()
  })
}

///|
fn cancellation_journal_text(
  object : @decode.ObjectView,
  key : String,
) -> String? {
  @decode.lookup(object, key).bind(value => @decode.text(value).to_option())
}

///|
pub fn client_cancellation_journal_index(
  namespace_id : String,
  authority : String,
  cancel_id : String,
) -> String? {
  try {
    let writer = @encode.writer(4096, 4, 1)
    @encode.begin_array(writer)
    for value in [namespace_id, authority, cancel_id] {
      @encode.string_value(writer, value)
    }
    @encode.end_array(writer)
    Some(@sha.hex(@utf8.encode(@encode.finish(writer))))
  } catch {
    _ => None
  }
}

///|
pub fn client_cancellation_journal_row_body(
  value : ClientCancellationJournalEncoding,
) -> Bytes? {
  encode_client_cancellation_journal_row(
    value,
    client_cancellation_intent_cid(value.identity),
  )
}

///|
// The codec supplies its own calculated CID. Decoding can use that same CID
// for canonical byte comparison after verifying the claimed field.
fn encode_client_cancellation_journal_row(
  value : ClientCancellationJournalEncoding,
  intent_cid : String,
) -> Bytes? {
  try {
    let writer = @encode.writer(131072, 32, 4)
    @encode.begin_object(writer)
    @encode.key(writer, "action")
    @encode.string_value(
      writer,
      match value.action {
        AcceptCancellation => "accepted"
        AlreadyRequested => "already_requested"
        AlreadyTerminal => "already_terminal"
      },
    )
    @encode.key(writer, "cancel_id")
    @encode.string_value(writer, value.cancel_id)
    @encode.key(writer, "expected_revision")
    @encode.string_value(writer, value.expected_revision.to_string())
    @encode.key(writer, "intent_cid")
    @encode.string_value(writer, intent_cid)
    @encode.key(writer, "namespace_id")
    @encode.string_value(writer, value.namespace_id)
    @encode.key(writer, "observed_revision")
    @encode.string_value(writer, value.observed_revision.to_string())
    @encode.key(writer, "request")
    @encode.string_value(
      writer,
      client_request_identity_record_wire(value.request).unwrap(),
    )
    @encode.key(writer, "run_definition")
    @encode.string_value(
      writer,
      @publication.publication_contract_json(value.definition),
    )
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-native-client-cancellation-row/0.1")
    @encode.end_object(writer)
    Some(@utf8.encode(@encode.finish(writer)))
  } catch {
    _ => None
  }
}

///|
pub fn decode_client_cancellation_journal_row(
  row : ClientJournalPhysicalRow,
) -> Result[ClientCancellationJournalEncoding, ClientJournalDecodingIssue] {
  if row.revision != 0L {
    return Err(CustodyLost)
  }
  guard cancellation_journal_cursor(row.body) is Some(cursor) &&
    @decode.closed_object(cursor, [
      "action", "cancel_id", "expected_revision", "intent_cid", "namespace_id", "observed_revision",
      "request", "run_definition", "version",
    ])
    is Ok(object) &&
    cancellation_journal_text(object, "version") ==
    Some("actql-native-client-cancellation-row/0.1") &&
    cancellation_journal_text(object, "namespace_id") is Some(namespace_id) &&
    cancellation_journal_text(object, "cancel_id") is Some(cancel_id) &&
    cancellation_journal_text(object, "request") is Some(request_wire) &&
    cancellation_journal_text(object, "run_definition") is Some(definition_wire) &&
    @decode.lookup(object, "expected_revision") is Some(expected) &&
    @decode.decimal_int64(expected) is Ok(expected) &&
    expected >= 0L &&
    expected <= 2147483647L &&
    @decode.lookup(object, "observed_revision") is Some(observed) &&
    @decode.decimal_int64(observed) is Ok(observed) &&
    observed >= 0L else {
    return Err(CustodyLost)
  }
  let request = match admit_client_request_identity_record_wire(request_wire) {
    Ok(value) => value
    _ => return Err(CustodyLost)
  }
  let definition = match
    @publication.admit_publication_contract(
      "run_definition", definition_wire, 65536, 4096, 64,
    ) {
    Ok(value) => value
    _ => return Err(CustodyLost)
  }
  let identity = match
    prepare_client_cancellation_identity(
      namespace_id,
      client_request_authority_scope_cid(request),
      cancel_id,
      definition,
      expected.to_int(),
    ) {
    Ok(value) => value
    _ => return Err(CustodyLost)
  }
  let action = match cancellation_journal_text(object, "action") {
    Some("accepted") => AcceptCancellation
    Some("already_requested") => AlreadyRequested
    Some("already_terminal") => AlreadyTerminal
    _ => return Err(CustodyLost)
  }
  let intent_cid = client_cancellation_intent_cid(identity)
  if cancellation_journal_text(object, "intent_cid") != Some(intent_cid) ||
    observed != expected + (if action == AcceptCancellation { 1L } else { 0L }) {
    return Err(CustodyLost)
  }
  let value = {
    namespace_id,
    cancel_id,
    expected_revision: expected.to_int(),
    request,
    definition,
    identity,
    action,
    observed_revision: observed,
  }
  guard encode_client_cancellation_journal_row(value, intent_cid) ==
    Some(row.body) else {
    return Err(CustodyLost)
  }
  Ok(value)
}

///|
// Workspace for the existing stored row, nested Request/Definition, its
// canonical equality, operation key and witness hashes. The caller keeps the
// physical row and any simultaneously decoded Run in separate backing.
fn client_cancellation_journal_scan_workspace(bytes : Int) -> Int64? {
  guard bytes > 0 && bytes <= 262144 &&
    @decode.preserving_json_admission_construction_inventory(bytes, 4096, 64)
    is Some(outer) &&
    client_run_decode_request_construction() is Some(request) &&
    client_run_decode_definition_construction() is Some(definition) &&
    @encode.text_writer_construction_inventory(131072, 32, 4) is Some(row) &&
    @encode.text_writer_construction_inventory(4096, 8, 1) is Some(identity) &&
    @encode.hash_writer_live_key_inventory(0, 0) is Some(digest) else {
    return None
  }
  // Four small writers cover scope, operation id, fingerprint and index.
  // The three fixed SHA workspaces cover fingerprint, index and row witness.
  // Co-count them with the outer cursor and two independently admitted values.
  let journal = client_run_decode_units(
    outer.record_headers + row.record_headers + 4L * identity.record_headers +
      3L * digest.record_headers + 48L,
    outer.reference_slots + row.reference_slots + 4L * identity.reference_slots +
      3L * digest.reference_slots + 72L,
    outer.scalar_words + row.scalar_words + 4L * identity.scalar_words +
      3L * digest.scalar_words + 64L,
    outer.owned_utf16_units + row.owned_utf16_units + 4L * identity.owned_utf16_units +
      3L * digest.owned_utf16_units + 3L * 71L,
    2L * 131072L + 2L * 4096L + 3L * digest.owned_wire_bytes,
  )
  @execution.compose_preparation_representation([journal, request, definition])
  .bind(@execution.preparation_representation_cost)
}
