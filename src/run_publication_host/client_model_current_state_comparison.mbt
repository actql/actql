///|
// Alias the exact four-field Core cursor. No new retained wrapper, map, Scope
// field or authentication record is added. Installed funding still covers the
// entire source tree, original park and per-block temporary snapshots first.
pub type ClientModelCurrentStateComparison = @resources.OriginalCurrentStateComparison[
  ClientModelReadOrigin,
]

///|
// Alias the completed comparison's two original borrows, not a journal park
// receipt. The original supplier funds the extra lifetime before construction.
pub type ClientModelCurrentStateMatch = @resources.OriginalCurrentStateMatch[
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

///|
pub fn advance_client_model_current_state_comparison_with_match(
  value : ClientModelCurrentStateComparison,
  park : ClientModelResourcePark,
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  quantum : Int,
) -> Result[
  @resources.OriginalCurrentStateMatchPoll[ClientModelReadOrigin],
  ClientModelReadPreparationIssue,
] {
  guard client_model_resource_park_current(
      park, scope, compiled, definition, plan,
    )
    is Some(_) &&
    @resources.original_current_state_comparison_current(value, park) is Some(_) else {
    return Err(Resource(@resources.ChangedOriginalState))
  }
  Ok(
    @resources.advance_original_current_state_comparison_with_match(
      value, quantum,
    ),
  )
}

///|
// Revalidate the original checked Run/Scope, not just equal Resource data.
pub fn client_model_current_state_match_current(
  value : ClientModelCurrentStateMatch,
  park : ClientModelResourcePark,
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
) -> ClientModelCurrentStateMatch? {
  guard client_model_resource_park_current(
      park, scope, compiled, definition, plan,
    )
    is Some(_) else {
    return None
  }
  @resources.original_current_state_match_current(value, park, scope.origin)
}

///|
pub fn retire_client_model_current_state_match(
  value : ClientModelCurrentStateMatch,
) -> Unit {
  @resources.retire_original_current_state_match(value)
}
