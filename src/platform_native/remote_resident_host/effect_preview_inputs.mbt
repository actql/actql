///|
/// Bind the checked Preview to this Native consumer's current retained inputs.
/// Target observations and capability evidence must be supplied by their
/// existing provider Owners; this operation does not author or approve them.
pub fn ResidentSourceCompute::bind_effect_preview_inputs(
  self : ResidentSourceCompute,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  invocation : @publication.PublicationContract,
  stage : Int,
  preview_wire : String,
  authoring_context_cid : String,
  identities : Array[@host.ClientEffectLocalIdentity],
  limits : @host.ClientCapturedEffectPreviewLimits,
) -> Result[
  @strategy.CapturedEffectPreviewInputs,
  @host.ClientCapturedEffectPreviewIssue,
] {
  guard !self.stopping && self.effect_run is Some(run) else {
    return Err(Unavailable)
  }
  let current = () => self.resident_effect_inputs_current(inputs)
  if !current() {
    return Err(Unavailable)
  }
  let preview = @host.bind_captured_client_effect_preview(
    materials, run, inputs, invocation, stage, preview_wire, authoring_context_cid,
    identities, limits,
  )
  // Current callbacks can revoke or close the holding before this bind returns.
  if !current() {
    return Err(Unavailable)
  }
  preview
}

///|
fn ResidentSourceCompute::resident_effect_inputs_current(
  self : ResidentSourceCompute,
  inputs : @strategy.CapturedEffectInputs,
) -> Bool {
  guard !self.stopping &&
    self.effect_run is Some(run) &&
    @strategy.captured_effect_inputs_match_run(inputs, run) else {
    return false
  }
  resident_effect_input_custody_current(
    run,
    self.effect_retained,
    self.source_closed,
    inputs,
  )
}

///|
fn resident_effect_input_custody_current(
  run : @strategy.CapturedEffectRunDAG,
  retained : ResidentEffectRetainedCapture?,
  source_closed : Ref[Bool],
  inputs : @strategy.CapturedEffectInputs,
) -> Bool {
  if !@strategy.captured_effect_inputs_match_run(inputs, run) {
    return false
  }
  match retained {
    Some(retained) =>
      @output.validate_native_remote_retained_task_input_borrow(
        retained.input,
        retained.material,
        retained.current,
      )
      is Ok(_)
    None => !source_closed.val
  }
}
