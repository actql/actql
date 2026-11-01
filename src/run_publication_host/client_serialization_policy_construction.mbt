///|
/// Read construction counts from this SAME prepared task and checked Sources.
/// No policy closure, Source evidence, permission or Graph is issued here.
pub fn prepared_client_serialization_policy_construction(
  prepared : PreparedClientProgram,
  task : Int,
) -> Result[
  @checked.SerializationPolicyConstruction,
  ClientSerializationPlanGraphIssue,
] {
  guard @strategy.graph_task_unit_index(prepared.graph, task) is Some(unit) &&
    @checked.serialization_source_policy_construction(
      @strategy.graph_program(prepared.graph),
      unit,
    )
    is Some(value) else {
    return Err(UnsupportedGraph)
  }
  Ok(value)
}
