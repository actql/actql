///|
#export_name("clientValuesHostEffectCheckpointBinding")
pub fn client_values_host_effect_checkpoint_binding(
  allowed : @host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  wire : String,
) -> Result[Array[String], @host.ClientEffectCheckpointBindingIssue] {
  let artifact = match
    @host.admit_client_effect_review_checkpoint_binding(
      allowed,
      definition,
      wire,
      { max_wire_bytes: 65536, max_nodes: 4096, max_depth: 64, },
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // No plan interpretation or caller-supplied unit lookup in the adapter.
  let fields = [artifact.checkpoint_cid, artifact.wire]
  match artifact.checkpoint.subject {
    @checkpoint.RunUnit(run_id~, unit_id~, run_definition_cid~) => {
      fields.push(run_id)
      fields.push(unit_id)
      fields.push(run_definition_cid)
    }
    _ => return Err(@host.ForeignSubject)
  }
  fields.push(artifact.checkpoint.required_artifact_cid)
  fields.push(artifact.checkpoint.review_projection_cid)
  fields.push(artifact.checkpoint.continuation_state_cid)
  Ok(fields)
}
