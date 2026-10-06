///|
/// Immutable receiver plan for an internal producer. It carries existing
/// canonical evidence and Transfer bodies, never publication payloads.
pub struct RemoteRetainedInputPlan {
  intent : RemoteRetainedInputIntent
  subject : RemoteManagedOutputSubject
  evidence : RemoteExecutionEvidence
  transfer : @transfer.RemoteTransferRequest
  body : String
  cid : String
}

///|
fn retained_plan_valid(
  intent : RemoteRetainedInputIntent,
  subject : RemoteManagedOutputSubject,
  evidence : RemoteExecutionEvidence,
  transfer : @transfer.RemoteTransferRequest,
) -> Bool {
  let selected = intent.projection
  let request = intent.request
  let scope = dispatch_request_execution_scope(request)
  let facts = @transfer.request_projection(transfer)
  let key = @transfer.request_journal_key(transfer)
  let managed = remote_managed_output_subject_projection(subject)
  let physical = @transfer.request_manifest(transfer)
  remote_managed_output_subject_matches_evidence(subject, evidence, request) &&
  remote_managed_output_subject_cid(subject) == selected.producer_subject_cid &&
  remote_execution_evidence_cid(evidence) == selected.producer_evidence_cid &&
  key[0] == dispatch_request_journal_key(request)[0] &&
  key[3] == selected.transfer_attempt &&
  @transfer.request_route(transfer) == @transfer.DirectStream &&
  facts[2] == scope[0] &&
  facts[3] == scope[1] &&
  facts[4] == scope[0] &&
  facts[5] == scope[1] &&
  facts[6] == managed[1] &&
  facts[7] == managed[7] &&
  facts[8] == selected.transfer_max_bytes.to_string() &&
  facts[9] == selected.transfer_expires_unix_ms.to_string() &&
  facts[10] == selected.source_grant_cid &&
  facts[11] == selected.destination_grant_cid &&
  facts[12] == selected.route_capability_cid &&
  managed[4] == selected.producer_schema_cid &&
  physical.schema_contract_cid == managed[4] &&
  physical.view_contract_cid == managed[5] &&
  physical.codec_contract_cid == managed[6] &&
  physical.manifest_cid == managed[7] &&
  physical.row_count.to_string() == managed[9] &&
  physical.referenced_bytes.to_string() == managed[10] &&
  physical.referenced_bytes <= selected.transfer_max_bytes
}

///|
pub fn prepare_remote_retained_input_plan(
  intent : RemoteRetainedInputIntent,
  subject : RemoteManagedOutputSubject,
  evidence : RemoteExecutionEvidence,
  transfer : @transfer.RemoteTransferRequest,
) -> Result[RemoteRetainedInputPlan, DispatchIssue] {
  if !retained_plan_valid(intent, subject, evidence, transfer) {
    return Err(InvalidDispatch)
  }
  let evidence_json = match remote_execution_evidence_json(evidence) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let subject_json = match remote_managed_output_subject_json(subject) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let transfer_json = match @transfer.request_json(transfer) {
    Ok(value) => value
    Err(_) => return Err(InvalidDispatch)
  }
  let manifest_json = match @transfer.request_manifest_json(transfer) {
    Ok(value) => value
    Err(_) => return Err(InvalidDispatch)
  }
  let writer = @encode.writer(3145728, 32, 2) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("dispatch_request_cid", dispatch_request_identity(intent.request)),
        ("evidence_cid", remote_execution_evidence_cid(evidence)),
        ("evidence_json", evidence_json),
        ("intent_cid", intent.cid),
        (
          "physical_manifest_cid",
          @transfer.request_manifest(transfer).manifest_cid,
        ),
        ("physical_manifest_json", manifest_json),
        ("subject_cid", remote_managed_output_subject_cid(subject)),
        ("subject_json", subject_json),
        ("transfer_request_cid", @transfer.request_cid(transfer)),
        ("transfer_request_json", transfer_json),
        ("version", "actql-remote-retained-input-plan/0.1"),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidDispatch)
  }
  let body = @encode.finish(writer) catch { _ => return Err(InvalidDispatch) }
  Ok({
    intent,
    subject,
    evidence,
    transfer,
    body,
    cid: "sha256:" + @sha.hex(@utf8.encode(body)),
  })
}

///|
pub fn admit_remote_retained_input_plan_json(
  body : String,
  claimed_cid : String,
  intent : RemoteRetainedInputIntent,
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_referenced_bytes : Int64,
) -> Result[RemoteRetainedInputPlan, DispatchIssue] {
  try {
    let fields = evidence_object(evidence_root(body, 3145728, 32, 2), [
      "dispatch_request_cid", "evidence_cid", "evidence_json", "intent_cid", "physical_manifest_cid",
      "physical_manifest_json", "subject_cid", "subject_json", "transfer_request_cid",
      "transfer_request_json", "version",
    ])
    if evidence_text(fields, "version") !=
      "actql-remote-retained-input-plan/0.1" ||
      evidence_text(fields, "dispatch_request_cid") !=
      dispatch_request_identity(intent.request) ||
      evidence_text(fields, "intent_cid") != intent.cid {
      raise EvidenceJsonStop
    }
    let evidence = match
      admit_remote_execution_evidence_json(
        evidence_text(fields, "evidence_json"),
        evidence_text(fields, "evidence_cid"),
        intent.request,
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    let subject = match
      admit_remote_managed_output_subject_json(
        evidence_text(fields, "subject_json"),
        evidence_text(fields, "subject_cid"),
        intent.request,
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    let transfer = match
      @transfer.admit_request_json(
        evidence_text(fields, "transfer_request_json"),
        evidence_text(fields, "physical_manifest_json"),
        evidence_text(fields, "transfer_request_cid"),
        evidence_text(fields, "physical_manifest_cid"),
        max_chunks,
        max_manifest_bytes,
        max_referenced_bytes,
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    let admitted = match
      prepare_remote_retained_input_plan(intent, subject, evidence, transfer) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    if admitted.body != body || admitted.cid != claimed_cid {
      raise EvidenceJsonStop
    }
    Ok(admitted)
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}

///|
pub fn remote_retained_input_plan_json(
  plan : RemoteRetainedInputPlan,
) -> String {
  plan.body
}

///|
pub fn remote_retained_input_plan_identity(
  plan : RemoteRetainedInputPlan,
) -> String {
  plan.cid
}

///|
pub fn remote_retained_input_plan_transfer(
  plan : RemoteRetainedInputPlan,
) -> @transfer.RemoteTransferRequest {
  plan.transfer
}
