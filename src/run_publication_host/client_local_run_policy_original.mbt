///|
/// Exact acceptance metadata. This is not authenticated Host custody,
/// current authorization, committed acceptance or a read/dispatch grant.
struct ClientLocalRunPolicyOriginal {
  body : Bytes
  retention : @publication.PublicationContract
  issued_at : String
  // The body getter can expose a mutable Host/FFI byte view. The private
  // fixed-size digest gates reuse of these already-admitted scalar facts.
  body_digest : Bytes
  request : ClientRequestIdentity
  run_definition_cid : String
  host_adoption_cid : String
  read_selection_cid : String
}

///|
fn local_run_policy_original_keys() -> Array[String] {
  [
    "host_adoption_cid", "issued_at", "profile_wire", "read_selection_cid", "request_wire",
    "retention_policy_wire", "run_definition_cid", "submission_reference_wire", "version",
  ]
}

///|
fn local_run_policy_original_cid(text : String) -> Bool {
  if !text.has_prefix("sha256:") || text.length() != 71 {
    return false
  }
  for index in 7..<71 {
    let unit = text[index].to_int()
    if !((unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102)) {
      return false
    }
  }
  true
}

///|
fn local_run_policy_original_intervals(
  profile : ClientLocalRunPolicyProfile,
  retention : @publication.PublicationContract,
  definition : @publication.PublicationContract,
  issued_at : String,
) -> Bool {
  guard @values.timestamp_epoch_milliseconds(issued_at) is Some(now) &&
    @values.epoch_milliseconds_timestamp(now + 86400000L) is Some(available) &&
    @values.epoch_milliseconds_timestamp(now + 172800000L) is Some(deletion) &&
    @values.epoch_milliseconds_timestamp(now + 604800000L) is Some(metadata) &&
    @publication.publication_contract_name(retention) ==
    "result_retention_policy" &&
    @publication.result_retention_intervals_valid(retention) &&
    @publication.publication_contract_name(definition) == "run_definition" &&
    run_profile_value(@publication.publication_contract_json(retention))
    is Some(policy) &&
    run_profile_value(@publication.publication_contract_json(definition))
    is Some(run) else {
    return false
  }
  run_profile_text(policy, "effective_data_policy_cid") ==
  Some(profile.result_policy_cid) &&
  run_profile_text(policy, "retention_contract_cid") ==
  Some(profile.retention_contract_cid) &&
  run_profile_text(policy, "metadata_retention_policy_cid") ==
  Some(profile.metadata_retention_policy_cid) &&
  run_profile_text(policy, "clock_contract_cid") ==
  Some(profile.clock_contract_cid) &&
  run_profile_text(policy, "available_until") == Some(available) &&
  run_profile_text(policy, "delete_by") == Some(deletion) &&
  run_profile_text(policy, "extension_ceiling_at") == Some(deletion) &&
  run_profile_text(policy, "metadata_delete_by") == Some(metadata) &&
  run_profile_text(run, "created_at") == Some(issued_at) &&
  run_profile_text(run, "valid_until") == Some(available)
}

///|
fn local_policy_contract_parse_workspace(
  contract : @publication.PublicationContract,
) -> @execution.PreparationRepresentationUnits? {
  let wire = @publication.publication_contract_json(contract)
  guard @publication.publication_contract_wire_usage(contract)
    is Some((bytes, nodes, depth)) &&
    @scalar.admit_utf8_length(wire, LOCAL_POLICY_JSON_BYTES) is Ok(actual_bytes) &&
    actual_bytes == bytes &&
    bytes > 0 &&
    nodes > 0 &&
    nodes <= LOCAL_POLICY_JSON_NODES &&
    depth > 0 &&
    depth <= LOCAL_POLICY_JSON_DEPTH else {
    return None
  }
  // The original encoder counted one node per value and container depth
  // on this exact retained wire, the same grammar the preserving parser uses.
  guard @decode.preserving_json_parser_construction_inventory(
      bytes, nodes, depth,
    )
    is Some(source) &&
    @canonical.source_conversion_construction_extent(
      nodes, nodes, nodes, nodes, depth, bytes,
    )
    is Some(canonical) else {
    return None
  }
  Some({
    record_headers: source.record_headers +
    canonical.retained.record_headers +
    canonical.scratch.record_headers +
    6L,
    reference_slots: source.reference_slots +
    canonical.retained.reference_slots +
    canonical.scratch.reference_slots +
    8L,
    scalar_words: source.scalar_words +
    canonical.retained.scalar_words +
    canonical.scratch.scalar_words +
    9L,
    owned_utf16_units: source.owned_utf16_units +
    canonical.retained_utf16_units +
    canonical.scratch_utf16_units,
    // The encoded input is built before the preserving parser. Neither the
    // original contract nor one of its two admitted trees pays for this copy.
    owned_wire_bytes: 2L * bytes.to_int64(),
  })
}

///|
/// Constructor quantities for the existing Local policy packet, priced by
/// the original material owner before binding. Return retained packet and
/// temporary execution bytes separately so the packet stays funded while
/// the journal encodes the first Run. The selected contracts are borrowed.
pub fn client_local_run_policy_original_construction_capacity(
  definition : @publication.PublicationContract,
  retention : @publication.PublicationContract,
) -> (Int64, Int64)? {
  guard @publication.publication_contract_name(definition) == "run_definition" &&
    @publication.publication_contract_name(retention) ==
    "result_retention_policy" &&
    local_policy_contract_parse_workspace(retention) is Some(policy_parse) &&
    local_policy_contract_parse_workspace(definition) is Some(run_parse) &&
    // client_request_identity_record_wire and client_local_original_record_body
    // use these existing output limits. Future strings are not observed yet.
    @encode.text_writer_construction_inventory(4096, 32, 2) is Some(request) &&
    @encode.text_writer_construction_inventory(8192, 64, 4) is Some(packet) &&
    @encode.hash_writer_live_key_inventory(0, 0) is Some(hash) else {
    return None
  }
  let retained : @execution.PreparationRepresentationUnits = {
    // Original, successful Result, two owned byte objects and output controls.
    record_headers: 5L,
    reference_slots: 10L,
    scalar_words: 4L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 8192L + 32L,
  }
  let encoding : @execution.PreparationRepresentationUnits = {
    // Two field arrays and their seven/nine tuples; packet conversion and
    // binder Result/Option controls. Timestamp parsing plus three calendar
    // renderers include all 12-month arrays and component/concat strings.
    record_headers: request.record_headers +
    packet.record_headers +
    hash.record_headers +
    48L +
    3L * 28L,
    reference_slots: request.reference_slots +
    packet.reference_slots +
    hash.reference_slots +
    64L +
    3L * 4L,
    scalar_words: request.scalar_words +
    packet.scalar_words +
    hash.scalar_words +
    128L +
    3L * 24L,
    owned_utf16_units: request.owned_utf16_units +
    packet.owned_utf16_units +
    hash.owned_utf16_units +
    3L * 24L * 24L,
    owned_wire_bytes: hash.owned_wire_bytes + 8192L,
  }
  // The accepted policy tree is still live when the definition is read.
  // Account for both full readers along with the encoder and SHA workspace.
  guard @execution.compose_preparation_representation([
      policy_parse, run_parse, encoding,
    ])
    is Some(workspace) &&
    @execution.preparation_representation_cost(retained) is Some(held) &&
    @execution.preparation_representation_cost(workspace) is Some(scratch) else {
    return None
  }
  Some((held, scratch))
}

///|
/// Bind the already issued finite Policy and checked-family Run definition.
/// Only the existing Native accept transaction may turn this into custody.
/// Its physical prepared owner, current Host and epoch checks remain required.
pub fn bind_client_local_run_policy_original(
  profile : ClientLocalRunPolicyProfile,
  reference : ClientSubmissionReferenceRecord,
  request : ClientRequestIdentity,
  definition : @publication.PublicationContract,
  retention : @publication.PublicationContract,
  issued_at : String,
  host_adoption_cid : String,
  read_selection_cid : String,
) -> Result[ClientLocalRunPolicyOriginal, ClientLocalRunPolicyProfileIssue] {
  if !client_submission_reference_matches_request(reference, request) ||
    !local_run_policy_original_cid(host_adoption_cid) ||
    !local_run_policy_original_cid(read_selection_cid) ||
    !local_run_policy_original_intervals(
      profile, retention, definition, issued_at,
    ) {
    return Err(InvalidOriginal)
  }
  let request_wire = match client_request_identity_record_wire(request) {
    Ok(value) => value
    Err(_) => return Err(InvalidOriginal)
  }
  let body = match
    client_local_original_record_body([
      ("host_adoption_cid", host_adoption_cid),
      ("issued_at", issued_at),
      ("profile_wire", profile.wire),
      ("read_selection_cid", read_selection_cid),
      ("request_wire", request_wire),
      (
        "retention_policy_wire",
        @publication.publication_contract_json(retention),
      ),
      (
        "run_definition_cid",
        @publication.publication_contract_identity(definition),
      ),
      (
        "submission_reference_wire",
        client_submission_reference_record_wire(reference),
      ),
      ("version", "actql-local-run-policy-original/0.1"),
    ]) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  Ok({
    body,
    retention,
    issued_at,
    body_digest: @sha.digest(body),
    request,
    run_definition_cid: @publication.publication_contract_identity(definition),
    host_adoption_cid,
    read_selection_cid,
  })
}

///|
/// Read the saved original and validate its old issuance time. No current
/// clock, new Policy issuance, custody repair, grant or I/O is performed.
pub fn admit_client_local_run_policy_original(
  body : Bytes,
  profile : ClientLocalRunPolicyProfile,
  reference : ClientSubmissionReferenceRecord,
  request : ClientRequestIdentity,
  definition : @publication.PublicationContract,
  host_adoption_cid : String,
  read_selection_cid : String,
  admit_alternate_read_selection? : ((String) -> Bool)? = None,
) -> Result[ClientLocalRunPolicyOriginal, ClientLocalRunPolicyProfileIssue] {
  let fields = match
    client_local_original_record_fields(body, local_run_policy_original_keys()) {
    Ok(value) => value
    Err(_) => return Err(InvalidOriginal)
  }
  if fields[8] != "actql-local-run-policy-original/0.1" {
    return Err(InvalidOriginal)
  }
  let retention = match
    @publication.admit_publication_contract(
      "result_retention_policy",
      fields[5],
      8192,
      512,
      8,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidOriginal)
  }
  bind_client_local_run_policy_original(
    profile,
    reference,
    request,
    definition,
    retention,
    fields[1],
    host_adoption_cid,
    fields[3],
  ).bind(original => {
    if original.body != body {
      return Err(InvalidOriginal)
    }
    // The installed original needs no alternate authorization or allocation.
    // A caller may recognize another selected CID after exact packet binding.
    if fields[3] != read_selection_cid {
      guard admit_alternate_read_selection is Some(admit) && admit(fields[3]) else {
        return Err(InvalidOriginal)
      }
    }
    Ok(original)
  })
}

///|
pub fn client_local_run_policy_original_body(
  original : ClientLocalRunPolicyOriginal,
) -> Bytes {
  original.body
}

///|
pub fn client_local_run_policy_original_retention(
  original : ClientLocalRunPolicyOriginal,
) -> @publication.PublicationContract {
  original.retention
}

///|
pub fn client_local_run_policy_original_issued_at(
  original : ClientLocalRunPolicyOriginal,
) -> String {
  original.issued_at
}

///|
/// Project the already-admitted original read endpoint. This is not a grant,
/// a current clock, a renewed Policy or a change to the retention endpoint.
pub fn client_local_run_policy_original_read_expires_at(
  original : ClientLocalRunPolicyOriginal,
) -> String {
  @publication.result_retention_available_until(original.retention).unwrap_or(
    "",
  )
}

///|
/// Read only the dependencies already bound into the admitted original body.
/// This metadata neither observes current adoption nor supplies read authority.
pub fn client_local_run_policy_original_read_dependencies(
  original : ClientLocalRunPolicyOriginal,
) -> Result[(String, String), ClientLocalRunPolicyProfileIssue] {
  client_local_original_record_fields(
    original.body,
    local_run_policy_original_keys(),
  )
  .map(fields => (fields[0], fields[3]))
  .map_err(_ => InvalidOriginal)
}

///|
/// Project the original Run correspondence and its dependent read metadata
/// together, without reparsing an unchanged admitted packet. Request equality
/// includes its immutable scope and every intent component. A Run definition's
/// admitted canonical identity also binds its issuance and expiry timestamps;
/// independently admitted equal values need no shared object identity.
///
/// Bytes can be mutated through a Host/FFI alias. A changed body follows the
/// original raw checks, including their acceptance of valid changed metadata.
/// This is structural metadata only, never custody or current permission.
pub fn client_local_run_policy_original_run_dependencies(
  original : ClientLocalRunPolicyOriginal,
  request : ClientRequestIdentity,
  definition : @publication.PublicationContract,
) -> Result[(String, String), ClientLocalRunPolicyProfileIssue] {
  if original.body.length() > 8192 {
    return Err(InvalidOriginal)
  }
  if @sha.digest(original.body) == original.body_digest &&
    original.request == request &&
    original.run_definition_cid ==
    @publication.publication_contract_identity(definition) {
    return Ok((original.host_adoption_cid, original.read_selection_cid))
  }
  match
    validate_client_local_run_policy_original_run(
      original.body,
      request,
      definition,
    ) {
    Err(issue) => Err(issue)
    Ok(_) => client_local_run_policy_original_read_dependencies(original)
  }
}

///|
/// Structural Run correspondence for the existing journal inventory reader.
/// This returns no selected profile, original custody or permission. Native
/// current/adoption and actual dependency-body admission remain separate.
pub fn validate_client_local_run_policy_original_run(
  body : Bytes,
  request : ClientRequestIdentity,
  definition : @publication.PublicationContract,
) -> Result[Unit, ClientLocalRunPolicyProfileIssue] {
  let fields = match
    client_local_original_record_fields(body, local_run_policy_original_keys()) {
    Ok(value) => value
    Err(_) => return Err(InvalidOriginal)
  }
  guard fields[8] == "actql-local-run-policy-original/0.1" &&
    local_run_policy_original_cid(fields[0]) &&
    local_run_policy_original_cid(fields[3]) &&
    client_request_identity_record_wire(request) == Ok(fields[4]) &&
    @publication.publication_contract_identity(definition) == fields[6] &&
    admit_client_submission_reference_record(fields[7]) is Ok(reference) &&
    client_submission_reference_matches_request(reference, request) &&
    run_profile_value(fields[2]) is Some(profile_value) &&
    run_profile_text(profile_value, "effective_data_policy_cid") is Some(policy) &&
    run_profile_text(profile_value, "retention_contract_cid")
    is Some(retention_cid) &&
    run_profile_text(profile_value, "metadata_retention_policy_cid")
    is Some(metadata) &&
    run_profile_text(profile_value, "clock_contract_cid") is Some(clock) &&
    [policy, retention_cid, metadata, clock].all(local_run_policy_original_cid) &&
    run_profile_wire(policy, retention_cid, metadata, clock) == Ok(fields[2]) &&
    @publication.admit_publication_contract(
      "result_retention_policy",
      fields[5],
      8192,
      512,
      8,
    )
    is Ok(retention) else {
    return Err(InvalidOriginal)
  }
  // This temporary value is used only for structural interval correspondence;
  // it is never returned as an admitted original dependency/profile.
  let profile : ClientLocalRunPolicyProfile = {
    wire: fields[2],
    result_policy_cid: policy,
    retention_contract_cid: retention_cid,
    metadata_retention_policy_cid: metadata,
    clock_contract_cid: clock,
  }
  if local_run_policy_original_intervals(
      profile,
      retention,
      definition,
      fields[1],
    ) {
    Ok(())
  } else {
    Err(InvalidOriginal)
  }
}
