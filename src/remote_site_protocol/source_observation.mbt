///|
/// A bounded, dispatch-bound completed Source observation candidate. Its
/// Source identity, policy and capture interval must still be checked against
/// the original Run by the publication owner before issuing an Invocation.
/// Persistence or authenticated transport grants no acquisition authority.
struct RemoteSourceObservation {
  request_cid : String
  run_definition_cid : String
  task : Int
  source : @publication.RunEvidenceValue
  input : @publication.RunEvidenceValue
  started_at : String
  completed_at : String
  wire : String
}

///|
pub fn prepare_remote_source_observation(
  request : DispatchRequest,
  task : Int,
  source : @publication.RunEvidenceValue,
  input : @publication.RunEvidenceValue,
  started_at : String,
  completed_at : String,
) -> Result[RemoteSourceObservation, DispatchIssue] {
  if task < 0 ||
    started_at.is_empty() ||
    completed_at.is_empty() ||
    @utf8.encode(started_at).length() > 32 ||
    @utf8.encode(completed_at).length() > 32 {
    return Err(InvalidDispatch)
  }
  let source_wire = @publication.run_evidence_value_json(source)
  let input_wire = @publication.run_evidence_value_json(input)
  try {
    let facts = evidence_decoded(
      @decode.open_object(evidence_root(source_wire, 32768, 256, 16)),
    )
    if @publication.admit_completed_source_observation_binding(
        source,
        input,
        evidence_text(facts, "source_ref"),
        evidence_text(facts, "source_contract_cid"),
        evidence_text(facts, "authority_scope_cid"),
        evidence_text(facts, "effective_data_policy_cid"),
        32768,
        256,
        16,
      )
      is Err(_) {
      raise EvidenceJsonStop
    }
  } catch {
    EvidenceJsonStop => return Err(InvalidDispatch)
  }
  let writer = @encode.writer(131072, 32, 2) catch {
    _ => return Err(InvalidDispatch)
  }
  let wire = try {
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("capture_completed_at", completed_at),
        ("capture_started_at", started_at),
        ("dispatch_request_cid", request.dispatch_request_cid),
        ("input_logical_wire", input_wire),
        ("run_definition_cid", request.run_definition_cid),
        ("source_evidence_wire", source_wire),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.key(writer, "task_ordinal")
    @encode.number_value(writer, task.to_double())
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-remote-source-observation/0.1")
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(InvalidDispatch)
  }
  Ok({
    request_cid: request.dispatch_request_cid,
    run_definition_cid: request.run_definition_cid,
    task,
    source,
    input,
    started_at,
    completed_at,
    wire,
  })
}

///|
pub fn admit_remote_source_observation_json(
  wire : String,
  request : DispatchRequest,
) -> Result[RemoteSourceObservation, DispatchIssue] {
  try {
    let object = evidence_object(evidence_root(wire, 131072, 32, 2), [
      "capture_completed_at", "capture_started_at", "dispatch_request_cid", "input_logical_wire",
      "run_definition_cid", "source_evidence_wire", "task_ordinal", "version",
    ])
    if evidence_text(object, "version") != "actql-remote-source-observation/0.1" ||
      evidence_text(object, "dispatch_request_cid") !=
      request.dispatch_request_cid ||
      evidence_text(object, "run_definition_cid") != request.run_definition_cid {
      raise EvidenceJsonStop
    }
    let admit = fn(kind : String, field : String) raise EvidenceJsonStop {
      match
        @publication.admit_run_evidence_value(
          kind,
          evidence_text(object, field),
          32768,
          256,
          16,
        ) {
        Ok(value) => value
        Err(_) => raise EvidenceJsonStop
      }
    }
    let value = match
      prepare_remote_source_observation(
        request,
        evidence_int(object, "task_ordinal"),
        admit("source_evidence", "source_evidence_wire"),
        admit("source_input_logical", "input_logical_wire"),
        evidence_text(object, "capture_started_at"),
        evidence_text(object, "capture_completed_at"),
      ) {
      Ok(value) => value
      Err(_) => raise EvidenceJsonStop
    }
    if value.wire != wire {
      raise EvidenceJsonStop
    }
    Ok(value)
  } catch {
    EvidenceJsonStop => Err(InvalidDispatch)
  }
}

///|
pub fn remote_source_observation_matches_dispatch(
  value : RemoteSourceObservation,
  request : DispatchRequest,
) -> Bool {
  value.request_cid == request.dispatch_request_cid &&
  value.run_definition_cid == request.run_definition_cid
}

///|
pub fn remote_source_observation_json(
  value : RemoteSourceObservation,
) -> String {
  value.wire
}

///|
/// The exact original wires and interval, never replacement Run materials.
pub fn remote_source_observation_projection(
  value : RemoteSourceObservation,
) -> (Int, String, String, String, String) {
  (
    value.task,
    @publication.run_evidence_value_json(value.source),
    @publication.run_evidence_value_json(value.input),
    value.started_at,
    value.completed_at,
  )
}
