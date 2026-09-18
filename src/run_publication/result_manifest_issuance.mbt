///|
pub(all) enum ResultManifestIssuanceIssue {
  ManifestIssuanceWrongContract
  ManifestIssuanceEmptyInventory
  ManifestIssuanceInventoryMismatch
  ManifestIssuanceDuplicateResult(String)
  ManifestIssuanceEncoding
  ManifestIssuanceContract(PublicationContractIssue)
  ManifestIssuanceChain(RunPublicationChainIssue)
} derive(Eq, Debug)

///|
priv struct ResultManifestEntry {
  name : String
  artifact : PublicationContract
}

///|
fn manifest_artifact_for_definition(
  artifacts : Array[PublicationContract],
  definition : PublicationContract,
) -> PublicationContract? {
  let matches = artifacts.filter(artifact => {
    contract_string(artifact, "result_definition_cid") ==
    Some(definition.identity)
  })
  if matches.length() == 1 {
    Some(matches[0])
  } else {
    None
  }
}

///|
fn emit_result_manifest_body(
  run_definition_cid : String,
  invocation_cid : String,
  entries : Array[ResultManifestEntry],
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "invocation_cid")
  @encode.string_value(writer, invocation_cid)
  @encode.key(writer, "results")
  @encode.begin_object(writer)
  for entry in entries {
    @encode.key(writer, entry.name)
    @json.emit_value(entry.artifact.value, writer)
  }
  @encode.end_object(writer)
  @encode.key(writer, "run_definition_cid")
  @encode.string_value(writer, run_definition_cid)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-result-manifest/0.1")
  @encode.end_object(writer)
}

///|
/// Issue the one complete Result Manifest for an exact Run occurrence. The
/// caller supplies admitted contracts, not result names or Artifact CIDs, so
/// the portable owner fixes the full declared inventory and canonical order.
pub fn issue_result_manifest(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[PublicationContract, ResultManifestIssuanceIssue] {
  if run_definition.name != "run_definition" ||
    invocation.name != "run_invocation" {
    return Err(ManifestIssuanceWrongContract)
  }
  if definitions.is_empty() || artifacts.is_empty() {
    return Err(ManifestIssuanceEmptyInventory)
  }
  if definitions.length() != artifacts.length() {
    return Err(ManifestIssuanceInventoryMismatch)
  }
  let entries : Array[ResultManifestEntry] = []
  let names : Array[String] = []
  for definition in definitions {
    if definition.name != "result_definition" {
      return Err(ManifestIssuanceWrongContract)
    }
    guard contract_string(definition, "result_name") is Some(name) else {
      return Err(ManifestIssuanceInventoryMismatch)
    }
    if names.contains(name) {
      return Err(ManifestIssuanceDuplicateResult(name))
    }
    names.push(name)
    guard manifest_artifact_for_definition(artifacts, definition)
      is Some(artifact) else {
      return Err(ManifestIssuanceInventoryMismatch)
    }
    if artifact.name != "result_artifact" {
      return Err(ManifestIssuanceWrongContract)
    }
    entries.push({ name, artifact, })
  }
  entries.sort_by((left, right) => {
    @canonical.compare_utf16(left.name, right.name)
  })
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(ManifestIssuanceEncoding)
  }
  emit_result_manifest_body(
    run_definition.identity,
    invocation.identity,
    entries,
    writer,
  ) catch {
    _ => return Err(ManifestIssuanceEncoding)
  }
  let body = @encode.finish(writer) catch {
    _ => return Err(ManifestIssuanceEncoding)
  }
  let manifest = match
    seal_publication_contract(
      "result_manifest", body, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(ManifestIssuanceContract(issue))
  }
  match
    validate_run_publication_chain(
      run_definition, invocation, definitions, artifacts, manifest, max_wire_bytes,
      max_nodes, max_depth,
    ) {
    Ok(_) => Ok(manifest)
    Err(issue) => Err(ManifestIssuanceChain(issue))
  }
}
