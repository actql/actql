///|
// Actual Common selection through the real Node bridge, not a JS object
// standing in for an opaque probability profile. This issues no capability.
test "Node native probability selector reuses the registered Common precision identity" {
  let selected = client_program_initial_jev_decision_profile()
  assert_eq(
    @check_environment.decision_probability_profile_cid(selected),
    "sha256:55dae6c0400f1d8da79714cd232f94c2fa05334078f86278244e1c6935ff3e7f",
  )
  assert_eq(
    @check_environment.decision_probability_profile_cid(selected),
    @check_environment.decision_probability_profile_cid(
      @check_environment.initial_jev_decision_profile(),
    ),
  )
}
