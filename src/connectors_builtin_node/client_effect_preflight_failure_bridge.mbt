///|
// Metadata projection of the SAME original returned issue, not another check.
#export_name("clientProgramEffectApplyPreflightTargetVersionChanged")
pub fn client_program_effect_apply_preflight_target_version_changed(
  issue : @strategy.CapturedEffectApplyPreflightIssue,
) -> Bool {
  @strategy.captured_effect_apply_preflight_target_version_changed(issue)
}
