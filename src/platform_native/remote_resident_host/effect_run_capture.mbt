///|
pub(all) enum ResidentEffectRunCaptureIssue {
  Unavailable
  Context(@host.ClientEffectCapturedRunIssue)
  Capture(@publication.CapturedRunIssuanceIssue)
}

///|
/// Fixed diagnostic phases, never execution permission or durable evidence.
pub(all) enum ResidentEffectRunCapturePhase {
  Preparing
  Prepared
  Advancing
  Completed
} derive(Eq)

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
  progress? : (ResidentEffectRunCapturePhase, Int64, Int64) -> Unit = (_, _, _) => {
    ()
  },
) -> Result[@publication.PublicationContract, ResidentEffectRunCaptureIssue] {
  let current = () => self.resident_effect_inputs_current(inputs)
  if !current() {
    return Err(Unavailable)
  }
  progress(Preparing, 0L, 0L)
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
  progress(Prepared, 0L, 0L)
  let mut advances = 0L
  let mut logical_work = 0L
  let mut next_progress = 1L
  while true {
    if !current() {
      preparation.cancel()
      return Err(Unavailable)
    }
    let (done, used) = match preparation.advance(16) {
      Ok(value) => value
      Err(issue) => {
        preparation.cancel()
        return Err(Capture(issue))
      }
    }
    advances += 1L
    logical_work += used.to_int64()
    // Sparse progress does not change the issuer's quantum or work contract.
    // Check current custody after every diagnostic callback as well as every
    // advance: even a trusted observer may retire its original inputs.
    if advances == next_progress {
      progress(Advancing, advances, logical_work)
      next_progress *= 2L
    }
    if done {
      break
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
  if captured is Ok(_) {
    progress(Completed, advances, logical_work)
    if !current() {
      return Err(Unavailable)
    }
  }
  captured
}
