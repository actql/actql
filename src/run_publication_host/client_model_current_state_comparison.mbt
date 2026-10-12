///|
// Alias the exact four-field Core cursor. No new retained wrapper, map, Scope
// field or authentication record is added. Installed funding still covers the
// entire source tree, original park and per-block temporary snapshots first.
pub type ClientModelCurrentStateComparison = @resources.OriginalCurrentStateComparison[
  ClientModelReadOrigin,
]

///|
// The checked Scope origin stays within its existing Host Owner. Equal decoded
// data does not authenticate Store custody, COMMIT, restoration or Model send.
pub fn start_client_model_current_state_comparison(
  park : ClientModelResourcePark,
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  document : @resources.OriginalCurrentStateDocument,
  max_work : Int,
) -> Result[
  ClientModelCurrentStateComparison,
  @resources.OriginalStateComparisonIssue,
] {
  guard client_model_resource_park_current(
      park, scope, compiled, definition, plan,
    )
    is Some(_) else {
    return Err(@resources.Original(@resources.ChangedOriginalState))
  }
  @resources.start_original_current_state_comparison(
    park,
    scope.origin,
    document,
    max_work,
  )
}

///|
// Recheck both actual original Scope and exact cursor/park before every step.
// A foreign caller cannot progress or cancel another Owner's borrowed cursor.
pub fn advance_client_model_current_state_comparison(
  value : ClientModelCurrentStateComparison,
  park : ClientModelResourcePark,
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  quantum : Int,
) -> Result[
  @resources.OriginalStateComparisonPoll,
  ClientModelReadPreparationIssue,
] {
  guard client_model_resource_park_current(
      park, scope, compiled, definition, plan,
    )
    is Some(_) &&
    @resources.original_current_state_comparison_current(value, park) is Some(_) else {
    return Err(Resource(@resources.ChangedOriginalState))
  }
  Ok(@resources.advance_original_current_state_comparison(value, quantum))
}

///|
pub fn cancel_client_model_current_state_comparison(
  value : ClientModelCurrentStateComparison,
) -> Unit {
  @resources.cancel_original_current_state_comparison(value)
  // Drop cursor borrows only; the original document and park keep their Owner.
}
