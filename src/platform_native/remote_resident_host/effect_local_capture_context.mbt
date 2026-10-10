///|
pub(all) enum ResidentLocalEffectCaptureIssue {
  Unavailable
  InvalidLimits
  Invocation(ResidentEffectSourceInvocationIssue)
  Source(ResidentEffectSourceEvidenceIssue)
  Pins(@strategy.RunIssue)
  Export(ResidentSourceComputeIssue)
  Read(ResidentEffectProducerCaptureIssue)
  Definition(@host.ClientEffectLocalResultDefinitionIssue)
  Artifact(@host.ClientEffectLocalResultArtifactIssue)
  Manifest(@host.ClientEffectLocalManifestIssue)
  Observation(@host.ClientEffectResultImportIssue)
  Imported(@host.ClientEffectImportedEvidenceIssue)
  Result(ResidentEffectResultCaptureIssue)
}

///|
/// Original acquired and imported evidence, borrowed from the same Run. These
/// facts grant neither Provider permission nor public read authorization.
pub(all) struct ResidentLocalEffectCaptureFacts {
  materials : @host.ClientEffectRunMaterials
  inputs : @strategy.CapturedEffectInputs
  acquired : @host.ClientEffectAcquiredEvidence
  acquired_bodies : (String, String)
  producer : @host.ClientEffectLocalResultArtifact
  producer_manifest : @host.ClientEffectLocalManifest
  producer_index : Int
  consumer : @host.ClientEffectLocalResultArtifact
  consumer_index : Int
  imported : @host.ClientEffectImportedEvidence
  observation : @publication.RunEvidenceValue
  invocation : @publication.PublicationContract
  result : ResidentEffectResultCapture
}

///|
/// A finite connection owning only capture pins and exports. The existing
/// acquisition/Compute Owner retains physical cleanup and its retry handle.
struct ResidentLocalEffectCaptureContext {
  source : ResidentSourceCompute
  current : () -> Bool
  mut inputs : @strategy.CapturedEffectInputs?
  mut exported : @strategy.CapturedEffectLocalResultExport?
  mut receipt : @execution.CompletedRelationExportReceipt?
  mut result : ResidentEffectResultCapture?
  mut facts : ResidentLocalEffectCaptureFacts?
  mut closed : Bool
}

///|
pub fn ResidentLocalEffectCaptureContext::close(
  self : ResidentLocalEffectCaptureContext,
) -> Bool {
  if self.closed {
    return true
  }
  self.facts = None
  if self.result is Some(result) {
    result.output.cancel()
    self.result = None
  }
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
  if self.inputs is Some(inputs) {
    // This revokes semantic aliases synchronously. It does not attest to
    // physical cleanup; false means that an alias was already revoked.
    @strategy.release_captured_effect_inputs(inputs) |> ignore
    self.inputs = None
  }
  self.closed = true
  true
}

///|
pub fn ResidentLocalEffectCaptureContext::facts(
  self : ResidentLocalEffectCaptureContext,
) -> ResidentLocalEffectCaptureFacts? {
  guard !self.closed &&
    (self.current)() &&
    self.inputs is Some(inputs) &&
    self.source.resident_effect_inputs_current(inputs) else {
    return None
  }
  self.facts
}

///|
fn ResidentLocalEffectCaptureContext::reject(
  self : ResidentLocalEffectCaptureContext,
  issue : ResidentLocalEffectCaptureIssue,
) -> Result[ResidentLocalEffectCaptureContext, ResidentLocalEffectCaptureIssue] {
  self.close() |> ignore
  Err(issue)
}

///|
/// Capture the supported one-Source/two-Stage Local graph without fabricating
/// a Remote dispatch or receiver. The import proof is issued from the actual
/// checked edge and producer holding. Original observation times and Policy
/// come from the acquisition, not a replacement Host configuration.
pub fn ResidentSourceCompute::prepare_local_effect_capture_context(
  self : ResidentSourceCompute,
  materials : @host.ClientEffectRunMaterials,
  request : @host.ClientRequestIdentity,
  started_at : String,
  completed_at : String,
  retention : @publication.PublicationContract,
  normalization : @publication.RunEvidenceValue,
  limits : @host.PublicationOutputExportLimits,
  max_pins : Int,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  current : () -> Bool,
) -> Result[ResidentLocalEffectCaptureContext, ResidentLocalEffectCaptureIssue] {
  if max_pins <= 0 ||
    max_work <= 0 ||
    max_work > 1000000 ||
    max_bytes <= 0 ||
    max_nodes <= 0 ||
    max_depth <= 0 {
    return Err(InvalidLimits)
  }
  guard current() && self.effect_run() is Some(run) else {
    return Err(Unavailable)
  }
  let (source, observation, invocation) = match
    self.effect_source_publication_invocation(
      materials, request, started_at, completed_at, limits, max_bytes, max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Invocation(issue))
  }
  let (_, _, _, _, policy) = resident_source_publication_observation_values(
    source,
  )
  if !current() {
    return Err(Unavailable)
  }
  let (acquired, acquired_bodies) = match
    self.prepare_effect_acquired_evidence(
      @host.client_request_authority_scope_cid(request),
      policy,
      completed_at,
      retention,
      limits,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Source(issue))
  }
  if !current() {
    return Err(Unavailable)
  }
  let inputs = match
    @strategy.pin_captured_effect_sources(
      run,
      max_pins,
      max_dependency_work=max_work,
      max_dependency_depth=max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Pins(issue))
  }
  let context : ResidentLocalEffectCaptureContext = {
    source: self,
    current,
    inputs: Some(inputs),
    exported: None,
    receipt: None,
    result: None,
    facts: None,
    closed: false,
  }
  if !current() || !self.resident_effect_inputs_current(inputs) {
    return context.reject(Unavailable)
  }
  // This first connection handles the already supported single Effect member
  // whose consumer imports one Result. Other graph shapes stay unsupported.
  guard @strategy.captured_effect_inputs_count(inputs) == 1 &&
    @strategy.captured_effect_input_at(inputs, 0) is Some(effect_input) else {
    return context.reject(Unavailable)
  }
  let consumer = @strategy.captured_effect_input_stage(effect_input)
  let imported_edge = match
    @strategy.capture_effect_result_import(inputs, consumer, 0, max_work) {
    Ok(value) => value
    Err(issue) => return context.reject(Pins(issue))
  }
  let producer = @strategy.captured_effect_result_import_producer(imported_edge)
  let mut producer_index = -1
  for index in 0..<@strategy.captured_effect_local_result_count(inputs) {
    if @strategy.captured_effect_local_result_at(inputs, index) is Some(value) &&
      @strategy.captured_any_result_borrows_share_view(
        @strategy.captured_effect_local_result_borrow(value),
        @strategy.captured_effect_local_result_borrow(producer),
      ) {
      producer_index = index
      break
    }
  }
  if producer_index < 0 {
    return context.reject(Unavailable)
  }
  let exported = match
    self.prepare_effect_result_export(inputs, producer_index, limits) {
    Ok(value) => value
    Err(issue) => return context.reject(Export(issue))
  }
  context.exported = Some(exported)
  let receipt = match finish_effect_dependency_export(exported, max_work) {
    Ok(value) => value
    Err(issue) => return context.reject(Read(issue))
  }
  context.receipt = Some(receipt)
  if !current() {
    return context.reject(Unavailable)
  }
  let producer_name = @execution.managed_result_occurrence_name(
    @strategy.captured_any_result_borrow_occurrence(
      @strategy.captured_effect_local_result_borrow(producer),
    ),
  )
  let definition = match
    @host.issue_client_effect_local_result_definition(
      materials.prepared,
      @strategy.captured_effect_local_result_stage(producer),
      producer_name,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return context.reject(Definition(issue))
  }
  let artifact = match
    @host.issue_acquired_client_effect_local_result_artifact(
      materials.prepared,
      inputs,
      exported,
      acquired,
      definition,
      receipt,
      @host.client_effect_allowed_run_admission(materials.allowed),
      materials.run_definition,
      invocation,
      observation,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return context.reject(Artifact(issue))
  }
  let manifest = match
    @host.issue_client_effect_local_manifest(
      materials.prepared,
      @host.client_effect_acquired_invocation(acquired),
      [artifact],
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return context.reject(Manifest(issue))
  }
  let import_observation = match
    @host.issue_client_effect_result_import_observation(
      materials.prepared,
      inputs,
      imported_edge,
      manifest,
      artifact,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return context.reject(Observation(issue))
  }
  let imported = match
    @host.issue_client_effect_imported_evidence(
      materials.prepared,
      inputs,
      consumer,
      [import_observation],
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return context.reject(Imported(issue))
  }
  // Receipt custody is needed to issue the Artifact; the Artifact and actual
  // input pin retain its provenance after that private export is retired.
  @execution.cancel_completed_relation_export_receipt(receipt)
  context.receipt = None
  @execution.cancel_completed_result_relation_export(
    @strategy.captured_effect_local_result_export_preparation(exported),
  )
  |> ignore
  context.exported = None
  if !current() {
    return context.reject(Unavailable)
  }
  // Locate the actual Effect member's Result, rather than assuming that the
  // consumer occupies the next array slot or using the producer's Artifact.
  let mut consumer_index = -1
  for index in 0..<@strategy.captured_effect_local_result_count(inputs) {
    if @strategy.captured_effect_local_result_matches_member(
        inputs,
        index,
        @strategy.captured_effect_input_member_index(effect_input),
      ) {
      consumer_index = index
      break
    }
  }
  guard consumer_index >= 0 &&
    @strategy.captured_effect_local_result_at(inputs, consumer_index)
    is Some(consumer_result) else {
    return context.reject(Unavailable)
  }
  let exported = match
    self.prepare_effect_result_export(inputs, consumer_index, limits) {
    Ok(value) => value
    Err(issue) => return context.reject(Export(issue))
  }
  context.exported = Some(exported)
  let receipt = match finish_effect_dependency_export(exported, max_work) {
    Ok(value) => value
    Err(issue) => return context.reject(Read(issue))
  }
  context.receipt = Some(receipt)
  if !current() {
    return context.reject(Unavailable)
  }
  let consumer_name = @execution.managed_result_occurrence_name(
    @strategy.captured_any_result_borrow_occurrence(
      @strategy.captured_effect_local_result_borrow(consumer_result),
    ),
  )
  let definition = match
    @host.issue_client_effect_local_result_definition(
      materials.prepared,
      consumer,
      consumer_name,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return context.reject(Definition(issue))
  }
  let consumer_artifact = match
    @host.issue_imported_client_effect_local_result_artifact(
      materials.prepared,
      inputs,
      exported,
      imported,
      definition,
      receipt,
      retention,
      @host.client_effect_allowed_run_admission(materials.allowed),
      materials.run_definition,
      invocation,
      observation,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return context.reject(Artifact(issue))
  }
  // The checked input pin retains the issued Artifact's provenance. Retire
  // this private export before opening the existing public Result capture.
  @execution.cancel_completed_relation_export_receipt(receipt)
  context.receipt = None
  @execution.cancel_completed_result_relation_export(
    @strategy.captured_effect_local_result_export_preparation(exported),
  )
  |> ignore
  context.exported = None
  if !current() {
    return context.reject(Unavailable)
  }
  let result = match
    self.capture_effect_result(
      materials,
      inputs,
      imported,
      invocation,
      observation,
      retention,
      normalization,
      [],
      [],
      [@host.client_effect_acquired_observation(acquired)],
      limits,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return context.reject(Result(issue))
  }
  context.result = Some(result)
  context.facts = Some({
    materials,
    inputs,
    acquired,
    acquired_bodies,
    producer: artifact,
    producer_manifest: manifest,
    producer_index,
    consumer: consumer_artifact,
    consumer_index,
    imported,
    observation,
    invocation,
    result,
  })
  if context.facts() is None {
    return context.reject(Unavailable)
  }
  Ok(context)
}
