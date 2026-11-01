///|
test "adopted initial Host signs restores and applies its real paired Reviewer candidate" {
  let fixture = paired_initial_reviewer_fixture(attest_host=true)
  native_local_effect_capture_acceptance(true, initial_reviewer=Some(fixture))
  assert_true(fixture.restored && fixture.host_applied)
}
