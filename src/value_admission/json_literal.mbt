///|
pub(all) enum JsonLiteralIssue {
  JsonLiteralParse(@source.ParseError)
  JsonLiteralAdmission(Issue)
} derive(Eq, Debug)

///|
/// Admit a typed JSON literal in the common Value owner, including JSON null.
/// Machine literal null remains SQL NULL. The source text and decoded payload
/// each meet the supplied ceilings; discarded duplicate values are parsed and
/// counted, rather than bypassing admission limits.
pub fn admit_json_literal(
  text : String,
  limits : Limits,
) -> Result[(CheckedValue, Int, Int), JsonLiteralIssue] {
  let parsed = match
    @source.parse_json_literal(text, {
      max_input_bytes: limits.max_text_bytes,
      max_nodes: limits.max_nodes,
      max_depth: Int::min(500, limits.max_depth),
    }) {
    Ok(parsed) => parsed
    Err(issue) => return Err(JsonLiteralParse(issue))
  }
  let root = match
    @decode.admit(parsed.node, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_text_bytes,
      max_total_string_bytes: limits.max_text_bytes,
    }) {
    Ok(root) => root
    Err(issue) => return Err(JsonLiteralAdmission(Decode(issue)))
  }
  let admission = match
    start_json_admission(root, limits, allow_json_null=true, data_keys=true) {
    Ok(admission) => admission
    Err(issue) => return Err(JsonLiteralAdmission(issue))
  }
  while true {
    match advance_json_admission(admission) {
      JsonAdmissionContinue => ()
      JsonAdmissionComplete(value, _, bytes) =>
        return Ok((value, parsed.usage.nodes, bytes))
      JsonAdmissionFailed(issue) => return Err(JsonLiteralAdmission(issue))
      JsonAdmissionTerminal => abort("JSON literal admission terminated")
    }
  } nobreak {
    abort("JSON literal admission stopped")
  }
}

///|
/// Read-only JSON payload access for common JSON consumers. An ordinary
/// scalar, closed object or SQL NULL cannot acquire a JSON domain this way.
pub fn json_payload(value : Value) -> Value? {
  match value {
    JsonData(payload) => Some(payload)
    _ => None
  }
}

///|
/// Validate an immutable raw JSON tree using the common resumable recheck.
/// Creating the cursor is not admission; only RecheckComplete issues a value.
pub fn start_json_payload_recheck(
  value : Value,
  limits : Limits,
) -> RecheckCursor? {
  start_recheck_runtime_value(
    JsonData(value),
    @contract.primitive(JsonType, nullable=false),
    limits,
  )
}

///|
pub fn recheck_json_payload_usage(
  value : Value,
  limits : Limits,
) -> (CheckedValue, Int, Int)? {
  guard start_json_payload_recheck(value, limits) is Some(cursor) else {
    return None
  }
  while true {
    match advance_recheck_runtime_value(cursor) {
      RecheckContinue => ()
      RecheckComplete(checked, nodes, bytes) =>
        return Some((checked, nodes, bytes))
      RecheckFailed => return None
    }
  } nobreak {
    None
  }
}
