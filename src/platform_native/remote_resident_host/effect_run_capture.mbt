///|
pub(all) enum ResidentEffectRunCaptureIssue {
  Unavailable
  Context(@host.ClientEffectCapturedRunIssue)
  Capture(@publication.CapturedRunIssuanceIssue)
}

///|
/// Complete the existing Captured Run issuer with the actual Native Result,
/// retained Source dependency closure and checked Preview plan proof. The
/// result is semantic capture evidence, not encrypted Store persistence,
/// waiting, approval, an Effect outcome or release. Parent Result export and
/// original Source/receiver/private payload custody remain with their owners.
pub fn ResidentSourceCompute::capture_effect_run(
  self : ResidentSourceCompute,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  result : ResidentEffectResultCapture,
  invocation : @publication.PublicationContract,
  preview : @strategy.CapturedEffectPreviewInputs,
  proofs : Array[@strategy.CapturedEffectPlanProof],
  sources : Array[@publication.CapturedEffectSourceArtifact],
  local_sources : Array[@publication.CapturedLocalEffectSourceEvidence],
  inventory : @publication.CapturedEffectDependencyInventory,
  authoring : @publication.RunEvidenceValue,
  max_fields : Int,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_workspace : Int,
) -> Result[@publication.PublicationContract, ResidentEffectRunCaptureIssue] {
  let current = () => self.resident_effect_inputs_current(inputs)
  if !current() {
    return Err(Unavailable)
  }
  let preparation = match
    @host.prepare_client_effect_captured_run(
      materials,
      inputs,
      preview,
      proofs,
      invocation,
      [result.definition],
      [result.artifact],
      result.manifest,
      result.receipt,
      [result.snapshot],
      sources,
      local_sources,
      inventory,
      authoring,
      max_fields,
      max_work,
      max_bytes,
      max_nodes,
      max_depth,
      max_workspace,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Context(issue))
  }
  while true {
    if !current() {
      preparation.cancel()
      return Err(Unavailable)
    }
    match preparation.advance(16) {
      Ok((true, _)) => break
      Ok(_) => ()
      Err(issue) => {
        preparation.cancel()
        return Err(Capture(issue))
      }
    }
  }
  if !current() {
    preparation.cancel()
    return Err(Unavailable)
  }
  let captured = preparation
    .finish()
    .map_err(issue => ResidentEffectRunCaptureIssue::Capture(issue))
  preparation.cancel()
  captured
}
