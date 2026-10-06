///|
/// A fresh control query for one original handoff. Its identity is not an
/// execution attempt, borrow, grant or permission to replay cached custody.
pub struct RemotePollRetainedCurrent {
  handoff : RemotePollRetainedTransfer
  query_id : String
}

///|
pub fn remote_poll_retained_input_current_json(
  plan : RemoteRetainedInputPlan,
  query_id : String,
) -> Result[String, DispatchIssue] {
  let size = @utf8.encode(query_id).length()
  if size < 1 || size > 256 {
    return Err(InvalidDispatch)
  }
  let handoff = match remote_poll_retained_input_transfer_json(plan) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let writer = @encode.writer(1048576, 32, 2) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("dispatch_request_cid", dispatch_request_identity(plan.intent.request)),
        ("handoff_json", handoff),
        ("plan_cid", plan.cid),
        ("query_id", query_id),
        ("version", "actql-remote-poll-retained-input-current/0.1"),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidDispatch)
  }
}

///|
pub fn admit_remote_poll_retained_input_current_json(
  body : String,
) -> Result[RemotePollRetainedCurrent, DispatchIssue] {
  try {
    let fields = evidence_object(evidence_root(body, 1048576, 32, 2), [
      "dispatch_request_cid", "handoff_json", "plan_cid", "query_id", "version",
    ])
    if evidence_text(fields, "version") !=
      "actql-remote-poll-retained-input-current/0.1" {
      raise EvidenceJsonStop
    }
    let handoff = match
      admit_remote_poll_retained_input_transfer_json(
        evidence_text(fields, "handoff_json"),
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    let query_id = evidence_text(fields, "query_id")
    if evidence_text(fields, "dispatch_request_cid") !=
      dispatch_request_identity(handoff.intent.request) ||
      evidence_text(fields, "plan_cid") != handoff.plan.cid ||
      remote_poll_retained_input_current_json(handoff.plan, query_id) !=
      Ok(body) {
      raise EvidenceJsonStop
    }
    Ok({ handoff, query_id, })
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}

///|
pub fn remote_retained_input_current_plan(
  query : RemotePollRetainedCurrent,
) -> RemoteRetainedInputPlan {
  query.handoff.plan
}

///|
/// This response is an observation tied to a fresh authenticated query. The
/// transport must not replay it as current authority after reconstruction.
/// Native still admits current holding/delegation before physical borrow/start.
pub struct RemoteRetainedCurrentReply {
  query : RemotePollRetainedCurrent
  transfer_record_json : String
  receipt : @transfer.RemoteTransferDestinationReceipt
  body : String
  cid : String
}

///|
pub fn prepare_remote_retained_input_current_reply(
  query : RemotePollRetainedCurrent,
  record : @transfer.RemoteTransferRecord,
  receipt : @transfer.RemoteTransferDestinationReceipt,
) -> Result[RemoteRetainedCurrentReply, DispatchIssue] {
  let plan = query.handoff.plan
  if !@transfer.record_is_destination_committed(record) ||
    @transfer.record_request_identity(record) !=
    @transfer.request_cid(plan.transfer) {
    return Err(InvalidDispatch)
  }
  let durable = match @transfer.remote_transfer_record_durable_json(record) {
    Ok(value) => value
    Err(_) => return Err(InvalidDispatch)
  }
  let receipt_json = match @transfer.destination_receipt_json(receipt) {
    Ok(value) => value
    Err(_) => return Err(InvalidDispatch)
  }
  let receipt_cid = @transfer.destination_receipt_cid(receipt)
  if @transfer.admit_destination_receipt_json(
      receipt_json,
      plan.transfer,
      receipt_cid,
    )
    is Err(_) {
    return Err(InvalidDispatch)
  }
  let writer = @encode.writer(1048576, 32, 2) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("destination_receipt_cid", receipt_cid),
        ("destination_receipt_json", receipt_json),
        ("dispatch_request_cid", dispatch_request_identity(plan.intent.request)),
        ("plan_cid", plan.cid),
        ("query_id", query.query_id),
        ("transfer_record_json", durable),
        ("version", "actql-remote-retained-input-current-reply/0.1"),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.end_object(writer)
    let body = @encode.finish(writer)
    Ok({
      query,
      transfer_record_json: durable,
      receipt,
      body,
      cid: "sha256:" + @sha.hex(@utf8.encode(body)),
    })
  } catch {
    _ => Err(InvalidDispatch)
  }
}

///|
pub fn admit_remote_retained_input_current_reply_json(
  body : String,
  cid : String,
  query : RemotePollRetainedCurrent,
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_referenced_bytes : Int64,
) -> Result[RemoteRetainedCurrentReply, DispatchIssue] {
  try {
    let fields = evidence_object(evidence_root(body, 1048576, 32, 2), [
      "destination_receipt_cid", "destination_receipt_json", "dispatch_request_cid",
      "plan_cid", "query_id", "transfer_record_json", "version",
    ])
    let plan = query.handoff.plan
    if evidence_text(fields, "version") !=
      "actql-remote-retained-input-current-reply/0.1" ||
      evidence_text(fields, "dispatch_request_cid") !=
      dispatch_request_identity(plan.intent.request) ||
      evidence_text(fields, "plan_cid") != plan.cid ||
      evidence_text(fields, "query_id") != query.query_id {
      raise EvidenceJsonStop
    }
    let durable = match
      @transfer.admit_durable_remote_transfer_record(
        @utf8.encode(evidence_text(fields, "transfer_record_json")),
        max_chunks,
        max_manifest_bytes,
        max_referenced_bytes,
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    let record = match
      @transfer.restore_durable_remote_transfer_record(durable) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    let receipt = match
      @transfer.admit_destination_receipt_json(
        evidence_text(fields, "destination_receipt_json"),
        plan.transfer,
        evidence_text(fields, "destination_receipt_cid"),
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    let reply = match
      prepare_remote_retained_input_current_reply(query, record, receipt) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    if reply.body != body || reply.cid != cid {
      raise EvidenceJsonStop
    }
    Ok(reply)
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}

///|
pub fn remote_retained_input_current_reply_json(
  reply : RemoteRetainedCurrentReply,
) -> String {
  reply.body
}

///|
pub fn remote_retained_input_current_reply_identity(
  reply : RemoteRetainedCurrentReply,
) -> String {
  reply.cid
}

///|
pub fn remote_retained_input_current_reply_transfer_record_json(
  reply : RemoteRetainedCurrentReply,
) -> String {
  reply.transfer_record_json
}

///|
pub fn remote_retained_input_current_reply_receipt(
  reply : RemoteRetainedCurrentReply,
) -> @transfer.RemoteTransferDestinationReceipt {
  reply.receipt
}

///|
pub fn remote_retained_input_current_query_identity(
  query : RemotePollRetainedCurrent,
) -> String {
  query.query_id
}

///|
pub fn remote_retained_input_current_request(
  query : RemotePollRetainedCurrent,
) -> DispatchRequest {
  query.handoff.intent.request
}
