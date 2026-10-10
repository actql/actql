///|
pub(all) enum ResidentEffectReviewInputIssue {
  Unavailable
  InvalidLimits
  Producer(ResidentEffectProducerCaptureIssue)
  Pins(@strategy.RunIssue)
  Import(@strategy.RunIssue)
  Export(ResidentSourceComputeIssue)
  Read(ResidentEffectProducerCaptureIssue)
  Binding(@host.ClientEffectTransferredArtifactIssue)
  Manifest(@host.ClientEffectLocalManifestIssue)
  Observation(@host.ClientEffectResultImportIssue)
  Evidence(@host.ClientEffectImportedEvidenceIssue)
}

///|
/// A failed preparation can still own a semantic producer borrow. That same
/// handle must be retried before its original Runtime can be released.
pub(all) struct ResidentEffectReviewInputFailure {
  issue : ResidentEffectReviewInputIssue
  pending : ResidentEffectReviewInputContext?
}

///|
/// Borrowed views of existing checked and physical Owners. The context owns
/// their semantic pins; returning these views transfers no holding or permit.
pub(all) struct ResidentEffectReviewInputFacts {
  materials : @host.ClientEffectRunMaterials
  inputs : @strategy.CapturedEffectInputs
  producer : ResidentEffectProducerCapture
  receiver : @host.ClientEffectLocalResultArtifact
  imported : @host.ClientEffectImportedEvidence
  root_index : Int
}

///|
/// Finite original-holder join for the existing one-Source/two-task path.
/// Source, Runtime, Transfer and receiver custody remain with their original
/// Owners. This retains no Provider authorization, approval or scheduler.
struct ResidentEffectReviewInputContext {
  holder : ResidentRetainedConsumer
  consumer : ResidentSourceCompute
  request : @host.ClientRequestIdentity
  retention : @publication.PublicationContract
  export_limits : @host.PublicationOutputExportLimits
  mut producer_pins : ResidentEffectDependencyPins?
  mut inputs : @strategy.CapturedEffectInputs?
  mut exported : @strategy.CapturedEffectLocalResultExport?
  mut receipt : @execution.CompletedRelationExportReceipt?
  mut facts : ResidentEffectReviewInputFacts?
  mut retiring : Bool
  mut closed : Bool
}

///|
fn ResidentEffectReviewInputContext::cancel_export(
  self : ResidentEffectReviewInputContext,
) -> Unit {
  if self.receipt is Some(receipt) {
    @execution.cancel_completed_relation_export_receipt(receipt)
    self.receipt = None
  }
  if self.exported is Some(exported) {
    @execution.cancel_completed_result_relation_export(
      @strategy.captured_effect_local_result_export_preparation(exported),
    )
    |> ignore
    self.exported = None
  }
}

///|
/// Close this connection's private pins only. Cleanup failure retains the
/// same pending owner and revokes further evidence access before returning.
/// A successful retry is idempotent; it is not physical dispatch cleanup.
pub fn ResidentEffectReviewInputContext::close(
  self : ResidentEffectReviewInputContext,
) -> Bool {
  if self.closed {
    return true
  }
  self.retiring = true
  self.cancel_export()
  if self.producer_pins is Some(pins) {
    if !pins.close() {
      return false
    }
    self.producer_pins = None
  }
  if self.inputs is Some(inputs) {
    // This existing operation revokes aliases synchronously; false denotes
    // an already revoked pin, not a physical cleanup confirmation.
    @strategy.release_captured_effect_inputs(inputs) |> ignore
    self.inputs = None
  }
  self.facts = None
  self.closed = true
  true
}

///|
fn ResidentEffectReviewInputContext::reject(
  self : ResidentEffectReviewInputContext,
  issue : ResidentEffectReviewInputIssue,
) -> Result[ResidentEffectReviewInputContext, ResidentEffectReviewInputFailure] {
  let pending = if self.close() { None } else { Some(self) }
  Err({ issue, pending, })
}

///|
/// Recheck the actual journal and receiver borrow, including cancellation,
/// before exposing the checked evidence to Preview or Result capture.
pub fn ResidentEffectReviewInputContext::facts(
  self : ResidentEffectReviewInputContext,
  journal : @journal.Journal,
) -> ResidentEffectReviewInputFacts? {
  guard !self.retiring &&
    !self.closed &&
    self.holder.effect_computation(journal) is Some(consumer) &&
    physical_equal(consumer, self.consumer) &&
    self.inputs is Some(inputs) &&
    consumer.request_for_effect_review(inputs) == Some(self.request) else {
    return None
  }
  self.facts
}

///|
/// Retention is selected by the trusted caller before the original producer
/// artifact is issued. A later Provider review cannot substitute another policy.
pub fn ResidentEffectReviewInputContext::retention_matches(
  self : ResidentEffectReviewInputContext,
  retention : @publication.PublicationContract,
) -> Bool {
  !self.retiring &&
  !self.closed &&
  @publication.publication_contract_identity(self.retention) ==
  @publication.publication_contract_identity(retention)
}

///|
pub fn ResidentEffectReviewInputContext::matches_holder(
  self : ResidentEffectReviewInputContext,
  holder : ResidentRetainedConsumer,
  journal : @journal.Journal,
) -> Bool {
  physical_equal(self.holder, holder) && self.facts(journal) is Some(_)
}

///|
/// Capture the actual consumer Result from the original acquired Source and
/// invocation. Normalization and binding metadata must come from the trusted
/// Host; this connection does not invent a normalization journal. The returned
/// export is separately owned and must retire before this context is closed.
pub fn ResidentEffectReviewInputContext::capture_result(
  self : ResidentEffectReviewInputContext,
  journal : @journal.Journal,
  normalization : @publication.RunEvidenceValue,
  binding_names : Array[String],
  binding_digests : Array[String],
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ResidentEffectResultCapture, ResidentEffectResultCaptureIssue] {
  guard self.facts(journal) is Some(facts) else { return Err(Unavailable) }
  self.consumer.capture_effect_result(
    facts.materials,
    facts.inputs,
    facts.imported,
    facts.producer.invocation,
    facts.producer.observation,
    self.retention,
    normalization,
    binding_names,
    binding_digests,
    [@host.client_effect_acquired_observation(facts.producer.acquired)],
    self.export_limits,
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// Resolve the input from the checked consumer edge, then bind the original
/// producer Artifact to this holder's already-admitted receiver holding. No
/// caller-authored input name, fresh observation or reconstructed cells can
/// replace those Owners. All newly acquired pins have a cleanup owner before
/// any further fallible operation. Normalization metadata and Provider policy
/// remain trusted caller inputs to subsequent existing capture operations.
pub fn ResidentRetainedConsumer::prepare_effect_review_inputs(
  self : ResidentRetainedConsumer,
  journal : @journal.Journal,
  producer : ResidentEffectProducerExecuted,
  producer_journal : @journal.Journal,
  consumer_stage : Int,
  import_index : Int,
  retention : @publication.PublicationContract,
  export_limits : @host.PublicationOutputExportLimits,
  max_pins : Int,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ResidentEffectReviewInputContext, ResidentEffectReviewInputFailure] {
  if max_pins <= 0 ||
    max_work <= 0 ||
    max_work > 1000000 ||
    max_bytes <= 0 ||
    max_nodes <= 0 ||
    max_depth <= 0 {
    return Err({ issue: InvalidLimits, pending: None, })
  }
  guard self.effect_computation(journal) is Some(consumer) &&
    consumer.effect_materials_for_capture() is Some(materials) &&
    materials.request is Some(request) &&
    consumer.effect_run() is Some(run) &&
    producer.request_for_capture(producer_journal) == Some(request) else {
    return Err({ issue: Unavailable, pending: None, })
  }
  let owner : ResidentEffectReviewInputContext = {
    holder: self,
    consumer,
    request,
    retention,
    export_limits,
    producer_pins: None,
    inputs: None,
    exported: None,
    receipt: None,
    facts: None,
    retiring: false,
    closed: false,
  }
  let dependency = match
    producer.prepare_dependency_capture(
      producer_journal, retention, export_limits, max_pins, max_work, max_bytes,
      max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(failure) => {
      owner.producer_pins = failure.pending
      return owner.reject(Producer(failure.issue))
    }
  }
  owner.producer_pins = Some(dependency.pins)
  let inputs = match @strategy.pin_captured_effect_sources(run, max_pins) {
    Ok(value) => value
    Err(issue) => return owner.reject(Pins(issue))
  }
  owner.inputs = Some(inputs)
  let captured = match
    @strategy.capture_effect_result_import(
      inputs, consumer_stage, import_index, max_work,
    ) {
    Ok(value) => value
    Err(issue) => return owner.reject(Import(issue))
  }
  let mut root_index = -1
  for index in 0..<@strategy.captured_effect_local_result_count(inputs) {
    if @strategy.captured_effect_local_result_at(inputs, index) is Some(result) &&
      @strategy.captured_effect_result_import_matches(
        captured, inputs, consumer_stage, result,
      ) {
      root_index = index
      break
    }
  }
  if root_index < 0 {
    return owner.reject(Unavailable)
  }
  let exported = match
    consumer.prepare_effect_result_export(inputs, root_index, export_limits) {
    Ok(value) => value
    Err(issue) => return owner.reject(Export(issue))
  }
  owner.exported = Some(exported)
  let receipt = match finish_effect_dependency_export(exported, max_work) {
    Ok(value) => value
    Err(issue) => return owner.reject(Read(issue))
  }
  owner.receipt = Some(receipt)
  let receiver = match
    consumer.bind_effect_retained_result_artifact(
      materials,
      inputs,
      captured,
      exported,
      receipt,
      dependency.token,
    ) {
    Ok(value) => value
    Err(issue) => return owner.reject(Binding(issue))
  }
  let manifest = match
    @host.issue_client_effect_local_manifest(
      materials.prepared,
      @host.client_effect_local_artifact_invocation(receiver),
      [receiver],
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return owner.reject(Manifest(issue))
  }
  let observation = match
    @host.issue_client_effect_result_import_observation(
      materials.prepared,
      inputs,
      captured,
      manifest,
      receiver,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return owner.reject(Observation(issue))
  }
  let imported = match
    @host.issue_client_effect_imported_evidence(
      materials.prepared,
      inputs,
      consumer_stage,
      [observation],
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return owner.reject(Evidence(issue))
  }
  owner.facts = Some({
    materials,
    inputs,
    producer: dependency,
    receiver,
    imported,
    root_index,
  })
  owner.cancel_export()
  if owner.facts(journal) is None {
    return owner.reject(Unavailable)
  }
  Ok(owner)
}
