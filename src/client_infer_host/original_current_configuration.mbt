///|
// DATA-only cold prerequisite, not a restored Scope, Ledger or Model startup.
// Reuse the SAME installed/checked intersections as original read creation;
// never configure a fresh Ledger from limits or quantities in a saved packet.
// The trusted original Host funds document and temporary projection overlap
// before entry. Store authentication, current cut, token-role custody and
// atomic original admission remain separate requirements.
pub fn check_original_model_current_configuration(
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : @publication_host.ClientInferPlanGraph,
  document : @resources.OriginalCurrentStateDocument,
  limits : @model.ModelExecutionLimits,
  quantity_capacity : @model.ModelQuantityCapacity?,
) -> Result[Unit, @resources.OriginalCurrentStateReadIssue] {
  if !@publication_host.client_compiled_run_has_infer(compiled, plan) ||
    @publication_host.check_client_compiled_run_definition(compiled, definition)
    is Err(_) {
    return Err(@resources.Original(@resources.ForeignOrigin))
  }
  let quantities = match quantity_capacity {
    None => None
    Some(installed) =>
      match original_model_quantity_capacity(plan, installed) {
        Ok(value) => Some(value.limits)
        // That existing intersection refuses only invalid installed limits.
        // Preserve a typed capacity refusal; do not default to no quantities.
        Err(_) =>
          return Err(
            @resources.Original(@resources.Resource(@resources.InvalidLimits)),
          )
      }
  }
  @resources.check_original_current_state_document_configuration(
    document, original_model_ledger_limits(plan, limits), quantities,
  ).map_err(issue => @resources.Document(issue))
}
