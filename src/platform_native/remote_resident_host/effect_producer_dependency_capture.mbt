///|
pub(all) enum ResidentEffectProducerCaptureIssue {
  Unavailable
  WorkLimit
  Source(ResidentEffectSourceEvidenceIssue)
  Invocation(ResidentEffectCapturedInvocationIssue)
  Pins(@strategy.RunIssue)
  Export(@strategy.CapturedEffectLocalResultExportIssue)
  Read(@execution.CompletedExportIssue)
  Definition(@host.ClientEffectLocalResultDefinitionIssue)
  Artifact(@host.ClientEffectLocalResultArtifactIssue)
  Manifest(@host.ClientEffectLocalManifestIssue)
  Binding(@host.ClientEffectTransferredArtifactIssue)
}

///|
pub(all) struct ResidentEffectProducerCaptureFailure {
  issue : ResidentEffectProducerCaptureIssue
  pending : ResidentEffectDependencyPins?
}

///|
/// Only the semantic capture borrows and export workspace are owned here.
/// Source, producer Runtime, Transfer and receiver remain separately owned.
struct ResidentEffectDependencyPins {
  inputs : @strategy.CapturedEffectLocalUnitInputs
  mut exported : @strategy.CapturedEffectLocalResultExport?
  mut receipt : @execution.CompletedRelationExportReceipt?
  mut released : Bool
}

///|
/// Returning these borrows does not confirm physical producer cleanup. A
/// failed return preserves the same handle; successful close is idempotent.
pub fn ResidentEffectDependencyPins::close(
  self : ResidentEffectDependencyPins,
) -> Bool {
  if self.released {
    return true
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
  if !@strategy.release_captured_effect_local_unit_inputs(self.inputs) {
    return false
  }
  self.released = true
  true
}

///|
/// Original producer evidence for the finite one-Source/two-task handoff.
/// Receiver admission must still check its actual Transfer and current borrow.
pub(all) struct ResidentEffectProducerCapture {
  pins : ResidentEffectDependencyPins
  acquired : @host.ClientEffectAcquiredEvidence
  acquired_bodies : (String, String)
  observation : @publication.RunEvidenceValue
  invocation : @publication.PublicationContract
  artifact : @host.ClientEffectLocalResultArtifact
  manifest : @host.ClientEffectLocalManifest
  token : @host.ClientEffectProducerArtifact
}

///|
fn reject_effect_dependency_capture(
  issue : ResidentEffectProducerCaptureIssue,
  pins? : ResidentEffectDependencyPins? = None,
) -> Result[ResidentEffectProducerCapture, ResidentEffectProducerCaptureFailure] {
  let pending = match pins {
    Some(owner) => if owner.close() { None } else { Some(owner) }
    None => None
  }
  Err({ issue, pending, })
}

///|
/// Bound both preparation and streaming passes. This computes identities from
/// existing retained output only; it never acquires or executes a Source.
fn finish_effect_dependency_export(
  exported : @strategy.CapturedEffectLocalResultExport,
  max_steps : Int,
) -> Result[
  @execution.CompletedRelationExportReceipt,
  ResidentEffectProducerCaptureIssue,
] {
  let preparation = @strategy.captured_effect_local_result_export_preparation(
    exported,
  )
  let mut steps = 0
  while true {
    if steps >= max_steps {
      return Err(WorkLimit)
    }
    steps += 1
    match @execution.advance_completed_result_relation_export(preparation, 16) {
      Ok((true, _)) => break
      Ok(_) => ()
      Err(issue) => return Err(Read(issue))
    }
  }
  let stream = match
    @execution.finish_completed_result_relation_export_preparation(preparation) {
    Ok(value) => value
    Err(issue) => return Err(Read(issue))
  }
  while true {
    if steps >= max_steps {
      return Err(WorkLimit)
    }
    steps += 1
    match @execution.next_completed_output_export(stream) {
      Ok(None) => break
      Ok(Some(_)) => ()
      Err(issue) => return Err(Read(issue))
    }
  }
  @execution.finish_completed_relation_export(stream)
  .map(value => value.0)
  .map_err(issue => Read(issue))
}

///|
/// Capture the actual completed producer's original journal observation and
/// checked Result. No caller-supplied name, observation time, Run identity or
/// authority substitutes for those Owners. Retention comes from the trusted
/// publication policy and grants no Effect authorization.
pub fn ResidentEffectProducerExecuted::prepare_dependency_capture(
  self : ResidentEffectProducerExecuted,
  journal : @journal.Journal,
  retention : @publication.PublicationContract,
  limits : @host.PublicationOutputExportLimits,
  max_pins : Int,
  max_export_steps : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ResidentEffectProducerCapture, ResidentEffectProducerCaptureFailure] {
  if max_export_steps <= 0 {
    return reject_effect_dependency_capture(WorkLimit)
  }
  guard self.source_for_capture(journal) is Some(source) &&
    self.materials_for_capture(journal) is Some(materials) &&
    source.effect_run() is Some(run) else {
    return reject_effect_dependency_capture(Unavailable)
  }
  let (acquired, acquired_bodies) = match
    self.acquired_evidence_for_capture(
      journal, retention, limits, max_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return reject_effect_dependency_capture(Source(issue))
  }
  let (observation, invocation) = match
    self.invocation_for_capture(journal, max_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(issue) => return reject_effect_dependency_capture(Invocation(issue))
  }
  let inputs = match
    @strategy.pin_captured_effect_acquired_unit_results(run, 0, max_pins) {
    Ok(value) => value
    Err(issue) => return reject_effect_dependency_capture(Pins(issue))
  }
  let pins : ResidentEffectDependencyPins = {
    inputs,
    exported: None,
    receipt: None,
    released: false,
  }
  guard @strategy.captured_effect_local_unit_result_count(inputs) == 1 &&
    @strategy.captured_effect_local_unit_result_at(inputs, 0) is Some(result) &&
    @strategy.captured_effect_local_result_stage(result) == 0 &&
    @strategy.captured_effect_local_result_task(result) == 0 else {
    return reject_effect_dependency_capture(Unavailable, pins=Some(pins))
  }
  let exported = match
    @strategy.start_captured_effect_local_unit_result_export(
      inputs,
      0,
      {
        max_fields: limits.max_result_fields,
        max_mapping_work: limits.max_result_mapping_work,
        max_order_work: limits.max_result_order_work,
        max_workspace_entries: limits.max_result_workspace_entries,
      },
      limits.max_rows,
      limits.values,
      limits.payload_wire,
      limits.logical_wire,
      limits.schema,
      limits.max_batch_bytes,
    ) {
    Ok(value) => value
    Err(issue) =>
      return reject_effect_dependency_capture(Export(issue), pins=Some(pins))
  }
  pins.exported = Some(exported)
  let receipt = match
    finish_effect_dependency_export(exported, max_export_steps) {
    Ok(value) => value
    Err(issue) =>
      return reject_effect_dependency_capture(issue, pins=Some(pins))
  }
  pins.receipt = Some(receipt)
  let name = @execution.managed_result_occurrence_name(
    @strategy.captured_any_result_borrow_occurrence(
      @strategy.captured_effect_local_result_borrow(result),
    ),
  )
  let definition = match
    @host.issue_client_effect_local_result_definition(
      materials.prepared,
      0,
      name,
      max_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) =>
      return reject_effect_dependency_capture(
        Definition(issue),
        pins=Some(pins),
      )
  }
  let artifact = match
    @host.issue_acquired_client_effect_unit_result_artifact(
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
    Err(issue) =>
      return reject_effect_dependency_capture(Artifact(issue), pins=Some(pins))
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
    Err(issue) =>
      return reject_effect_dependency_capture(Manifest(issue), pins=Some(pins))
  }
  let token = match source.bind_effect_producer_artifact(artifact) {
    Ok(value) => value
    Err(issue) =>
      return reject_effect_dependency_capture(Binding(issue), pins=Some(pins))
  }
  if self.source_for_capture(journal) is None {
    return reject_effect_dependency_capture(Unavailable, pins=Some(pins))
  }
  Ok({
    pins,
    acquired,
    acquired_bodies,
    observation,
    invocation,
    artifact,
    manifest,
    token,
  })
}
