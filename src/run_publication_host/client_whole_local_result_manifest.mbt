///|
/// The complete checked Result inventory of one finished Whole Source Unit.
struct ClientWholeLocalResultManifest {
  unit : ClientWholeLocalUnitPublication
  artifacts : Array[ClientWholeLocalResultArtifact]
  cid : String
  wire : String
}

///|
pub fn client_whole_local_result_artifact_cid(
  value : ClientWholeLocalResultArtifact,
) -> String {
  @publication.publication_contract_identity(value.artifact)
}

///|
fn client_whole_local_result_manifest_inputs_match(
  unit : ClientWholeLocalUnitPublication,
  artifacts : Array[ClientWholeLocalResultArtifact],
) -> Bool {
  let original = unit.invocation.owner
  if !client_whole_local_unit_original_live(original) ||
    artifacts.length() !=
    @strategy.captured_completed_unit_result_count(original.results) {
    return false
  }
  for index, artifact in artifacts {
    if !physical_equal(artifact.invocation, unit.invocation) ||
      !physical_equal(artifact.source.owner, original) ||
      !(artifact.scope is Some(scope) && physical_equal(scope, unit.scope)) ||
      !@publication.result_retention_bounds_equal(
        artifact.retention,
        unit.retention,
      ) ||
      !(@strategy.captured_completed_unit_result_export_original(
        artifact.custody,
        original.results,
        index,
      )
      is Some((_, receipt)) &&
      physical_equal(artifact.export_receipt, receipt)) {
      return false
    }
  }
  true
}

///|
/// Require the complete checked Result inventory in Unit order. The stored
/// Manifest uses the same canonical emitter and sorting as Effect Results.
pub fn issue_client_whole_local_result_manifest(
  unit : ClientWholeLocalUnitPublication,
  artifacts : Array[ClientWholeLocalResultArtifact],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  fund_controls : (Int) -> Bool,
  fund_body : (@encode.EncodingConstructionGeometry) -> Bool,
) -> Result[ClientWholeLocalResultManifest, ClientEffectLocalManifestIssue] {
  let count = artifacts.length()
  if count == 0 ||
    count !=
    @strategy.captured_completed_unit_result_count(
      unit.invocation.owner.results,
    ) {
    return Err(IncompleteResults)
  }
  if !fund_controls(count) ||
    artifacts.length() != count ||
    !client_whole_local_result_manifest_inputs_match(unit, artifacts) {
    return Err(ForeignArtifact)
  }
  let artifacts = artifacts.copy()
  let by_name : Map[String, ClientWholeLocalResultArtifact] = Map([])
  let names = Array(capacity=count)
  for artifact in artifacts {
    let name = artifact.source.result_name
    if by_name.contains(name) {
      return Err(DuplicateResult)
    }
    names.push(name)
    by_name[name] = artifact
  }
  names.sort_by(@canonical_value.compare_utf16)
  let invocation = unit.invocation
  let table_names : Array[String] = []
  let table_artifacts : Map[String, ClientWholeLocalResultArtifact] = Map([])
  let measure = @encode.construction_measuring_writer(
    max_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  let geometry = try {
    emit_client_local_result_manifest(
      measure,
      invocation.unit_definition_cid,
      invocation.cid,
      names,
      by_name,
      table_names,
      table_artifacts,
      client_whole_local_result_artifact_cid,
      Some(invocation.cid),
    )
    @encode.finish_construction_measurement(measure)
  } catch {
    _ => {
      @encode.cancel_writer(measure)
      return Err(Encoding)
    }
  }
  if !fund_body(geometry) {
    return Err(Encoding)
  }
  if !client_whole_local_result_manifest_inputs_match(unit, artifacts) {
    return Err(ForeignArtifact)
  }
  let hash = @encode.hashing_writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  emit_client_local_result_manifest(
    hash,
    invocation.unit_definition_cid,
    invocation.cid,
    names,
    by_name,
    table_names,
    table_artifacts,
    client_whole_local_result_artifact_cid,
    None,
  ) catch {
    _ => return Err(Encoding)
  }
  let cid = "sha256:" +
    (@encode.finish_hash(hash) catch { _ => return Err(Encoding) })
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  emit_client_local_result_manifest(
    writer,
    invocation.unit_definition_cid,
    invocation.cid,
    names,
    by_name,
    table_names,
    table_artifacts,
    client_whole_local_result_artifact_cid,
    Some(cid),
  ) catch {
    _ => return Err(Encoding)
  }
  let wire = @encode.finish(writer) catch { _ => return Err(Encoding) }
  Ok({ unit, artifacts, cid, wire, })
}

///|
pub fn client_whole_local_result_manifest_cid(
  value : ClientWholeLocalResultManifest,
) -> String {
  value.cid
}

///|
pub fn client_whole_local_result_manifest_json(
  value : ClientWholeLocalResultManifest,
) -> String {
  value.wire
}

///|
/// The same complete Manifest and exact artifact are needed by the receiver.
pub fn client_whole_local_result_manifest_matches(
  value : ClientWholeLocalResultManifest,
  artifact : ClientWholeLocalResultArtifact,
) -> Bool {
  client_whole_local_result_manifest_inputs_match(value.unit, value.artifacts) &&
  value.artifacts.any(original => physical_equal(original, artifact))
}
