///|
/// Validated unbound metadata. The trusted local adapter supplies and pins the
/// original; this header grants neither candidate membership nor authority.
pub(all) struct OperationalProfileTemplateHeader {
  profile_revision : String
  candidate_snapshot_cid : String
  conditions : OperationalEstimateConditions
  oldest_ms : Int64
  newest_ms : Int64
  max_age_ms : Int64
} derive(Eq, Debug)

///|
pub fn operational_profile_template_header(
  template : String,
) -> Result[OperationalProfileTemplateHeader, SearchIssue] {
  try {
    let bytes = @utf8.encode(template)
    if bytes.length() > 61440 {
      raise PolicyWireStop
    }
    let node = match
      @source.parse_json_bytes(bytes, {
        max_input_bytes: 61440,
        max_nodes: 4096,
        max_depth: 8,
      }) {
      Ok(v) => v
      Err(_) => raise PolicyWireStop
    }
    let cursor = policy_wire_decoded(
      @decode.admit(node, {
        max_nodes: 4096,
        max_depth: 8,
        max_string_bytes: 1024,
        max_total_string_bytes: 61440,
      }),
    )
    let root = policy_wire_decoded(
      @decode.closed_object(cursor, [
        "version", "profile_revision", "candidate_snapshot_cid", "conditions", "oldest_ms",
        "newest_ms", "max_age_ms", "capture_ms", "overhead", "entries",
      ]),
    )
    if policy_wire_text(root, "version") != "actql-operational-estimate/0.1" ||
      policy_wire_text(root, "overhead") != "unknown-no-off-comparison" {
      raise PolicyWireStop
    }
    let conditions = decode_operational_conditions(
      policy_wire_decoded(
        @decode.closed_object(
          policy_wire_decoded(@decode.required(root, "conditions")),
          [
            "host", "realization", "captureMode", "runtimeRevision", "binaryDigest",
            "inputDigest", "programDigest", "inputRows", "schemaLayout", "limitsDigest",
            "instrumentationRevision", "measurementScopeRevision", "environmentDigest",
            "controlDigest", "concurrency", "processState", "osCache", "authorizedScope",
          ],
        ),
      ),
    )
    let oldest = policy_wire_decoded(
      @decode.decimal_int64(
        policy_wire_decoded(@decode.required(root, "oldest_ms")),
      ),
    )
    let newest = policy_wire_decoded(
      @decode.decimal_int64(
        policy_wire_decoded(@decode.required(root, "newest_ms")),
      ),
    )
    let age = policy_wire_decoded(
      @decode.decimal_int64(
        policy_wire_decoded(@decode.required(root, "max_age_ms")),
      ),
    )
    let profile = policy_wire_text(root, "profile_revision")
    let candidate = policy_wire_text(root, "candidate_snapshot_cid")
    if oldest < 0L ||
      newest < oldest ||
      age < 1L ||
      age > 86400000L ||
      profile.is_empty() ||
      candidate.is_empty() ||
      @utf8.encode(profile).length() > 128 ||
      @utf8.encode(candidate).length() > 128 {
      raise PolicyWireStop
    }
    estimate_number(root, "capture_ms") |> ignore
    let entries = policy_wire_decoded(
      @decode.elements(policy_wire_decoded(@decode.required(root, "entries"))),
    )
    if entries.length() > 64 {
      raise PolicyWireStop
    }
    let seen : Set[String] = Set([])
    for entry in entries {
      let item = policy_wire_decoded(
        @decode.closed_object(entry, [
          "position", "task", "quantity", "status", "reason", "median_ms", "minimum_ms",
          "maximum_ms", "sample_count",
        ]),
      )
      let reference = decode_operational_reference(item, false, false)
      let key = reference.position.to_string() +
        ":" +
        reference.task.to_string() +
        ":" +
        reference.quantity
      if seen.contains(key) {
        raise PolicyWireStop
      }
      seen.add(key)
    }
    Ok({
      profile_revision: profile,
      candidate_snapshot_cid: candidate,
      conditions,
      oldest_ms: oldest,
      newest_ms: newest,
      max_age_ms: age,
    })
  } catch {
    _ => Err(InvalidPreference)
  }
}

///|
/// Add only the current Owner-issued binding to a validated immutable template.
/// Ordinary sidecar admission still checks every entry against current offers.
pub fn bind_operational_profile_template(
  template : String,
  request : PolicyRequest,
) -> Result[String, SearchIssue] {
  match operational_profile_template_header(template) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let wire = match placement_policy_request_json(request) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  guard template.trim().strip_prefix("{") is Some(body) else {
    return Err(InvalidPreference)
  }
  Ok("{\"binding\":" + wire + "," + body.to_owned())
}
