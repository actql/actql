///|
/// Project actual Native retained input facts for the private Effect Source.
/// Recheck the existing receiver borrow before and after semantic issuance.
/// No payload is copied, no reservation is returned and no Store commit or
/// Effect permission is claimed by this operation.
pub fn ResidentSourceCompute::issue_effect_source_artifact(
  self : ResidentSourceCompute,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  artifact : @host.ClientEffectLocalResultArtifact,
  invocation : @publication.PublicationContract,
  retention : @publication.PublicationContract,
  source_binding_cid : String,
  store_authority_cid : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication.PublicationContract,
  @host.ClientEffectSourceArtifactIssue,
] {
  if !self.resident_effect_inputs_current(inputs) {
    return Err(Unavailable)
  }
  let source = @host.issue_client_effect_local_source_artifact(
    materials, inputs, member_index, artifact, invocation, retention, source_binding_cid,
    store_authority_cid, max_bytes, max_nodes, max_depth,
  )
  if !self.resident_effect_inputs_current(inputs) {
    return Err(Unavailable)
  }
  source
}
