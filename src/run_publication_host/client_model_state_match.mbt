///|
// Compare data against the existing live checked Run's exact read claim. This
// is not a Store authenticator, durable restoration issuer, send permission or
// a way to bind a new Ledger to an alleged original Run. The document is owned
// and funded by the existing read/Store caller before admission. Every record,
// whole decode tree, current census scan and temporary frame remains part of
// that complete original envelope. No additional control is allocated here.
pub fn client_model_read_state_block_matches(
  value : ClientModelReadPreparation,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  document : @resources.OriginalStateDocument,
  position : Int,
) -> Result[Bool, @resources.OriginalReadIssue] {
  if !client_model_read_origin_matches(value, compiled, definition, plan) {
    return Err(@resources.ForeignOrigin)
  }
  @resources.original_state_document_block_matches(
    value.claim,
    value.origin,
    document,
    position,
  )
}
