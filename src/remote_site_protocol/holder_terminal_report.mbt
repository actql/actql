///|
/// Immutable original-holder DATA. Neither construction nor admission proves
/// physical stop, grants authority, settles capacity, or acknowledges a Run.
struct RemoteHolderTerminalReport {
  root : DispatchRequest
  requests : Array[DispatchRequest]
  body : String
  identity : String
}

///|
/// The resident issuer separately confirms the original private channel,
/// caller settlement, child wait, endpoint retirement and named-slot hold.
pub fn prepare_remote_holder_terminal_report(
  root : DispatchRequest,
  requests : Array[DispatchRequest],
  maximum : Int,
) -> Result[RemoteHolderTerminalReport, DispatchIssue] {
  if maximum <= 0 || requests.is_empty() {
    return Err(InvalidDispatch)
  }
  let seen : Map[String, Bool] = Map([])
  let tasks : Map[String, Bool] = Map([])
  let wires : Array[String] = []
  let root_cid = dispatch_request_identity(root)
  for request in requests {
    let identity = dispatch_request_identity(request)
    let (run, task) = dispatch_request_task_scope(request)
    if run != dispatch_request_task_scope(root).0 ||
      dispatch_request_execution_scope(root) !=
      dispatch_request_execution_scope(request) ||
      dispatch_request_journal_key(root)[0] !=
      dispatch_request_journal_key(request)[0] ||
      seen.contains(identity) ||
      tasks.contains(task) {
      return Err(InvalidDispatch)
    }
    let wire = match emit_dispatch_request_body(request) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    seen.set(identity, true)
    tasks.set(task, true)
    wires.push(wire)
  }
  if !seen.contains(root_cid) {
    return Err(InvalidDispatch)
  }
  try {
    let writer = @encode.writer(maximum, maximum, 3)
    @encode.begin_object(writer)
    @encode.key(writer, "dispatch_request_jsons")
    @encode.begin_array(writer)
    for wire in wires {
      @encode.string_value(writer, wire)
    }
    @encode.end_array(writer)
    @encode.key(writer, "root_request_cid")
    @encode.string_value(writer, root_cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-native-holder-terminal/0.1")
    @encode.end_object(writer)
    let body = @encode.finish(writer)
    Ok({
      root,
      requests: requests.copy(),
      body,
      identity: "sha256:" + @sha.hex(@utf8.encode(body)),
    })
  } catch {
    _ => Err(InvalidDispatch)
  }
}

///|
/// Admit one exact closed wire once. Saved report DATA is never current
/// permission or evidence that the remote physical operation was performed.
pub fn admit_remote_holder_terminal_report_json(
  body : String,
  maximum : Int,
) -> Result[RemoteHolderTerminalReport, DispatchIssue] {
  if maximum <= 0 {
    return Err(InvalidDispatch)
  }
  try {
    let object = evidence_object(evidence_root(body, maximum, maximum, 3), [
      "dispatch_request_jsons", "root_request_cid", "version",
    ])
    if evidence_text(object, "version") != "actql-native-holder-terminal/0.1" {
      raise EvidenceJsonStop
    }
    let root_cid = evidence_text(object, "root_request_cid")
    let wires = evidence_decoded(
      @decode.required(object, "dispatch_request_jsons"),
    )
    let count = match @decode.array_length(wires) {
      Some(value) if value > 0 => value
      _ => raise EvidenceJsonStop
    }
    let requests : Array[DispatchRequest] = []
    let mut root : DispatchRequest? = None
    for index in 0..<count {
      let item = match @decode.element_at(wires, index) {
        Some(value) => value
        None => raise EvidenceJsonStop
      }
      let text = evidence_decoded(@decode.text(item))
      // This private owner entry validates the complete closed canonical
      // request and computes its identity once. No caller supplies a CID.
      let request = admit_dispatch_request_body(text) catch {
        DurableRecordStop => raise EvidenceJsonStop
      }
      requests.push(request)
      if dispatch_request_identity(request) == root_cid {
        root = Some(request)
      }
    }
    guard root is Some(original) else { raise EvidenceJsonStop }
    match prepare_remote_holder_terminal_report(original, requests, maximum) {
      Ok(report) if report.body == body => Ok(report)
      _ => Err(InvalidDispatch)
    }
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}

///|
pub fn remote_holder_terminal_report_root(
  report : RemoteHolderTerminalReport,
) -> DispatchRequest {
  report.root
}

///|
pub fn remote_holder_terminal_report_requests(
  report : RemoteHolderTerminalReport,
) -> Array[DispatchRequest] {
  report.requests.copy()
}

///|
pub fn remote_holder_terminal_report_json(
  report : RemoteHolderTerminalReport,
) -> String {
  report.body
}

///|
pub fn remote_holder_terminal_report_identity(
  report : RemoteHolderTerminalReport,
) -> String {
  report.identity
}

///|
/// Receipt of this exact inventory report, not a whole-Run stop, Result,
/// current permission or capacity-release acknowledgement.
struct RemoteHolderTerminalReply {
  report_identity : String
  root_identity : String
  body : String
}

///|
/// The receiving Owner calls this only after durably retaining the admitted
/// report and its original dispatch association. Partial Run inventories may
/// be acknowledged while the Run itself remains physically unconfirmed.
pub fn prepare_remote_holder_terminal_reply(
  report : RemoteHolderTerminalReport,
) -> Result[RemoteHolderTerminalReply, DispatchIssue] {
  try {
    let writer = @encode.writer(2048, 16, 2)
    @encode.begin_object(writer)
    @encode.key(writer, "report_cid")
    @encode.string_value(writer, report.identity)
    @encode.key(writer, "root_request_cid")
    @encode.string_value(writer, dispatch_request_identity(report.root))
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-native-holder-terminal-ack/0.1")
    @encode.end_object(writer)
    Ok({
      report_identity: report.identity,
      root_identity: dispatch_request_identity(report.root),
      body: @encode.finish(writer),
    })
  } catch {
    _ => Err(InvalidDispatch)
  }
}

///|
pub fn admit_remote_holder_terminal_reply_json(
  body : String,
  report : RemoteHolderTerminalReport,
) -> Result[RemoteHolderTerminalReply, DispatchIssue] {
  try {
    let object = evidence_object(evidence_root(body, 2048, 16, 2), [
      "report_cid", "root_request_cid", "version",
    ])
    if evidence_text(object, "version") !=
      "actql-native-holder-terminal-ack/0.1" ||
      evidence_text(object, "report_cid") != report.identity ||
      evidence_text(object, "root_request_cid") !=
      dispatch_request_identity(report.root) {
      raise EvidenceJsonStop
    }
    match prepare_remote_holder_terminal_reply(report) {
      Ok(value) if value.body == body => Ok(value)
      _ => Err(InvalidDispatch)
    }
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}

///|
pub fn remote_holder_terminal_reply_json(
  reply : RemoteHolderTerminalReply,
) -> String {
  reply.body
}

///|
pub fn remote_holder_terminal_reply_matches(
  reply : RemoteHolderTerminalReply,
  report : RemoteHolderTerminalReport,
) -> Bool {
  reply.report_identity == report.identity &&
  reply.root_identity == dispatch_request_identity(report.root)
}
