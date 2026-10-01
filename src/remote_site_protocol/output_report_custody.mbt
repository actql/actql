///|
/// Immutable recovery inputs, independent of physical payload custody.
/// The canonical original report is always re-admitted against these owners.
struct RemoteOutputReportCustody {
  output : RemotePollOutput
  result : RemoteOutputResult
  body : String
}

///|
/// Compute the exact upper-bound snapshot size before any payload or transfer
/// side effect.  The transfer reply has a fixed canonical shape for a given
/// request, so a committed synthetic record is sufficient to measure the
/// report envelope without inventing a second execution or transfer.
pub fn remote_output_report_custody_preflight_bytes(
  output : RemotePollOutput,
  payload : @payload.PublicationPayloadRequest,
  transfer : @transfer.RemoteTransferRequest,
) -> Result[Int64, DispatchIssue] {
  let record = @transfer.open_record(transfer)
  let record = match
    @transfer.commit_transition(@transfer.prepare_start(record).unwrap(), true) {
    Ok(value) => value
    Err(_) => return Err(InvalidDispatch)
  }
  let store_route = @transfer.request_route(transfer) == @transfer.TransferStore
  let record = match
    @transfer.commit_transition(
      @transfer.prepare_source_settled(record, true, store_route).unwrap(),
      true,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidDispatch)
  }
  let record = match
    @transfer.commit_transition(
      @transfer.prepare_destination_commit(record).unwrap(),
      true,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidDispatch)
  }
  let result = match
    prepare_remote_output_result(
      output,
      payload,
      "sha256:" + "0".repeat(64),
      record,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    prepare_remote_output_report_custody(output, payload, transfer, result) {
    Ok(custody) => Ok(@utf8.encode(custody.body).length().to_int64())
    Err(issue) => Err(issue)
  }
}

///|
pub fn prepare_remote_output_report_custody(
  output : RemotePollOutput,
  payload : @payload.PublicationPayloadRequest,
  transfer : @transfer.RemoteTransferRequest,
  result : RemoteOutputResult,
) -> Result[RemoteOutputReportCustody, DispatchIssue] {
  let report = match remote_output_result_json(result) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match admit_remote_output_result_json(report, output, payload, transfer) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let output_json = match
    remote_poll_output_json(output.request, output.intent) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let payload_json = match @payload.publication_payload_request_json(payload) {
    Ok(value) => value
    Err(_) => return Err(InvalidDispatch)
  }
  let envelope = match @transfer.transfer_admission_envelope_json(transfer) {
    Ok(value) => value
    Err(_) => return Err(InvalidDispatch)
  }
  let writer = @encode.writer(2097152, 32, 2) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    for
      entry in [
        ("manifest_cid", @transfer.request_projection(transfer)[7]),
        ("output_json", output_json),
        ("payload_cid", result.payload_request_cid),
        ("payload_json", payload_json),
        ("report_cid", result.result_cid),
        ("report_json", report),
        ("transfer_cid", result.transfer_request_cid),
        ("transfer_envelope", envelope),
        ("version", "actql-site-output-report-custody/0.1"),
      ] {
      @encode.key(writer, entry.0)
      @encode.string_value(writer, entry.1)
    }
    @encode.end_object(writer)
    Ok({ output, result, body: @encode.finish(writer), })
  } catch {
    _ => Err(InvalidDispatch)
  }
}

///|
pub fn admit_remote_output_report_custody_json(
  body : String,
) -> Result[RemoteOutputReportCustody, DispatchIssue] {
  try {
    let object = evidence_object(evidence_root(body, 2097152, 32, 2), [
      "manifest_cid", "output_json", "payload_cid", "payload_json", "report_cid",
      "report_json", "transfer_cid", "transfer_envelope", "version",
    ])
    if evidence_text(object, "version") !=
      "actql-site-output-report-custody/0.1" {
      raise EvidenceJsonStop
    }
    let output = match
      admit_remote_poll_output_json(evidence_text(object, "output_json")) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    let payload = match
      @payload.admit_publication_payload_request_json(
        evidence_text(object, "payload_json"),
        evidence_text(object, "payload_cid"),
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    let transfer = match
      @transfer.admit_transfer_admission_envelope_json(
        evidence_text(object, "transfer_envelope"),
        evidence_text(object, "transfer_cid"),
        evidence_text(object, "manifest_cid"),
        65536,
        1048576,
        remote_output_intent_projection(output.intent).transfer_max_bytes,
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    let result = match
      admit_remote_output_result_json(
        evidence_text(object, "report_json"),
        output,
        payload,
        transfer,
      ) {
      Ok(value) if value.result_cid == evidence_text(object, "report_cid") =>
        value
      _ => raise EvidenceJsonStop
    }
    match
      prepare_remote_output_report_custody(output, payload, transfer, result) {
      Ok(value) if value.body == body => Ok(value)
      _ => Err(InvalidDispatch)
    }
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}

///|
pub fn remote_output_report_custody_json(
  custody : RemoteOutputReportCustody,
) -> String {
  custody.body
}

///|
pub fn remote_output_report_custody_result(
  custody : RemoteOutputReportCustody,
) -> RemoteOutputResult {
  custody.result
}

///|
pub fn remote_output_report_custody_dispatch(
  custody : RemoteOutputReportCustody,
) -> DispatchRequest {
  custody.output.request
}

///|
pub fn remote_output_report_custody_output(
  custody : RemoteOutputReportCustody,
) -> RemotePollOutput {
  custody.output
}

///|
/// One bounded slot per Output intent. Retries never allocate another slot.
pub fn remote_output_report_custody_key(
  custody : RemoteOutputReportCustody,
) -> String {
  custody.result.intent_cid
}
