///|
/// Admitted durable body for one Site-owned dispatch record.
struct DurableDispatchRecord {
  request : DispatchRequest
  revision : Int
  execution_code : Int
  evidence_code : Int
  cleanup_code : Int
  material_available : Bool
  quarantined_capacity : Bool
  material_generation : String
  holding_evidence_cid : String
  execution_evidence_cid : String
  body : String
}

///|
priv suberror DurableRecordStop {
  DurableRecordStop
}

///|
fn[T] durable_decoded(
  value : Result[T, @decode.Issue],
) -> T raise DurableRecordStop {
  match value {
    Ok(result) => result
    Err(_) => raise DurableRecordStop
  }
}

///|
fn durable_text(
  object : @decode.ObjectView,
  key : String,
) -> String raise DurableRecordStop {
  durable_decoded(@decode.text(durable_decoded(@decode.required(object, key))))
}

///|
fn durable_int(
  object : @decode.ObjectView,
  key : String,
) -> Int raise DurableRecordStop {
  let value = durable_decoded(
    @decode.safe_integer(durable_decoded(@decode.required(object, key))),
  )
  if value < 0L || value > 2147483647L {
    raise DurableRecordStop
  }
  value.to_int()
}

///|
fn durable_bool(
  object : @decode.ObjectView,
  key : String,
) -> Bool raise DurableRecordStop {
  durable_decoded(
    @decode.boolean(durable_decoded(@decode.required(object, key))),
  )
}

///|
fn admit_dispatch_request_body(
  body : String,
) -> DispatchRequest raise DurableRecordStop {
  let bytes = @utf8.encode(body)
  let node = match
    @source.parse_json_bytes(bytes, {
      max_input_bytes: 65536,
      max_nodes: 32,
      max_depth: 2,
    }) {
    Ok(value) => value
    Err(_) => raise DurableRecordStop
  }
  let cursor = durable_decoded(
    @decode.admit(node, {
      max_nodes: 32,
      max_depth: 2,
      max_string_bytes: 65536,
      max_total_string_bytes: 65536,
    }),
  )
  let object = durable_decoded(
    @decode.closed_object(cursor, [
      "budget_cid", "connector_registration", "connector_revision", "coordinator_authority",
      "dispatch_id", "evidence_issuer_capability_cid", "grant_cid", "input_binding_cid",
      "obligations_cid", "run_definition_cid", "runtime_bundle_cid", "site_generation",
      "site_key", "strategy_revision", "task_attempt", "task_key", "version",
    ]),
  )
  if durable_text(object, "version") != "actql-remote-dispatch-request/0.1" {
    raise DurableRecordStop
  }
  let request = match
    prepare_dispatch_request(
      durable_text(object, "coordinator_authority"),
      durable_text(object, "run_definition_cid"),
      durable_text(object, "task_key"),
      durable_int(object, "task_attempt"),
      durable_text(object, "dispatch_id"),
      durable_text(object, "site_key"),
      durable_int(object, "site_generation"),
      durable_text(object, "runtime_bundle_cid"),
      durable_text(object, "connector_registration"),
      durable_text(object, "connector_revision"),
      durable_text(object, "strategy_revision"),
      durable_text(object, "input_binding_cid"),
      durable_text(object, "obligations_cid"),
      durable_text(object, "budget_cid"),
      durable_text(object, "evidence_issuer_capability_cid"),
      durable_text(object, "grant_cid"),
    ) {
    Ok(value) => value
    Err(_) => raise DurableRecordStop
  }
  if dispatch_request_json(request) != Ok(body) {
    raise DurableRecordStop
  }
  request
}

///|
/// Re-admits one canonical dispatch request body and its claimed identity.
/// Transport adapters must not reconstruct the request field by field.
pub fn admit_dispatch_request_json(
  body : String,
  claimed_cid : String,
) -> Result[DispatchRequest, DispatchIssue] {
  try {
    let request = admit_dispatch_request_body(body)
    if request.dispatch_request_cid != claimed_cid {
      return Err(DispatchIdentityMismatch)
    }
    Ok(request)
  } catch {
    DurableRecordStop => Err(InvalidDispatch)
  }
}

///|
fn emit_durable_dispatch_record(
  request : DispatchRequest,
  revision : Int,
  execution_code : Int,
  evidence_code : Int,
  cleanup_code : Int,
  material_available : Bool,
  quarantined_capacity : Bool,
  material_generation : String,
  holding_evidence_cid : String,
  execution_evidence_cid : String,
) -> Result[String, DispatchIssue] {
  if revision < 0 {
    return Err(InvalidJournal)
  }
  let request_json = match dispatch_request_json(request) {
    Ok(value) => value
    Err(_) => return Err(InvalidJournal)
  }
  let writer = @encode.writer(262144, 32, 2) catch {
    _ => return Err(InvalidJournal)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "cleanup_state")
    @encode.number_value(writer, cleanup_code.to_double())
    @encode.key(writer, "dispatch_request_cid")
    @encode.string_value(writer, request.dispatch_request_cid)
    @encode.key(writer, "evidence_state")
    @encode.number_value(writer, evidence_code.to_double())
    @encode.key(writer, "execution_evidence_cid")
    @encode.string_value(writer, execution_evidence_cid)
    @encode.key(writer, "execution_state")
    @encode.number_value(writer, execution_code.to_double())
    @encode.key(writer, "holding_evidence_cid")
    @encode.string_value(writer, holding_evidence_cid)
    @encode.key(writer, "material_available")
    @encode.bool_value(writer, material_available)
    @encode.key(writer, "material_generation")
    @encode.string_value(writer, material_generation)
    @encode.key(writer, "quarantined_capacity")
    @encode.bool_value(writer, quarantined_capacity)
    @encode.key(writer, "request_json")
    @encode.string_value(writer, request_json)
    @encode.key(writer, "revision")
    @encode.number_value(writer, revision.to_double())
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-dispatch-record/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidJournal)
  }
  Ok(@encode.finish(writer) catch { _ => return Err(InvalidJournal) })
}

///|
pub fn dispatch_record_durable_json(
  record : DispatchRecord,
) -> Result[String, DispatchIssue] {
  let state = dispatch_record_state_codes(record)
  let evidence = evidence_state_fields(record.evidence)
  emit_durable_dispatch_record(
    record.request,
    record.revision,
    state[0],
    state[1],
    state[2],
    record.material_available,
    record.quarantined_capacity,
    evidence[0],
    evidence[1],
    evidence[2],
  )
}

///|
/// Initial durable body installed before an admitted dispatch may start.
pub fn dispatch_admission_durable_json(
  admission : DispatchAdmission,
) -> Result[String, DispatchIssue] {
  emit_durable_dispatch_record(
    admission.request,
    0,
    0,
    0,
    0,
    false,
    false,
    "",
    "",
    "",
  )
}

///|
/// Desired durable body for one already prepared CAS transition.
pub fn dispatch_transition_durable_json(
  transition : DispatchTransition,
) -> Result[String, DispatchIssue] {
  let evidence = evidence_state_fields(transition.next_evidence)
  emit_durable_dispatch_record(
    transition.record.request,
    transition.expected_revision + 1,
    execution_state_code(transition.next_execution),
    evidence_state_code(transition.next_evidence),
    cleanup_state_code(transition.next_cleanup),
    transition.next_material_available,
    transition.next_quarantined_capacity,
    evidence[0],
    evidence[1],
    evidence[2],
  )
}

///|
pub fn dispatch_transition_expected_revision(
  transition : DispatchTransition,
) -> Int {
  transition.expected_revision
}

///|
pub fn dispatch_transition_request_identity(
  transition : DispatchTransition,
) -> String {
  transition.record.request.dispatch_request_cid
}

///|
pub fn dispatch_transition_attempt_identity(
  transition : DispatchTransition,
) -> Result[String, DispatchIssue] {
  dispatch_request_attempt_identity(transition.record.request)
}

///|
pub fn admit_durable_dispatch_record(
  bytes : Bytes,
) -> Result[DurableDispatchRecord, DispatchIssue] {
  try {
    let node = match
      @source.parse_json_bytes(bytes, {
        max_input_bytes: 262144,
        max_nodes: 32,
        max_depth: 2,
      }) {
      Ok(value) => value
      Err(_) => raise DurableRecordStop
    }
    let cursor = durable_decoded(
      @decode.admit(node, {
        max_nodes: 32,
        max_depth: 2,
        max_string_bytes: 65536,
        max_total_string_bytes: 131072,
      }),
    )
    let object = durable_decoded(
      @decode.closed_object(cursor, [
        "cleanup_state", "dispatch_request_cid", "evidence_state", "execution_evidence_cid",
        "execution_state", "holding_evidence_cid", "material_available", "material_generation",
        "quarantined_capacity", "request_json", "revision", "version",
      ]),
    )
    if durable_text(object, "version") != "actql-remote-dispatch-record/0.1" {
      raise DurableRecordStop
    }
    let request = admit_dispatch_request_body(
      durable_text(object, "request_json"),
    )
    if durable_text(object, "dispatch_request_cid") !=
      request.dispatch_request_cid {
      raise DurableRecordStop
    }
    let revision = durable_int(object, "revision")
    let execution_code = durable_int(object, "execution_state")
    let evidence_code = durable_int(object, "evidence_state")
    let cleanup_code = durable_int(object, "cleanup_state")
    let material_available = durable_bool(object, "material_available")
    let quarantined_capacity = durable_bool(object, "quarantined_capacity")
    let material_generation = durable_text(object, "material_generation")
    let holding_evidence_cid = durable_text(object, "holding_evidence_cid")
    let execution_evidence_cid = durable_text(object, "execution_evidence_cid")
    let body = @utf8.decode(bytes) catch { _ => raise DurableRecordStop }
    let canonical = match
      emit_durable_dispatch_record(
        request, revision, execution_code, evidence_code, cleanup_code, material_available,
        quarantined_capacity, material_generation, holding_evidence_cid, execution_evidence_cid,
      ) {
      Ok(value) => value
      Err(_) => raise DurableRecordStop
    }
    if canonical != body {
      raise DurableRecordStop
    }
    let check : DispatchRecord = {
      request,
      revision: 0,
      execution: Accepted,
      evidence: NoEvidence,
      cleanup: CleanupActive,
      material_available: false,
      quarantined_capacity: false,
    }
    if restore_dispatch_record(
        check, revision, execution_code, evidence_code, cleanup_code, material_available,
        quarantined_capacity, material_generation, holding_evidence_cid, execution_evidence_cid,
      )
      is Err(_) {
      raise DurableRecordStop
    }
    Ok({
      request,
      revision,
      execution_code,
      evidence_code,
      cleanup_code,
      material_available,
      quarantined_capacity,
      material_generation,
      holding_evidence_cid,
      execution_evidence_cid,
      body,
    })
  } catch {
    DurableRecordStop => Err(InvalidJournal)
  }
}

///|
pub fn restore_durable_dispatch_record(
  journal : SiteDispatchJournal,
  durable : DurableDispatchRecord,
) -> Result[DispatchRecord, DispatchIssue] {
  let record = match restore_historical_dispatch(journal, durable.request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if dispatch_record_durable_json(record) == Ok(durable.body) {
    return Ok(record)
  }
  match
    restore_dispatch_record(
      record,
      durable.revision,
      durable.execution_code,
      durable.evidence_code,
      durable.cleanup_code,
      durable.material_available,
      durable.quarantined_capacity,
      durable.material_generation,
      durable.holding_evidence_cid,
      durable.execution_evidence_cid,
    ) {
    Ok(_) =>
      if dispatch_record_durable_json(record) == Ok(durable.body) {
        Ok(record)
      } else {
        Err(InvalidJournal)
      }
    Err(_) => Err(StateCollision)
  }
}

///|
pub fn durable_dispatch_record_journal_key(
  durable : DurableDispatchRecord,
) -> Array[String] {
  dispatch_request_journal_key(durable.request)
}

///|
pub fn durable_dispatch_record_revision(durable : DurableDispatchRecord) -> Int {
  durable.revision
}

///|
pub fn durable_dispatch_record_json(durable : DurableDispatchRecord) -> String {
  durable.body
}

///|
pub fn durable_dispatch_record_request_identity(
  durable : DurableDispatchRecord,
) -> String {
  durable.request.dispatch_request_cid
}

///|
pub fn durable_dispatch_record_attempt_identity(
  durable : DurableDispatchRecord,
) -> Result[String, DispatchIssue] {
  dispatch_request_attempt_identity(durable.request)
}

///|
/// True when the durable record says execution was cancelled.
pub fn durable_dispatch_record_execution_cancelled(
  record : DurableDispatchRecord,
) -> Bool {
  record.execution_code == 5
}
