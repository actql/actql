///|
pub(all) enum ClientModelInputCapacityIssue {
  ForeignCallScope
  ForeignInput
  Read(ClientModelReadPreparationIssue)
} derive(Eq, Debug)

///|
// Join original read custody to the exact live mapped-input owner. The caller
// funds validation/control before this entry and supplies a separately reviewed
// physical byte grant. This function derives no numeric policy or send permit,
// retains no new owner, and does not authenticate a durable Store descriptor.
pub fn handoff_client_model_read_input_capacity(
  value : ClientModelReadPreparation,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  scope : ClientInferCallScope,
  rows : @execution.PreparedInferRows,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[
  (@resources.Ledger, @resources.CapacityReservation),
  ClientModelInputCapacityIssue,
] {
  if !client_model_read_origin_matches(value, compiled, definition, plan) {
    return Err(Read(ForeignRun))
  }
  if !physical_equal(scope.owner, compiled.owner) ||
    !physical_equal(scope.plan, plan) {
    return Err(ForeignCallScope)
  }
  // This existing predicate checks a live original CompletedOutput occurrence
  // and ModelTask. Equal row bytes, request CIDs or generic origins cannot
  // substitute for that input owner, including an empty input.
  if !client_infer_call_scope_matches_rows(scope, rows, plan.request_cid) {
    return Err(ForeignInput)
  }
  handoff_client_model_read_capacity(
    value, compiled, definition, plan, retained_bytes, execution_bytes,
  ).map_err(issue => Read(issue))
}
