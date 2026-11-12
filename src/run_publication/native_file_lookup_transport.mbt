///|
/// Pure identities from an already admitted implementation descriptor. The
/// selected Source capability and actual provider remain Host-owned duties.
pub fn file_read_profile_contract_bindings(
  profile : PublicationContract,
) -> (String, String, String)? {
  guard ["native_file_content_read", "declared_file_content_read"].contains(
      profile.name,
    ) &&
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
/// Original physical SourceView identity of this admitted file descriptor.
/// It selects an immutable body, never permission to read that Source.
pub fn file_read_profile_physical_source_contract_cid(
  profile : PublicationContract,
) -> String? {
  if !["native_file_content_read", "declared_file_content_read"].contains(
      profile.name,
    ) {
    return None
  }
  optional_string(
    @json.object_field(profile.value, "physical_source_view_contract_cid"),
  )
}

///|
/// The selected declared-file reader performs single-key version-checked file
/// reads, without pagination or retry. This closes only its implementation
/// transport DATA; neither an HTTP profile nor another execution is implied.
/// Caller same-parent backing precedes construction. The original measured
/// static document is embedded unchanged, without re-observing its Ref fields.
pub fn issue_file_lookup_transport(
  profile : PublicationContract,
  static_request : @encode.EncodedDocument,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, PublicationContractIssue] {
  guard file_read_profile_contract_bindings(profile)
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

///|
/// Compatibility projection for the explicitly Native implementation only.
pub fn native_file_read_profile_contract_bindings(
  profile : PublicationContract,
) -> (String, String, String)? {
  if profile.name != "native_file_content_read" {
    return None
  }
  file_read_profile_contract_bindings(profile)
}

///|
pub fn native_file_read_profile_physical_source_contract_cid(
  profile : PublicationContract,
) -> String? {
  if profile.name != "native_file_content_read" {
    return None
  }
  file_read_profile_physical_source_contract_cid(profile)
}

///|
/// Preserve the existing Native entrance and its implementation restriction.
pub fn issue_native_file_lookup_transport(
  profile : PublicationContract,
  static_request : @encode.EncodedDocument,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, PublicationContractIssue] {
  if profile.name != "native_file_content_read" {
    return Err(InvalidField("native_file_read_profile"))
  }
  issue_file_lookup_transport(
    profile, static_request, max_bytes, max_nodes, max_depth,
  )
}
