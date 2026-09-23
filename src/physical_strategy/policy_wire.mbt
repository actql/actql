///|
/// This is the public transport body, not the authority to select a strategy.
/// A Host authenticates the policy peer before admitting its response here.
pub fn placement_policy_request_json(
  request : PolicyRequest,
) -> Result[String, SearchIssue] {
  let writer = @encode.writer(4096, 24, 2) catch {
    _ => return Err(InvalidPreference)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "authority")
    @encode.string_value(writer, request.authority)
    @encode.key(writer, "candidate_set_cid")
    @encode.string_value(writer, request.candidate_set_cid)
    @encode.key(writer, "deadline_ms")
    @encode.string_value(writer, request.deadline_ms.to_string())
    @encode.key(writer, "generation")
    @encode.number_value(writer, request.generation.to_double())
    @encode.key(writer, "request_id")
    @encode.string_value(writer, request.request_id)
    @encode.key(writer, "revision")
    @encode.number_value(writer, request.revision.to_double())
    @encode.key(writer, "run_identity")
    @encode.string_value(writer, request.run_identity)
    @encode.key(writer, "version")
    @encode.string_value(writer, request.version)
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(InvalidPreference)
  }
}

///|
priv suberror PolicyWireStop {
  PolicyWireStop
}

///|
fn[T] policy_wire_decoded(
  value : Result[T, @decode.Issue],
) -> T raise PolicyWireStop {
  match value {
    Ok(result) => result
    Err(_) => raise PolicyWireStop
  }
}

///|
fn policy_wire_text(
  object : @decode.ObjectView,
  name : String,
) -> String raise PolicyWireStop {
  policy_wire_decoded(
    @decode.text(policy_wire_decoded(@decode.required(object, name))),
  )
}

///|
fn policy_wire_int(
  object : @decode.ObjectView,
  name : String,
) -> Int raise PolicyWireStop {
  let value = policy_wire_decoded(
    @decode.safe_integer(policy_wire_decoded(@decode.required(object, name))),
  )
  if value < 0L || value > 2147483647L {
    raise PolicyWireStop
  }
  value.to_int()
}

///|
/// Parse a closed, bounded decision and bind every echoed field to the exact
/// pending request. `authenticated_policy_id` must come from the Host's peer
/// authentication, never from this JSON. Commit still checks freshness,
/// registration and the current resource snapshot.
pub fn admit_placement_policy_response_json(
  body : String,
  pending : PolicyRequest,
  authenticated_policy_id : String,
) -> Result[PolicyResponse, SearchIssue] {
  try {
    let bytes = @utf8.encode(body)
    if bytes.length() > 4096 || authenticated_policy_id.is_empty() {
      raise PolicyWireStop
    }
    let source = match
      @source.parse_json_bytes(bytes, {
        max_input_bytes: 4096,
        max_nodes: 32,
        max_depth: 2,
      }) {
      Ok(value) => value
      Err(_) => raise PolicyWireStop
    }
    let cursor = policy_wire_decoded(
      @decode.admit(source, {
        max_nodes: 32,
        max_depth: 2,
        max_string_bytes: 1024,
        max_total_string_bytes: 4096,
      }),
    )
    let object = policy_wire_decoded(
      @decode.closed_object(cursor, [
        "authority", "candidate_set_cid", "deadline_ms", "explanation", "generation",
        "policy_id", "policy_revision", "position", "request_id", "revision", "run_identity",
        "version",
      ]),
    )
    if policy_wire_text(object, "version") != pending.version ||
      pending.version != "actql-placement-policy/0.1" ||
      policy_wire_text(object, "request_id") != pending.request_id ||
      policy_wire_text(object, "run_identity") != pending.run_identity ||
      policy_wire_text(object, "authority") != pending.authority ||
      policy_wire_text(object, "candidate_set_cid") != pending.candidate_set_cid ||
      policy_wire_text(object, "deadline_ms") != pending.deadline_ms.to_string() ||
      policy_wire_int(object, "generation") != pending.generation ||
      policy_wire_int(object, "revision") != pending.revision {
      raise PolicyWireStop
    }
    let policy_id = policy_wire_text(object, "policy_id")
    if policy_id != authenticated_policy_id {
      raise PolicyWireStop
    }
    Ok({
      request: pending,
      position: policy_wire_int(object, "position"),
      policy_id,
      policy_revision: policy_wire_text(object, "policy_revision"),
      explanation: policy_wire_text(object, "explanation"),
    })
  } catch {
    _ => Err(InvalidPreference)
  }
}
