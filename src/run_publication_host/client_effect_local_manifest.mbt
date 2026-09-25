///|
pub(all) enum ClientEffectLocalManifestIssue {
  ForeignInvocation
  MissingUnit
  IncompleteResults
  ForeignArtifact
  DuplicateResult
  Encoding
} derive(Eq, Debug)

///|
/// The complete semantic Result inventory of one checked local Unit. This
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
  @encode.key(writer, "unit_definition_cid")
  @encode.string_value(writer, unit_definition_cid)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-local-result-manifest/0.1")
  @encode.end_object(writer)
}

///|
/// Require every declared Result of the checked Unit. A Manifest of only the
/// Effect-consumed subset would falsely claim a complete local projection.
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
  if expected_count == 0 || artifacts.length() != expected_count {
    return Err(IncompleteResults)
  }
  let by_name : Map[String, ClientEffectLocalResultArtifact] = Map([])
  for artifact in artifacts {
    let name = artifact.definition.result_name
    if by_name.contains(name) {
      return Err(DuplicateResult)
    }
    if !@strategy.captured_effect_inputs_match_computation(
        artifact.inputs,
        owner.graph,
      ) ||
      !physical_equal(artifact.invocation, invocation) ||
      !client_effect_local_result_definition_matches(
        artifact.definition,
        owner,
        invocation.unit,
        name,
      ) {
      return Err(ForeignArtifact)
    }
    by_name[name] = artifact
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
  let hash = @encode.hashing_writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  emit_client_effect_local_manifest(
    hash,
    invocation.unit_definition_cid,
    invocation.cid,
    names,
    by_name,
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
