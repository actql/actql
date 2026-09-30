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
test "a request delivered during one step suppresses completion" {
  let execution_control = control()
  let state = { current: 0, limit: 1, cleanup_calls: 0, cleanup_ready: true, }
  let result_held = Ref(true)
  let dispose_calls = Ref(0)
  let step : (CounterState, Int, Reader) -> KernelStep[Int, String] = fn(
    state,
    _quantum,
    _reader,
  ) {
    state.current = 1
    request_cancel(execution_control) |> ignore
    Complete(1, 1, 1)
  }
  let (session, token) = start(execution_control, state, step, _state => true, _value => {
    dispose_calls.val += 1
    result_held.val = false
    true
  })
  assert_true(
    advance(session, token, 1).unwrap()
    is StoppedWith(Cancelled, progress=1L, work=1L),
  )
  assert_true(session_stopped(session))
  assert_true(cleanup_pending(session))
  assert_true(result_held.val)
  assert_eq(cleanup(session), Ok(true))
  assert_false(result_held.val)
  assert_eq(dispose_calls.val, 1)
  assert_false(cleanup_pending(session))
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
  let (session, token) = start(
    invalid_control,
    state,
    invalid_step,
    _state => true,
    _value => true,
  )
  assert_true(advance(session, token, 1) is Err(InvalidKernelReport))
  assert_true(session_stopped(session))
  assert_eq(cleanup(session), Ok(true))

  let (pending, pending_token) = start(
    control(),
    state,
    counter_step,
    _state => true,
    _value => true,
  )
  assert_true(cleanup(pending) is Err(NotStopped))
  assert_true(advance(pending, pending_token, 0) is Err(InvalidQuantum))
}

///|
test "unaccepted result disposal remains pending and retryable" {
  let execution_control = control()
  let state = { current: 0, limit: 1, cleanup_calls: 0, cleanup_ready: true, }
  let result_held = Ref(true)
  let disposal_ready = Ref(false)
  let disposal_calls = Ref(0)
  let step : (CounterState, Int, Reader) -> KernelStep[Int, String] = fn(
    _state,
    quantum,
    _reader,
  ) {
    Complete(7, 1, quantum + 1)
  }
  let (session, token) = start(execution_control, state, step, _state => true, _value => {
    disposal_calls.val += 1
    if disposal_ready.val {
      result_held.val = false
      true
    } else {
      false
    }
  })
  assert_true(advance(session, token, 1) is Err(InvalidKernelReport))
  assert_true(session_stopped(session))
  assert_eq(cleanup(session), Ok(false))
  assert_true(result_held.val)
  assert_true(cleanup_pending(session))
  disposal_ready.val = true
  assert_eq(cleanup(session), Ok(true))
  assert_false(result_held.val)
  assert_false(cleanup_pending(session))
  assert_eq(disposal_calls.val, 2)
  assert_eq(cleanup(session), Ok(false))
}

///|
test "accepted result custody transfers without session disposal" {
  let state = { current: 0, limit: 1, cleanup_calls: 0, cleanup_ready: true, }
  let result_held = Ref(true)
  let disposal_calls = Ref(0)
  let (session, token) = start(control(), state, counter_step, _state => true, _value => {
    disposal_calls.val += 1
    result_held.val = false
    true
  })
  assert_true(
    advance(session, token, 1).unwrap() is Completed(1, progress=1L, work=1L),
  )
  assert_eq(cleanup(session), Ok(true))
  assert_true(result_held.val)
  assert_eq(disposal_calls.val, 0)
}

///|
test "counter overflow retains completed result for cleanup" {
  let state = { current: 0, limit: 1, cleanup_calls: 0, cleanup_ready: true, }
  let result_held = Ref(true)
  let step : (CounterState, Int, Reader) -> KernelStep[Int, String] = fn(
    _state,
    _quantum,
    _reader,
  ) {
    Complete(9, 1, 1)
  }
  let (session, token) = start(control(), state, step, _state => true, _value => {
    result_held.val = false
    true
  })
  session.progress = 9223372036854775807L
  assert_true(advance(session, token, 1) is Err(CounterOverflow))
  assert_true(result_held.val)
  assert_true(cleanup_pending(session))
  assert_eq(cleanup(session), Ok(true))
  assert_false(result_held.val)
  assert_false(cleanup_pending(session))
}
