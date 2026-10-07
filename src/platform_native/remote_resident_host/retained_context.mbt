///|
/// Rebuilt original Run and checked producer, selected from the existing Site
/// journal. This context creates no physical reader, reservation or borrow.
pub struct ResidentRetainedProducerContext {
  intent : @remote.RemoteRetainedInputIntent
  materials : @host.ClientRunMaterials
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
  Ok({ intent, materials, producer, journal, })
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
    @resident.check_resident_materials_current(context.materials, at) is Err(_) {
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
