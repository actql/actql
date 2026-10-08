///|
/// A diagnostic proposal over existing assignments. No reservation or authority.
pub(all) struct EmpiricalRanking {
  request : PolicyRequest
  profile_revision : String
  policy_revision : String
  task : Int
  positions : Array[Int]
  selected_position : Int?
  reason : String
} derive(Eq, Debug)

///|
/// Minimize the descriptive median of the explicitly requested measured quantity.
/// Positions are presented complete assignments, not a global search optimum.
/// Every presented position must have a usable reference. Ties use position.
pub fn rank_operational_candidates(
  candidates : PolicyCandidateSet,
  sidecar : OperationalEstimateSidecar,
  task : Int,
  policy_revision : String,
  now_ms : Int64,
  quantity? : String = "task-processing",
) -> Result[EmpiricalRanking, SearchIssue] {
  try {
    if !["task-processing", "run-caller-elapsed"].contains(quantity) ||
      candidates.cid != sidecar.request.candidate_set_cid ||
      task < 1 ||
      sidecar.oldest_ms < 0L ||
      sidecar.newest_ms < sidecar.oldest_ms ||
      sidecar.max_age_ms < 1L ||
      sidecar.max_age_ms > 86400000L ||
      sidecar.references.length() > 64 ||
      now_ms < 0L ||
      now_ms > sidecar.request.deadline_ms ||
      policy_revision.is_empty() ||
      @utf8.encode(policy_revision).length() > 128 {
      raise PolicyWireStop
    }
    let node = match
      @source.parse_json_bytes(@utf8.encode(candidates.canonical_json), {
        max_input_bytes: 8388608,
        max_nodes: 1000000,
        max_depth: 24,
      }) {
      Ok(value) => value
      Err(_) => raise PolicyWireStop
    }
    let cursor = policy_wire_decoded(
      @decode.admit(node, {
        max_nodes: 1000000,
        max_depth: 24,
        max_string_bytes: 1024,
        max_total_string_bytes: 8388608,
      }),
    )
    let assignments = policy_wire_decoded(
      @decode.elements(
        match @decode.element_at(cursor, 5) {
          Some(value) => value
          None => raise PolicyWireStop
        },
      ),
    )
    let positions : Array[Int] = []
    for assignment in assignments {
      let fields = policy_wire_decoded(@decode.elements(assignment))
      if fields.length() != 6 {
        raise PolicyWireStop
      }
      let tasks = policy_wire_decoded(@decode.elements(fields[5]))
      if task >= tasks.length() || @decode.is_null(tasks[task]) {
        raise PolicyWireStop
      }
      let position = policy_wire_decoded(@decode.int32(fields[0]))
      if position < 0 || positions.contains(position) {
        raise PolicyWireStop
      }
      positions.push(position)
    }
    // This local pilot has an explicit finite comparison ceiling. A larger
    // presented set remains intact and receives no empirical proposal.
    let base : EmpiricalRanking = {
      request: sidecar.request,
      profile_revision: sidecar.profile_revision,
      policy_revision,
      task,
      positions,
      selected_position: None,
      reason: "incomplete-reference",
    }
    if positions.length() == 0 || positions.length() > 64 {
      return Ok({ ..base, reason: "comparison-limit", })
    }
    if positions.length() == 1 {
      return Ok({ ..base, reason: "single-candidate", })
    }
    if now_ms < sidecar.newest_ms ||
      now_ms - sidecar.oldest_ms > sidecar.max_age_ms {
      return Ok({ ..base, reason: "freshness-insufficient", })
    }
    let mut best : (Int, Double)? = None
    for position in positions {
      let references = sidecar.references.filter(reference => {
        reference.task == task &&
        reference.position == position &&
        reference.quantity == quantity
      })
      if references.length() != 1 {
        return Ok(base)
      }
      let reference = references[0]
      guard reference.median_ms is Some(duration) &&
        duration >= 0.0 &&
        duration - duration == 0.0 &&
        reference.unknown_reason is None &&
        reference.sample_count >= 3 else {
        return Ok(base)
      }
      match best {
        None => best = Some((position, duration))
        Some((current, elapsed)) =>
          if duration < elapsed || (duration == elapsed && position < current) {
            best = Some((position, duration))
          }
      }
    }
    Ok({
      ..base,
      selected_position: Some(best.unwrap().0),
      reason: quantity + "-median",
    })
  } catch {
    _ => Err(InvalidPreference)
  }
}

///|
/// Encode the existing closed policy response; a score cannot add fields.
pub fn placement_policy_response_json(
  response : PolicyResponse,
) -> Result[String, SearchIssue] {
  let request_json = match placement_policy_request_json(response.request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let writer = @encode.writer(4096, 32, 2) catch {
    _ => return Err(InvalidPreference)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "explanation")
    @encode.string_value(writer, response.explanation)
    @encode.key(writer, "policy_id")
    @encode.string_value(writer, response.policy_id)
    @encode.key(writer, "policy_revision")
    @encode.string_value(writer, response.policy_revision)
    @encode.key(writer, "position")
    @encode.number_value(writer, response.position.to_double())
    @encode.end_object(writer)
    let fields = @encode.finish(writer)
    let body = request_json.strip_suffix("}").unwrap().to_owned() +
      "," +
      fields.strip_prefix("{").unwrap().to_owned()
    // Use the existing decoder to enforce its byte/string/field ceilings.
    match
      admit_placement_policy_response_json(
        body,
        response.request,
        response.policy_id,
      ) {
      Ok(_) => Ok(body)
      Err(issue) => Err(issue)
    }
  } catch {
    _ => Err(InvalidPreference)
  }
}
