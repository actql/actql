///|
/// Query correlation is not an execution attempt, approval or current fact.
/// The caller obtains the member ID from the original checked Effect Owner.
struct RemoteEffectCurrentQuery {
  report : RemoteEffectCheckpointReport
  effect_id : String
  query_id : String
  body : String
  cid : String
}

///|
fn effect_current_text_valid(value : String) -> Bool {
  !value.is_empty() &&
  value.length() <= 256 &&
  @utf8.encode(value).length() <= 256 &&
  value.iter().all(c => c >= ' ' && c != '\u{7f}')
}

///|
fn effect_current_limits_valid(limits : @checkpoint.WireLimits) -> Bool {
  limits.max_wire_bytes > 0 &&
  limits.max_wire_bytes <= 65536 &&
  limits.max_nodes > 0 &&
  limits.max_nodes <= 4096 &&
  limits.max_depth > 0 &&
  limits.max_depth <= 32
}

///|
pub fn prepare_remote_effect_current_query(
  report : RemoteEffectCheckpointReport,
  effect_id : String,
  query_id : String,
  limits : @checkpoint.WireLimits,
) -> Result[RemoteEffectCurrentQuery, DispatchIssue] {
  if !effect_current_limits_valid(limits) ||
    !effect_current_text_valid(effect_id) ||
    !effect_current_text_valid(query_id) {
    return Err(InvalidDispatch)
  }
  let writer = @encode.writer(
    limits.max_wire_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    for
      (name, value) in [
        ("checkpoint_cid", report.checkpoint.checkpoint_cid),
        ("dispatch_request_cid", report.dispatch.dispatch_request_cid),
        ("effect_id", effect_id),
        ("query_id", query_id),
        ("report_cid", report.report_cid),
        ("version", "actql-remote-effect-current-query/0.1"),
      ] {
      @encode.key(writer, name)
      @encode.string_value(writer, value)
    }
    @encode.end_object(writer)
    let body = @encode.finish(writer)
    Ok({
      report,
      effect_id,
      query_id,
      body,
      cid: "sha256:" + @sha.hex(@utf8.encode(body)),
    })
  } catch {
    _ => Err(InvalidDispatch)
  }
}

///|
/// Match the receiver's own admitted original report, not a transported copy.
pub fn admit_remote_effect_current_query_json(
  body : String,
  report : RemoteEffectCheckpointReport,
  limits : @checkpoint.WireLimits,
) -> Result[RemoteEffectCurrentQuery, DispatchIssue] {
  if !effect_current_limits_valid(limits) ||
    body.length() > limits.max_wire_bytes {
    return Err(InvalidDispatch)
  }
  try {
    let fields = evidence_object(
      evidence_root(
        body,
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      ),
      [
        "checkpoint_cid", "dispatch_request_cid", "effect_id", "query_id", "report_cid",
        "version",
      ],
    )
    if evidence_text(fields, "version") !=
      "actql-remote-effect-current-query/0.1" ||
      evidence_text(fields, "checkpoint_cid") !=
      report.checkpoint.checkpoint_cid ||
      evidence_text(fields, "dispatch_request_cid") !=
      report.dispatch.dispatch_request_cid ||
      evidence_text(fields, "report_cid") != report.report_cid {
      raise EvidenceJsonStop
    }
    let query = match
      prepare_remote_effect_current_query(
        report,
        evidence_text(fields, "effect_id"),
        evidence_text(fields, "query_id"),
        limits,
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    if query.body != body {
      raise EvidenceJsonStop
    }
    Ok(query)
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}

///|
/// Metadata only. The receiving Host authenticates the current Site/generation
/// and accepts only its currently outstanding query. This is not a Ledger,
/// current authorization, physical stop, approval, publication or cleanup proof.
struct RemoteEffectCurrentReply {
  query : RemoteEffectCurrentQuery
  ledger_head_cid : String?
  recovery_action : Int
  response_saved : Bool
  body : String
  cid : String
}

///|
pub fn prepare_remote_effect_current_reply(
  query : RemoteEffectCurrentQuery,
  ledger_head_cid : String?,
  recovery_action : Int,
  response_saved : Bool,
  limits : @checkpoint.WireLimits,
) -> Result[RemoteEffectCurrentReply, DispatchIssue] {
  if !effect_current_limits_valid(limits) ||
    !(recovery_action == 0 ||
    recovery_action == 1 ||
    recovery_action == 3 ||
    recovery_action == 4 ||
    recovery_action == 5 ||
    recovery_action == 6 ||
    recovery_action == 7) ||
    (recovery_action == 0) != (ledger_head_cid is None) ||
    (ledger_head_cid is Some(cid) && !valid_cid(cid)) ||
    (response_saved && (recovery_action == 0 || recovery_action == 1)) {
    return Err(InvalidDispatch)
  }
  let writer = @encode.writer(
    limits.max_wire_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return Err(InvalidDispatch)
  }
  try {
    @encode.begin_object(writer)
    for
      (name, value) in [
        ("checkpoint_cid", query.report.checkpoint.checkpoint_cid),
        ("dispatch_request_cid", query.report.dispatch.dispatch_request_cid),
        ("effect_id", query.effect_id),
        ("ledger_head_cid", ledger_head_cid.unwrap_or("")),
        ("query_cid", query.cid),
        ("query_id", query.query_id),
      ] {
      @encode.key(writer, name)
      @encode.string_value(writer, value)
    }
    @encode.key(writer, "recovery_action")
    @encode.number_value(writer, recovery_action.to_double())
    @encode.key(writer, "report_cid")
    @encode.string_value(writer, query.report.report_cid)
    @encode.key(writer, "response_saved")
    @encode.bool_value(writer, response_saved)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-effect-current-reply/0.1")
    @encode.end_object(writer)
    let body = @encode.finish(writer)
    Ok({
      query,
      ledger_head_cid,
      recovery_action,
      response_saved,
      body,
      cid: "sha256:" + @sha.hex(@utf8.encode(body)),
    })
  } catch {
    _ => Err(InvalidDispatch)
  }
}

///|
/// An old reply for the same report is refused against a fresh query identity.
pub fn admit_remote_effect_current_reply_json(
  query : RemoteEffectCurrentQuery,
  body : String,
  limits : @checkpoint.WireLimits,
) -> Result[RemoteEffectCurrentReply, DispatchIssue] {
  if !effect_current_limits_valid(limits) ||
    body.length() > limits.max_wire_bytes {
    return Err(InvalidDispatch)
  }
  try {
    let fields = evidence_object(
      evidence_root(
        body,
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      ),
      [
        "checkpoint_cid", "dispatch_request_cid", "effect_id", "ledger_head_cid",
        "query_cid", "query_id", "recovery_action", "report_cid", "response_saved",
        "version",
      ],
    )
    if evidence_text(fields, "version") !=
      "actql-remote-effect-current-reply/0.1" ||
      evidence_text(fields, "checkpoint_cid") !=
      query.report.checkpoint.checkpoint_cid ||
      evidence_text(fields, "dispatch_request_cid") !=
      query.report.dispatch.dispatch_request_cid ||
      evidence_text(fields, "effect_id") != query.effect_id ||
      evidence_text(fields, "query_cid") != query.cid ||
      evidence_text(fields, "query_id") != query.query_id ||
      evidence_text(fields, "report_cid") != query.report.report_cid {
      raise EvidenceJsonStop
    }
    let head = evidence_text(fields, "ledger_head_cid")
    let response_saved = evidence_decoded(
      @decode.boolean(
        evidence_decoded(@decode.required(fields, "response_saved")),
      ),
    )
    let reply = match
      prepare_remote_effect_current_reply(
        query,
        if head.is_empty() {
          None
        } else {
          Some(head)
        },
        evidence_int(fields, "recovery_action"),
        response_saved,
        limits,
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    if reply.body != body {
      raise EvidenceJsonStop
    }
    Ok(reply)
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}

///|
pub fn remote_effect_current_query_json(
  query : RemoteEffectCurrentQuery,
) -> String {
  query.body
}

///|
pub fn remote_effect_current_query_identity(
  query : RemoteEffectCurrentQuery,
) -> String {
  query.cid
}

///|
pub fn remote_effect_current_query_id(
  query : RemoteEffectCurrentQuery,
) -> String {
  query.query_id
}

///|
pub fn remote_effect_current_query_report(
  query : RemoteEffectCurrentQuery,
) -> RemoteEffectCheckpointReport {
  query.report
}

///|
pub fn remote_effect_current_query_effect_id(
  query : RemoteEffectCurrentQuery,
) -> String {
  query.effect_id
}

///|
pub fn remote_effect_current_reply_json(
  reply : RemoteEffectCurrentReply,
) -> String {
  reply.body
}

///|
pub fn remote_effect_current_reply_identity(
  reply : RemoteEffectCurrentReply,
) -> String {
  reply.cid
}

///|
pub fn remote_effect_current_reply_query(
  reply : RemoteEffectCurrentReply,
) -> RemoteEffectCurrentQuery {
  reply.query
}

///|
pub fn remote_effect_current_reply_facts(
  reply : RemoteEffectCurrentReply,
) -> (String?, Int, Bool) {
  (reply.ledger_head_cid, reply.recovery_action, reply.response_saved)
}
