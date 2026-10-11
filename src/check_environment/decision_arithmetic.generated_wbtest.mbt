// Generated independent binary64 boundary vectors.

///|
test "Decision fixed arithmetic margin exact and next representation" {
  let profile = initial_jev_decision_profile()
  assert_true(decision_distribution_error_allowed(0.015000999999999999, 3, profile))
  assert_false(decision_distribution_error_allowed(0.015001, 3, profile))
  assert_true(decision_score_error_allowed(0.020001, 3.0, profile))
  assert_false(decision_score_error_allowed(0.020001000000000005, 3.0, profile))
  assert_false(decision_score_error_allowed(0.0, 9007199254740992.0, profile))
}
