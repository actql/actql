///|
pub(all) enum ClientJournalEncodingIssue {
  Encoding
  CapacityExceeded
} derive(Eq, Debug)

///|
/// Serialization fields of the existing physical journal row, not admission,
/// authorization or execution state. Checkpoint and private originals remain
/// the original Owner-produced bytes; their validators run at readmission.
pub(all) struct ClientRunJournalEncoding {
  request : ClientRequestIdentity
  definition : @publication.PublicationContract
  dispatch_reserved : Bool
  physical_start_claimed : Bool
  cancellation_requested : Bool
  publication_binding : String?
  publication_policy_originals : String?
  effect_material_originals : String?
  checkpoint : String?
}

///|
/// Preserve the existing Native row bytes and limits. Producing this body
/// proves neither a committed transaction nor permission to dispatch.
pub fn client_run_journal_row_body(
  record : ClientRunJournalEncoding,
) -> Result[Bytes, ClientJournalEncodingIssue] {
  let request = match client_request_identity_record_wire(record.request) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  try {
    let writer = @encode.writer(131072, 32, 4)
    @encode.begin_object(writer)
    @encode.key(writer, "cancellation_requested")
    @encode.bool_value(writer, record.cancellation_requested)
    @encode.key(writer, "checkpoint")
    match record.checkpoint {
      Some(value) => @encode.string_value(writer, value)
      None => @encode.null_value(writer)
    }
    @encode.key(writer, "dispatch_reserved")
    @encode.bool_value(writer, record.dispatch_reserved)
    // Optional private originals preserve absent-field bytes for older rows.
    if record.effect_material_originals is Some(original) {
      @encode.key(writer, "effect_material_originals")
      @encode.string_value(writer, original)
    }
    @encode.key(writer, "physical_start_claimed")
    @encode.bool_value(writer, record.physical_start_claimed)
    @encode.key(writer, "publication_binding")
    match record.publication_binding {
      Some(value) => @encode.string_value(writer, value)
      None => @encode.null_value(writer)
    }
    // Omit absent originals: old retained rows keep their exact original bytes.
    if record.publication_policy_originals is Some(originals) {
      @encode.key(writer, "publication_policy_originals")
      @encode.string_value(writer, originals)
    }
    @encode.key(writer, "request")
    @encode.string_value(writer, request)
    @encode.key(writer, "run_definition")
    @encode.string_value(
      writer,
      @publication.publication_contract_json(record.definition),
    )
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-native-client-run-row/0.1")
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    @encode.OutputLimit => Err(CapacityExceeded)
    _ => Err(Encoding)
  }
}

///|
/// Exact existing submitted-intent row encoding. The reference is the original
/// epoch Owner's wire; this writer does not admit it or claim durable custody.
pub fn client_submitted_intent_journal_row_body(
  reference_wire : String,
  intent : ClientSubmittedIntent,
  run_admission? : (ClientRequestIdentity, String, Int64)? = None,
) -> Result[Bytes, ClientJournalEncodingIssue] {
  let wire = client_submitted_intent_wire(intent)
  // This physical profile is explicitly finite. Capacity does not classify
  // the caller's Program as invalid or provide permission to retry it.
  if @utf8.encode(wire).length() > 65536 {
    return Err(CapacityExceeded)
  }
  try {
    let writer = @encode.writer(262144, 16, 2)
    @encode.begin_object(writer)
    @encode.key(writer, "intent")
    @encode.string_value(writer, wire)
    @encode.key(writer, "phase")
    @encode.string_value(
      writer,
      if run_admission is Some(_) {
        "ready"
      } else {
        "preparing"
      },
    )
    @encode.key(writer, "reference")
    @encode.string_value(writer, reference_wire)
    if run_admission is Some((request, definition_cid, revision)) {
      let wire = match
        client_submitted_run_admission_wire(request, definition_cid, revision) {
        Ok(value) => value
        Err(_) => return Err(Encoding)
      }
      @encode.key(writer, "run_admission")
      @encode.string_value(writer, wire)
    }
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-native-client-submitted-intent-row/0.1")
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    _ => Err(Encoding)
  }
}
