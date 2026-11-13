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
  before_construction? : ((Int, Int, Int) -> Result[Unit, ClientJournalEncodingIssue])? = None,
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
    before_construction~,
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
  comparison_bytes? : Int? = None,
  before_construction? : ((Int, Int, Int) -> Result[Unit, ClientJournalEncodingIssue])? = None,
) -> Result[Bytes, ClientJournalEncodingIssue] {
  if local_run_policy_originals is Some(wire) &&
    @utf8.encode(wire).length() > 8192 {
    return Err(CapacityExceeded)
  }
  if record.task_materials_cid is Some(cid) && !valid_client_request_cid(cid) {
    return Err(Encoding)
  }
  // Derive constructor geometry from immutable originals; this is not a new
  // allowance. Only the observation field may exceed the legacy row profile.
  let fixed = "{\"cancellation_requested\":false,\"checkpoint\":null,\"dispatch_reserved\":false,\"effect_material_originals\":\"\",\"local_run_policy_originals\":\"\",\"physical_start_claimed\":false,\"publication_binding\":null,\"publication_policy_originals\":\"\",\"request\":\"\",\"run_definition\":\"\",\"run_observation_originals\":\"\",\"task_materials_cid\":\"\",\"version\":\"actql-native-client-run-row/0.1\"}".length().to_int64()
  let other_units = request.length().to_int64() + definition.length().to_int64() +
    record.checkpoint.map(value => value.length().to_int64()).unwrap_or(0L) +
    record.publication_binding.map(value => value.length().to_int64()).unwrap_or(0L) +
    record.publication_policy_originals.map(value => value.length().to_int64()).unwrap_or(0L) +
    record.effect_material_originals.map(value => value.length().to_int64()).unwrap_or(0L) +
    record.task_materials_cid.map(value => value.length().to_int64()).unwrap_or(0L) +
    local_run_policy_originals.map(value => value.length().to_int64()).unwrap_or(0L)
  let observation_units = run_observation_originals.map(value => value.length().to_int64()).unwrap_or(0L)
  let (maximum, construction_base) = match before_construction {
    None => (131072, 0L)
    Some(_) => {
      guard @execution.checked_preparation_add_product(fixed, other_units, 6L) is Some(base) &&
        @execution.checked_preparation_add_product(base, observation_units, 6L) is Some(bound) &&
        bound > 0L && bound < 2147483519L else { return Err(CapacityExceeded) }
      (bound.to_int(), base)
    }
  }
  // A canonical comparison cannot construct beyond the already funded original
  // body, including rejected noncanonical candidates. Ordinary writers retain
  // their independently observed construction bound.
  let maximum = match comparison_bytes {
    Some(bytes) if bytes > 0 => Int::min(maximum, bytes)
    Some(_) => return Err(CapacityExceeded)
    None => maximum
  }
  try {
    let batch_units = 65L * 256L
    if before_construction is Some(reserve) {
      let initial = @execution.checked_preparation_add_product(
        construction_base, Int64::min(observation_units, batch_units), 6L,
      ).unwrap()
      match reserve(Int64::min(initial, maximum.to_int64()).to_int(), 32, 4) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
    }
    let writer = @encode.writer(maximum, 32, 4)
    let mut observed_field_bytes = 0
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
      let (before_field, _, _) = @encode.writer_progress(writer)
      @encode.key(writer, "run_observation_originals")
      match before_construction {
        None => @encode.string_value(writer, originals)
        Some(reserve) => {
          let cursor = @encode.start_string_value(writer, originals)
          let mut done = false
          while !done {
            for _ in 0..<256 {
              if @encode.advance_string_value(cursor) {
                done = true
                break
              }
            }
            if !done {
              let (emitted, _, _) = @encode.writer_progress(writer)
              guard @execution.checked_preparation_add_product(
                construction_base + emitted.to_int64(), batch_units, 6L,
              ) is Some(next) else { return Err(CapacityExceeded) }
              match reserve(Int64::min(next, maximum.to_int64()).to_int(), 32, 4) {
                Err(issue) => return Err(issue)
                Ok(_) => ()
              }
            }
          }
        }
      }
      let (after_field, _, _) = @encode.writer_progress(writer)
      observed_field_bytes = after_field - before_field
    }
    if record.task_materials_cid is Some(cid) {
      @encode.key(writer, "task_materials_cid")
      @encode.string_value(writer, cid)
    }
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-native-client-run-row/0.1")
    @encode.end_object(writer)
    let (emitted, _, _) = @encode.writer_progress(writer)
    // The observed route enlarges only the private observation field, never
    // the combined legacy fields or their independent semantic limits.
    if emitted - observed_field_bytes > 131072 { return Err(CapacityExceeded) }
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
  before_construction? : ((Int, Int, Int) -> Result[
    Unit,
    ClientJournalEncodingIssue,
  ])? = None,
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
  if before_construction is None && intent.wire_bytes > 65536 {
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
  // This original admission wire is bounded by its existing identity Owner.
  // Construct it once and retain it through the outer row writer.
  let admission_wire = run_admission.map(value => {
    client_submitted_run_admission_wire(value.0, value.1, value.2).map_err(_ => {
      ClientJournalEncodingIssue::Encoding
    })
  })
  let (maximum, construction_base) = match before_construction {
    None => (262144, 0L)
    Some(_) => {
      // Complete fixed keys/punctuation/version, longest phase and null-key
      // spelling. Variable immutable Strings escape by at most six UTF8 bytes
      // per UTF16 unit. This is observed constructor geometry, not a quota.
      let fixed = "{\"intent\":\"\",\"phase\":\"preparation_failed\",\"preparation_problem_classification\":\"\",\"preparation_problem_code\":\"\",\"reference\":\"\",\"run_admission\":\"\",\"run_state_key\":null,\"run_state_original\":\"\",\"run_state_revision\":9007199254740991,\"version\":\"actql-native-client-submitted-intent-row/0.1\"}"
        .length()
        .to_int64()
      let other_units = reference_wire.length().to_int64() +
        admission_wire
        .map(value => value.map(wire => wire.length().to_int64()).unwrap_or(0L))
        .unwrap_or(0L) +
        run_state_original.map(value => value.length().to_int64()).unwrap_or(0L) +
        run_state_observation
        .map(value => value.1.map(key => key.length().to_int64()).unwrap_or(0L))
        .unwrap_or(0L) +
        preparation_problem
        .map(value => value.0.length().to_int64() + value.1.length().to_int64())
        .unwrap_or(0L)
      guard @execution.checked_preparation_add_product(fixed, other_units, 6L)
        is Some(base) &&
        @execution.checked_preparation_add_product(
          base,
          wire.length().to_int64(),
          6L,
        )
        is Some(bound) &&
        bound > 0L &&
        bound < 2147483519L else {
        return Err(CapacityExceeded)
      }
      (bound.to_int(), base)
    }
  }
  try {
    // One real emission, not a size-only serialization followed by another
    // full traversal. The existing cursor emits at most 65 UTF16 units per
    // advance (including a crossing surrogate pair). Reserve a finite batch
    // before its constructor/growth, using actual prior writer progress.
    let batch_units = 65L * 256L
    if before_construction is Some(reserve) {
      let initial = @execution.checked_preparation_add_product(
        construction_base,
        Int64::min(wire.length().to_int64(), batch_units),
        6L,
      ).unwrap()
      match reserve(initial.to_int(), 16, 2) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
    }
    let writer = @encode.writer(maximum, 16, 2)
    @encode.begin_object(writer)
    @encode.key(writer, "intent")
    match before_construction {
      None => @encode.string_value(writer, wire)
      Some(reserve) => {
        let cursor = @encode.start_string_value(writer, wire)
        let mut done = false
        while !done {
          for _ in 0..<256 {
            if @encode.advance_string_value(cursor) {
              done = true
              break
            }
          }
          if !done {
            let (emitted, _, _) = @encode.writer_progress(writer)
            guard @execution.checked_preparation_add_product(
                construction_base + emitted.to_int64(),
                batch_units,
                6L,
              )
              is Some(next) else {
              return Err(CapacityExceeded)
            }
            match
              reserve(Int64::min(next, maximum.to_int64()).to_int(), 16, 2) {
              Err(issue) => return Err(issue)
              Ok(_) => ()
            }
          }
        }
      }
    }
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
    if admission_wire is Some(original) {
      // Keep the old writer-first refusal precedence for explicit finite
      // callers: an invalid admission does not mask earlier output overflow.
      let wire = match original {
        Ok(wire) => wire
        Err(issue) => return Err(issue)
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
