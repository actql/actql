///|
test "preflight failure projection distinguishes only the original typed stale version" {
  let issue = CapturedEffectApplyPreflightIssue::Guard(
    Current(@effect.StalePreview(2, 3)),
  )
  assert_true(captured_effect_apply_preflight_target_version_changed(issue))
  for
    other in [
      CapturedEffectApplyPreflightIssue::Binding(NotReady),
      Guard(InvalidLimits),
      Guard(NotReady),
      Guard(Current(@effect.InvalidObservation(0))),
      Guard(Current(@effect.DuplicateObservation(0))),
      Guard(Current(@effect.MissingObservation(2, 3))),
      Guard(Current(@effect.ForeignObservation)),
      Guard(Current(@effect.ForeignRecoveryEvidence)),
    ] {
    assert_false(captured_effect_apply_preflight_target_version_changed(other))
  }
}
