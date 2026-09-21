///|
/// Side-effect-free physical plan for one retained output occurrence. The
/// Site derives it from an immutable observed output; the Coordinator
/// re-admits every nested body before durably authorizing physical output.
struct RemoteOutputPlan {
  payload_request : @payload.PublicationPayloadRequest
  transfer_request : @transfer.RemoteTransferRequest
  body : String
  plan_cid : String
}

///|
fn output_plan_inputs_valid(
  output : RemotePollOutput,
  subject : RemoteManagedOutputSubject,
  payload_request : @payload.PublicationPayloadRequest,
  transfer_request : @transfer.RemoteTransferRequest,
) -> Bool {
  let manifest = @transfer.request_manifest(transfer_request)
  output_expected_inputs_valid(output, payload_request, transfer_request) &&
  remote_managed_output_subject_matches_dispatch(subject, output.request) &&
  subject.material_generation ==
  @payload.publication_payload_material_identity(payload_request) &&
  subject.result_schema_cid ==
  @payload.publication_payload_request_schema(payload_request) &&
  subject.logical_view_cid ==
  @payload.publication_payload_request_logical_relation(payload_request) &&
  subject.representation_codec_cid ==
  @payload.publication_payload_request_codec(payload_request) &&
  subject.row_count.to_int64() ==
  @payload.publication_payload_request_row_count(payload_request) &&
  subject.retained_bytes ==
  @payload.publication_payload_request_max_bytes(payload_request) &&
  subject.physical_manifest_cid == @manifest.manifest_cid(manifest) &&
  subject.result_schema_cid == manifest.schema_contract_cid &&
  subject.logical_view_cid == manifest.view_contract_cid &&
  subject.representation_codec_cid == manifest.codec_contract_cid &&
  subject.row_count == manifest.row_count &&
  subject.retained_bytes == manifest.referenced_bytes
}

///|
fn emit_remote_output_plan(
  output : RemotePollOutput,
  subject : RemoteManagedOutputSubject,
  payload_request : @payload.PublicationPayloadRequest,
  transfer_request : @transfer.RemoteTransferRequest,
) -> Result[(String, String), DispatchIssue] {
  if !output_plan_inputs_valid(
      output, subject, payload_request, transfer_request,
    ) {
    return Err(InvalidDispatch)
  }
  let payload_body = match
    @payload.publication_payload_request_json(payload_request) {
    Ok(value) => value
    Err(_) => return Err(InvalidDispatch)
  }
  let transfer_body = match @transfer.request_json(transfer_request) {
    Ok(value) => value
    Err(_) => return Err(InvalidDispatch)
  }
  let manifest_body = match @transfer.request_manifest_json(transfer_request) {
    Ok(value) => value
    Err(_) => return Err(InvalidDispatch)
  }
  let writer = @encode.writer(3145728, 32, 2) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "dispatch_request_cid")
    @encode.string_value(writer, dispatch_request_identity(output.request))
    @encode.key(writer, "intent_cid")
    @encode.string_value(writer, remote_output_intent_identity(output.intent))
    @encode.key(writer, "payload_request_cid")
    @encode.string_value(
      writer,
      @payload.publication_payload_request_identity(payload_request),
    )
    @encode.key(writer, "payload_request_json")
    @encode.string_value(writer, payload_body)
    @encode.key(writer, "physical_manifest_cid")
    @encode.string_value(
      writer,
      @manifest.manifest_cid(@transfer.request_manifest(transfer_request)),
    )
    @encode.key(writer, "physical_manifest_json")
    @encode.string_value(writer, manifest_body)
    @encode.key(writer, "subject_cid")
    @encode.string_value(writer, remote_managed_output_subject_cid(subject))
    @encode.key(writer, "transfer_request_cid")
    @encode.string_value(writer, @transfer.request_cid(transfer_request))
    @encode.key(writer, "transfer_request_json")
    @encode.string_value(writer, transfer_body)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-output-plan/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidDispatch)
  }
  let body = @encode.finish(writer) catch { _ => return Err(InvalidDispatch) }
  Ok((body, "sha256:" + @sha.hex(@utf8.encode(body))))
}

///|
pub fn prepare_remote_output_plan(
  output : RemotePollOutput,
  subject : RemoteManagedOutputSubject,
  payload_request : @payload.PublicationPayloadRequest,
  transfer_request : @transfer.RemoteTransferRequest,
) -> Result[RemoteOutputPlan, DispatchIssue] {
  match
    emit_remote_output_plan(output, subject, payload_request, transfer_request) {
    Ok((body, plan_cid)) =>
      Ok({ payload_request, transfer_request, body, plan_cid, })
    Err(issue) => Err(issue)
  }
}

///|
pub fn admit_remote_output_plan_json(
  body : String,
  output : RemotePollOutput,
  subject : RemoteManagedOutputSubject,
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_referenced_bytes : Int64,
) -> Result[RemoteOutputPlan, DispatchIssue] {
  try {
    let object = evidence_object(evidence_root(body, 3145728, 32, 2), [
      "dispatch_request_cid", "intent_cid", "payload_request_cid", "payload_request_json",
      "physical_manifest_cid", "physical_manifest_json", "subject_cid", "transfer_request_cid",
      "transfer_request_json", "version",
    ])
    if evidence_text(object, "version") != "actql-remote-output-plan/0.1" ||
      evidence_text(object, "dispatch_request_cid") !=
      dispatch_request_identity(output.request) ||
      evidence_text(object, "intent_cid") !=
      remote_output_intent_identity(output.intent) ||
      evidence_text(object, "subject_cid") !=
      remote_managed_output_subject_cid(subject) {
      raise EvidenceJsonStop
    }
    let payload_request = match
      @payload.admit_publication_payload_request_json(
        evidence_text(object, "payload_request_json"),
        evidence_text(object, "payload_request_cid"),
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    let transfer_request = match
      @transfer.admit_request_json(
        evidence_text(object, "transfer_request_json"),
        evidence_text(object, "physical_manifest_json"),
        evidence_text(object, "transfer_request_cid"),
        evidence_text(object, "physical_manifest_cid"),
        max_chunks,
        max_manifest_bytes,
        max_referenced_bytes,
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    let admitted = match
      prepare_remote_output_plan(
        output, subject, payload_request, transfer_request,
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    if admitted.body != body {
      raise EvidenceJsonStop
    }
    Ok(admitted)
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}

///|
pub fn remote_output_plan_json(
  plan : RemoteOutputPlan,
) -> Result[String, DispatchIssue] {
  if "sha256:" + @sha.hex(@utf8.encode(plan.body)) == plan.plan_cid {
    Ok(plan.body)
  } else {
    Err(InvalidDispatch)
  }
}

///|
pub fn remote_output_plan_identity(plan : RemoteOutputPlan) -> String {
  plan.plan_cid
}

///|
pub fn remote_output_plan_payload_request(
  plan : RemoteOutputPlan,
) -> @payload.PublicationPayloadRequest {
  plan.payload_request
}

///|
pub fn remote_output_plan_transfer_request(
  plan : RemoteOutputPlan,
) -> @transfer.RemoteTransferRequest {
  plan.transfer_request
}
