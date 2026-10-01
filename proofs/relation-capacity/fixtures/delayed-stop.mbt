///|
/// Expected-failure reproducer, copied only by repro-delayed-stop.mjs. It is
/// deliberately outside the ordinary MoonBit suites and the capacity proof.
test "delayed stop registered callback preserves actual child work" {
  let sequence = chain_evidence_sequence(2)
  let actual = chain_evidence_family(sequence, chain_evidence_probe())
  let cancelled = Ref(false)
  let stopped = Ref(false)
  let stop_polls = Ref(0)
  let child_work = Ref(0L)
  let computes = Ref(0)
  let family = @local_connector.managed_provider(
    s => @local_connector.managed_provider_accepts(actual, s),
    s => @local_connector.managed_provider_capacity(actual, s),
    fn(_, _, _, _, _) {
      Ok(
        @local_connector.managed_provider_execution(
          quantum => {
            if quantum != 1 || stopped.val {
              return Err(@connector.InvalidLimits)
            }
            child_work.val += 1L
            if cancelled.val {
              stop_polls.val += 1
              if stop_polls.val == 3 {
                stopped.val = true
                Ok(@local_connector.managed_provider_stopped_poll(0L, 1L))
              } else {
                Ok(@local_connector.managed_provider_continue(0L, 1L))
              }
            } else {
              computes.val += 1
              Ok(@local_connector.managed_provider_continue(0L, 1L))
            }
          },
          fn() {
            let changed = !cancelled.val
            cancelled.val = true
            changed
          },
          fn() { stopped.val },
          fn() { Ok(stopped.val) },
        ),
      )
    },
  )
  // Actual existing module registration and chain selection, not a second
  // owner or a direct call to a private chain function.
  let provider = chain_evidence_provider(sequence, family)
  let active = @local_connector.start_managed_provider_with_execution(
    provider, sequence, [], 100, 10000,
    { ..dispatch_test_limits().local_execution, max_work: 1, },
  ).unwrap()
  let mut reported = 0L
  let mut failed = false
  for _ in 0..<4 {
    match @local_connector.advance_managed_provider(active, 1).unwrap() {
      @local_connector.Continue(work~, ..) => reported += work
      @local_connector.Failed(_, work~, ..) => {
        reported += work
        failed = true
      }
      _ => fail("unexpected delayed stop reproduction")
    }
  }
  assert_true(failed)
  assert_true(@local_connector.managed_provider_stopped(active))
  assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
  assert_eq(computes.val, 1)
  println(
    "DELAYED_STOP_RECEIPT parent=" + reported.to_string() +
    " child=" + child_work.val.to_string() +
    " stop_polls=" + stop_polls.val.to_string(),
  )
  // The real child did 4 units, while current chain reports only 3. Do not
  // change this expectation to bless the discarded terminal child work.
  assert_eq(reported, child_work.val)
}
