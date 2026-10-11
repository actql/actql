///|
#export_name("clientValuesHostEffectCheckpointMembers")
pub fn client_values_host_effect_checkpoint_members(
  allowed : @host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  checkpoint_wire : String,
) -> Result[Array[String], @host.ClientEffectCheckpointMembersIssue] {
  @host.client_effect_review_checkpoint_members(
    allowed,
    definition,
    checkpoint_wire,
    { max_wire_bytes: 65536, max_nodes: 4096, max_depth: 64, },
    64,
    10000,
  )
}
