///|
/// Bounded transport of a saved plan. Admission preserves the original bytes;
/// it grants no current authorization, receiver reservation or consumer start.
pub struct RemotePollRetainedTransfer {
  intent : RemoteRetainedInputIntent
  plan : RemoteRetainedInputPlan
}

///|
pub fn remote_poll_retained_input_transfer_json(
  plan : RemoteRetainedInputPlan,
) -> Result[String, DispatchIssue] {
  let request = match dispatch_request_json(plan.intent.request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // This profile fits the existing holder channel and control-body ceiling.
  // A larger plan is refused here; no existing transport ceiling is raised.
  let writer = @encode.writer(1048576, 32, 2) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("dispatch_request_cid", dispatch_request_identity(plan.intent.request)),
        ("intent_cid", plan.intent.cid),
        ("intent_json", plan.intent.body),
        ("plan_cid", plan.cid),
        ("plan_json", plan.body),
        ("request_json", request),
        ("version", "actql-remote-poll-retained-input-transfer/0.1"),
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
pub fn admit_remote_poll_retained_input_transfer_json(
  body : String,
) -> Result[RemotePollRetainedTransfer, DispatchIssue] {
  try {
    let fields = evidence_object(evidence_root(body, 1048576, 32, 2), [
      "dispatch_request_cid", "intent_cid", "intent_json", "plan_cid", "plan_json",
      "request_json", "version",
    ])
    if evidence_text(fields, "version") !=
      "actql-remote-poll-retained-input-transfer/0.1" {
      raise EvidenceJsonStop
    }
    let request = match
      admit_dispatch_request_json(
        evidence_text(fields, "request_json"),
        evidence_text(fields, "dispatch_request_cid"),
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    let intent = match
      admit_remote_retained_input_intent_json(
        evidence_text(fields, "intent_json"),
        evidence_text(fields, "intent_cid"),
        request,
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    let plan = match
      admit_remote_retained_input_plan_json(
        evidence_text(fields, "plan_json"),
        evidence_text(fields, "plan_cid"),
        intent,
        65536,
        1048576,
        536870912L,
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    if remote_poll_retained_input_transfer_json(plan) != Ok(body) {
      raise EvidenceJsonStop
    }
    Ok({ intent, plan, })
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}

///|
pub fn remote_poll_retained_transfer_intent(
  poll : RemotePollRetainedTransfer,
) -> RemoteRetainedInputIntent {
  poll.intent
}

///|
pub fn remote_poll_retained_transfer_plan(
  poll : RemotePollRetainedTransfer,
) -> RemoteRetainedInputPlan {
  poll.plan
}

///|
/// Exact completed receiver evidence under a saved plan. This is historical
/// protocol evidence, not proof of current physical availability or a borrow.
pub struct RemoteRetainedInputResult {
  plan : RemoteRetainedInputPlan
  record : @transfer.RemoteTransferRecord
  receipt : @transfer.RemoteTransferDestinationReceipt
  body : String
  cid : String
}

///|
pub fn prepare_remote_retained_input_result(
  plan : RemoteRetainedInputPlan,
  record : @transfer.RemoteTransferRecord,
  receipt : @transfer.RemoteTransferDestinationReceipt,
) -> Result[RemoteRetainedInputResult, DispatchIssue] {
  if !@transfer.record_is_destination_committed(record) ||
    @transfer.record_request_identity(record) !=
    @transfer.request_cid(plan.transfer) {
    return Err(InvalidDispatch)
  }
  let transfer_reply = match @transfer.remote_transfer_reply_json(record) {
    Ok(value) => value
    Err(_) => return Err(InvalidDispatch)
  }
  // Re-admission compares the exact original request, not equal payload bytes.
  let record = match
    @transfer.admit_remote_transfer_reply_json(transfer_reply, plan.transfer) {
    Ok(value) => value
    Err(_) => return Err(InvalidDispatch)
  }
  let receipt_json = match @transfer.destination_receipt_json(receipt) {
    Ok(value) => value
    Err(_) => return Err(InvalidDispatch)
  }
  let receipt_cid = @transfer.destination_receipt_cid(receipt)
  let receipt = match
    @transfer.admit_destination_receipt_json(
      receipt_json,
      plan.transfer,
      receipt_cid,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidDispatch)
  }
  let writer = @encode.writer(65536, 32, 2) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("destination_receipt_cid", receipt_cid),
        ("destination_receipt_json", receipt_json),
        ("dispatch_request_cid", dispatch_request_identity(plan.intent.request)),
        ("intent_cid", plan.intent.cid),
        ("plan_cid", plan.cid),
        ("transfer_reply_json", transfer_reply),
        ("transfer_request_cid", @transfer.request_cid(plan.transfer)),
        ("version", "actql-remote-retained-input-result/0.1"),
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
    plan,
    record,
    receipt,
    body,
    cid: "sha256:" + @sha.hex(@utf8.encode(body)),
  })
}

///|
pub fn admit_remote_retained_input_result_json(
  body : String,
  cid : String,
  plan : RemoteRetainedInputPlan,
) -> Result[RemoteRetainedInputResult, DispatchIssue] {
  try {
    let fields = evidence_object(evidence_root(body, 65536, 32, 2), [
      "destination_receipt_cid", "destination_receipt_json", "dispatch_request_cid",
      "intent_cid", "plan_cid", "transfer_reply_json", "transfer_request_cid", "version",
    ])
    if evidence_text(fields, "version") !=
      "actql-remote-retained-input-result/0.1" ||
      evidence_text(fields, "dispatch_request_cid") !=
      dispatch_request_identity(plan.intent.request) ||
      evidence_text(fields, "intent_cid") != plan.intent.cid ||
      evidence_text(fields, "plan_cid") != plan.cid ||
      evidence_text(fields, "transfer_request_cid") !=
      @transfer.request_cid(plan.transfer) {
      raise EvidenceJsonStop
    }
    let record = match
      @transfer.admit_remote_transfer_reply_json(
        evidence_text(fields, "transfer_reply_json"),
        plan.transfer,
      ) {
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
    let result = match
      prepare_remote_retained_input_result(plan, record, receipt) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    if result.body != body || result.cid != cid {
      raise EvidenceJsonStop
    }
    Ok(result)
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}

///|
pub fn remote_retained_input_result_json(
  value : RemoteRetainedInputResult,
) -> String {
  value.body
}

///|
pub fn remote_retained_input_result_identity(
  value : RemoteRetainedInputResult,
) -> String {
  value.cid
}

///|
pub fn remote_retained_input_result_record(
  value : RemoteRetainedInputResult,
) -> @transfer.RemoteTransferRecord {
  value.record
}

///|
pub fn remote_retained_input_result_receipt(
  value : RemoteRetainedInputResult,
) -> @transfer.RemoteTransferDestinationReceipt {
  value.receipt
}

///|
pub fn remote_retained_input_result_plan(
  value : RemoteRetainedInputResult,
) -> RemoteRetainedInputPlan {
  value.plan
}
