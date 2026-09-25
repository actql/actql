///|
pub(all) enum ClientEffectLocalIdentityIssue {
  ForeignInput
  MissingMember
  ForeignArtifact
  MissingMapping
  WorkLimit
  Encoding
} derive(Eq, Debug)

///|
/// One checked local Effect occurrence. This is semantic identity, not a
/// current write grant or evidence that its Result remains available.
struct ClientEffectLocalIdentity {
  owner : PreparedClientEffectComputation
  member_index : Int
  artifact : ClientEffectLocalResultArtifact
  cid : String
  wire : String
}

///|
fn emit_client_effect_local_identity(
  writer : @encode.Writer,
  header : @syntax.EffectHeader,
  unit_definition_cid : String,
  local_invocation_cid : String,
  result_artifact_cid : String,
  resolved_contract_cid : String,
  self_cid : String?,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "effect_id")
  @encode.string_value(writer, @syntax.effect_header_id(header))
  @encode.key(writer, "effect_semantics")
  @syntax.emit_effect_header_semantics(header, writer)
  @encode.key(writer, "local_invocation_cid")
  @encode.string_value(writer, local_invocation_cid)
  @encode.key(writer, "resolved_contract_cid")
  @encode.string_value(writer, resolved_contract_cid)
  @encode.key(writer, "result_artifact_cid")
  @encode.string_value(writer, result_artifact_cid)
  if self_cid is Some(cid) {
    @encode.key(writer, "self_cid")
    @encode.string_value(writer, cid)
  }
  @encode.key(writer, "unit_definition_cid")
  @encode.string_value(writer, unit_definition_cid)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-local-effect-identity/0.1")
  @encode.end_object(writer)
}

///|
/// Bind the authored member and its resolved Mapping to the same checked
/// source pin, local Invocation, and completed local Result Artifact.
pub fn issue_source_free_client_effect_local_identity(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  artifact : ClientEffectLocalResultArtifact,
  max_work : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientEffectLocalIdentity, ClientEffectLocalIdentityIssue] {
  if !@strategy.captured_effect_inputs_match_computation(inputs, owner.graph) ||
    !physical_equal(artifact.inputs, inputs) ||
    !@strategy.captured_effect_inputs_share_view(
      inputs,
      artifact.member_index,
      member_index,
    ) {
    return Err(ForeignInput)
  }
  guard @strategy.captured_effect_input_at(inputs, member_index) is Some(input) else {
    return Err(MissingMember)
  }
  let unit = @strategy.captured_effect_input_stage(input)
  let headers = @checked.effect_program_static_headers(owner.candidate)
  guard @syntax.effect_header_at(headers, member_index) is Some(header) &&
    @syntax.effect_header_stage(header) == unit &&
    @syntax.effect_header_source_result(header) ==
    Some(artifact.definition.result_name) else {
    return Err(MissingMember)
  }
  if !client_effect_local_result_definition_matches(
      artifact.definition,
      owner,
      unit,
      artifact.definition.result_name,
    ) ||
    !client_effect_local_invocation_matches(artifact.invocation, owner, unit) {
    return Err(ForeignArtifact)
  }
  let descriptor = match
    client_effect_member_descriptor(
      owner,
      unit,
      @syntax.effect_header_id(header),
      max_work,
    ) {
    Ok(value) => value
    Err(WorkLimit) => return Err(WorkLimit)
    Err(_) => return Err(MissingMapping)
  }
  let (_, _, _, _, _, resolved_contract_cid, source_result, _) = descriptor
  if source_result != Some(artifact.definition.result_name) {
    return Err(ForeignArtifact)
  }
  let definition_cid = artifact.definition.unit_definition_cid
  let invocation_cid = artifact.invocation.cid
  let artifact_cid = @publication.publication_contract_identity(
    artifact.artifact,
  )
  let hash = @encode.hashing_writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  emit_client_effect_local_identity(
    hash,
    header,
    definition_cid,
    invocation_cid,
    artifact_cid,
    resolved_contract_cid,
    None,
  ) catch {
    _ => return Err(Encoding)
  }
  let cid = "sha256:" +
    (@encode.finish_hash(hash) catch { _ => return Err(Encoding) })
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  emit_client_effect_local_identity(
    writer,
    header,
    definition_cid,
    invocation_cid,
    artifact_cid,
    resolved_contract_cid,
    Some(cid),
  ) catch {
    _ => return Err(Encoding)
  }
  let wire = @encode.finish(writer) catch { _ => return Err(Encoding) }
  Ok({ owner, member_index, artifact, cid, wire, })
}

///|
pub fn client_effect_local_identity_cid(
  identity : ClientEffectLocalIdentity,
) -> String {
  identity.cid
}

///|
pub fn client_effect_local_identity_json(
  identity : ClientEffectLocalIdentity,
) -> String {
  identity.wire
}

///|
pub fn client_effect_local_identity_matches(
  identity : ClientEffectLocalIdentity,
  owner : PreparedClientEffectComputation,
  member_index : Int,
  artifact : ClientEffectLocalResultArtifact,
) -> Bool {
  physical_equal(identity.owner, owner) &&
  identity.member_index == member_index &&
  physical_equal(identity.artifact, artifact)
}
