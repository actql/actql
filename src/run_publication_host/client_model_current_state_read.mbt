///|
// Borrow only actual census data from the same opaque Scope/park. This does
// not expose the Ledger or let a JS aggregate establish original resource
// authority. The transient seven-field result is part of existing bootstrap
// inventory; no new retained wrapper, map or Scope/Model field is installed.
pub fn client_model_current_state_read_bounds(
  park : ClientModelResourcePark,
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
) -> Result[
  @resources.OriginalCurrentStateReadBounds,
  ClientModelReadPreparationIssue,
] {
  if !client_model_origin_matches(scope.origin, compiled, definition, plan) {
    return Err(ForeignRun)
  }
  @resources.original_current_state_read_bounds(park, scope.origin).map_err(issue => {
    Resource(issue)
  })
}

///|
// Use actual same-Owner ceilings before installing the existing bounded data
// Reader. The caller funds parent-tree admission/metadata/Reader overlap before
// this call; a shape or work limit is never used as its byte funding source.
pub fn start_client_model_current_state_document_read(
  park : ClientModelResourcePark,
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  source : @decode.Cursor,
  max_work : Int,
  owned_tree_limits : @decode.Limits,
) -> Result[
  @resources.OriginalCurrentStateDocumentRead,
  @resources.OriginalCurrentStateReadIssue,
] {
  if !client_model_origin_matches(scope.origin, compiled, definition, plan) {
    return Err(@resources.Original(@resources.ForeignOrigin))
  }
  @resources.start_original_current_state_document_read_for_park(
    park,
    scope.origin,
    source,
    max_work,
    owned_tree_limits,
  )
}
