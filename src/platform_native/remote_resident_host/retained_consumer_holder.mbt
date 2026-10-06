///|
/// One exact consumer inside the original producer holder. The existing Site
/// journal owns its dispatch/start record, Transfer owns the independent
/// receiver and borrow, and Runtime owns its execution/output cleanup.
/// No Source acquisition, physical borrow or reservation occurs at preparation.
pub struct ResidentRetainedConsumer {
  handoff : ResidentRetainedTransfer
  producer_journal : @journal.Journal
  request : @remote.DispatchRequest
  binding : @remote.RemoteInputBinding
  current : @output.NativeRemoteRetainedInputCurrent
  binding_limits : @output.NativeRemoteStandardTransferBindingLimits
  codec : @output.NativeRemoteStandardRowCodec
  mut material : @transfer_client.NativeRemoteDestinationMaterialUse?
  mut executed : ResidentExecuted?
  mut pending_runtime : @runtime.NativeRemoteRuntime?
  mut failure : ResidentRetainedExecutionIssue?
  mut closing : Bool
  mut closed : Bool
}

///|
fn retained_consumer_failure(
  issue : ResidentRetainedExecutionIssue,
) -> ResidentRetainedExecutionFailure {
  { issue, pending_runtime: None, }
}

///|
fn retained_consumer_input(
  handoff : ResidentRetainedTransfer,
  producer_journal : @journal.Journal,
  materials : @host.ClientRunMaterials,
  request : @remote.DispatchRequest,
  binding : @remote.RemoteInputBinding,
  current : @output.NativeRemoteRetainedInputCurrent,
  limits : @output.NativeRemoteStandardTransferBindingLimits,
) -> Result[
  @output.NativeRemoteRetainedTaskInput,
  @output.NativeRemoteRetainedTaskInputIssue,
] {
  if handoff.reclaimed ||
    handoff.cleanup_started ||
    handoff.result is None ||
    handoff.require_current() is Err(_) {
    return Err(@output.ProducerUnavailable)
  }
  guard materials.compilation is @host.Tasks(compilation) &&
    resident_source_dispatch_role(materials, handoff.dispatch)
    is Ok(InternalSourceProducer) else {
    return Err(@output.InvalidBinding)
  }
  let edge = match
    @host.prepare_client_retained_input_edge(
      materials.prepared,
      compilation,
      materials.admission,
      materials.run_definition,
      1,
      0,
    ) {
    Ok(value) => value
    Err(_) => return Err(@output.InvalidBinding)
  }
  let projection = @host.client_retained_input_edge_projection(edge)
  if @remote.dispatch_request_task_scope(request) !=
    (projection[0], projection[5]) ||
    !@remote.remote_input_binding_matches_dispatch(binding, request) ||
    @remote.dispatch_request_execution_scope(request) !=
    @remote.dispatch_request_execution_scope(handoff.dispatch) {
    return Err(@output.InvalidBinding)
  }
  let observation = match producer_journal.observation(handoff.dispatch) {
    Ok(value) => value
    Err(_) => return Err(@output.ProducerUnavailable)
  }
  guard @journal.recovered_site_dispatch_evidence(observation) is Some(evidence) &&
    @journal.recovered_site_dispatch_subject(observation) is Some(subject) else {
    return Err(@output.ProducerUnavailable)
  }
  let record = match producer_journal.require(handoff.dispatch) {
    Ok(value) => value
    Err(_) => return Err(@output.ProducerUnavailable)
  }
  let producer = match
    @host.prepare_client_retained_input_producer(
      edge, record, evidence, subject,
    ) {
    Ok(value) => value
    Err(_) => return Err(@output.ProducerUnavailable)
  }
  let committed = match handoff.journal.require(handoff.request) {
    Ok(value) => value
    Err(_) => return Err(@output.ForeignTransfer)
  }
  let receipt = match
    handoff.journal.inspect_destination_receipt(handoff.request) {
    Ok(Some(value)) if handoff.receipt_cid ==
      Some(@transfer.destination_receipt_cid(value)) => value
    _ => return Err(@output.ForeignTransfer)
  }
  let input = match
    @output.restore_native_remote_retained_task_input(
      binding, producer, committed, receipt, current, limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // The existing Direct receiver Owner supplies this material-use role; the
  // saved binding must not choose another provider or invent its own use.
  if @output.native_remote_retained_task_input_destination_use_id(input) !=
    "direct-destination" {
    return Err(@output.ForeignTransfer)
  }
  if handoff.require_current() is Err(_) {
    return Err(@output.ProducerUnavailable)
  }
  Ok(input)
}

///|
pub fn prepare_resident_retained_consumer(
  handoff : ResidentRetainedTransfer,
  producer_journal : @journal.Journal,
  admission : ResidentRunAdmission,
  dispatch : @remote.RemotePollDispatch,
  at : String,
  limits : @output.NativeRemoteStandardTransferBindingLimits,
) -> Result[ResidentRetainedConsumer, ResidentRetainedExecutionFailure] {
  let request = @remote.remote_poll_dispatch_request(dispatch)
  let binding = @remote.remote_poll_dispatch_input_binding(dispatch)
  guard @remote.remote_poll_dispatch_run_materials(dispatch) is Some(body) else {
    return Err(retained_consumer_failure(Host(EnvelopeMissing)))
  }
  let materials = match rebuild_materials(admission, request, body) {
    Ok(value) => value
    Err(issue) => return Err(retained_consumer_failure(Host(Refused(issue))))
  }
  match @resident.check_resident_materials_current(materials, at) {
    Ok(_) => ()
    Err(issue) => return Err(retained_consumer_failure(Host(Refused(issue))))
  }
  let current = @output.install_native_remote_retained_input_owner_current(
    handoff.current,
  )
  match
    retained_consumer_input(
      handoff, producer_journal, materials, request, binding, current, limits,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(retained_consumer_failure(Input(issue)))
  }
  if handoff.consumer is Some(consumer) {
    if @remote.dispatch_request_identity(consumer.request) ==
      @remote.dispatch_request_identity(request) &&
      @remote.remote_input_binding_body(consumer.binding) ==
      @remote.remote_input_binding_body(binding) {
      return Ok(consumer)
    }
    return Err(retained_consumer_failure(Input(@output.InvalidBinding)))
  }
  let codec = match
    @output.register_native_remote_standard_row_codec(
      @transfer.request_schema_contract_cid(handoff.request),
      @transfer.request_view_contract_cid(handoff.request),
      @transfer.request_codec_contract_cid(handoff.request),
    ) {
    Ok(value) => value
    Err(_) =>
      return Err(retained_consumer_failure(Input(@output.InvalidBinding)))
  }
  let consumer : ResidentRetainedConsumer = {
    handoff,
    producer_journal,
    request,
    binding,
    current,
    binding_limits: limits,
    codec,
    material: None,
    executed: None,
    pending_runtime: None,
    failure: None,
    closing: false,
    closed: false,
  }
  handoff.consumer = Some(consumer)
  Ok(consumer)
}

///|
pub fn resident_retained_consumer_request(
  consumer : ResidentRetainedConsumer,
) -> @remote.DispatchRequest {
  consumer.request
}

///|
/// The consumer is admitted by its live producer holder, not the slot queue.
/// The same authentication/delegation, exact envelope, durable acceptance and
/// transport ACK boundary is used by ordinary resident dispatch admission.
pub fn ResidentRetainedConsumer::accept(
  self : ResidentRetainedConsumer,
  journal : @journal.Journal,
  client : @http.Client,
  observation_url : String,
  delegation : @resident.ResidentSiteDelegation,
  site_generation : Int,
  admission : ResidentRunAdmission,
  dispatch : @remote.RemotePollDispatch,
  at : String,
) -> Result[ResidentAcceptance, ResidentHostIssue] {
  if self.closing ||
    @remote.dispatch_request_identity(
      @remote.remote_poll_dispatch_request(dispatch),
    ) !=
    @remote.dispatch_request_identity(self.request) ||
    @remote.remote_input_binding_body(
      @remote.remote_poll_dispatch_input_binding(dispatch),
    ) !=
    @remote.remote_input_binding_body(self.binding) {
    return Ok(Refused(@resident.ForeignSource))
  }
  match
    @resident.check_resident_dispatch_delegation(
      delegation,
      self.request,
      site_generation,
    ) {
    Ok(_) => ()
    Err(issue) => return Ok(Refused(issue))
  }
  guard @remote.remote_poll_dispatch_run_materials(dispatch) is Some(body) else {
    return Ok(Refused(@resident.MaterialsMissing))
  }
  let materials = match rebuild_materials(admission, self.request, body) {
    Ok(value) => value
    Err(issue) => return Ok(Refused(issue))
  }
  match @resident.check_resident_materials_current(materials, at) {
    Ok(_) => ()
    Err(issue) => return Ok(Refused(issue))
  }
  match
    retained_consumer_input(
      self.handoff,
      self.producer_journal,
      materials,
      self.request,
      self.binding,
      self.current,
      self.binding_limits,
    ) {
    Ok(_) => ()
    Err(_) => return Ok(Refused(@resident.ForeignSource))
  }
  retain_and_acknowledge_resident_dispatch(
    journal,
    client,
    observation_url,
    self.request,
    self.binding,
    body,
    () => (),
  )
}

///|
/// The caller first persists and acknowledges this exact consumer envelope in
/// its existing Site journal. Repeated calls retain the same Runtime/borrow;
/// the exclusive start Owner also refuses a restored nonstartable attempt.
pub fn ResidentRetainedConsumer::execute(
  self : ResidentRetainedConsumer,
  journal : @journal.Journal,
  execution : ResidentExecution,
  admission : ResidentRunAdmission,
  configuration : ResidentSourceComputeConfiguration,
  input_limits : @output.NativeRemoteStandardTransferSourceLimits,
  claimant : String,
  current_time : () -> String,
  executor_entry : ((String) -> Bool)?,
) -> Result[ResidentExecuted, ResidentRetainedExecutionFailure] {
  if self.closing {
    return Err(retained_consumer_failure(Input(@output.ProducerUnavailable)))
  }
  if self.executed is Some(value) {
    return Ok(value)
  }
  if self.failure is Some(issue) {
    return Err({ issue, pending_runtime: self.pending_runtime, })
  }
  let record = match journal.require(self.request) {
    Ok(value) => value
    Err(issue) => return Err(retained_consumer_failure(Host(Journal(issue))))
  }
  if !@remote.remote_runtime_record_startable(record) {
    return Err(retained_consumer_failure(Host(Refused(@resident.NotCurrent))))
  }
  if self.handoff.require_current() is Err(_) {
    return Err(retained_consumer_failure(Input(@output.ProducerUnavailable)))
  }
  if self.material is None {
    self.material = Some(
      match
        @transfer_client.pin_durable_direct_destination_material(
          self.handoff.journal,
          self.handoff.root,
          self.handoff.request,
          @remote.dispatch_request_identity(self.request),
          self.handoff.receipt_cid.unwrap(),
        ) {
        Ok(value) => value
        Err(issue) =>
          return Err(
            retained_consumer_failure(Input(@output.InputMaterial(issue))),
          )
      },
    )
  }
  let attempt = match @remote.dispatch_request_attempt_identity(self.request) {
    Ok(value) => value
    Err(issue) => return Err(retained_consumer_failure(Host(Protocol(issue))))
  }
  match
    execute_resident_retained_attempt(
      journal,
      execution,
      admission,
      configuration,
      (materials, binding) => {
        if @remote.remote_input_binding_body(binding) !=
          @remote.remote_input_binding_body(self.binding) {
          return Err(@output.InvalidBinding)
        }
        retained_consumer_input(
          self.handoff,
          self.producer_journal,
          materials,
          self.request,
          binding,
          self.current,
          self.binding_limits,
        )
      },
      self.material.unwrap(),
      self.codec,
      input_limits,
      self.current,
      attempt,
      claimant,
      current_time,
      executor_entry,
    ) {
    Ok(value) => {
      self.executed = Some(value)
      Ok(value)
    }
    Err(failure) => {
      self.failure = Some(failure.issue)
      self.pending_runtime = failure.pending_runtime
      Err(failure)
    }
  }
}

///|
/// Release through Runtime, then return only this borrow. Receiver and producer
/// holdings remain with their separate existing Owners. Failed cleanup keeps
/// the same Runtime/material for retry and returns no holding reservation.
pub fn ResidentRetainedConsumer::close(self : ResidentRetainedConsumer) -> Bool {
  if self.closed {
    return true
  }
  self.closing = true
  if self.executed is Some(executed) {
    match executed.runtime.release(self.request) {
      Ok(_) if !executed.runtime.retains_dispatch_resources() => ()
      _ => return false
    }
    match executed.runtime.close() {
      Ok(_) => self.executed = None
      Err(_) => return false
    }
  }
  if self.pending_runtime is Some(runtime) {
    match runtime.close() {
      Ok(_) => self.pending_runtime = None
      Err(_) => return false
    }
  }
  if self.material is Some(material) {
    match @transfer_client.release_destination_material_use(material) {
      Ok(_) => self.material = None
      Err(_) => return false
    }
  }
  self.closed = true
  true
}
