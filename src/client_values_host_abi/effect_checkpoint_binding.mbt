///|
#export_name("clientValuesHostEffectCheckpointBinding")
pub fn client_values_host_effect_checkpoint_binding(
  allowed : @host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  wire : String,
) -> Result[Array[String], @host.ClientEffectCheckpointBindingIssue] {
  let artifact = match
    client_values_host_admit_effect_checkpoint_binding(
      allowed, definition, wire,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @host.client_effect_review_checkpoint_binding_fields(artifact)
}

///|
#export_name("clientValuesHostAdmitEffectCheckpointBinding")
pub fn client_values_host_admit_effect_checkpoint_binding(
  allowed : @host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  wire : String,
) -> Result[
  @checkpoint.SealedCheckpoint,
  @host.ClientEffectCheckpointBindingIssue,
] {
  @host.admit_client_effect_review_checkpoint_binding(
    allowed,
    definition,
    wire,
    { max_wire_bytes: 65536, max_nodes: 4096, max_depth: 64, },
  )
}

///|
#export_name("clientValuesHostEffectCheckpointBindingFields")
pub fn client_values_host_effect_checkpoint_binding_fields(
  original : @checkpoint.SealedCheckpoint,
) -> Result[Array[String], @host.ClientEffectCheckpointBindingIssue] {
  @host.client_effect_review_checkpoint_binding_fields(original)
}

///|
#export_name("clientValuesHostEffectCheckpointWaitingState")
pub fn client_values_host_effect_checkpoint_waiting_state(
  original : @checkpoint.SealedCheckpoint,
  stored_wire : String,
  updated_at : String,
  declared_results : Array[String],
) -> Result[String, @host.ClientEffectCheckpointWaitingIssue] {
  @host.client_effect_review_checkpoint_waiting_state(
    original,
    stored_wire,
    updated_at,
    declared_results,
    // Same full waiting-projection bounds as the external Checkpoint bridge.
    { max_wire_bytes: 1048576, max_nodes: 65536, max_depth: 64, },
  )
}
