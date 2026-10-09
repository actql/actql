///|
pub(all) enum ResidentEffectResultCaptureIssue {
  Unavailable
  Context(@host.ClientEffectLocalResultArtifactIssue)
  Native(ResidentSourceComputeIssue)
  Export(@host.PublicationOutputExportIssue)
  Manifest(@publication.ResultManifestIssuanceIssue)
  Receipt(@publication.RunReceiptIssuanceIssue)
}

///|
/// Actual completed Named Result and its pre-Effect computation evidence.
/// The existing export owns its Result borrow; the caller must cancel it after
/// persistence or on failure. These contracts are not a Store commit, a waiting
/// transition, approval, a final Effect Receipt or a cleanup observation.
pub(all) struct ResidentEffectResultCapture {
  output : @host.PublicationOutputExport
  definition : @publication.PublicationContract
  artifact : @publication.PublicationContract
  manifest : @publication.PublicationContract
  receipt : @publication.PublicationContract
  snapshot : @publication.CapturedResultSnapshot
}

///|
/// Capture this consumer's actual Named Result through the existing export,
/// Manifest and Receipt Owners. Private local Result Artifacts cannot replace
/// this checked public occurrence. Only newly created export/snapshot work is
/// cancelled on failure; original retained inputs and payload custody stay live.
pub fn ResidentSourceCompute::capture_effect_result(
  self : ResidentSourceCompute,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  imported : @host.ClientEffectImportedEvidence,
  invocation : @publication.PublicationContract,
  observation : @publication.RunEvidenceValue,
  retention : @publication.PublicationContract,
  normalization_journal : @publication.RunEvidenceValue,
  binding_names : Array[String],
  binding_digests : Array[String],
  source_evidence : Array[@publication.RunEvidenceValue],
  limits : @host.PublicationOutputExportLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ResidentEffectResultCapture, ResidentEffectResultCaptureIssue] {
  let current = () => self.resident_effect_inputs_current(inputs)
  if !current() {
    return Err(Unavailable)
  }
  let (computation, relations, scope, policy, authority) = match
    @host.client_effect_imported_result_evidence_refs(
      materials, inputs, imported, invocation, observation, retention,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Context(issue))
  }
  if !current() {
    return Err(Unavailable)
  }
  let output = match self.prepare_result_export(limits) {
    Ok(value) => value
    Err(issue) => return Err(Native(issue))
  }
  let reject = (issue : ResidentEffectResultCaptureIssue) => {
    output.cancel()
    Err(issue)
  }
  while true {
    if !current() {
      return reject(Unavailable)
    }
    match output.next() {
      Ok(Some(_)) => ()
      Ok(None) => break
      Err(issue) => return reject(Export(issue))
    }
  }
  match output.finish() {
    Ok(_) => ()
    Err(issue) => return reject(Export(issue))
  }
  if !current() {
    return reject(Unavailable)
  }
  match
    output.issue_result_evidence(
      computation, relations, scope, policy, authority, max_wire_bytes, max_nodes,
      max_depth,
    ) {
    Ok(_) => ()
    Err(issue) => return reject(Export(issue))
  }
  let definition = match output.definition() {
    Ok(value) => value
    Err(issue) => return reject(Export(issue))
  }
  let artifact = match
    output.issue_artifact(
      invocation, retention, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return reject(Export(issue))
  }
  let manifest = match
    @publication.issue_result_manifest(
      materials.run_definition,
      invocation,
      [definition],
      [artifact],
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return reject(Manifest(issue))
  }
  // This is the computation Receipt before Effect execution, matching the
  // existing Host capture protocol. A final Effect Receipt remains separate.
  let receipt = match
    @publication.issue_effect_free_run_receipt(
      @host.client_effect_allowed_run_admission(materials.allowed),
      materials.run_definition,
      invocation,
      observation,
      [definition],
      [artifact],
      manifest,
      normalization_journal,
      binding_names,
      binding_digests,
      source_evidence,
      [],
      [],
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return reject(Receipt(issue))
  }
  let preparation = match
    output.start_captured_snapshot(max_wire_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(issue) => return reject(Export(issue))
  }
  while true {
    if !current() {
      preparation.cancel()
      return reject(Unavailable)
    }
    match preparation.advance(16) {
      Ok((true, _)) => break
      Ok(_) => continue
      Err(issue) => {
        preparation.cancel()
        return reject(Export(issue))
      }
    }
  }
  let snapshot = match preparation.finish() {
    Ok(value) => value
    Err(issue) => {
      preparation.cancel()
      return reject(Export(issue))
    }
  }
  if !current() {
    return reject(Unavailable)
  }
  Ok({ output, definition, artifact, manifest, receipt, snapshot, })
}
