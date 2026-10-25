///|
// Keep the original opaque family; Effect materials are not an ordinary Run.
priv enum ResidentRetainedProducerMaterials {
  OrdinaryMaterials(@host.ClientRunMaterials)
  EffectMaterials(@host.ClientEffectRunMaterials)
}

///|
fn resident_retained_producer_materials_current(
  materials : ResidentRetainedProducerMaterials,
  at : String,
) -> Bool {
  match materials {
    OrdinaryMaterials(value) =>
      @resident.check_resident_materials_current(value, at) is Ok(_)
    EffectMaterials(value) =>
      @host.client_effect_run_start_current(
        value.allowed,
        value.run_definition,
        at,
      )
  }
}

///|
/// Rebuilt original Run and checked producer, selected from the existing Site
/// journal. This context creates no physical reader, reservation or borrow.
pub struct ResidentRetainedProducerContext {
  intent : @remote.RemoteRetainedInputIntent
  run_current : (String) -> Bool
  producer : @host.ClientRetainedInputProducer
  journal : @journal.Journal
}

///|
pub fn prepare_resident_retained_producer_context(
  journal : @journal.Journal,
  admission : ResidentRunAdmission,
  intent : @remote.RemoteRetainedInputIntent,
  at : String,
) -> Result[ResidentRetainedProducerContext, ResidentHostIssue] {
  let request = @remote.remote_retained_input_intent_request(intent)
  let attempt = match @remote.dispatch_request_attempt_identity(request) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  let envelope = match journal.dispatch_envelope(attempt) {
    Ok(Some(value)) => value
    Ok(None) => return Err(EnvelopeMissing)
    Err(issue) => return Err(Journal(issue))
  }
  let dispatch = match @remote.admit_remote_poll_dispatch_json(envelope) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  if @remote.dispatch_request_identity(
      @remote.remote_poll_dispatch_request(dispatch),
    ) !=
    @remote.dispatch_request_identity(request) {
    return Err(Protocol(@remote.DispatchIdentityMismatch))
  }
  guard @remote.remote_poll_dispatch_run_materials(dispatch) is Some(body) else {
    return Err(EnvelopeMissing)
  }
  let materials = match
    admit_resident_chain_materials(
      admission,
      request,
      body,
      @remote.remote_poll_dispatch_input_binding(dispatch),
      at,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Refused(issue))
  }
  guard resident_linear_task_index(materials, request) is Some(task) &&
    task + 1 <
    @strategy.graph_task_count(@host.prepared_client_graph(materials.prepared)) else {
    return Err(Refused(@resident.UnsupportedTask))
  }
  guard materials.compilation is @host.Tasks(compilation) else {
    return Err(Refused(@resident.UnsupportedTask))
  }
  let edge = match
    @host.prepare_client_retained_input_edge(
      materials.prepared,
      compilation,
      materials.admission,
      materials.run_definition,
      task + 1,
      0,
    ) {
    Ok(value) => value
    Err(_) => return Err(Refused(@resident.UnsupportedTask))
  }
  resident_retained_context_from_edge(
    journal,
    intent,
    request,
    OrdinaryMaterials(materials),
    edge,
  )
}

///|
fn resident_retained_context_from_edge(
  journal : @journal.Journal,
  intent : @remote.RemoteRetainedInputIntent,
  request : @remote.DispatchRequest,
  materials : ResidentRetainedProducerMaterials,
  edge : @host.ClientRetainedInputEdge,
) -> Result[ResidentRetainedProducerContext, ResidentHostIssue] {
  let observation = match journal.observation(request) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  guard @journal.recovered_site_dispatch_evidence(observation) is Some(evidence) &&
    @journal.recovered_site_dispatch_subject(observation) is Some(subject) else {
    return Err(Protocol(@remote.InvalidDispatch))
  }
  let record = match journal.require(request) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  let producer = match
    @host.prepare_client_retained_input_producer(
      edge, record, evidence, subject,
    ) {
    Ok(value) => value
    Err(_) => return Err(Protocol(@remote.InvalidDispatch))
  }
  match @host.validate_client_retained_input_intent(producer, intent) {
    Ok(_) => ()
    Err(_) => return Err(Protocol(@remote.DispatchIdentityMismatch))
  }
  Ok({
    intent,
    producer,
    journal,
    run_current: at => {
      resident_retained_producer_materials_current(materials, at)
    },
  })
}

///|
/// Inspect the live journal and local delegation at each handoff, rather than
/// treating a saved record or historical authorization as current permission.
/// A cancellation request withholds movement; it does not imply Cancelled or
/// cleanup completion. Failure retains existing resource responsibilities.
pub fn resident_retained_producer_authorized(
  context : ResidentRetainedProducerContext,
  delegation : @resident.ResidentRetainedInputDelegation,
  request : @transfer.RemoteTransferRequest,
  site_generation : Int,
  at : String,
) -> Bool {
  let producer = context.producer
  let dispatch = @host.client_retained_input_producer_dispatch(producer)
  if @resident.check_resident_retained_input_delegation(
      delegation, dispatch, request, site_generation,
    )
    is Err(_) ||
    !(context.run_current)(at) {
    return false
  }
  if @remote.prepare_remote_retained_input_plan(
      context.intent,
      @host.client_retained_input_producer_subject(producer),
      @host.client_retained_input_producer_evidence(producer),
      request,
    )
    is Err(_) {
    return false
  }
  if !(context.journal.cancellation_requested(dispatch) is Ok(false)) {
    return false
  }
  let record = match context.journal.require(dispatch) {
    Ok(value) => value
    Err(_) => return false
  }
  @host.prepare_client_retained_input_producer(
    @host.client_retained_input_producer_edge(producer),
    record,
    @host.client_retained_input_producer_evidence(producer),
    @host.client_retained_input_producer_subject(producer),
  )
  is Ok(_)
}

///|
pub fn resident_retained_producer(
  context : ResidentRetainedProducerContext,
) -> @host.ClientRetainedInputProducer {
  context.producer
}

///|
/// Reconstruct the original Effect producer from its exact saved envelope and
/// actual journal completion. Existing Transfer/current Owners still authorize
/// every physical movement; this context allocates no receiver or borrow and
/// cannot renew the original Run or manufacture Source evidence from Cells.
pub fn prepare_resident_effect_retained_producer_context(
  journal : @journal.Journal,
  admission : ResidentRunAdmission,
  limits : @host.ClientEffectComputationLimits,
  delegation : @resident.ResidentSiteDelegation,
  site_generation : Int,
  intent : @remote.RemoteRetainedInputIntent,
  at : String,
  installed_contracts : @local.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_contract_body : String,
) -> Result[
  ResidentRetainedProducerContext,
  ResidentEffectProducerExecutionIssue,
] {
  let request = @remote.remote_retained_input_intent_request(intent)
  let attempt = match @remote.dispatch_request_attempt_identity(request) {
    Ok(value) => value
    Err(issue) => return Err(Host(Protocol(issue)))
  }
  let envelope = match journal.dispatch_envelope(attempt) {
    Ok(Some(value)) => value
    Ok(None) => return Err(Host(EnvelopeMissing))
    Err(issue) => return Err(Host(Journal(issue)))
  }
  let dispatch = match @remote.admit_remote_poll_dispatch_json(envelope) {
    Ok(value) => value
    Err(issue) => return Err(Host(Protocol(issue)))
  }
  if @remote.dispatch_request_identity(
      @remote.remote_poll_dispatch_request(dispatch),
    ) !=
    @remote.dispatch_request_identity(request) {
    return Err(Host(Protocol(@remote.DispatchIdentityMismatch)))
  }
  guard @remote.remote_poll_dispatch_run_materials(dispatch) is Some(body) else {
    return Err(Host(EnvelopeMissing))
  }
  let (materials, _) = match
    admit_resident_effect_source_dispatch_owned(
      admission,
      limits,
      delegation,
      site_generation,
      request,
      body,
      @remote.remote_poll_dispatch_input_binding(dispatch),
      at,
      // Requirement preparation needs trusted compilation contracts. They are
      // supplied explicitly by the existing Site configuration, not the wire.
      installed_contracts,
      values_body,
      fragment_contract_body,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Dispatch(issue))
  }
  let observation = match journal.observation(request) {
    Ok(value) => value
    Err(issue) => return Err(Host(Journal(issue)))
  }
  guard @journal.recovered_site_dispatch_source_observation(observation)
    is Some(source) &&
    @remote.remote_source_observation_matches_dispatch(source, request) &&
    @remote.remote_source_observation_projection(source).0 == 0 else {
    return Err(Host(Protocol(@remote.InvalidDispatch)))
  }
  let edge = match
    @host.prepare_client_effect_retained_input_edge(
      materials.allowed,
      materials.run_definition,
    ) {
    Ok(value) => value
    Err(_) => return Err(Host(Refused(@resident.UnsupportedTask)))
  }
  resident_retained_context_from_edge(
    journal,
    intent,
    request,
    EffectMaterials(materials),
    edge,
  ).map_err(issue => Host(issue))
}
