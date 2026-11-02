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
  task_materials_cid : String?
  checkpoint : String?
}

///|
/// Preserve the existing Native row bytes and limits. Producing this body
/// proves neither a committed transaction nor permission to dispatch.
pub fn client_run_journal_row_body(
  record : ClientRunJournalEncoding,
  local_run_policy_originals? : String? = None,
  run_observation_originals? : String? = None,
) -> Result[Bytes, ClientJournalEncodingIssue] {
  let request = match client_request_identity_record_wire(record.request) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  client_run_journal_row_body_from_wires(
    record,
    request,
    @publication.publication_contract_json(record.definition),
    local_run_policy_originals~,
    run_observation_originals~,
  )
}

///|
// Closed internal codec route. Both callers already have the canonical wires
// of their typed request and Definition; this adds no public wire factory.
fn client_run_journal_row_body_from_wires(
  record : ClientRunJournalEncoding,
  request : String,
  definition : String,
  local_run_policy_originals? : String? = None,
  run_observation_originals? : String? = None,
) -> Result[Bytes, ClientJournalEncodingIssue] {
  if local_run_policy_originals is Some(wire) &&
    @utf8.encode(wire).length() > 8192 {
    return Err(CapacityExceeded)
  }
  if record.task_materials_cid is Some(cid) && !valid_client_request_cid(cid) {
    return Err(Encoding)
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
    if local_run_policy_originals is Some(original) {
      @encode.key(writer, "local_run_policy_originals")
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
    @encode.string_value(writer, definition)
    if run_observation_originals is Some(originals) {
      @encode.key(writer, "run_observation_originals")
      @encode.string_value(writer, originals)
    }
    if record.task_materials_cid is Some(cid) {
      @encode.key(writer, "task_materials_cid")
      @encode.string_value(writer, cid)
    }
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
  run_state_original? : String? = None,
  run_state_observation? : (Int64, String?)? = None,
  preparation_problem? : (String, String)? = None,
) -> Result[Bytes, ClientJournalEncodingIssue] {
  if preparation_problem is Some((code, classification)) {
    if run_admission is Some(_) ||
      run_state_original is Some(_) ||
      run_state_observation is Some(_) ||
      code.is_empty() ||
      @utf8.encode(code).length() > 256 ||
      ![
        "invalid_input", "requirements", "implementation_limit", "authorization",
        "operation_failed",
      ].contains(classification) {
      return Err(Encoding)
    }
    for character in code.iter() {
      if character.to_int() < 32 || character.to_int() == 127 {
        return Err(Encoding)
      }
    }
  }
  let wire = client_submitted_intent_wire(intent)
  // This physical profile is explicitly finite. Capacity does not classify
  // the caller's Program as invalid or provide permission to retry it.
  if @utf8.encode(wire).length() > 65536 {
    return Err(CapacityExceeded)
  }
  if run_state_original is Some(original) &&
    (run_admission is None || @utf8.encode(original).length() > 131072) {
    return Err(CapacityExceeded)
  }
  if run_state_observation is Some((revision, key)) {
    if run_admission is None || revision < 0L || revision > 9007199254740991L {
      return Err(Encoding)
    }
    match key {
      None if revision != 0L || run_state_original is Some(_) =>
        return Err(Encoding)
      Some(value) if value.is_empty() || run_state_original is None =>
        return Err(Encoding)
      _ => ()
    }
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
      } else if preparation_problem is Some(_) {
        "preparation_failed"
      } else {
        "preparing"
      },
    )
    if preparation_problem is Some((code, classification)) {
      @encode.key(writer, "preparation_problem_classification")
      @encode.string_value(writer, classification)
      @encode.key(writer, "preparation_problem_code")
      @encode.string_value(writer, code)
    }
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
    // Absence preserves legacy bytes. A present zero/NULL pair is issued only
    // with fresh acceptance by the physical Owner, never inferred on restore.
    if run_state_observation is Some((_, key)) {
      @encode.key(writer, "run_state_key")
      match key {
        Some(value) => @encode.string_value(writer, value)
        None => @encode.null_value(writer)
      }
    }
    if run_state_original is Some(original) {
      @encode.key(writer, "run_state_original")
      @encode.string_value(writer, original)
    }
    if run_state_observation is Some((revision, _)) {
      @encode.key(writer, "run_state_revision")
      @encode.decimal_number_value(writer, revision.to_string())
    }
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-native-client-submitted-intent-row/0.1")
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    @encode.OutputLimit => Err(CapacityExceeded)
    _ => Err(Encoding)
  }
}
