///|
// Borrow only the existing original read and six-field resource comparison
// cursor. Before construction the original read envelope must cover these two
// optional references, the cursor and its document/tree/census/frame overlap.
// This wrapper is not a reservation, Store authenticator or restoration grant.
struct ClientModelOriginalPreparationComparison {
  mut read : ClientModelReadPreparation?
  mut cursor : @resources.OriginalStateComparison[ClientModelReadOrigin]?
}

///|
// Keep the resource poll read-only outside its owner. This Host poll preserves
// the exact result/work while also representing checked-origin refusals. The
// short overlap of the returned resource and Host poll belongs to the original
// workspace; a successful nominal fixture is not a physical bound for it.
pub enum ClientModelOriginalPreparationComparisonPoll {
  PreparationComparisonContinue(work~ : Int)
  PreparationComparisonComplete(work~ : Int)
  PreparationComparisonFailed(
    @resources.OriginalStateComparisonIssue,
    work~ : Int
  )
}

///|
// A true result for one block is insufficient: the existing resource cursor
// checks bootstrap, every original token/read and its final live census fence.
// The document comes from the original preparation Reader; matching all data
// still does not prove a stable current cut, Store ACK or Model-send authority.
// max_work counts existing comparison steps, not complete census scanning,
// planning work, Model KernelStep or a physical profile's byte allowance.
pub fn start_client_model_original_preparation_comparison(
  read : ClientModelReadPreparation,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  document : @resources.OriginalStateDocument,
  max_work : Int,
) -> Result[
  ClientModelOriginalPreparationComparison,
  @resources.OriginalStateComparisonIssue,
] {
  if !client_model_read_origin_matches(read, compiled, definition, plan) {
    return Err(@resources.Original(@resources.ForeignOrigin))
  }
  match
    @resources.start_original_state_comparison(
      read.claim,
      read.origin,
      document,
      max_work,
    ) {
    Ok(cursor) => Ok({ read: Some(read), cursor: Some(cursor), })
    Err(issue) => Err(issue)
  }
}

///|
// Retire only borrowed references, never the original document, read, physical
// custody or reservation. Original cleanup false must still retain them.
pub fn cancel_client_model_original_preparation_comparison(
  value : ClientModelOriginalPreparationComparison,
) -> Unit {
  if value.cursor is Some(cursor) {
    @resources.cancel_original_state_comparison(cursor)
  }
  value.cursor = None
  value.read = None
}

///|
pub fn advance_client_model_original_preparation_comparison(
  value : ClientModelOriginalPreparationComparison,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  quantum : Int,
) -> ClientModelOriginalPreparationComparisonPoll {
  guard value.read is Some(read) && value.cursor is Some(cursor) else {
    return PreparationComparisonFailed(@resources.Terminal, work=0)
  }
  // Foreign arguments cannot advance or cancel the original caller's cursor.
  if !client_model_read_origin_matches(read, compiled, definition, plan) {
    return PreparationComparisonFailed(
      @resources.Original(@resources.ForeignOrigin),
      work=0,
    )
  }
  let result = @resources.advance_original_state_comparison(cursor, quantum)
  match result {
    @resources.ComparisonContinue(work=n) =>
      PreparationComparisonContinue(work=n)
    // Invalid quantum leaves the existing cursor resumable; it is not a
    // physical cleanup failure or permission to release original resources.
    @resources.ComparisonFailed(@resources.InvalidQuantum, work=n) =>
      PreparationComparisonFailed(@resources.InvalidQuantum, work=n)
    @resources.ComparisonComplete(work=n) => {
      cancel_client_model_original_preparation_comparison(value)
      PreparationComparisonComplete(work=n)
    }
    @resources.ComparisonFailed(issue, work=n) => {
      cancel_client_model_original_preparation_comparison(value)
      PreparationComparisonFailed(issue, work=n)
    }
  }
}
