///|
/// Admitted durable body for one Coordinator-owned dispatch intent.
struct DurableCoordinatorDispatchRecord {
  request : DispatchRequest
  revision : Int
  progress_code : Int
  site_revision : Int
  site_execution : Int
  site_evidence : Int
  site_cleanup : Int
  site_material_available : Bool
  site_quarantined_capacity : Bool
  accepted_evidence_cid : String
  accepted_evidence_json : String
  accepted_subject_cid : String
  accepted_subject_json : String
  accepted_measurement_cid : String
  accepted_measurement_json : String
  evidence : RemoteExecutionEvidence?
  subject : RemoteManagedOutputSubject?
  measurement : RemoteManagedOutputMeasurement?
  body : String
}

///|
fn emit_durable_coordinator_record(
  request : DispatchRequest,
  revision : Int,
  progress_code : Int,
  site_revision : Int,
  site_execution : Int,
  site_evidence : Int,
  site_cleanup : Int,
  site_material_available : Bool,
  site_quarantined_capacity : Bool,
  accepted_evidence_cid : String,
  accepted_evidence_json : String,
  accepted_subject_cid : String,
  accepted_subject_json : String,
  accepted_measurement_cid : String,
  accepted_measurement_json : String,
) -> Result[String, DispatchIssue] {
  if revision < 0 {
    return Err(InvalidJournal)
  }
  let request_json = match dispatch_request_json(request) {
    Ok(value) => value
    Err(_) => return Err(InvalidJournal)
  }
  let writer = @encode.writer(1048576, 64, 2) catch {
    _ => return Err(InvalidJournal)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "accepted_evidence_cid")
    @encode.string_value(writer, accepted_evidence_cid)
    @encode.key(writer, "accepted_evidence_json")
    @encode.string_value(writer, accepted_evidence_json)
    @encode.key(writer, "accepted_measurement_cid")
    @encode.string_value(writer, accepted_measurement_cid)
    @encode.key(writer, "accepted_measurement_json")
    @encode.string_value(writer, accepted_measurement_json)
    @encode.key(writer, "accepted_subject_cid")
    @encode.string_value(writer, accepted_subject_cid)
    @encode.key(writer, "accepted_subject_json")
    @encode.string_value(writer, accepted_subject_json)
    @encode.key(writer, "dispatch_request_cid")
    @encode.string_value(writer, request.dispatch_request_cid)
    @encode.key(writer, "progress_state")
    @encode.number_value(writer, progress_code.to_double())
    @encode.key(writer, "request_json")
    @encode.string_value(writer, request_json)
    @encode.key(writer, "revision")
    @encode.number_value(writer, revision.to_double())
    @encode.key(writer, "site_cleanup")
    @encode.number_value(writer, site_cleanup.to_double())
    @encode.key(writer, "site_evidence")
    @encode.number_value(writer, site_evidence.to_double())
    @encode.key(writer, "site_execution")
    @encode.number_value(writer, site_execution.to_double())
    @encode.key(writer, "site_material_available")
    @encode.bool_value(writer, site_material_available)
    @encode.key(writer, "site_quarantined_capacity")
    @encode.bool_value(writer, site_quarantined_capacity)
    @encode.key(writer, "site_revision")
    @encode.number_value(writer, site_revision.to_double())
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-coordinator-record/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidJournal)
  }
  Ok(@encode.finish(writer) catch { _ => return Err(InvalidJournal) })
}

///|
pub fn coordinator_dispatch_admission_durable_json(
  admission : CoordinatorDispatchIntentAdmission,
) -> Result[String, DispatchIssue] {
  emit_durable_coordinator_record(
    admission.request,
    0,
    0,
    -1,
    -1,
    -1,
    -1,
    false,
    false,
    "",
    "",
    "",
    "",
    "",
    "",
  )
}

///|
fn durable_coordinator_projection(
  durable : DurableCoordinatorDispatchRecord,
) -> Array[String] {
  [
    durable.revision.to_string(),
    durable.progress_code.to_string(),
    durable.site_revision.to_string(),
    durable.site_execution.to_string(),
    durable.site_evidence.to_string(),
    durable.site_cleanup.to_string(),
    bool_code(durable.site_material_available),
    bool_code(durable.site_quarantined_capacity),
    durable.accepted_evidence_cid,
    durable.accepted_subject_cid,
    durable.accepted_measurement_cid,
  ]
}

///|
fn transition_evidence_body(
  current_cid : String,
  current_body : String,
  next_cid : String,
  supplied : RemoteExecutionEvidence?,
  request : DispatchRequest,
) -> Result[(String, String, RemoteExecutionEvidence?), DispatchIssue] {
  match supplied {
    Some(value) => {
      let cid = remote_execution_evidence_cid(value)
      let body = match remote_execution_evidence_json(value) {
        Ok(text) => text
        Err(issue) => return Err(issue)
      }
      if cid != next_cid ||
        !remote_execution_evidence_matches_dispatch(value, request) ||
        (
          !current_cid.is_empty() &&
          (cid != current_cid || body != current_body)
        ) {
        return Err(StateCollision)
      }
      Ok((cid, body, Some(value)))
    }
    None =>
      if next_cid != current_cid {
        Err(InvalidJournal)
      } else {
        Ok((current_cid, current_body, None))
      }
  }
}

///|
fn transition_subject_body(
  current_cid : String,
  current_body : String,
  next_cid : String,
  supplied : RemoteManagedOutputSubject?,
  evidence : RemoteExecutionEvidence?,
  request : DispatchRequest,
) -> Result[(String, String, RemoteManagedOutputSubject?), DispatchIssue] {
  match supplied {
    Some(value) => {
      let admitted_evidence = match evidence {
        Some(item) => item
        None => return Err(InvalidJournal)
      }
      let cid = remote_managed_output_subject_cid(value)
      let body = match remote_managed_output_subject_json(value) {
        Ok(text) => text
        Err(issue) => return Err(issue)
      }
      if cid != next_cid ||
        !remote_managed_output_subject_matches_evidence(
          value, admitted_evidence, request,
        ) ||
        (
          !current_cid.is_empty() &&
          (cid != current_cid || body != current_body)
        ) {
        return Err(StateCollision)
      }
      Ok((cid, body, Some(value)))
    }
    None =>
      if next_cid != current_cid {
        Err(InvalidJournal)
      } else {
        Ok((current_cid, current_body, None))
      }
  }
}

///|
fn transition_measurement_body(
  current_cid : String,
  current_body : String,
  next_cid : String,
  supplied : RemoteManagedOutputMeasurement?,
  subject : RemoteManagedOutputSubject?,
) -> Result[(String, String, RemoteManagedOutputMeasurement?), DispatchIssue] {
  match supplied {
    Some(value) => {
      let admitted_subject = match subject {
        Some(item) => item
        None => return Err(InvalidJournal)
      }
      let cid = remote_managed_output_measurement_cid(value)
      let body = match remote_managed_output_measurement_json(value) {
        Ok(text) => text
        Err(issue) => return Err(issue)
      }
      if cid != next_cid ||
        !remote_managed_output_subject_matches_measurement(
          admitted_subject, value,
        ) ||
        (
          !current_cid.is_empty() &&
          (cid != current_cid || body != current_body)
        ) {
        return Err(StateCollision)
      }
      Ok((cid, body, Some(value)))
    }
    None =>
      if next_cid != current_cid {
        Err(InvalidJournal)
      } else {
        Ok((current_cid, current_body, None))
      }
  }
}

///|
/// Produces the exact next durable Coordinator body. Newly accepted evidence
/// must be supplied as typed values; CID strings alone cannot create evidence.
pub fn coordinator_dispatch_transition_durable_json(
  current : DurableCoordinatorDispatchRecord,
  transition : CoordinatorDispatchTransition,
  evidence? : RemoteExecutionEvidence? = None,
  subject? : RemoteManagedOutputSubject? = None,
  measurement? : RemoteManagedOutputMeasurement? = None,
) -> Result[String, DispatchIssue] {
  if current.request.dispatch_request_cid !=
    transition.record.request.dispatch_request_cid ||
    durable_coordinator_projection(current) != transition.expected ||
    coordinator_record_projection(transition.record) != transition.expected {
    return Err(StateCollision)
  }
  let next_evidence = match
    transition_evidence_body(
      current.accepted_evidence_cid,
      current.accepted_evidence_json,
      transition.next_accepted_evidence_cid,
      evidence,
      current.request,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let effective_evidence = match next_evidence.2 {
    Some(value) => Some(value)
    None => current.evidence
  }
  let next_subject = match
    transition_subject_body(
      current.accepted_subject_cid,
      current.accepted_subject_json,
      transition.next_accepted_subject_cid,
      subject,
      effective_evidence,
      current.request,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let effective_subject = match next_subject.2 {
    Some(value) => Some(value)
    None => current.subject
  }
  let next_measurement = match
    transition_measurement_body(
      current.accepted_measurement_cid,
      current.accepted_measurement_json,
      transition.next_accepted_measurement_cid,
      measurement,
      effective_subject,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  emit_durable_coordinator_record(
    current.request,
    current.revision + 1,
    coordinator_progress_code(transition.next_progress),
    transition.next_site_revision,
    transition.next_site_execution,
    transition.next_site_evidence,
    transition.next_site_cleanup,
    transition.next_site_material_available,
    transition.next_site_quarantined_capacity,
    next_evidence.0,
    next_evidence.1,
    next_subject.0,
    next_subject.1,
    next_measurement.0,
    next_measurement.1,
  )
}

///|
pub fn coordinator_dispatch_transition_expected_revision(
  transition : CoordinatorDispatchTransition,
) -> Int {
  transition.record.revision
}

///|
pub fn coordinator_dispatch_transition_attempt_identity(
  transition : CoordinatorDispatchTransition,
) -> Result[String, DispatchIssue] {
  dispatch_request_attempt_identity(transition.record.request)
}

///|
fn coordinator_signed_int(
  object : @decode.ObjectView,
  name : String,
) -> Int raise EvidenceJsonStop {
  let value = evidence_decoded(
    @decode.safe_integer(evidence_decoded(@decode.required(object, name))),
  )
  if value < -1L || value > 2147483647L {
    raise EvidenceJsonStop
  }
  value.to_int()
}

///|
fn coordinator_bool(
  object : @decode.ObjectView,
  name : String,
) -> Bool raise EvidenceJsonStop {
  evidence_decoded(
    @decode.boolean(evidence_decoded(@decode.required(object, name))),
  )
}

///|
pub fn admit_durable_coordinator_dispatch_record(
  bytes : Bytes,
) -> Result[DurableCoordinatorDispatchRecord, DispatchIssue] {
  try {
    let body = @utf8.decode(bytes) catch { _ => raise EvidenceJsonStop }
    let object = evidence_object(evidence_root(body, 1048576, 64, 2), [
      "accepted_evidence_cid", "accepted_evidence_json", "accepted_measurement_cid",
      "accepted_measurement_json", "accepted_subject_cid", "accepted_subject_json",
      "dispatch_request_cid", "progress_state", "request_json", "revision", "site_cleanup",
      "site_evidence", "site_execution", "site_material_available", "site_quarantined_capacity",
      "site_revision", "version",
    ])
    if evidence_text(object, "version") != "actql-remote-coordinator-record/0.1" {
      raise EvidenceJsonStop
    }
    let request = admit_dispatch_request_body(
      evidence_text(object, "request_json"),
    ) catch {
      _ => raise EvidenceJsonStop
    }
    if evidence_text(object, "dispatch_request_cid") !=
      request.dispatch_request_cid {
      raise EvidenceJsonStop
    }
    let accepted_evidence_cid = evidence_text(object, "accepted_evidence_cid")
    let accepted_evidence_json = evidence_text(object, "accepted_evidence_json")
    let evidence = if accepted_evidence_cid.is_empty() {
      if !accepted_evidence_json.is_empty() {
        raise EvidenceJsonStop
      }
      None
    } else {
      Some(
        match
          admit_remote_execution_evidence_json(
            accepted_evidence_json, accepted_evidence_cid, request,
          ) {
          Ok(value) => value
          Err(_) => raise EvidenceJsonStop
        },
      )
    }
    let accepted_subject_cid = evidence_text(object, "accepted_subject_cid")
    let accepted_subject_json = evidence_text(object, "accepted_subject_json")
    let subject = if accepted_subject_cid.is_empty() {
      if !accepted_subject_json.is_empty() {
        raise EvidenceJsonStop
      }
      None
    } else {
      let value = match
        admit_remote_managed_output_subject_json(
          accepted_subject_json, accepted_subject_cid, request,
        ) {
        Ok(item) => item
        Err(_) => raise EvidenceJsonStop
      }
      guard evidence is Some(admitted_evidence) &&
        remote_managed_output_subject_matches_evidence(
          value, admitted_evidence, request,
        ) else {
        raise EvidenceJsonStop
      }
      Some(value)
    }
    let accepted_measurement_cid = evidence_text(
      object, "accepted_measurement_cid",
    )
    let accepted_measurement_json = evidence_text(
      object, "accepted_measurement_json",
    )
    let measurement = if accepted_measurement_cid.is_empty() {
      if !accepted_measurement_json.is_empty() {
        raise EvidenceJsonStop
      }
      None
    } else {
      let value = match
        admit_remote_managed_output_measurement_json(
          accepted_measurement_json, accepted_measurement_cid,
        ) {
        Ok(item) => item
        Err(_) => raise EvidenceJsonStop
      }
      guard subject is Some(admitted_subject) &&
        remote_managed_output_subject_matches_measurement(
          admitted_subject, value,
        ) else {
        raise EvidenceJsonStop
      }
      Some(value)
    }
    let revision = evidence_int(object, "revision")
    let progress_code = evidence_int(object, "progress_state")
    let site_revision = coordinator_signed_int(object, "site_revision")
    let site_execution = coordinator_signed_int(object, "site_execution")
    let site_evidence = coordinator_signed_int(object, "site_evidence")
    let site_cleanup = coordinator_signed_int(object, "site_cleanup")
    let site_material_available = coordinator_bool(
      object, "site_material_available",
    )
    let site_quarantined_capacity = coordinator_bool(
      object, "site_quarantined_capacity",
    )
    let journal = match
      create_coordinator_dispatch_journal(request.coordinator_authority) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    let record = match restore_coordinator_dispatch_intent(journal, request) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    if restore_coordinator_dispatch_record(
        record, revision, progress_code, site_revision, site_execution, site_evidence,
        site_cleanup, site_material_available, site_quarantined_capacity, accepted_evidence_cid,
        accepted_subject_cid, accepted_measurement_cid,
      )
      is Err(_) {
      raise EvidenceJsonStop
    }
    let canonical = match
      emit_durable_coordinator_record(
        request, revision, progress_code, site_revision, site_execution, site_evidence,
        site_cleanup, site_material_available, site_quarantined_capacity, accepted_evidence_cid,
        accepted_evidence_json, accepted_subject_cid, accepted_subject_json, accepted_measurement_cid,
        accepted_measurement_json,
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    if canonical != body {
      raise EvidenceJsonStop
    }
    Ok({
      request,
      revision,
      progress_code,
      site_revision,
      site_execution,
      site_evidence,
      site_cleanup,
      site_material_available,
      site_quarantined_capacity,
      accepted_evidence_cid,
      accepted_evidence_json,
      accepted_subject_cid,
      accepted_subject_json,
      accepted_measurement_cid,
      accepted_measurement_json,
      evidence,
      subject,
      measurement,
      body,
    })
  } catch {
    EvidenceJsonStop => Err(InvalidJournal)
  }
}

///|
pub fn restore_durable_coordinator_dispatch_record(
  journal : CoordinatorDispatchJournal,
  durable : DurableCoordinatorDispatchRecord,
) -> Result[CoordinatorDispatchIntentRecord, DispatchIssue] {
  let record = match
    restore_coordinator_dispatch_intent(journal, durable.request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if coordinator_record_projection(record) ==
    durable_coordinator_projection(durable) {
    return Ok(record)
  }
  match
    restore_coordinator_dispatch_record(
      record,
      durable.revision,
      durable.progress_code,
      durable.site_revision,
      durable.site_execution,
      durable.site_evidence,
      durable.site_cleanup,
      durable.site_material_available,
      durable.site_quarantined_capacity,
      durable.accepted_evidence_cid,
      durable.accepted_subject_cid,
      durable.accepted_measurement_cid,
    ) {
    Ok(_) => Ok(record)
    Err(issue) => Err(issue)
  }
}

///|
pub fn durable_coordinator_dispatch_record_revision(
  durable : DurableCoordinatorDispatchRecord,
) -> Int {
  durable.revision
}

///|
pub fn durable_coordinator_dispatch_record_json(
  durable : DurableCoordinatorDispatchRecord,
) -> String {
  durable.body
}

///|
pub fn durable_coordinator_dispatch_record_request_identity(
  durable : DurableCoordinatorDispatchRecord,
) -> String {
  durable.request.dispatch_request_cid
}

///|
/// Return the exact admitted dispatch handle restored from durable bytes.
pub fn durable_coordinator_dispatch_record_request(
  durable : DurableCoordinatorDispatchRecord,
) -> DispatchRequest {
  durable.request
}

///|
pub fn durable_coordinator_dispatch_record_attempt_identity(
  durable : DurableCoordinatorDispatchRecord,
) -> Result[String, DispatchIssue] {
  dispatch_request_attempt_identity(durable.request)
}

///|
pub fn durable_coordinator_dispatch_record_evidence(
  durable : DurableCoordinatorDispatchRecord,
) -> RemoteExecutionEvidence? {
  durable.evidence
}

///|
pub fn durable_coordinator_dispatch_record_subject(
  durable : DurableCoordinatorDispatchRecord,
) -> RemoteManagedOutputSubject? {
  durable.subject
}

///|
pub fn durable_coordinator_dispatch_record_measurement(
  durable : DurableCoordinatorDispatchRecord,
) -> RemoteManagedOutputMeasurement? {
  durable.measurement
}
