///|
priv struct PublicIndexEntryInputs {
  namespace_id : String
  authority_scope_cid : String
  binding_cids : Array[String]
}

///|
// One closed fact-selection/order implementation for both the real issuer
// and its constructor measurement. The returned facts are DATA, not authority.
fn public_index_entry_inputs(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  manifest : PublicationContract,
  receipt : PublicationContract,
  captured_run : PublicationContract,
  durable_bindings : Array[PublicationContract],
  request : PublicationContract,
  attempt : PublicationContract,
) -> Result[PublicIndexEntryInputs, PublicationCommitIssuanceIssue] {
  for
    (contract, expected) in [
      (run_definition, "run_definition"),
      (invocation, "run_invocation"),
      (manifest, "result_manifest"),
      (receipt, "run_receipt"),
      (captured_run, "captured_run"),
      (request, "publication_request"),
      (attempt, "publication_attempt"),
    ] {
    if contract.name != expected {
      return Err(CommitIssuanceWrongContract)
    }
  }
  for
    (actual, expected, field) in [
      (
        contract_string(manifest, "run_definition_cid"),
        run_definition.identity,
        "manifest.run_definition_cid",
      ),
      (
        contract_string(manifest, "invocation_cid"),
        invocation.identity,
        "manifest.invocation_cid",
      ),
      (
        contract_string(request, "run_definition_cid"),
        run_definition.identity,
        "request.run_definition_cid",
      ),
      (
        contract_string(attempt, "publication_request_cid"),
        request.identity,
        "attempt.publication_request_cid",
      ),
      (
        contract_string(attempt, "run_definition_cid"),
        run_definition.identity,
        "attempt.run_definition_cid",
      ),
    ] {
    if actual != Some(expected) {
      return Err(CommitIssuanceReferenceMismatch(field))
    }
  }
  guard contract_string(request, "namespace_id") is Some(namespace_id) &&
    contract_string(request, "authority_scope_cid") is Some(authority_scope_cid) else {
    return Err(CommitIssuanceReferenceMismatch("request.authority"))
  }
  let binding_cids : Array[String] = []
  for binding in durable_bindings {
    if binding.name != "durable_result_binding" {
      return Err(CommitIssuanceWrongContract)
    }
    if contract_string(binding, "run_definition_cid") !=
      Some(run_definition.identity) ||
      contract_string(binding, "invocation_cid") != Some(invocation.identity) {
      return Err(CommitIssuanceReferenceMismatch("durable_result_binding"))
    }
    if binding_cids.contains(binding.identity) {
      return Err(CommitIssuanceInventoryMismatch)
    }
    binding_cids.push(binding.identity)
  }
  binding_cids.sort_by(@canonical.compare_utf16)
  Ok({ namespace_id, authority_scope_cid, binding_cids, })
}

///|
/// Measure the exact closed index emitter without constructing wire, hash or
/// contract. The same nominal fact checks and sorted binding occurrences are
/// used by issue_public_index_entry; this measurement grants no publication.
pub fn public_index_entry_construction_geometry(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  manifest : PublicationContract,
  receipt : PublicationContract,
  captured_run : PublicationContract,
  durable_bindings : Array[PublicationContract],
  request : PublicationContract,
  attempt : PublicationContract,
  committed_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @encode.EncodingConstructionGeometry,
  PublicationCommitIssuanceIssue,
] {
  let inputs = match
    public_index_entry_inputs(
      run_definition, invocation, manifest, receipt, captured_run, durable_bindings,
      request, attempt,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let writer = @encode.construction_measuring_writer(
    max_wire_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(CommitIssuanceEncoding)
  }
  emit_public_index_entry_body(
    inputs.namespace_id,
    inputs.authority_scope_cid,
    run_definition.identity,
    invocation.identity,
    manifest.identity,
    receipt.identity,
    captured_run.identity,
    request.identity,
    attempt.identity,
    committed_at,
    inputs.binding_cids.length(),
    index => inputs.binding_cids[index],
    writer,
  ) catch {
    _ => return Err(CommitIssuanceEncoding)
  }
  let geometry = @encode.finish_construction_measurement(writer) catch {
    _ => return Err(CommitIssuanceEncoding)
  }
  // The issuer seals this body with one fixed self-CID field. Its exact
  // spelling and 71-byte CID are part of the same public contract, not a
  // placeholder contract or another emitter.
  let key = "public_index_entry_cid".length()
  let bytes = geometry.bytes.to_int64() + key.to_int64() + 77L
  if bytes > max_wire_bytes.to_int64() || geometry.nodes >= max_nodes {
    return Err(CommitIssuanceEncoding)
  }
  Ok({
    ..geometry,
    bytes: bytes.to_int(),
    nodes: geometry.nodes + 1,
    fields: geometry.fields + 1,
    largest_object: geometry.largest_object + 1,
    strings: geometry.strings + 2,
    text_units: geometry.text_units + key + 71,
  })
}

///|
/// Complete existing preserving Source/Canonical/generated-shape codec and
/// its ordered writers. Return one true escaping contract beside the complete
/// conservative eight-class constructor workspace. No semantic admit occurs.
pub fn publication_wire_construction_inventory(
  geometry : @encode.EncodingConstructionGeometry,
) -> (
  EffectPreviewIdentityConstructionInventory,
  EffectPreviewIdentityConstructionInventory,
)? {
  guard geometry.bytes > 0 &&
    geometry.nodes > 0 &&
    geometry.depth > 0 &&
    publication_returned_contract_inventory(
      geometry.bytes,
      geometry.nodes,
      geometry.depth,
      geometry=Some(geometry),
    )
    is Some(retained) &&
    protocol_wire_codec_construction_inventory(
      geometry.bytes,
      geometry.nodes,
      geometry.depth,
      geometry=Some(geometry),
      live_keys=Some(0),
    )
    is Some(workspace) else {
    return None
  }
  Some((retained, workspace))
}
