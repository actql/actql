///|
/// Exact Coordinator output state retained beside one durable dispatch.
/// This internal record carries an admitted Site plan, not a public Result.
struct DurableCoordinatorOutputRecord {
  output : RemotePollOutput
  plan : RemoteOutputPlan
  revision : Int
  progress_code : Int
  result_json : String
  body : String
}

///|
/// Re-admit all Site-supplied plan bodies against the durable dispatch output
/// before allowing the Coordinator to persist an output occurrence.
pub fn admit_coordinator_output_plan(
  dispatch : DurableCoordinatorDispatchRecord,
  poll_body : String,
  plan_body : String,
  expected_result_definition_cid : String,
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_referenced_bytes : Int64,
) -> Result[(RemotePollOutput, RemoteOutputPlan), DispatchIssue] {
  let output = match admit_remote_poll_output_plan_json(poll_body) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let request = remote_poll_output_request(output)
  let retained = durable_coordinator_dispatch_record_request(dispatch)
  if dispatch_request_identity(request) != dispatch_request_identity(retained) ||
    remote_output_intent_projection(remote_poll_output_intent(output)).result_definition_cid !=
    expected_result_definition_cid {
    return Err(DispatchIdentityMismatch)
  }
  guard durable_coordinator_dispatch_record_evidence(dispatch) is Some(evidence) &&
    durable_coordinator_dispatch_record_subject(dispatch) is Some(subject) &&
    durable_coordinator_dispatch_record_measurement(dispatch)
    is Some(measurement) else {
    return Err(InvalidJournal)
  }
  if !remote_managed_output_subject_matches_evidence(subject, evidence, request) ||
    !remote_managed_output_subject_matches_measurement(subject, measurement) {
    return Err(InvalidJournal)
  }
  let plan = match
    admit_remote_output_plan_json(
      plan_body, output, subject, max_chunks, max_manifest_bytes, max_referenced_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok((output, plan))
}

///|
fn emit_durable_coordinator_output_record(
  output : RemotePollOutput,
  plan : RemoteOutputPlan,
  revision : Int,
  progress_code : Int,
  result_json : String,
) -> Result[String, DispatchIssue] {
  if revision < 0 ||
    revision > 2147483647 ||
    coordinator_output_progress_from_code(progress_code) is Err(_) ||
    (revision == 0) != (progress_code == 0) ||
    (progress_code == 2) != !result_json.is_empty() {
    return Err(InvalidJournal)
  }
  let poll_body = match
    remote_poll_output_plan_json(output.request, output.intent) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let plan_body = match remote_output_plan_json(plan) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let result_cid = if result_json.is_empty() {
    ""
  } else {
    let result = match
      admit_remote_output_result_json(
        result_json,
        output,
        plan.payload_request,
        plan.transfer_request,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    remote_output_result_identity(result)
  }
  let writer = @encode.writer(4194304, 64, 2) catch {
    _ => return Err(InvalidJournal)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "dispatch_request_cid")
    @encode.string_value(writer, dispatch_request_identity(output.request))
    @encode.key(writer, "output_intent_cid")
    @encode.string_value(writer, remote_output_intent_identity(output.intent))
    @encode.key(writer, "output_plan_cid")
    @encode.string_value(writer, remote_output_plan_identity(plan))
    @encode.key(writer, "output_plan_json")
    @encode.string_value(writer, plan_body)
    @encode.key(writer, "output_poll_json")
    @encode.string_value(writer, poll_body)
    @encode.key(writer, "progress_state")
    @encode.number_value(writer, progress_code.to_double())
    @encode.key(writer, "result_cid")
    @encode.string_value(writer, result_cid)
    @encode.key(writer, "result_json")
    @encode.string_value(writer, result_json)
    @encode.key(writer, "revision")
    @encode.number_value(writer, revision.to_double())
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-coordinator-output-record/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidJournal)
  }
  Ok(@encode.finish(writer) catch { _ => return Err(InvalidJournal) })
}

///|
pub fn coordinator_output_admission_durable_json(
  output : RemotePollOutput,
  plan : RemoteOutputPlan,
) -> Result[String, DispatchIssue] {
  match prepare_durable_coordinator_output_record(output, plan) {
    Ok(value) => Ok(value.body)
    Err(issue) => Err(issue)
  }
}

///|
pub fn prepare_durable_coordinator_output_record(
  output : RemotePollOutput,
  plan : RemoteOutputPlan,
) -> Result[DurableCoordinatorOutputRecord, DispatchIssue] {
  if !output_expected_inputs_valid(
      output,
      plan.payload_request,
      plan.transfer_request,
    ) {
    return Err(InvalidDispatch)
  }
  match emit_durable_coordinator_output_record(output, plan, 0, 0, "") {
    Ok(body) => Ok({
      output,
      plan,
      revision: 0,
      progress_code: 0,
      result_json: "",
      body,
    })
    Err(issue) => Err(issue)
  }
}

///|
pub fn admit_durable_coordinator_output_record(
  bytes : Bytes,
  dispatch : DurableCoordinatorDispatchRecord,
  expected_result_definition_cid : String,
  max_chunks : Int,
  max_manifest_bytes : Int,
  max_referenced_bytes : Int64,
) -> Result[DurableCoordinatorOutputRecord, DispatchIssue] {
  try {
    let body = @utf8.decode(bytes) catch { _ => raise EvidenceJsonStop }
    let object = evidence_object(evidence_root(body, 4194304, 64, 2), [
      "dispatch_request_cid", "output_intent_cid", "output_plan_cid", "output_plan_json",
      "output_poll_json", "progress_state", "result_cid", "result_json", "revision",
      "version",
    ])
    if evidence_text(object, "version") !=
      "actql-remote-coordinator-output-record/0.1" {
      raise EvidenceJsonStop
    }
    let poll_body = evidence_text(object, "output_poll_json")
    let plan_body = evidence_text(object, "output_plan_json")
    let (output, plan) = match
      admit_coordinator_output_plan(
        dispatch, poll_body, plan_body, expected_result_definition_cid, max_chunks,
        max_manifest_bytes, max_referenced_bytes,
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    if evidence_text(object, "dispatch_request_cid") !=
      dispatch_request_identity(output.request) ||
      evidence_text(object, "output_intent_cid") !=
      remote_output_intent_identity(output.intent) ||
      evidence_text(object, "output_plan_cid") !=
      remote_output_plan_identity(plan) {
      raise EvidenceJsonStop
    }
    let revision = evidence_int(object, "revision")
    let progress_code = evidence_int(object, "progress_state")
    let result_json = evidence_text(object, "result_json")
    let canonical = match
      emit_durable_coordinator_output_record(
        output, plan, revision, progress_code, result_json,
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    if canonical != body {
      raise EvidenceJsonStop
    }
    let journal = match
      create_coordinator_dispatch_journal(output.request.coordinator_authority) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    if restore_durable_coordinator_dispatch_record(journal, dispatch) is Err(_) {
      raise EvidenceJsonStop
    }
    let admission = match
      prepare_coordinator_output_intent(
        journal,
        output,
        plan.payload_request,
        plan.transfer_request,
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    let record = match commit_coordinator_output_intent(admission, true) {
      Ok((_, value)) => value
      Err(_) => raise EvidenceJsonStop
    }
    if restore_coordinator_output_record(
        record, revision, progress_code, result_json,
      )
      is Err(_) {
      raise EvidenceJsonStop
    }
    Ok({ output, plan, revision, progress_code, result_json, body, })
  } catch {
    EvidenceJsonStop => Err(InvalidJournal)
  }
}

///|
pub fn restore_durable_coordinator_output_record(
  journal : CoordinatorDispatchJournal,
  durable : DurableCoordinatorOutputRecord,
) -> Result[CoordinatorOutputRecord, DispatchIssue] {
  let admission = match
    prepare_coordinator_output_intent(
      journal,
      durable.output,
      durable.plan.payload_request,
      durable.plan.transfer_request,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let record = match commit_coordinator_output_intent(admission, true) {
    Ok((_, value)) => value
    Err(issue) => return Err(issue)
  }
  if coordinator_output_record_status(record) ==
    [
      durable.revision.to_string(),
      durable.progress_code.to_string(),
      if durable.result_json.is_empty() {
        ""
      } else {
        let result = match
          admit_remote_output_result_json(
            durable.result_json,
            durable.output,
            durable.plan.payload_request,
            durable.plan.transfer_request,
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        remote_output_result_identity(result)
      },
    ] {
    return Ok(record)
  }
  restore_coordinator_output_record(
    record,
    durable.revision,
    durable.progress_code,
    durable.result_json,
  )
}

///|
pub fn durable_coordinator_output_record_json(
  durable : DurableCoordinatorOutputRecord,
) -> String {
  durable.body
}

///|
/// Reissue the exact admitted poll after a Coordinator process restart.
pub fn durable_coordinator_output_record_poll_json(
  durable : DurableCoordinatorOutputRecord,
) -> Result[String, DispatchIssue] {
  remote_poll_output_plan_json(durable.output.request, durable.output.intent)
}

///|
/// Re-admit a physical reply only against the Transfer request in this
/// retained Output Plan. This is evidence, not proof of local payload custody.
pub fn durable_coordinator_output_admit_transfer_reply_json(
  durable : DurableCoordinatorOutputRecord,
  reply : String,
) -> Result[String, DispatchIssue] {
  let record = match
    @transfer.admit_remote_transfer_reply_json(
      reply, durable.plan.transfer_request,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidDispatch)
  }
  if !@transfer.record_is_destination_committed(record) {
    return Err(InvalidDispatch)
  }
  match @transfer.remote_transfer_reply_json(record) {
    Ok(body) if body == reply => Ok(body)
    _ => Err(InvalidDispatch)
  }
}

///|
/// The caller supplies an independently checked physical payload digest.
/// Neither the Site reply nor its receipt establishes the local bytes alone.
pub fn durable_coordinator_output_prepare_result_json(
  durable : DurableCoordinatorOutputRecord,
  reply : String,
  payload_physical_digest : String,
) -> Result[String, DispatchIssue] {
  if durable_coordinator_output_admit_transfer_reply_json(durable, reply)
    is Err(_) {
    return Err(InvalidDispatch)
  }
  let record = match
    @transfer.admit_remote_transfer_reply_json(
      reply, durable.plan.transfer_request,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidDispatch)
  }
  let result = match
    prepare_remote_output_result(
      durable.output,
      durable.plan.payload_request,
      payload_physical_digest,
      record,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  remote_output_result_json(result)
}

///|
pub fn durable_coordinator_output_record_revision(
  durable : DurableCoordinatorOutputRecord,
) -> Int {
  durable.revision
}

///|
pub fn coordinator_output_transition_expected_revision(
  transition : CoordinatorOutputTransition,
) -> Int {
  transition.record.revision
}

///|
/// Issue the next exact durable body only for a transition prepared against
/// the retained record represented by this durable body.
pub fn coordinator_output_transition_durable_json(
  durable : DurableCoordinatorOutputRecord,
  transition : CoordinatorOutputTransition,
) -> Result[String, DispatchIssue] {
  match advance_durable_coordinator_output_record(durable, transition) {
    Ok(value) => Ok(value.body)
    Err(issue) => Err(issue)
  }
}

///|
pub fn advance_durable_coordinator_output_record(
  durable : DurableCoordinatorOutputRecord,
  transition : CoordinatorOutputTransition,
) -> Result[DurableCoordinatorOutputRecord, DispatchIssue] {
  if coordinator_output_record_projection(transition.record) !=
    transition.expected ||
    transition.record.revision != durable.revision ||
    transition.expected != [
      durable.revision.to_string(),
      durable.progress_code.to_string(),
      if durable.result_json.is_empty() {
        ""
      } else {
        let result = match
          admit_remote_output_result_json(
            durable.result_json,
            durable.output,
            durable.plan.payload_request,
            durable.plan.transfer_request,
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        remote_output_result_identity(result)
      },
    ] ||
    !coordinator_output_matches(
      transition.record,
      durable.output,
      durable.plan.payload_request,
      durable.plan.transfer_request,
    ) ||
    transition.next[0] != (durable.revision + 1).to_string() ||
    transition.next[1] !=
    coordinator_output_progress_code(transition.next_progress).to_string() ||
    transition.next[2] !=
    coordinator_output_result_identity_or_empty(transition.next_result) {
    return Err(StateCollision)
  }
  let result_json = match transition.next_result {
    Some(value) => match remote_output_result_json(value) {
      Ok(body) => body
      Err(issue) => return Err(issue)
    }
    None => ""
  }
  let progress_code = coordinator_output_progress_code(
    transition.next_progress,
  )
  match emit_durable_coordinator_output_record(
      durable.output,
      durable.plan,
      durable.revision + 1,
      progress_code,
      result_json,
    ) {
    Ok(body) => Ok({
      output: durable.output,
      plan: durable.plan,
      revision: durable.revision + 1,
      progress_code,
      result_json,
      body,
    })
    Err(issue) => Err(issue)
  }
}
