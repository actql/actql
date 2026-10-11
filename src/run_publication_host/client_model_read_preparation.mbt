///|
// The physical descriptor's origin is issued from the original checked Run.
// It cannot be constructed from a JSON usage aggregate or a reported Run CID.
priv struct ClientModelReadOrigin {
  compiled : ClientCompiledRun
  definition_cid : String
  plan : ClientInferPlanGraph
  host_policy_cid : String
  execution_context_cid : String
}

///|
struct ClientModelReadPreparation {
  origin : ClientModelReadOrigin
  claim : @resources.FundedReadClaim[ClientModelReadOrigin]
}

///|
pub(all) enum ClientModelReadPreparationIssue {
  ForeignRun
  InvalidBootstrap
  Resource(@resources.OriginalReadIssue)
} derive(Eq, Debug)

///|
// The existing Run owner reserves bootstrap before this call, including this
// binding, descriptor inventory and checker/authentication workspace. Profile
// coefficients and durable descriptor admission are not established here.
pub fn prepare_client_model_read(
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  ledger : @resources.Ledger,
  bootstrap : @resources.CapacityReservation,
  reservations : Array[@resources.Reservation],
  holdings : Array[@resources.Holding],
  delegations : Array[@resources.ExecutionDelegation],
  max_items : Int,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[ClientModelReadPreparation, ClientModelReadPreparationIssue] {
  // No Run authentication or binding allocation precedes the funded envelope.
  if !@resources.original_read_bootstrap_available(ledger, bootstrap) {
    return Err(InvalidBootstrap)
  }
  if !client_compiled_run_has_infer(compiled, plan) ||
    check_client_compiled_run_definition(compiled, definition) is Err(_) {
    return Err(ForeignRun)
  }
  let origin : ClientModelReadOrigin = {
    compiled,
    definition_cid: @publication.publication_contract_identity(definition),
    plan,
    host_policy_cid: @publication.run_publication_host_policy(
      compiled.admission,
    ),
    execution_context_cid: @publication.run_publication_execution_context(
      compiled.admission,
    ),
  }
  let descriptor = match
    @resources.issue_original_ledger_descriptor(
      ledger, origin, bootstrap, reservations, holdings, delegations, max_items,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Resource(issue))
  }
  match
    @resources.fund_original_read(
      ledger, origin, descriptor, retained_bytes, execution_bytes,
    ) {
    Ok(claim) => Ok({ origin, claim, })
    Err(issue) => Err(Resource(issue))
  }
}

///|
fn client_model_read_origin_matches(
  value : ClientModelReadPreparation,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
) -> Bool {
  let origin = value.origin
  physical_equal(origin.compiled, compiled) &&
  physical_equal(origin.plan, plan) &&
  @publication.publication_contract_identity(definition) ==
  origin.definition_cid &&
  @publication.run_publication_host_policy(compiled.admission) ==
  origin.host_policy_cid &&
  @publication.run_publication_execution_context(compiled.admission) ==
  origin.execution_context_cid
}

///|
pub fn client_model_read_available(
  value : ClientModelReadPreparation,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
) -> Bool {
  client_model_read_origin_matches(value, compiled, definition, plan) &&
  @resources.funded_read_available(value.claim, value.origin)
}

///|
// This is a ledger handoff, not model-send authorization. Existing current
// authority, egress, fence and dispatch checks are still required downstream.
pub fn handoff_client_model_read(
  value : ClientModelReadPreparation,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
) -> Result[@resources.Ledger, ClientModelReadPreparationIssue] {
  if !client_model_read_origin_matches(value, compiled, definition, plan) {
    return Err(ForeignRun)
  }
  @resources.handoff_funded_read(value.claim, value.origin).map_err(issue => {
    Resource(issue)
  })
}

///|
pub fn stop_client_model_read(value : ClientModelReadPreparation) -> Unit {
  @resources.stop_funded_read(value.claim)
}

///|
pub fn settle_client_model_read(
  value : ClientModelReadPreparation,
  physical_cleanup_complete : Bool,
) -> Result[Unit, ClientModelReadPreparationIssue] {
  @resources.settle_funded_read(value.claim, physical_cleanup_complete).map_err(issue => {
      Resource(issue)
    },
  )
}
