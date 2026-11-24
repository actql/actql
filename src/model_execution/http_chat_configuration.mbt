///|
fn read_portable_model_http_configuration_value(
  body : Bytes,
  limits : @environment.Limits,
) -> @decode.Cursor? {
  guard @source.parse_json_bytes_preserving(body, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    })
    is Ok(node) &&
    @decode.admit(node, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    })
    is Ok(value) else {
    return None
  }
  Some(value)
}

///|
/// Read nonsecret route data from a previously selected installation file.
/// The caller funds parsing and supplies the adopted file identities.
/// Provider binding, credential custody and dispatch remain separate.
pub fn read_portable_model_http_chat_file_route(
  body : Bytes,
  provider_id : String,
  revision_cid : String,
  contract_cid : String,
  profile_cid : String,
  credential_file : String,
  limits : @environment.Limits,
) -> ResolvedStructuredModel? {
  guard read_portable_model_http_configuration_value(body, limits)
    is Some(value) &&
    @decode.open_object(value) is Ok(object) else {
    return None
  }
  for
    (field, expected) in [
      ("installation_revision_cid", revision_cid),
      ("configuration_contract_cid", contract_cid),
      ("response_profile_cid", profile_cid),
      ("credential_ref", "file:" + credential_file),
      ("provider_id", provider_id),
      ("adapter_kind", "portable-http"),
      ("api_mode", "chat-completions"),
    ] {
    guard @decode.lookup(object, field) is Some(original) &&
      @decode.text(original) == Ok(expected) else {
      return None
    }
  }
  guard @decode.lookup(object, "selector").bind(value => {
      @decode.text(value).to_option()
    })
    is Some(selector) &&
    !selector.is_empty() &&
    @decode.lookup(object, "model_id").bind(value => {
      @decode.text(value).to_option()
    })
    is Some(model_id) &&
    !model_id.is_empty() &&
    @decode.lookup(object, "endpoint").bind(value => {
      @decode.text(value).to_option()
    })
    is Some(endpoint) &&
    endpoint.has_prefix("https://") else {
    return None
  }
  Some({
    selector,
    model_id,
    adapter_kind: "portable-http",
    api_mode: "chat-completions",
    endpoint,
  })
}

///|
/// Read the closed bundle used by the existing execution and dependency
/// readers. The embedded documents stay as original wire data.
pub fn read_portable_model_http_execution_wires(
  bytes : Bytes,
  limits : @environment.Limits,
) -> (String, String, String, String, String)? {
  guard read_portable_model_http_configuration_value(bytes, limits)
    is Some(value) &&
    @decode.closed_object(value, [
      "contract_cid", "contract", "prompt", "retry_policy", "backoff",
    ])
    is Ok(fields) &&
    @decode.lookup(fields, "contract_cid") is Some(cid) &&
    @decode.text(cid) is Ok(cid) &&
    @decode.lookup(fields, "contract") is Some(contract) &&
    @decode.text(contract) is Ok(contract) &&
    @decode.lookup(fields, "prompt") is Some(prompt) &&
    @decode.text(prompt) is Ok(prompt) &&
    @decode.lookup(fields, "retry_policy") is Some(retry) &&
    @decode.text(retry) is Ok(retry) &&
    @decode.lookup(fields, "backoff") is Some(backoff) &&
    @decode.text(backoff) is Ok(backoff) else {
    return None
  }
  Some((cid, contract, prompt, retry, backoff))
}
