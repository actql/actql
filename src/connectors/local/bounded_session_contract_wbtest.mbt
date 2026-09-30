///|
/// Compare actual adapter observations with the contract: successive cumulative
/// counters telescope; terminal is observed once; cleanup has its own retries.
/// Callback errors are observable failures, not empty successful results.
fn check_adapter_contract(
  reports : Array[(Int64, Int64)],
  ending : Int,
) -> Unit raise {
  let calls = Ref(0)
  let cleanup_calls = Ref(0)
  let cancel_calls = Ref(0)
  let issue = @connector.Execution(@execution.InputSet)
  let active = bounded_session_execution(
    _ => {
      let index = calls.val
      calls.val += 1
      let (progress, work) = reports[index]
      if index + 1 < reports.length() {
        Ok(SessionContinue(progress, work))
      } else {
        match ending {
          0 => Ok(SessionFailed(issue, progress, work))
          1 => Ok(SessionStopped(progress, work))
          _ => Err(issue)
        }
      }
    },
    fn() {
      cancel_calls.val += 1
      cancel_calls.val == 1
    },
    fn() {
      cleanup_calls.val += 1
      match cleanup_calls.val {
        1 => Ok(false)
        2 => Err(issue)
        _ => Ok(true)
      }
    },
  )
  assert_true((active.cleanup)() is Ok(false))
  assert_eq(cleanup_calls.val, 0)
  assert_true((active.advance)(0) is Err(@connector.InvalidLimits))
  assert_true((active.advance)(-1) is Err(@connector.InvalidLimits))
  assert_eq(calls.val, 0)
  assert_true((active.cancel)())
  assert_false((active.cancel)())
  assert_eq(cancel_calls.val, 2)
  assert_false((active.stopped)())
  let mut previous_progress = 0L
  let mut previous_work = 0L
  let mut sum_progress = 0L
  let mut sum_work = 0L
  for index in 0..<reports.length() {
    let (progress, work) = reports[index]
    let regressed = progress < previous_progress || work < previous_work
    let callback_error = index + 1 == reports.length() && ending == 2
    let terminal = regressed || index + 1 == reports.length()
    let expected_progress = if regressed || callback_error {
      0L
    } else {
      progress - previous_progress
    }
    let expected_work = if regressed || callback_error {
      0L
    } else {
      work - previous_work
    }
    let observed = (active.advance)(2147483647).unwrap()
    match observed {
      Continue(progress~, work~) => {
        assert_false(terminal)
        assert_eq(progress, expected_progress)
        assert_eq(work, expected_work)
      }
      Failed(actual_issue, progress~, work~) => {
        assert_true(terminal)
        assert_true(regressed || callback_error || ending == 0)
        assert_true(actual_issue is @connector.Execution(@execution.InputSet))
        assert_eq(progress, expected_progress)
        assert_eq(work, expected_work)
      }
      Stopped(progress~, work~) => {
        assert_true(terminal && !regressed && ending == 1)
        assert_eq(progress, expected_progress)
        assert_eq(work, expected_work)
      }
      _ => fail("unexpected contract outcome")
    }
    sum_progress += expected_progress
    sum_work += expected_work
    assert_eq((active.stopped)(), terminal)
    if !regressed && !callback_error {
      assert_eq(sum_progress, progress)
      assert_eq(sum_work, work)
    }
    previous_progress = progress
    previous_work = work
    if terminal {
      assert_eq(calls.val, index + 1)
      break
    }
    assert_true((active.cleanup)() is Ok(false))
    assert_eq(cleanup_calls.val, 0)
  }
  let stopped_calls = calls.val
  assert_true((active.advance)(1) is Err(@connector.InvalidLimits))
  assert_eq(calls.val, stopped_calls)
  assert_true((active.cleanup)() is Ok(false))
  assert_true(
    (active.cleanup)() is Err(@connector.Execution(@execution.InputSet)),
  )
  assert_true((active.cleanup)() is Ok(true))
  assert_true((active.cleanup)() is Ok(true))
  assert_eq(cleanup_calls.val, 3)
  assert_true((active.stopped)())
  assert_true((active.advance)(1) is Err(@connector.InvalidLimits))
  assert_eq(calls.val, stopped_calls)
}

///|
test "adapter contract explores cumulative reports and cleanup histories" {
  // All pairs in this small counter domain, plus explicit Int64 endpoints.
  for p1 in [-1L, 0L, 1L, 2L, 7L] {
    for w1 in [-1L, 0L, 1L, 2L, 7L] {
      for p2 in [-1L, 0L, 1L, 2L, 7L] {
        for w2 in [-1L, 0L, 1L, 2L, 7L] {
          for ending in 0..<3 {
            check_adapter_contract([(p1, w1), (p2, w2)], ending)
          }
        }
      }
    }
  }
  for ending in 0..<3 {
    check_adapter_contract(
      [
        (9223372036854775806L, 9223372036854775806L),
        (9223372036854775807L, 9223372036854775807L),
      ],
      ending,
    )
  }
}
