///|
/// Read the computation component of the retained Effect compilation. The
/// private checked view remains owned by that original compilation; neither
/// this projection nor its capability metadata admits an executable Run.
/// Effect declarations, gates and sealed Preview require separate projections
/// before a Host can advertise a complete Effectful static Plan response.
pub fn client_effect_static_computation_plan_view(
  prepared : PreparedClientEffectComputation,
  compiled : ClientEffectCompilation,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, ClientInteractivePlanIssue] {
  if !physical_equal(compiled.owner, prepared) {
    return Err(ClientInteractivePlanIssue::ForeignCompilation)
  }
  issue_client_static_plan_view(
    compiled.compiled.owner,
    compiled.compiled.compiled_plan,
    max_bytes,
    max_nodes,
    max_depth,
    false,
  )
}
