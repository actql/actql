///|
/// A durable request may reserve one physical dispatch. A reservation is not
/// evidence that the task started or completed; after a lost dispatch outcome
/// the Host must inspect the same Run rather than start another Compute.
pub(all) enum ClientRunStartAction {
  ReserveDispatch
  ReconcileReservedDispatch
} derive(Eq, Debug)

///|
pub(all) enum ClientRunStartIssue {
  DifferentRequest
  ChangedIntent
  ForeignRunDefinition
  AuthorizationDenied
} derive(Eq, Debug)

///|
/// Decide the start boundary from the exact retained request and Run. The
/// adapter atomically persists ReserveDispatch before physical work. An
/// existing reservation can only be reconciled, even when the caller resends
/// the same Program and request ID.
pub fn prepare_client_run_start(
  requested : ClientRequestIdentity,
  retained : ClientRequestIdentity,
  run_definition : @publication.PublicationContract,
  retained_run_definition_cid : String,
  dispatch_reserved : Bool,
  current_authorization : Bool,
) -> Result[ClientRunStartAction, ClientRunStartIssue] {
  if !current_authorization {
    return Err(AuthorizationDenied)
  }
  match client_request_identity_relation(requested, retained) {
    DifferentRequest => return Err(DifferentRequest)
    ChangedIntent => return Err(ChangedIntent)
    SameRequest => ()
  }
  if @publication.publication_contract_name(run_definition) != "run_definition" ||
    @publication.publication_contract_identity(run_definition) !=
    retained_run_definition_cid {
    return Err(ForeignRunDefinition)
  }
  if dispatch_reserved {
    Ok(ReconcileReservedDispatch)
  } else {
    Ok(ReserveDispatch)
  }
}

///|
/// A retained reservation may be resumed only when the Host durably proves
/// that no physical start claim was made. A missing or legacy observation
/// cannot authorize another Compute. The ordinary start decision still binds
/// exact request intent, Run Definition and current authorization.
pub fn prepare_client_run_physical_start(
  requested : ClientRequestIdentity,
  retained : ClientRequestIdentity,
  run_definition : @publication.PublicationContract,
  retained_run_definition_cid : String,
  dispatch_reserved : Bool,
  physically_unstarted : Bool,
  current_authorization : Bool,
) -> Result[Bool, ClientRunStartIssue] {
  match
    prepare_client_run_start(
      requested, retained, run_definition, retained_run_definition_cid, dispatch_reserved,
      current_authorization,
    ) {
    Ok(ReconcileReservedDispatch) => Ok(physically_unstarted)
    Ok(ReserveDispatch) => Ok(false)
    Err(issue) => Err(issue)
  }
}
