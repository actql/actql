///|
/// Pure identities from an already admitted implementation descriptor. The
/// selected Source capability and actual provider remain Host-owned duties.
pub fn native_file_read_profile_contract_bindings(
  profile : PublicationContract,
) -> (String, String, String)? {
  guard profile.name == "native_file_content_read" &&
    optional_string(
      @json.object_field(profile.value, "source_view_contract_cid"),
    )
    is Some(source) &&
    optional_string(@json.object_field(profile.value, "request_schema_cid"))
    is Some(request) &&
    optional_string(@json.object_field(profile.value, "response_schema_cid"))
    is Some(response) else {
    return None
  }
  Some((source, request, response))
}

///|
/// The actual existing Native reader performs single-key version-checked file
/// reads, without pagination or retry. This closes only its implementation
/// transport DATA; neither an HTTP profile nor another execution is implied.
/// Caller same-parent backing precedes construction. The original measured
/// static document is embedded unchanged, without re-observing its Ref fields.
pub fn issue_native_file_lookup_transport(
  profile : PublicationContract,
  static_request : @encode.EncodedDocument,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, PublicationContractIssue] {
  guard native_file_read_profile_contract_bindings(profile)
    is Some((source, request, response)) else {
    return Err(InvalidField("native_file_read_profile"))
  }
  let body = try {
    let w = @encode.writer(max_bytes, max_nodes, max_depth)
    @encode.begin_object(w)
    for
      (key, value) in [
        ("adapter_contract_cid", profile.identity),
        ("request_schema_cid", request),
        ("response_schema_cid", response),
        ("source_view_contract_cid", source),
        ("version", "actql-lookup-transport-plan/0.1"),
      ] {
      @encode.key(w, key)
      @encode.string_value(w, value)
    }
    @encode.key(w, "static_request_values")
    @encode.emit_document(w, static_request)
    @encode.key(w, "batching")
    @encode.begin_object(w)
    @encode.key(w, "kind")
    @encode.string_value(w, "single")
    @encode.key(w, "max_keys_per_batch")
    @encode.number_value(w, 1.0)
    @encode.end_object(w)
    @encode.key(w, "pagination")
    @encode.begin_object(w)
    @encode.key(w, "kind")
    @encode.string_value(w, "none")
    @encode.key(w, "max_pages_per_batch")
    @encode.number_value(w, 1.0)
    @encode.key(w, "token_contract")
    @encode.null_value(w)
    @encode.end_object(w)
    @encode.key(w, "retry")
    @encode.begin_object(w)
    @encode.key(w, "max_network_attempts_per_request")
    @encode.number_value(w, 1.0)
    @encode.key(w, "retryable_error_codes")
    @encode.begin_array(w)
    @encode.end_array(w)
    @encode.end_object(w)
    @encode.end_object(w)
    @encode.finish(w)
  } catch {
    _ => return Err(Encoding)
  }
  seal_publication_contract(
    "native_file_lookup_transport", body, max_bytes, max_nodes, max_depth,
  )
}
