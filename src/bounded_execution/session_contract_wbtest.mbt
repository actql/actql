///|
/// A contract oracle over command history. It knows no Session fields: work
/// is the amount removed from an initial demand, tokens count admitted calls,
/// and reclamation is a separate obligation after an observed terminal result.
fn check_session_contract_trace(commands : Array[Int]) -> Unit raise {
  let owner = control()
  let actual = { current: 0, limit: 3, cleanup_calls: 0, cleanup_ready: false, }
  let (session, first) = start(
    owner,
    actual,
    counter_step,
    state => {
      state.cleanup_calls += 1
      state.cleanup_ready
    },
    _ => true,
  )
  let (_, foreign) = start(control(), actual, counter_step, _ => true, _ => true)
  let mut current = first
  let mut demand = 3
  let mut generations = 0
  let mut stopped = false
  let mut reclaimed = false
  let mut requested : StopReason? = None
  let mut ready = false
  let mut cleanup_attempts = 0
  for command in commands {
    match command {
      0 | 1 | 2 | 3 | 4 => {
        let quantum = if command == 1 {
          2
        } else if command == 4 {
          0
        } else {
          1
        }
        let token = if command == 2 {
          first
        } else if command == 3 {
          foreign
        } else {
          current
        }
        let invalid = if quantum == 0 {
          Some(InvalidQuantum)
        } else if stopped {
          Some(Terminal)
        } else if command == 3 || (command == 2 && generations > 0) {
          Some(ForeignToken)
        } else {
          None
        }
        let observed = advance(session, token, quantum)
        if invalid is Some(issue) {
          assert_true(observed is Err(actual_issue) && actual_issue == issue)
        } else {
          generations += 1
          if requested is Some(reason) {
            stopped = true
            assert_true(
              observed is Ok(StoppedWith(actual_reason, progress~, work~)) &&
              actual_reason == reason &&
              progress == (3 - demand).to_int64() &&
              work == (3 - demand).to_int64(),
            )
          } else {
            demand = Int::max(0, demand - quantum)
            let expected = (3 - demand).to_int64()
            if demand == 0 {
              stopped = true
              assert_true(
                observed is Ok(Completed(3, progress~, work~)) &&
                progress == expected &&
                work == expected,
              )
            } else {
              guard observed is Ok(ContinueWith(next, progress~, work~)) else {
                fail("missing contract continuation")
              }
              assert_eq(progress, expected)
              assert_eq(work, expected)
              current = next
            }
          }
        }
      }
      5 | 6 => {
        let changed = if command == 5 {
          request_cancel(owner)
        } else {
          request_deadline(owner)
        }
        assert_eq(changed, requested is None)
        if requested is None {
          requested = Some(if command == 5 { Cancelled } else { Deadline })
        }
      }
      7 => {
        ready = !ready
        actual.cleanup_ready = ready
      }
      8 => {
        let observed = cleanup(session)
        if !stopped {
          assert_eq(observed, Err(NotStopped))
        } else if reclaimed {
          assert_eq(observed, Ok(false))
        } else {
          cleanup_attempts += 1
          assert_eq(observed, Ok(ready))
          reclaimed = ready
        }
      }
      _ => fail("unknown contract command")
    }
    assert_eq(session_stopped(session), stopped)
    assert_eq(cleanup_pending(session), stopped && !reclaimed)
    assert_eq(actual.cleanup_calls, cleanup_attempts)
    assert_eq(actual.current, 3 - demand)
  }
}

///|
test "session contract explores command histories independently of kernels" {
  // Complete enumeration, so every failing trace is its base-9 index. Extend
  // each prefix with stop, cleanup failure, recovery, and repeated cleanup.
  for seed in 0..<6561 {
    let mut encoded = seed
    let commands = []
    for _ in 0..<4 {
      commands.push(encoded % 9)
      encoded /= 9
    }
    commands.append([5, 0, 8, 7, 8, 8])
    check_session_contract_trace(commands)
  }
  // A normal completion, stale token, and both stop reasons after positive work.
  for prefix in [[0, 2, 0, 0], [1, 1], [1, 5, 0], [1, 6, 0]] {
    let trace = prefix.copy()
    trace.append([8, 7, 8, 8])
    check_session_contract_trace(trace)
  }
}

///|
test "session contract checks Int64 boundaries and reentrant resume" {
  assert_eq(add_counter(9223372036854775806L, 1), Some(9223372036854775807L))
  assert_eq(add_counter(9223372036854775807L, 1), None)
  assert_eq(add_counter(0L, -1), None)
  assert_eq(add_counter(0L, 2147483647), Some(2147483647L))
  let state = { current: 0, limit: 1, cleanup_calls: 0, cleanup_ready: true, }
  let (session, token) = start(control(), state, counter_step, _ => true, _ => {
    true
  })
  session.ordinal = 9223372036854775807L
  let last = { owner: token.owner, ordinal: 9223372036854775807L, }
  assert_true(advance(session, last, 1) is Err(CounterOverflow))
  assert_true(session_stopped(session))
  assert_eq(state.current, 0)
  assert_eq(cleanup(session), Ok(true))
  // Reentrant access is blocked before invoking the kernel again.
  let nested = Ref(None)
  let perform = Ref(fn() -> Unit { () })
  let step : (CounterState, Int, Reader) -> KernelStep[Int, String] = fn(
    _,
    _,
    _,
  ) {
    (perform.val)()
    Complete(3, 0, 0)
  }
  let (reentrant, first) = start(control(), state, step, _ => true, _ => true)
  perform.val = fn() { nested.val = Some(advance(reentrant, first, 1)) }
  assert_true(advance(reentrant, first, 1) is Ok(Completed(3, ..)))
  assert_true(nested.val is Some(Err(ConcurrentResume)))
}
