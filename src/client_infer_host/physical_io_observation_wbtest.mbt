///|
fn async_io_stop_and_cleanup(active : Execution) -> Unit raise {
  cancel(active) |> ignore
  let mut terminal = active.phase is Terminal
  for _ in 0..<2000 {
    if terminal {
      break
    }
    match advance(active, 1).unwrap() {
      Settling(_, ..) =>
        assert_true(
          @model.acknowledge_model_call_settlement(
            call_settlement(active).unwrap(),
          ),
        )
      Stopped(_) | Failed(_, ..) => {
        terminal = true
        break
      }
      Complete(_, ..) => abort("cancelled original cannot become success")
      Continue(_) | AwaitIo(_) | Waiting(_) => ()
    }
  }
  assert_true(terminal)
  let mut retired = false
  for _ in 0..<10 {
    if cleanup(active).unwrap() {
      retired = true
      break
    }
  }
  assert_true(retired)
}

///|
// Ordinary Core Program/Entry handles; physical close and Store ACK are
// explicit doubles. This does not establish an actual installed port ACK.
test "same call caches a response while late I/O close progresses and holding remains" {
  let original : Ref[@model.ModelPhysicalCall?] = Ref(None)
  let mode = Ref(0)
  let calls = Ref(0)
  let polls = Ref(0)
  let release = Ref(false)
  let cleaned : Array[Bool] = []
  let response = @model.PhysicalResponse(async_response_observation(None))
  let (active, prefix) = async_response_fixture(
    calls,
    polls,
    Ref(0),
    cleaned,
    Ref(true),
    release,
    response,
    observe_call=call => original.val = Some(call),
    observe_response=Some(() => {
      let call = original.val.unwrap()
      if mode.val == 0 {
        @model.PhysicalIoPending(call, @model.PhysicalPending)
      } else if mode.val == 1 {
        @model.PhysicalIoPending(call, response)
      } else {
        @model.PhysicalIoQuiescent(call, @model.PhysicalPending)
      }
    }),
  )
  guard fixture_finish(active, initial_work=prefix) is AwaitIo(work~) else {
    abort("inner Pending must not be terminal")
  }
  async_assert_wait(active, work)
  mode.val = 1
  guard fixture_finish(active, initial_work=work) is Settling(0, work=settled) else {
    abort("response before original close")
  }
  let wire = async_settlement_wire(active)
  let before = polls.val
  assert_true(
    @model.acknowledge_model_call_settlement(call_settlement(active).unwrap()),
  )
  async_assert_wait(active, settled)
  assert_true(
    polls.val > before,
    msg="same original poll remains live after response",
  )
  assert_eq(calls.val, 1)
  mode.val = 2
  let late = polls.val
  async_assert_wait(active, settled)
  assert_true(polls.val > late)
  let confirmed = polls.val
  async_assert_wait(active, settled)
  assert_eq(
    polls.val,
    confirmed,
    msg="confirmed original observation is not issued twice",
  )
  assert_eq(
    calls.val,
    1,
    msg="I/O retirement is not holding retirement or another dispatch",
  )
  assert_true(cleaned.all(value => value))
  assert_true(wire.contains("\"response_complete\":true"))
  release.val = true
  async_io_stop_and_cleanup(active)
  assert_eq(calls.val, 1)
}

///|
test "I/O quiescence around Pending does not consume the later original response" {
  let original : Ref[@model.ModelPhysicalCall?] = Ref(None)
  let ready = Ref(false)
  let calls = Ref(0)
  let polls = Ref(0)
  let release = Ref(false)
  let response = @model.PhysicalResponse(async_response_observation(None))
  let (active, prefix) = async_response_fixture(
    calls,
    polls,
    Ref(0),
    [],
    Ref(true),
    release,
    response,
    observe_call=call => original.val = Some(call),
    observe_response=Some(() => {
      @model.PhysicalIoQuiescent(
        original.val.unwrap(),
        if ready.val {
          response
        } else {
          @model.PhysicalPending
        },
      )
    }),
  )
  guard fixture_finish(active, initial_work=prefix) is AwaitIo(work~) else {
    abort("quiescent inner Pending")
  }
  let before = polls.val
  async_assert_wait(active, work)
  assert_true(polls.val > before)
  ready.val = true
  assert_true(fixture_finish(active, initial_work=work) is Settling(0, ..))
  assert_eq(calls.val, 1)
  release.val = true
  async_io_stop_and_cleanup(active)
}

///|
test "foreign Call I/O carrier is refused without replacing or redispatching the original" {
  let foreign : Ref[@model.ModelPhysicalCall?] = Ref(None)
  let foreign_ready = Ref(false)
  let (other, other_prefix) = async_response_fixture(
    Ref(0),
    Ref(0),
    Ref(0),
    [],
    foreign_ready,
    Ref(true),
    @model.PhysicalUnknown({ input_tokens: None, output_tokens: None, }),
    observe_call=call => foreign.val = Some(call),
  )
  assert_true(fixture_finish(other, initial_work=other_prefix) is AwaitIo(_))
  let original : Ref[@model.ModelPhysicalCall?] = Ref(None)
  let bad = Ref(false)
  let calls = Ref(0)
  let stopped = Ref(false)
  let release = Ref(false)
  let (active, prefix) = async_response_fixture(
    calls,
    Ref(0),
    Ref(0),
    [],
    Ref(true),
    release,
    @model.PhysicalPending,
    observe_call=call => original.val = Some(call),
    observe_response=Some(() => {
      @model.PhysicalIoQuiescent(
        if bad.val {
          foreign.val.unwrap()
        } else {
          original.val.unwrap()
        },
        if stopped.val {
          @model.PhysicalUnknown({ input_tokens: None, output_tokens: None, })
        } else {
          @model.PhysicalPending
        },
      )
    }),
  )
  assert_true(fixture_finish(active, initial_work=prefix) is AwaitIo(_))
  bad.val = true
  assert_true(
    advance(active, 1) is Ok(Failed(Model(@model.RequestIdentity), ..)),
  )
  assert_eq(calls.val, 1)
  assert_true(!cleanup(active).unwrap())
  assert_eq(calls.val, 1)
  cancel(active) |> ignore
  cancel(other) |> ignore
  bad.val = false
  stopped.val = true
  release.val = true
  foreign_ready.val = true
  async_io_stop_and_cleanup(active)
  async_io_stop_and_cleanup(other)
}

///|
test "cancel acceptance with I/O pending retains the original cleanup and terminal Unknown" {
  let original : Ref[@model.ModelPhysicalCall?] = Ref(None)
  let closed = Ref(false)
  let unknown = Ref(false)
  let release = Ref(false)
  let calls = Ref(0)
  let cancels = Ref(0)
  let (active, prefix) = async_response_fixture(
    calls,
    Ref(0),
    cancels,
    [],
    Ref(true),
    release,
    @model.PhysicalPending,
    observe_call=call => original.val = Some(call),
    observe_response=Some(() => {
      let inner = if unknown.val {
        @model.PhysicalUnknown({ input_tokens: Some(3L), output_tokens: None, })
      } else {
        @model.PhysicalPending
      }
      if closed.val {
        @model.PhysicalIoQuiescent(original.val.unwrap(), inner)
      } else {
        @model.PhysicalIoPending(original.val.unwrap(), inner)
      }
    }),
  )
  guard fixture_finish(active, initial_work=prefix) is AwaitIo(work~) else {
    abort("original pending")
  }
  assert_true(cancel(active))
  async_assert_wait(active, work)
  assert_true(!cleanup(active).unwrap())
  assert_eq(cancels.val, 1)
  unknown.val = true
  assert_true(
    fixture_finish(active, initial_work=work)
    is Failed(Model(@model.UnknownCalls), ..),
  )
  assert_true(!cleanup(active).unwrap())
  closed.val = true
  assert_true(!cleanup(active).unwrap())
  release.val = true
  async_io_stop_and_cleanup(active)
  assert_eq(calls.val, 1)
  assert_true(work >= prefix)
}
