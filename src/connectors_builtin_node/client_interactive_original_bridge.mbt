///|
// The original compiler holder is needed only at first admission. Restored
// metadata is validated through the existing logical-map binding Owner.
#export_name("clientProgramCompiledRunStaticPlanView")
pub fn client_program_compiled_run_static_plan_view(
  compiled : @publication_host.ClientCompiledRun,
  original : @publication_host.PreparedClientProgram,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @publication_host.ClientCompiledRunPlanIssue] {
  @publication_host.client_compiled_run_static_plan_view(
    compiled, original, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramCheckLogicalMapBinding")
pub fn client_program_check_logical_map_binding(
  map : @publication.RunEvidenceValue,
  plan : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, @publication.RunEvidenceValueIssue] {
  @publication.check_interactive_logical_map_binding(
    map, plan, max_bytes, max_nodes, max_depth,
  )
}
