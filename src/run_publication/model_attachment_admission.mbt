///|
/// Check the exact owner-issued attachment inventory referenced by a captured
/// slot. A saved inventory is historical validation, never fresh send authority.
pub fn verify_model_slot_attachment_admission(
  capture : RunEvidenceValue,
  authority : RunEvidenceValue,
  admission : RunEvidenceValue?,
) -> Result[Unit, RunEvidenceValueIssue] {
  guard capture.name == "model_slot_capture" &&
    authority.name == "model_dispatch_authority" &&
    @json.object_field(capture.value, "attachment_admission_cids")
    is Some(@json.Array(cids)) else {
    return Err(RunEvidenceReferenceMismatch("attachment_admission_cids"))
  }
  if optional_string(
      @json.object_field(capture.value, "authority_evidence_cid"),
    ) !=
    Some(authority.identity) {
    return Err(RunEvidenceReferenceMismatch("authority_evidence_cid"))
  }
  if @json.array_count(cids) == 0 && admission is None {
    return Ok(())
  }
  guard @json.array_count(cids) == 1 &&
    admission is Some(record) &&
    record.name == "model_attachment_admission" &&
    optional_string(@json.array_at(cids, 0)) == Some(record.identity) else {
    return Err(RunEvidenceReferenceMismatch("attachment_admission_cids"))
  }
  for
    name in [
      "slot_cid", "model_task_cid", "fixed_request_cid", "authority_evidence_cid",
    ] {
    if optional_string(@json.object_field(record.value, name)) !=
      optional_string(@json.object_field(capture.value, name)) {
      return Err(RunEvidenceReferenceMismatch(name))
    }
  }
  Ok(())
}
