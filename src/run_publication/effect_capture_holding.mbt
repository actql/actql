///|
/// An exact private capture binding issued only after the existing computation
/// evidence Owner validates the original Run, Preview and complete capture.
/// This authorizes physical custody, never approval or execution.
struct EffectCaptureHoldingBinding {
  authority : String
  holding : String
  capture : PublicationContract
}

///|
pub fn prepare_effect_capture_holding_binding(
  run : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  artifacts : Array[PublicationContract],
  manifest : PublicationContract,
  receipt : PublicationContract,
  captured : PublicationContract,
  preview : EffectPreviewIdentity,
  store_authority : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[EffectCaptureHoldingBinding, RunEvidenceChainIssue] {
  guard effect_computation_record_holding_cid(run, store_authority)
    is Some(holding) else {
    return Err(EvidenceReferenceMismatch("store_authority_cid"))
  }
  match
    validate_effectful_computation_evidence_chain(
      run, invocation, definitions, artifacts, manifest, receipt, captured, preview,
      max_bytes, max_nodes, max_depth,
    ) {
    Ok(_) => Ok({ authority: store_authority, holding, capture: captured, })
    Err(issue) => Err(issue)
  }
}

///|
pub fn effect_capture_holding_authority(
  binding : EffectCaptureHoldingBinding,
) -> String {
  binding.authority
}

///|
pub fn effect_capture_holding_identity(
  binding : EffectCaptureHoldingBinding,
) -> String {
  binding.holding
}

///|
pub fn effect_capture_holding_contract(
  binding : EffectCaptureHoldingBinding,
) -> PublicationContract {
  binding.capture
}
