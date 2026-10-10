///|
/// Transport the existing seven-component request record. This is not a new
/// request issuer or current authorization; admission rechecks both saved CIDs.
pub fn client_request_identity_record_wire(
  request : ClientRequestIdentity,
) -> Result[String, ClientRequestIdentityIssue] {
  try {
    let writer = @encode.writer(4096, 32, 2)
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("authority_scope_cid", client_request_authority_scope_cid(request)),
        ("caller_input_intent_cid", client_request_input_cid(request)),
        ("caller_request_id", client_request_caller_id(request)),
        ("intent_fingerprint_cid", client_request_intent_cid(request)),
        ("logical_request_scope_cid", client_request_scope_cid(request)),
        ("parameter_values_cid", client_request_parameters_cid(request)),
        ("program_definition_cid", client_request_program_cid(request)),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(Encoding)
  }
}

///|
/// Re-admit an original saved record through the existing request identity
/// Owner. Closed bounded fields prevent missing, duplicate or extra metadata
/// from being silently substituted. No new caller id or scope is chosen.
pub fn admit_client_request_identity_record_wire(
  wire : String,
) -> Result[ClientRequestIdentity, ClientRequestIdentityIssue] {
  let source = match
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: 4096,
      max_nodes: 32,
      max_depth: 2,
    }) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  let root = match
    @decode.admit(source, {
      max_nodes: 32,
      max_depth: 2,
      max_string_bytes: 4096,
      max_total_string_bytes: 4096,
    }) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  let fields = [
    "authority_scope_cid", "caller_input_intent_cid", "caller_request_id", "intent_fingerprint_cid",
    "logical_request_scope_cid", "parameter_values_cid", "program_definition_cid",
  ]
  let object = match @decode.closed_object(root, fields) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  let text = name => {
    @decode.lookup(object, name).bind(cursor => @decode.text(cursor).to_option())
  }
  guard text("authority_scope_cid") is Some(authority) &&
    text("caller_input_intent_cid") is Some(input) &&
    text("caller_request_id") is Some(caller) &&
    text("intent_fingerprint_cid") is Some(intent) &&
    text("logical_request_scope_cid") is Some(scope) &&
    text("parameter_values_cid") is Some(parameters) &&
    text("program_definition_cid") is Some(program) else {
    return Err(Encoding)
  }
  admit_client_request_identity_record(
    authority, caller, program, parameters, input, scope, intent,
  )
}
