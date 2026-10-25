///|
/// Continuation of the selected Store/read service's admitted-original
/// validation. This is not a preparation Ledger grant or a numeric heap bound.
priv enum ClientStorePublicationValidationState {
  Chain(@publication.ComputationEvidenceCheck)
  Commit(@publication.PublicationCommitPreparation)
}

///|
struct ClientStorePublicationValidation {
  mut state : ClientStorePublicationValidationState?
}

///|
pub(all) enum ClientStorePublicationValidationIssue {
  InvalidOriginal
  Closed
  Chain(@publication.RunEvidenceChainIssue)
  Commit(@publication.PublicationCommitIssue)
}

///|
#export_name("clientStoreBeginOriginalChainValidation")
pub fn client_store_begin_original_chain_validation(
  definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  artifacts : Array[@publication.PublicationContract],
  manifest : @publication.PublicationContract,
  receipt : @publication.PublicationContract,
  captured_run : @publication.PublicationContract,
) -> Result[
  ClientStorePublicationValidation,
  ClientStorePublicationValidationIssue,
] {
  guard @publication.prepare_original_effect_free_chain_validation(
      definition, invocation, definitions, artifacts, manifest, receipt, captured_run,
    )
    is Some(plan) else {
    return Err(InvalidOriginal)
  }
  guard @publication.start_planned_chain_validation(plan) is Some(checker) else {
    @publication.cancel_publication_validation_plan(plan)
    return Err(InvalidOriginal)
  }
  Ok({ state: Some(Chain(checker)), })
}

///|
#export_name("clientStoreBeginOriginalCommitValidation")
pub fn client_store_begin_original_commit_validation(
  definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  definitions : Array[@publication.PublicationContract],
  artifacts : Array[@publication.PublicationContract],
  derivations : Array[@publication.PublicationContract],
  orderings : Array[@publication.PublicationContract],
  retentions : Array[@publication.PublicationContract],
  bindings : Array[@publication.PublicationContract],
  manifest : @publication.PublicationContract,
  receipt : @publication.PublicationContract,
  captured_run : @publication.PublicationContract,
  request : @publication.PublicationContract,
  attempt : @publication.PublicationContract,
  index : @publication.PublicationContract,
) -> Result[
  ClientStorePublicationValidation,
  ClientStorePublicationValidationIssue,
] {
  guard @publication.prepare_original_effect_free_commit_validation(
      definition, invocation, definitions, artifacts, derivations, orderings, retentions,
      bindings, manifest, receipt, captured_run, request, attempt, index,
    )
    is Some(plan) else {
    return Err(InvalidOriginal)
  }
  guard @publication.start_planned_commit_validation(plan) is Some(checker) else {
    @publication.cancel_publication_validation_plan(plan)
    return Err(InvalidOriginal)
  }
  Ok({ state: Some(Commit(checker)), })
}

///|
#export_name("clientStoreAdvanceOriginalValidation")
pub fn client_store_advance_original_validation(
  value : ClientStorePublicationValidation,
  quantum : Int,
) -> Result[(Bool, Int), ClientStorePublicationValidationIssue] {
  match value.state {
    None => Err(Closed)
    Some(Chain(checker)) =>
      checker.advance(quantum).map_err(issue => Chain(issue))
    Some(Commit(checker)) =>
      checker.advance(quantum).map_err(issue => Commit(issue))
  }
}

///|
#export_name("clientStoreFinishOriginalValidation")
pub fn client_store_finish_original_validation(
  value : ClientStorePublicationValidation,
) -> Result[Unit, ClientStorePublicationValidationIssue] {
  match value.state {
    None => Err(Closed)
    Some(Chain(checker)) => checker.finish().map_err(issue => Chain(issue))
    Some(Commit(checker)) => checker.finish().map_err(issue => Commit(issue))
  }
}

///|
#export_name("clientStoreCancelOriginalValidation")
pub fn client_store_cancel_original_validation(
  value : ClientStorePublicationValidation,
) -> Unit {
  match value.state {
    None => ()
    Some(Chain(checker)) => checker.cancel()
    Some(Commit(checker)) => checker.cancel()
  }
  value.state = None
}
