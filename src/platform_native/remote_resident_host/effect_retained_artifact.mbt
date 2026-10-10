///|
/// The already-admitted destination reader remains owned by the existing
/// retained output. Keeping this reference does not acquire another borrow.
priv struct ResidentEffectRetainedCapture {
  dispatch : @remote.DispatchRequest
  input : @output.NativeRemoteRetainedTaskInput
  material : @transfer_client.NativeRemoteDestinationMaterialUse
  current : @output.NativeRemoteRetainedInputCurrent
}

///|
/// Join original producer semantic evidence to this exact decoded destination.
/// The producer Artifact is not regenerated from receiver Cells. This initial
/// live handoff is distinct from restoring saved semantic bodies after restart.
pub fn ResidentSourceCompute::bind_effect_retained_result_artifact(
  self : ResidentSourceCompute,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  captured : @strategy.CapturedEffectResultImport,
  exported : @strategy.CapturedEffectLocalResultExport,
  receipt : @execution.CompletedRelationExportReceipt,
  artifact : @host.ClientEffectProducerArtifact,
) -> Result[
  @host.ClientEffectLocalResultArtifact,
  @host.ClientEffectTransferredArtifactIssue,
] {
  guard !self.stopping &&
    self.effect_run is Some(run) &&
    self.effect_retained is Some(retained) else {
    return Err(Unavailable)
  }
  if !@strategy.captured_effect_inputs_match_run(inputs, run) {
    return Err(ForeignInput)
  }
  @host.bind_transferred_client_effect_local_result_artifact(
    materials,
    inputs,
    captured,
    exported,
    receipt,
    artifact,
    retained.input.common,
    retained.current.common,
    () => {
      !self.stopping &&
      @strategy.captured_effect_inputs_match_run(inputs, run) &&
      @output.validate_native_remote_retained_task_input_borrow(
        retained.input,
        retained.material,
        retained.current,
      )
      is Ok(_)
    },
  )
}
