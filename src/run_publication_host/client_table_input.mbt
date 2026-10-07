///|
pub(all) enum ClientTableInputIssue {
  ForeignOwner
  ForeignIdentity
  NotStore
  Mapping(@effect.TableStorageMappingIssue)
  Operation(@effect.TableContractIssue)
  ForeignInput
  Encoding
} derive(Eq, Debug)

///|
/// A whole-Relation request bound to the checked member and captured Artifact.
/// This is not approval, current authority, a dispatch claim, or a commit fact.
struct ClientTableInput {
  artifact : ClientEffectLocalResultArtifact
  identity : ClientEffectLocalIdentity
  mapping : @effect.TableStorageMapping
  operation : @effect.TableOperation
}

///|
pub fn client_effect_local_table_storage_mapping(
  artifact : ClientEffectLocalResultArtifact,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@effect.TableStorageMapping, ClientTableInputIssue] {
  @effect.issue_table_storage_mapping(
    artifact.export_receipt,
    max_bytes,
    max_nodes,
    max_depth,
  ).map_err(issue => Mapping(issue))
}

///|
/// Adapters may author target/action material, but cannot substitute the input
/// Artifact, effective policy, logical Relation, schema, or physical mapping.
/// Existing Preview/current-authority and send-once Ledger gates remain needed.
pub fn bind_client_table_input(
  owner : PreparedClientEffectComputation,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  artifact : ClientEffectLocalResultArtifact,
  identity : ClientEffectLocalIdentity,
  scope : @request_scope.LogicalRequestScope,
  operation_wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientTableInput, ClientTableInputIssue] {
  if !@strategy.captured_effect_inputs_match_computation(inputs, owner.graph) ||
    !client_effect_local_artifact_matches_member(artifact, inputs, member_index) {
    return Err(ForeignOwner)
  }
  if !client_effect_local_identity_matches(
      identity, owner, member_index, artifact,
    ) {
    return Err(ForeignIdentity)
  }
  let headers = @checked.effect_program_static_headers(owner.candidate)
  guard @syntax.effect_header_at(headers, member_index) is Some(header) &&
    @syntax.effect_header_kind(header) == "store" else {
    return Err(NotStore)
  }
  let mapping = match
    client_effect_local_table_storage_mapping(
      artifact, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let operation = match
    @effect.admit_table_operation(
      operation_wire, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Operation(issue))
  }
  // Read only the already-issued Artifact, not caller-provided evidence JSON.
  let source = match
    @source.parse_json(
      @publication.publication_contract_json(artifact.artifact),
      { max_input_bytes: max_bytes, max_nodes, max_depth, },
    ) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  let value = @canonical.from_source(source, max_nodes, max_depth, max_bytes) catch {
    _ => return Err(Encoding)
  }
  guard @canonical.object_field(value, "logical_result_cid")
    is Some(@canonical.String(relation)) &&
    @canonical.object_field(value, "effective_data_policy_cid")
    is Some(@canonical.String(policy)) else {
    return Err(Encoding)
  }
  if !@effect.table_operation_matches_input(
      operation,
      scope,
      identity.cid,
      client_effect_local_result_artifact_cid(artifact),
      relation,
      mapping,
      policy,
    ) {
    return Err(ForeignInput)
  }
  Ok({ artifact, identity, mapping, operation, })
}

///|
pub fn client_table_input_operation(
  value : ClientTableInput,
) -> @effect.TableOperation {
  value.operation
}

///|
pub fn client_table_input_mapping(
  value : ClientTableInput,
) -> @effect.TableStorageMapping {
  value.mapping
}

///|
/// Equal content is not custody of the exact checked/captured input owners.
pub fn client_table_input_matches_source(
  value : ClientTableInput,
  artifact : ClientEffectLocalResultArtifact,
  identity : ClientEffectLocalIdentity,
) -> Bool {
  physical_equal(value.artifact, artifact) &&
  physical_equal(value.identity, identity)
}
