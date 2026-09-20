///|
/// Verify that one typed managed-output observation is exactly the evidence
/// installed by a prepared durable-evidence transition.
pub fn remote_managed_output_observation_matches_transition(
  transition : DispatchTransition,
  evidence : RemoteExecutionEvidence,
  subject : RemoteManagedOutputSubject,
  measurement : RemoteManagedOutputMeasurement,
) -> Bool {
  let request = transition.record.request
  match transition.next_evidence {
    EvidenceDurable(material_generation, holding_evidence_cid, evidence_cid) =>
      remote_execution_evidence_matches_dispatch(evidence, request) &&
      remote_managed_output_subject_matches_evidence(subject, evidence, request) &&
      remote_managed_output_subject_matches_measurement(subject, measurement) &&
      evidence.evidence_cid == evidence_cid &&
      evidence.material_generation == material_generation &&
      evidence.holding_evidence_cid == holding_evidence_cid
    _ => false
  }
}

///|
/// Reports whether this transition installs typed managed-output evidence for
/// the first time. Physical journals use this to prevent CID-only commits.
pub fn dispatch_transition_installs_managed_observation(
  transition : DispatchTransition,
) -> Bool {
  !(transition.expected_evidence is EvidenceDurable(_, _, _)) &&
  transition.next_evidence is EvidenceDurable(_, _, _)
}

///|
/// Reports whether an exact durable Site record requires the typed
/// observation envelope to be present.
pub fn dispatch_record_requires_managed_observation(
  record : DispatchRecord,
) -> Bool {
  record.evidence is EvidenceDurable(_, _, _)
}

///|
/// Re-admit canonical evidence bodies for one durable Site observation.
/// Physical journals store bytes; this function owns their semantic binding.
pub fn admit_remote_managed_output_observation(
  record : DispatchRecord,
  evidence_body : String,
  evidence_cid : String,
  subject_body : String,
  subject_cid : String,
  measurement_body : String,
  measurement_cid : String,
) -> Result[
  (
    RemoteExecutionEvidence,
    RemoteManagedOutputSubject,
    RemoteManagedOutputMeasurement,
  ),
  DispatchIssue,
] {
  let evidence = match
    admit_remote_execution_evidence_json(
      evidence_body,
      evidence_cid,
      record.request,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let subject = match
    admit_remote_managed_output_subject_json(
      subject_body,
      subject_cid,
      record.request,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let measurement = match
    admit_remote_managed_output_measurement_json(
      measurement_body, measurement_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match record.evidence {
    EvidenceDurable(material_generation, holding_evidence_cid, durable_cid) =>
      if durable_cid == evidence_cid &&
        evidence.material_generation == material_generation &&
        evidence.holding_evidence_cid == holding_evidence_cid &&
        remote_managed_output_subject_matches_evidence(
          subject,
          evidence,
          record.request,
        ) &&
        remote_managed_output_subject_matches_measurement(subject, measurement) {
        Ok((evidence, subject, measurement))
      } else {
        Err(InvalidJournal)
      }
    _ => Err(InvalidTransition)
  }
}

///|
fn emit_remote_managed_output_observation_json(
  evidence : RemoteExecutionEvidence,
  subject : RemoteManagedOutputSubject,
  measurement : RemoteManagedOutputMeasurement,
) -> Result[String, DispatchIssue] {
  let evidence_body = match remote_execution_evidence_json(evidence) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let subject_body = match remote_managed_output_subject_json(subject) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let measurement_body = match
    remote_managed_output_measurement_json(measurement) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let writer = @encode.writer(1048576, 32, 2) catch {
    _ => return Err(InvalidJournal)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "evidence_cid")
    @encode.string_value(writer, remote_execution_evidence_cid(evidence))
    @encode.key(writer, "evidence_json")
    @encode.string_value(writer, evidence_body)
    @encode.key(writer, "measurement_cid")
    @encode.string_value(
      writer,
      remote_managed_output_measurement_cid(measurement),
    )
    @encode.key(writer, "measurement_json")
    @encode.string_value(writer, measurement_body)
    @encode.key(writer, "subject_cid")
    @encode.string_value(writer, remote_managed_output_subject_cid(subject))
    @encode.key(writer, "subject_json")
    @encode.string_value(writer, subject_body)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-managed-observation/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidJournal)
  }
  Ok(@encode.finish(writer) catch { _ => return Err(InvalidJournal) })
}

///|
/// Emit the canonical durable envelope for one typed managed-output
/// observation. The envelope keeps self identities beside the canonical
/// bodies because those identities are deliberately not embedded in their
/// own preimages.
pub fn remote_managed_output_observation_json(
  transition : DispatchTransition,
  evidence : RemoteExecutionEvidence,
  subject : RemoteManagedOutputSubject,
  measurement : RemoteManagedOutputMeasurement,
) -> Result[String, DispatchIssue] {
  if !remote_managed_output_observation_matches_transition(
      transition, evidence, subject, measurement,
    ) {
    return Err(InvalidTransition)
  }
  emit_remote_managed_output_observation_json(evidence, subject, measurement)
}

///|
/// Re-admit a durable observation envelope against the exact durable Site
/// record. Stored bytes never acquire semantic authority merely by surviving
/// a restart.
pub fn admit_remote_managed_output_observation_json(
  record : DispatchRecord,
  body : String,
) -> Result[
  (
    RemoteExecutionEvidence,
    RemoteManagedOutputSubject,
    RemoteManagedOutputMeasurement,
  ),
  DispatchIssue,
] {
  try {
    let object = evidence_object(evidence_root(body, 1048576, 32, 2), [
      "evidence_cid", "evidence_json", "measurement_cid", "measurement_json", "subject_cid",
      "subject_json", "version",
    ])
    if evidence_text(object, "version") !=
      "actql-remote-managed-observation/0.1" {
      raise EvidenceJsonStop
    }
    let restored = match
      admit_remote_managed_output_observation(
        record,
        evidence_text(object, "evidence_json"),
        evidence_text(object, "evidence_cid"),
        evidence_text(object, "subject_json"),
        evidence_text(object, "subject_cid"),
        evidence_text(object, "measurement_json"),
        evidence_text(object, "measurement_cid"),
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    let canonical = match
      emit_remote_managed_output_observation_json(
        restored.0,
        restored.1,
        restored.2,
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    if canonical != body {
      raise EvidenceJsonStop
    }
    Ok(restored)
  } catch {
    EvidenceJsonStop => Err(InvalidJournal)
  }
}
