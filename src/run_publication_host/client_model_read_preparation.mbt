///|
// The physical descriptor's origin is issued from the original checked Run.
// It cannot be constructed from a JSON usage aggregate or a reported Run CID.
// Opaque module type so the same Resource token can be projected without a
// second wrapper. Construction and every field remain private to this Owner.
struct ClientModelReadOrigin {
  compiled : ClientCompiledRun
  definition_cid : String
  plan : ClientInferPlanGraph
  host_policy_cid : String
  execution_context_cid : String
}

///|
// The census is issued before any child resources. Its one original Run/Host
// binding may follow preparation; it never reconstructs a used Ledger census.
struct ClientModelReadScope {
  origin : ClientModelReadOrigin
  ledger : @resources.Ledger
  identity : @resources.OriginalLedgerIdentity
  group : ClientModelReadGroup?
  retained_bytes : Int64
  execution_bytes : Int64
  mut read_attempted : Bool
  mut finished : Bool
}

///|
// This Owner's two actual records above. The group slot borrows its existing
// closed Scope set; byte partitions and lifecycle flags are scalar fields. All
// original identity fields borrow originals;
// CID getters return retained strings and create no copied UTF16 backing.
let client_model_read_scope_construction_units : @execution.PreparationRepresentationUnits = {
  record_headers: 2L,
  reference_slots: 9L,
  scalar_words: 4L,
  owned_utf16_units: 0L,
  owned_wire_bytes: 0L,
}

///|
/// Immutable construction DATA, not a byte allowance or Scope/permission.
/// The original caller must fund this and its census growth before binding.
pub fn client_model_read_scope_construction_inventory() -> @execution.PreparationRepresentationUnits {
  // The existing Resource claim now retains a resident optional closed-child
  // reference even on the singular path. Back it on the same original scope
  // entrance before that later claim allocation; it issues no child/grant.
  let slots = @resources.original_read_children_construction_slots(1).unwrap()
  {
    ..client_model_read_scope_construction_units,
    record_headers: client_model_read_scope_construction_units.record_headers +
    slots.0,
    reference_slots: client_model_read_scope_construction_units.reference_slots +
    slots.1 +
    1L,
    scalar_words: client_model_read_scope_construction_units.scalar_words +
    slots.2 +
    2L,
  }
}

///|
struct ClientModelReadPreparation {
  origin : ClientModelReadOrigin
  claim : @resources.FundedReadClaim[ClientModelReadOrigin]
  consumer : @resources.FundedReadConsumer[ClientModelReadOrigin]?
  mut consumer_claimed : Bool
  mut retired : Bool
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
pub fn begin_client_model_read_scope(
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  ledger : @resources.Ledger,
  bootstrap : @resources.CapacityReservation,
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
) -> Result[ClientModelReadScope, ClientModelReadPreparationIssue] {
  // No Run authentication or binding allocation precedes the funded envelope.
  if !@resources.original_read_bootstrap_available(ledger, bootstrap) {
    return Err(InvalidBootstrap)
  }
  if !client_compiled_run_has_infer(compiled, plan) ||
    check_client_compiled_run_definition(compiled, definition) is Err(_) {
    return Err(ForeignRun)
  }
  let identity = match
    @resources.begin_original_ledger_inventory(
      ledger, bootstrap, max_reservations, max_holdings, max_delegations,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Resource(issue))
  }
  bind_client_model_read_scope(compiled, definition, plan, ledger, identity)
}

///|
// The initial preparation owner has already registered every original child
// on this identity. Bind the actual compiled Model once, without dropping
// preparation history or demanding a second pristine Ledger. Equal bounds,
// a foreign Ledger/Run or a second scope cannot replace this association.
pub fn bind_client_model_read_scope(
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  ledger : @resources.Ledger,
  identity : @resources.OriginalLedgerIdentity,
) -> Result[ClientModelReadScope, ClientModelReadPreparationIssue] {
  if !client_compiled_run_has_infer(compiled, plan) ||
    check_client_compiled_run_definition(compiled, definition) is Err(_) {
    return Err(ForeignRun)
  }
  match @resources.claim_original_ledger_run_binding(identity, ledger) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
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
  Ok({
    origin,
    ledger,
    identity,
    group: None,
    retained_bytes: 0L,
    execution_bytes: 0L,
    read_attempted: false,
    finished: false,
  })
}

///|
pub fn prepare_client_model_read(
  scope : ClientModelReadScope,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[ClientModelReadPreparation, ClientModelReadPreparationIssue] {
  if scope.group is Some(group) {
    return prepare_client_model_group_read(
      scope, group, retained_bytes, execution_bytes,
    )
  }
  let origin = scope.origin
  let ledger = scope.ledger
  let descriptor = match
    @resources.issue_recorded_original_ledger_descriptor(scope.identity, origin) {
    Ok(value) => value
    Err(issue) => return Err(Resource(issue))
  }
  match
    @resources.fund_original_read(
      ledger, origin, descriptor, retained_bytes, execution_bytes,
    ) {
    Ok(claim) =>
      Ok({
        origin,
        claim,
        consumer: None,
        consumer_claimed: false,
        retired: false,
      })
    Err(issue) => Err(Resource(issue))
  }
}

///|
// The original owning Run retains this scope when layout/descriptor/read
// admission fails before a preparation exists. Its final cleanup uses the
// same census/bootstrap; no Ledger projection or reconstructed binding is
// needed. The acknowledgement covers the owning Run, not merely read failure.
// Existing live-child checks still prevent early return after successful issue.
pub fn finish_client_model_read_scope(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  original_run_cleanup_complete : Bool,
) -> Result[Bool, ClientModelReadPreparationIssue] {
  if !client_model_origin_matches(scope.origin, compiled, definition, plan) {
    return Err(ForeignRun)
  }
  if scope.group is Some(group) {
    return finish_client_model_group_scope(
      scope, group, original_run_cleanup_complete,
    )
  }
  @resources.finish_original_ledger_inventory(
    scope.ledger,
    original_run_cleanup_complete,
  ).map_err(issue => Resource(issue))
}

///|
fn client_model_read_origin_matches(
  value : ClientModelReadPreparation,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
) -> Bool {
  client_model_origin_matches(value.origin, compiled, definition, plan)
}

///|
fn client_model_origin_matches(
  origin : ClientModelReadOrigin,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
) -> Bool {
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
// Lifetime of the SAME original scope, not availability for allocation or
// permission to send. A legitimate park remains live until its original
// Resource owner closes/retires it. Never expose its Ledger/bootstrap fields.
pub fn client_model_read_scope_live(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
) -> Bool {
  client_model_origin_matches(scope.origin, compiled, definition, plan) &&
  @resources.original_ledger_inventory_live(scope.identity)
}

///|
/// Same original preparation census only. This pure identity projection is
/// used before the existing Run adoption; a live Scope on a foreign Ledger
/// cannot replace it even when its compiled Run and Plan are the same.
/// It performs no current callback, admission, descriptor issue or Model send.
pub fn client_model_read_scope_original_inventory(
  scope : ClientModelReadScope,
  ledger : @resources.Ledger,
  identity : @resources.OriginalLedgerIdentity,
) -> Bool {
  physical_equal(scope.ledger, ledger) &&
  physical_equal(scope.identity, identity) &&
  @resources.original_ledger_inventory_live(identity)
}

///|
pub fn client_model_read_available(
  value : ClientModelReadPreparation,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
) -> Bool {
  client_model_read_origin_matches(value, compiled, definition, plan) &&
  (match value.consumer {
    Some(consumer) =>
      !value.consumer_claimed &&
      @resources.funded_read_consumer_available(consumer, value.origin, 1L, 1L)
    None => @resources.funded_read_available(value.claim, value.origin)
  })
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
// Verify already reserved derivation workspace on this exact checked Run/Host
// read. The consumer still derives its complete overlap envelope separately.
// Check the retained envelope before constructing its original preparation or
// Execution as well. This verifies an existing token, without reserving again.
pub fn client_model_read_preparation_available(
  value : ClientModelReadPreparation,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  execution_bytes : Int64,
  retained_bytes? : Int64 = 0L,
) -> Bool {
  if value.consumer is Some(consumer) {
    return client_model_read_origin_matches(value, compiled, definition, plan) &&
      !value.consumer_claimed &&
      @resources.funded_read_consumer_available(
        consumer,
        value.origin,
        Int64::max(1L, retained_bytes),
        execution_bytes,
      )
  }
  client_model_read_origin_matches(value, compiled, definition, plan) &&
  @resources.funded_read_preparation_available(
    value.claim,
    value.origin,
    execution_bytes,
    retained_bytes~,
  )
}

///|
// The same original checked Run owner transfers byte custody atomically.
// This does not authenticate arbitrary PreparedInferRows, select a physical
// profile or authorize Model dispatch; those checked boundaries remain separate.
pub fn handoff_client_model_read_capacity(
  value : ClientModelReadPreparation,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[
  (@resources.Ledger, @resources.CapacityReservation),
  ClientModelReadPreparationIssue,
] {
  if !client_model_read_origin_matches(value, compiled, definition, plan) {
    return Err(ForeignRun)
  }
  @resources.handoff_funded_read_capacity(
    value.claim,
    value.origin,
    retained_bytes,
    execution_bytes,
  ).map_err(issue => Resource(issue))
}

///|
pub fn stop_client_model_read(
  value : ClientModelReadPreparation,
) -> Result[Unit, ClientModelReadPreparationIssue] {
  let result = match value.consumer {
    Some(consumer) => @resources.stop_funded_read_consumer(consumer)
    None => @resources.stop_funded_read(value.claim)
  }
  result.map_err(issue => Resource(issue))
}

///|
pub fn settle_client_model_read(
  value : ClientModelReadPreparation,
  physical_cleanup_complete : Bool,
) -> Result[Unit, ClientModelReadPreparationIssue] {
  let result = match value.consumer {
    Some(consumer) =>
      @resources.settle_funded_read_consumer(
        consumer, physical_cleanup_complete,
      )
    None =>
      @resources.settle_funded_read(value.claim, physical_cleanup_complete)
  }
  if result is Ok(_) {
    value.retired = true
  }
  result.map_err(issue => Resource(issue))
}

///|
// The original owning Run calls this only on its final cleanup path. Read
// retirement alone does not acknowledge other Run children/FD/Store cleanup.
// No Ledger getter or reconstructed origin is added for this finalization.
pub fn finish_client_model_read_inventory(
  value : ClientModelReadPreparation,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  original_run_cleanup_complete : Bool,
) -> Result[Bool, ClientModelReadPreparationIssue] {
  if !client_model_read_origin_matches(value, compiled, definition, plan) {
    return Err(ForeignRun)
  }
  @resources.finish_funded_read_inventory(
    value.claim,
    value.origin,
    original_run_cleanup_complete,
  ).map_err(issue => Resource(issue))
}
