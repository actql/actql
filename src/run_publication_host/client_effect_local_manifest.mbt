///|
pub(all) enum ClientEffectLocalManifestIssue {
  ForeignInvocation
  MissingUnit
  IncompleteResults
  IncompleteTableInputs
  ForeignArtifact
  DuplicateResult
  DuplicateTableInput
  Encoding
} derive(Eq, Debug)

///|
/// The complete Result inventory and Effect-consumed private Table inputs of
/// one checked local Unit. Private inputs have a separate namespace. This
/// does not attest current physical availability or publication custody.
struct ClientEffectLocalManifest {
  owner : PreparedClientEffectComputation
  invocation : ClientEffectLocalInvocation
  artifacts : Array[ClientEffectLocalResultArtifact]
  cid : String
  wire : String
}

///|
fn emit_client_effect_local_manifest(
  writer : @encode.Writer,
  unit_definition_cid : String,
  invocation_cid : String,
  names : Array[String],
  artifacts : Map[String, ClientEffectLocalResultArtifact],
  table_names : Array[String],
  table_artifacts : Map[String, ClientEffectLocalResultArtifact],
  self_cid : String?,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "local_invocation_cid")
  @encode.string_value(writer, invocation_cid)
  @encode.key(writer, "results")
  @encode.begin_object(writer)
  for name in names {
    @encode.key(writer, name)
    @encode.string_value(
      writer,
      @publication.publication_contract_identity(artifacts[name].artifact),
    )
  }
  @encode.end_object(writer)
  if self_cid is Some(cid) {
    @encode.key(writer, "self_cid")
    @encode.string_value(writer, cid)
  }
  // Omitting the absent private inventory preserves ordinary-only preimages.
  if !table_names.is_empty() {
    @encode.key(writer, "table_inputs")
    @encode.begin_object(writer)
    for name in table_names {
      @encode.key(writer, name)
      @encode.string_value(
        writer,
        @publication.publication_contract_identity(
          table_artifacts[name].artifact,
        ),
      )
    }
    @encode.end_object(writer)
  }
  @encode.key(writer, "unit_definition_cid")
  @encode.string_value(writer, unit_definition_cid)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-local-result-manifest/0.1")
  @encode.end_object(writer)
}

///|
/// Require every declared Result of the checked Unit. A Manifest of only the
/// Effect-consumed Result subset would falsely claim a complete projection.
/// Private inputs instead cover every distinct declaration consumed by an
/// Effect in this Unit. Unused private declarations do not invent a capture.
pub fn issue_client_effect_local_manifest(
  owner : PreparedClientEffectComputation,
  invocation : ClientEffectLocalInvocation,
  artifacts : Array[ClientEffectLocalResultArtifact],
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientEffectLocalManifest, ClientEffectLocalManifestIssue] {
  if !client_effect_local_invocation_matches(invocation, owner, invocation.unit) {
    return Err(ForeignInvocation)
  }
  let program = @checked.effect_program_static_checked_computation(
    owner.candidate,
  )
  guard @stage_results.stage_at(
      @checked.checked_stage_results(program),
      invocation.unit,
    )
    is Some(stage) else {
    return Err(MissingUnit)
  }
  let expected_count = @results.count(stage)
  let table_members : Map[String, Int] = Map([])
  let headers = @checked.effect_program_static_headers(owner.candidate)
  for index in 0..<@syntax.effect_header_count(headers) {
    let header = @syntax.effect_header_at(headers, index).unwrap()
    if @syntax.effect_header_stage(header) == invocation.unit &&
      @syntax.effect_header_source_table_input(header) is Some(name) &&
      !table_members.contains(name) {
      table_members[name] = index
    }
  }
  if expected_count + table_members.length() == 0 {
    return Err(IncompleteResults)
  }
  let by_name : Map[String, ClientEffectLocalResultArtifact] = Map([])
  let by_table : Map[String, ClientEffectLocalResultArtifact] = Map([])
  for artifact in artifacts {
    if !client_effect_local_artifact_matches_computation(artifact, owner) ||
      !physical_equal(artifact.invocation, invocation) {
      return Err(ForeignArtifact)
    }
    match artifact.source {
      ResultSource(_, definition) => {
        let name = definition.result_name
        if by_name.contains(name) {
          return Err(DuplicateResult)
        }
        if !client_effect_local_result_definition_matches(
            definition,
            owner,
            invocation.unit,
            name,
          ) {
          return Err(ForeignArtifact)
        }
        by_name[name] = artifact
      }
      TableSource(_, definition) => {
        let name = definition.name
        if by_table.contains(name) {
          return Err(DuplicateTableInput)
        }
        guard table_members.get(name) is Some(index) &&
          client_effect_local_artifact_inputs(artifact) is Some(inputs) &&
          @strategy.captured_effect_table_input_at(inputs, index) is Some(input) &&
          client_effect_local_table_definition_matches(definition, owner, input) &&
          client_effect_local_artifact_matches_member(artifact, inputs, index) else {
          return Err(ForeignArtifact)
        }
        by_table[name] = artifact
      }
    }
  }
  if by_name.length() != expected_count {
    return Err(IncompleteResults)
  }
  if by_table.length() != table_members.length() {
    return Err(IncompleteTableInputs)
  }
  let names : Array[String] = []
  for index in 0..<expected_count {
    let result = @results.result_at(stage, index).unwrap()
    let name = @results.name(result)
    if !by_name.contains(name) {
      return Err(IncompleteResults)
    }
    names.push(name)
  }
  names.sort_by(@canonical_value.compare_utf16)
  let table_names : Array[String] = []
  for name, _ in table_members {
    if !by_table.contains(name) {
      return Err(IncompleteTableInputs)
    }
    table_names.push(name)
  }
  table_names.sort_by(@canonical_value.compare_utf16)
  let hash = @encode.hashing_writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  emit_client_effect_local_manifest(
    hash,
    invocation.unit_definition_cid,
    invocation.cid,
    names,
    by_name,
    table_names,
    by_table,
    None,
  ) catch {
    _ => return Err(Encoding)
  }
  let cid = "sha256:" +
    (@encode.finish_hash(hash) catch { _ => return Err(Encoding) })
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  emit_client_effect_local_manifest(
    writer,
    invocation.unit_definition_cid,
    invocation.cid,
    names,
    by_name,
    table_names,
    by_table,
    Some(cid),
  ) catch {
    _ => return Err(Encoding)
  }
  let wire = @encode.finish(writer) catch { _ => return Err(Encoding) }
  Ok({ owner, invocation, artifacts: artifacts.copy(), cid, wire, })
}

///|
pub fn client_effect_local_manifest_cid(
  value : ClientEffectLocalManifest,
) -> String {
  value.cid
}

///|
pub fn client_effect_local_manifest_json(
  value : ClientEffectLocalManifest,
) -> String {
  value.wire
}

///|
/// Opaque owner check for a later capture. Equal semantic CIDs from another
/// checked occurrence do not transfer the original Artifact owner.
pub fn client_effect_local_manifest_matches(
  value : ClientEffectLocalManifest,
  owner : PreparedClientEffectComputation,
  invocation : ClientEffectLocalInvocation,
  artifacts : Array[ClientEffectLocalResultArtifact],
) -> Bool {
  if !physical_equal(value.owner, owner) ||
    !physical_equal(value.invocation, invocation) ||
    value.artifacts.length() != artifacts.length() {
    return false
  }
  for artifact in artifacts {
    let mut matches = 0
    for owned in value.artifacts {
      if physical_equal(owned, artifact) {
        matches += 1
      }
    }
    if matches != 1 {
      return false
    }
  }
  for owned in value.artifacts {
    let mut matches = 0
    for artifact in artifacts {
      if physical_equal(owned, artifact) {
        matches += 1
      }
    }
    if matches != 1 {
      return false
    }
  }
  true
}

///|
/// Measure the existing Manifest emitter over original local Artifacts. The
/// parent has already backed the checked Unit inventory before retaining it;
/// this sink allocates no manifest wire, hash identity or publication grant.
pub fn client_effect_local_manifest_construction_geometry(
  invocation : ClientEffectLocalInvocation,
  artifacts : Array[ClientEffectLocalResultArtifact],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @encode.EncodingConstructionGeometry,
  ClientEffectLocalManifestIssue,
] {
  let names : Array[String] = []
  let tables : Array[String] = []
  let by_name : Map[String, ClientEffectLocalResultArtifact] = Map([])
  let by_table : Map[String, ClientEffectLocalResultArtifact] = Map([])
  for artifact in artifacts {
    match artifact.source {
      ResultSource(_, definition) => {
        names.push(definition.result_name)
        by_name[definition.result_name] = artifact
      }
      TableSource(_, definition) => {
        tables.push(definition.name)
        by_table[definition.name] = artifact
      }
    }
  }
  names.sort_by(@canonical_value.compare_utf16)
  tables.sort_by(@canonical_value.compare_utf16)
  let writer = @encode.construction_measuring_writer(
    max_bytes, max_nodes, max_depth,
  ) catch {
    _ => return Err(Encoding)
  }
  try {
    emit_client_effect_local_manifest(
      writer,
      invocation.unit_definition_cid,
      invocation.cid,
      names,
      by_name,
      tables,
      by_table,
      Some(invocation.cid),
    )
    Ok(@encode.finish_construction_measurement(writer))
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      Err(Encoding)
    }
  }
}
