///|
/// Routing/label tests only; no current Owner, Review or response is mocked.
test "holder Cloud Resume read keeps the installed observation origin and Site path" {
  let scope = "https://cloud.example/v1/sites/site-a/generations/4"
  assert_eq(
    holder_effect_resume_current_url(scope + "/outbound/observations"),
    Some(scope + "/outbound/effect-resume-current"),
  )
  for
    url in [
      "http://cloud.example/v1/sites/site-a/generations/4/outbound/observations",
      scope + "/outbound/poll",
      scope + "/outbound/observations?alternate=1",
      scope + "/outbound/observations#alternate",
      scope + "/outbound/observations/",
    ] {
    assert_eq(holder_effect_resume_current_url(url), None)
  }
}

///|
test "holder Cloud Resume challenges distinguish same-clock reads without changing dispatch identity" {
  let dispatch = "sha256:" + "a".repeat(64)
  let first = holder_effect_resume_query_id(dispatch, 1000L, 1L).unwrap()
  let second = holder_effect_resume_query_id(dispatch, 1000L, 2L).unwrap()
  assert_false(first == second)
  assert_eq(first, dispatch + ":1000:1")
  for (clock, sequence) in [(-1L, 1L), (1000L, 0L), (1000L, 9007199254740992L)] {
    assert_eq(holder_effect_resume_query_id(dispatch, clock, sequence), None)
  }
}
