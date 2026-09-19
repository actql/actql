///|
priv struct CounterState {
  mut current : Int
  limit : Int
  mut cleanup_calls : Int
  mut cleanup_ready : Bool
}

///|
fn counter_step(
  state : CounterState,
  quantum : Int,
  reader : Reader,
) -> KernelStep[Int, String] {
  let mut used = 0
  while state.current < state.limit && used < quantum {
    if stop_requested(reader) is Some(reason) {
      return Stopped(reason, 0, used)
    }
    state.current += 1
    used += 1
  }
  if state.current == state.limit {
    Complete(state.current, used, used)
  } else {
    Continue(used, used)
  }
}

///|
test "bounded session advances with fresh tokens and finite work" {
  let control = control()
  let state = { current: 0, limit: 7, cleanup_calls: 0, cleanup_ready: true, }
  let (session, first) = start(control, state, counter_step, state => {
    state.cleanup_calls += 1
    state.cleanup_ready
  })
  guard advance(session, first, 3).unwrap()
    is ContinueWith(second, progress=3L, work=3L) else {
    fail("first bounded step")
  }
  assert_true(advance(session, first, 3) is Err(ForeignToken))
  guard advance(session, second, 3).unwrap()
    is ContinueWith(third, progress=6L, work=6L) else {
    fail("second bounded step")
  }
  assert_true(
    advance(session, third, 1).unwrap() is Completed(7, progress=7L, work=7L),
  )
  assert_true(session_stopped(session))
  assert_true(cleanup_pending(session))
  assert_eq(cleanup(session), Ok(true))
  assert_false(cleanup_pending(session))
  assert_eq(cleanup(session), Ok(false))
  assert_eq(state.cleanup_calls, 1)
}

///|
test "stop confirmation precedes retryable cleanup" {
  for deadline in [false, true] {
    let control = control()
    let state = {
      current: 0,
      limit: 100,
      cleanup_calls: 0,
      cleanup_ready: false,
    }
    let (session, first) = start(control, state, counter_step, state => {
      state.cleanup_calls += 1
      state.cleanup_ready
    })
    guard advance(session, first, 2).unwrap()
      is ContinueWith(next, progress=2L, work=2L) else {
      fail("running step")
    }
    if deadline {
      assert_true(request_deadline(control))
    } else {
      assert_true(request_cancel(control))
    }
    let expected = if deadline { Deadline } else { Cancelled }
    assert_true(
      advance(session, next, 2).unwrap()
      is StoppedWith(reason, progress=2L, work=2L) &&
      reason == expected,
    )
    assert_true(session_stopped(session))
    assert_eq(cleanup(session), Ok(false))
    assert_true(cleanup_pending(session))
    state.cleanup_ready = true
    assert_eq(cleanup(session), Ok(true))
    assert_false(cleanup_pending(session))
    assert_eq(state.cleanup_calls, 2)
  }
}

///|
test "a request delivered during one step suppresses completion" {
  let execution_control = control()
  let state = { current: 0, limit: 1, cleanup_calls: 0, cleanup_ready: true, }
  let step : (CounterState, Int, Reader) -> KernelStep[Int, String] = fn(
    state,
    _quantum,
    _reader,
  ) {
    state.current = 1
    request_cancel(execution_control) |> ignore
    Complete(1, 1, 1)
  }
  let (session, token) = start(execution_control, state, step, _state => true)
  assert_true(
    advance(session, token, 1).unwrap()
    is StoppedWith(Cancelled, progress=1L, work=1L),
  )
  assert_true(session_stopped(session))
  assert_true(cleanup_pending(session))
}

///|
test "bounded session rejects invalid reports before cleanup" {
  let invalid_control = control()
  let state = { current: 0, limit: 1, cleanup_calls: 0, cleanup_ready: true, }
  let invalid_step : (CounterState, Int, Reader) -> KernelStep[Int, String] = fn(
    _state,
    quantum,
    _reader,
  ) {
    Continue(1, quantum + 1)
  }
  let (session, token) = start(invalid_control, state, invalid_step, _state => {
    true
  })
  assert_true(advance(session, token, 1) is Err(InvalidKernelReport))
  assert_true(session_stopped(session))
  assert_eq(cleanup(session), Ok(true))

  let (pending, pending_token) = start(control(), state, counter_step, _state => {
    true
  })
  assert_true(cleanup(pending) is Err(NotStopped))
  assert_true(advance(pending, pending_token, 0) is Err(InvalidQuantum))
}
