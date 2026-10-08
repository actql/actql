///|
test "stopped release fault preserves the original journal until owner cleanup" {
  let (_, journal, request, _, _) = cleanup_test_open("stopped-release-fault")
  ignore(journal.accept(request).unwrap())
  let before = journal.request_cancellation(request).unwrap()
  let revision = @remote.dispatch_record_revision(before)
  let codes = @remote.dispatch_record_state_codes(before)
  let hook : StoppedReleaseFailureHook = { remaining: 5, attempts: 0, }
  for attempt = 1; attempt <= 5; attempt = attempt + 1 {
    assert_eq(stopped_release_failure_attempt(hook, false), Some(attempt))
    let pending = journal.require(request).unwrap()
    assert_eq(@remote.dispatch_record_revision(pending), revision)
    assert_eq(@remote.dispatch_record_state_codes(pending), codes)
    assert_true(@remote.dispatch_record_state_codes(pending)[2] != 2)
  }
  assert_eq(stopped_release_failure_attempt(hook, false), None)
  // Only the existing journal/cleanup owner commits a formal terminal.
  assert_true(confirm_unstarted_consumer_cleanup(journal, request))
  let released = journal.require(request).unwrap()
  assert_eq(@remote.dispatch_record_state_codes(released)[2], 2)
  let released_revision = @remote.dispatch_record_revision(released)
  assert_eq(stopped_release_failure_attempt(hook, true), None)
  assert_true(confirm_unstarted_consumer_cleanup(journal, request))
  assert_eq(
    @remote.dispatch_record_revision(journal.require(request).unwrap()),
    released_revision,
  )
  assert_eq(journal.start_claimant(request).unwrap(), None)
  assert_true(journal.close())
}

///|
test "stopped release default and terminal replay never inject pending cleanup" {
  let (_, journal, request, _, _) = cleanup_test_open(
    "stopped-release-fault-default",
  )
  ignore(journal.accept(request).unwrap())
  ignore(journal.request_cancellation(request).unwrap())
  let default_hook : StoppedReleaseFailureHook = { remaining: 0, attempts: 0, }
  assert_eq(stopped_release_failure_attempt(default_hook, false), None)
  assert_true(confirm_unstarted_consumer_cleanup(journal, request))
  let released_revision = @remote.dispatch_record_revision(
    journal.require(request).unwrap(),
  )
  let replay_hook : StoppedReleaseFailureHook = { remaining: 5, attempts: 0, }
  assert_eq(stopped_release_failure_attempt(replay_hook, true), None)
  assert_eq(replay_hook.remaining, 5)
  assert_eq(replay_hook.attempts, 0)
  assert_eq(
    @remote.dispatch_record_revision(journal.require(request).unwrap()),
    released_revision,
  )
  assert_true(journal.close())
}
