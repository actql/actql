///|
pub(all) enum NativeClientEffectCaptureIssue {
  Original(NativeClientSourceWorkIssue)
  Capture(@resident.ResidentLocalEffectCaptureIssue)
}

///|
/// Assemble existing capture Owners for the original accepted Local Run.
/// This does not commit waiting, approve a write or establish public delivery.
pub fn NativeClientEffectSourceWork::prepare_capture_context(
  self : NativeClientEffectSourceWork,
  retention : @publication.PublicationContract,
  normalization : @publication.RunEvidenceValue,
  limits : @host.PublicationOutputExportLimits,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_pins? : Int = 4,
  max_work? : Int = 10000,
) -> Result[
  @resident.ResidentLocalEffectCaptureContext,
  NativeClientEffectCaptureIssue,
] {
  match self.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(Original(issue))
  }
  self.owner
  .prepare_local_effect_capture_context(
    self.materials,
    self.request,
    self.capture_started_at,
    self.capture_completed_at,
    retention,
    normalization,
    limits,
    max_pins,
    max_work,
    max_bytes,
    max_nodes,
    max_depth,
    () => self.require_current() is Ok(_),
  )
  .map_err(issue => Capture(issue))
}
