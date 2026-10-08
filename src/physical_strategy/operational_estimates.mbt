///|
/// A descriptive observation, never a prediction interval or dispatch grant.
pub(all) struct OperationalTimeReference {
  position : Int
  task : Int
  quantity : String
  median_ms : Double?
  minimum_ms : Double?
  maximum_ms : Double?
  sample_count : Int
  unknown_reason : String?
} derive(Eq, Debug)

///|
pub(all) struct OperationalEstimateSidecar {
  request : PolicyRequest
  conditions : OperationalEstimateConditions
  profile_revision : String
  oldest_ms : Int64
  newest_ms : Int64
  max_age_ms : Int64
  capture_ms : Double?
  references : Array[OperationalTimeReference]
} derive(Eq, Debug)

///|
fn estimate_number(
  object : @decode.ObjectView,
  key : String,
) -> Double? raise PolicyWireStop {
  let cursor = match @decode.lookup(object, key) {
    Some(value) => value
    None => raise PolicyWireStop
  }
  if @decode.is_null(cursor) {
    return None
  }
  let value = policy_wire_decoded(@decode.finite_number(cursor))
  if value < 0.0 {
    raise PolicyWireStop
  }
  Some(value)
}

///|
/// The Host authenticates the local producer independently and pins the
/// validated profile digest. No identity asserted by this body is authority.
pub fn admit_operational_estimate_sidecar_json(
  body : String,
  pending : PolicyRequest,
  candidates : PolicyCandidateSet,
  authenticated_issuer : String,
  expected_profile_revision : String,
  now_ms : Int64,
) -> Result[OperationalEstimateSidecar, SearchIssue] {
  try {
    let bytes = @utf8.encode(body)
    if bytes.length() > 65536 ||
      authenticated_issuer != "configured-local-profile-producer" ||
      @utf8.encode(authenticated_issuer).length() > 128 ||
      now_ms < 0L ||
      now_ms > pending.deadline_ms ||
      candidates.cid != pending.candidate_set_cid {
      raise PolicyWireStop
    }
    let node = match
      @source.parse_json_bytes(bytes, {
        max_input_bytes: 65536,
        max_nodes: 4096,
        max_depth: 8,
      }) {
      Ok(value) => value
      Err(_) => raise PolicyWireStop
    }
    let cursor = policy_wire_decoded(
      @decode.admit(node, {
        max_nodes: 4096,
        max_depth: 8,
        max_string_bytes: 1024,
        max_total_string_bytes: 65536,
      }),
    )
    let object = policy_wire_decoded(
      @decode.closed_object(cursor, [
        "version", "binding", "profile_revision", "conditions", "oldest_ms", "newest_ms",
        "max_age_ms", "capture_ms", "overhead", "entries", "candidate_snapshot_cid",
      ]),
    )
    if policy_wire_text(object, "version") != "actql-operational-estimate/0.1" ||
      policy_wire_text(object, "profile_revision") != expected_profile_revision ||
      expected_profile_revision.is_empty() ||
      @utf8.encode(expected_profile_revision).length() > 128 ||
      policy_wire_text(object, "candidate_snapshot_cid") != candidates.cid ||
      policy_wire_text(object, "overhead") != "unknown-no-off-comparison" {
      raise PolicyWireStop
    }
    let binding = policy_wire_decoded(
      @decode.closed_object(
        policy_wire_decoded(@decode.required(object, "binding")),
        [
          "version", "request_id", "run_identity", "authority", "candidate_set_cid",
          "generation", "revision", "deadline_ms",
        ],
      ),
    )
    if pending.version != "actql-placement-policy/0.1" ||
      policy_wire_text(binding, "version") != pending.version ||
      policy_wire_text(binding, "request_id") != pending.request_id ||
      policy_wire_text(binding, "run_identity") != pending.run_identity ||
      policy_wire_text(binding, "authority") != pending.authority ||
      policy_wire_text(binding, "candidate_set_cid") !=
      pending.candidate_set_cid ||
      policy_wire_int(binding, "generation") != pending.generation ||
      policy_wire_int(binding, "revision") != pending.revision ||
      policy_wire_text(binding, "deadline_ms") !=
      pending.deadline_ms.to_string() {
      raise PolicyWireStop
    }
    let conditions = policy_wire_decoded(
      @decode.closed_object(
        policy_wire_decoded(@decode.required(object, "conditions")),
        [
          "host", "realization", "captureMode", "runtimeRevision", "binaryDigest",
          "inputDigest", "programDigest", "inputRows", "schemaLayout", "limitsDigest",
          "instrumentationRevision", "measurementScopeRevision", "environmentDigest",
          "controlDigest", "concurrency", "processState", "osCache", "authorizedScope",
        ],
      ),
    )
    for
      name in [
        "host", "realization", "captureMode", "runtimeRevision", "binaryDigest",
        "inputDigest", "programDigest", "schemaLayout", "limitsDigest", "instrumentationRevision",
        "measurementScopeRevision", "environmentDigest", "controlDigest", "processState",
        "osCache", "authorizedScope",
      ] {
      let text = policy_wire_text(conditions, name)
      if text.is_empty() || @utf8.encode(text).length() > 128 {
        raise PolicyWireStop
      }
    }
    if !["off", "metadata-only", "evidence-enabled"].contains(
        policy_wire_text(conditions, "captureMode"),
      ) ||
      !["fresh", "resident"].contains(
        policy_wire_text(conditions, "realization"),
      ) ||
      policy_wire_text(conditions, "host") != "native" ||
      policy_wire_int(conditions, "concurrency") != 1 ||
      policy_wire_int(conditions, "inputRows") < 1 {
      raise PolicyWireStop
    }
    let oldest = policy_wire_decoded(
      @decode.decimal_int64(
        policy_wire_decoded(@decode.required(object, "oldest_ms")),
      ),
    )
    let newest = policy_wire_decoded(
      @decode.decimal_int64(
        policy_wire_decoded(@decode.required(object, "newest_ms")),
      ),
    )
    let age = policy_wire_decoded(
      @decode.decimal_int64(
        policy_wire_decoded(@decode.required(object, "max_age_ms")),
      ),
    )
    if oldest < 0L || newest < oldest || age < 1L || age > 86400000L {
      raise PolicyWireStop
    }
    let capture_ms = estimate_number(object, "capture_ms")
    let entries = policy_wire_decoded(
      @decode.elements(policy_wire_decoded(@decode.required(object, "entries"))),
    )
    if entries.length() > 64 {
      raise PolicyWireStop
    }
    // Positions are admitted from the exact immutable candidate bytes.
    let candidate_node = match
      @source.parse_json_bytes(@utf8.encode(candidates.canonical_json), {
        max_input_bytes: 8388608,
        max_nodes: 1000000,
        max_depth: 24,
      }) {
      Ok(value) => value
      Err(_) => raise PolicyWireStop
    }
    let candidate_cursor = policy_wire_decoded(
      @decode.admit(candidate_node, {
        max_nodes: 1000000,
        max_depth: 24,
        max_string_bytes: 1024,
        max_total_string_bytes: 8388608,
      }),
    )
    let assignments = policy_wire_decoded(
      @decode.elements(
        match @decode.element_at(candidate_cursor, 5) {
          Some(value) => value
          None => raise PolicyWireStop
        },
      ),
    )
    let references : Array[OperationalTimeReference] = []
    let seen : Set[String] = Set([])
    for entry in entries {
      let item = policy_wire_decoded(
        @decode.closed_object(entry, [
          "position", "task", "quantity", "status", "reason", "median_ms", "minimum_ms",
          "maximum_ms", "sample_count",
        ]),
      )
      let position = policy_wire_int(item, "position")
      let task = policy_wire_int(item, "task")
      let quantity = policy_wire_text(item, "quantity")
      let key = position.to_string() + ":" + task.to_string() + ":" + quantity
      if seen.contains(key) ||
        ![
          "task-processing", "task-release", "resident-preparation", "resident-import",
          "run-caller-elapsed",
        ].contains(quantity) {
        raise PolicyWireStop
      }
      seen.add(key)
      let mut found = false
      for assignment in assignments {
        let projected = policy_wire_decoded(@decode.elements(assignment))
        if projected.length() != 6 {
          raise PolicyWireStop
        }
        if policy_wire_decoded(@decode.int32(projected[0])) == position {
          let tasks = policy_wire_decoded(@decode.elements(projected[5]))
          if task > 0 && task < tasks.length() && !@decode.is_null(tasks[task]) {
            found = true
          }
        }
      }
      if !found {
        raise PolicyWireStop
      }
      references.push(
        decode_operational_reference(
          item,
          now_ms < newest || now_ms - oldest > age,
          policy_wire_text(conditions, "captureMode") == "off",
        ),
      )
    }
    Ok({
      request: pending,
      conditions: decode_operational_conditions(conditions),
      profile_revision: expected_profile_revision,
      oldest_ms: oldest,
      newest_ms: newest,
      max_age_ms: age,
      capture_ms,
      references,
    })
  } catch {
    _ => Err(InvalidPreference)
  }
}
