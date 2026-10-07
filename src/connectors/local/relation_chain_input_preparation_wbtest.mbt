///|
test "long internal producer names remain private during bounded handoff" {
  let name = "x".repeat(256)
  let body = "[{\"from\":\"source\",\"select\":[\"" +
    name +
    "\"],\"as\":\"first\"},{\"from\":\"first\",\"select\":[\"" +
    name +
    "\"],\"as\":\"out\"}]"
  let (sequence, read, source) = chain_lifetime_fixture(body, source_name=name)
  let (active, state) = chain_lifetime_start(sequence, read)
  let mut at_handoff = false
  for _ in 0..<10000 {
    if !at_handoff {
      match advance_managed_provider(active, 1).unwrap() {
        Continue(..) => ()
        _ => fail("first child did not reach handoff")
      }
      at_handoff = state.position == 1 && state.pending
    }
  }
  assert_true(at_handoff)
  assert_true(
    advance_managed_provider(active, 1).unwrap()
    is Continue(work=1L, progress=0L),
  )
  assert_true(state.pending)
  assert_true(
    state.current is None,
    msg="long producer metadata must yield before starting the next child",
  )
  assert_true(@execution.producer_read_available(read))
  assert_true(@execution.completed_output_available(source))
  for _ in 0..<5 {
    assert_true(
      advance_managed_provider(active, 1).unwrap()
      is Continue(work=1L, progress=0L),
    )
    assert_true(state.pending)
    assert_true(state.current is None)
  }
  // Setup/port/probe/field and two fragments: cancellation is inside the
  // receiving spelling, before any child or complete read is issued.
  assert_false(cleanup_managed_provider(active).unwrap())
  assert_true(
    @execution.completed_output_available(state.completed[0].unwrap()),
  )
  assert_true(cancel_managed_provider(active))
  assert_false(cleanup_managed_provider(active).unwrap())
  assert_true(advance_managed_provider(active, 1).unwrap() is Stopped(..))
  assert_true(cleanup_managed_provider(active).unwrap())
  assert_true(@execution.completed_output_available(source))
}

///|
test "long producer handoff keeps nineteen independent control polls across quanta" {
  let name = "x".repeat(256)
  let body = "[{\"from\":\"source\",\"select\":[\"" +
    name +
    "\"],\"as\":\"first\"},{\"from\":\"first\",\"select\":[\"" +
    name +
    "\"],\"as\":\"out\"}]"
  for quantum in [1, 7, 256] {
    let (sequence, read, source) = chain_lifetime_fixture(
      body,
      source_name=name,
    )
    let (active, state) = chain_lifetime_start(sequence, read)
    let mut at_handoff = false
    for _ in 0..<10000 {
      if !at_handoff {
        assert_true(
          advance_managed_provider(active, quantum).unwrap() is Continue(..),
        )
        at_handoff = state.position == 1 && state.pending
      }
    }
    assert_true(at_handoff)
    // Setup + port + predecessor + (field, 4 receiver chunks, column,
    // 4 producer chunks, 4 comparisons, terminal) + final port = 19.
    for _ in 0..<18 {
      assert_true(
        advance_managed_provider(active, quantum).unwrap()
        is Continue(work=1L, progress=0L),
      )
      assert_true(state.pending)
      assert_true(state.current is None)
    }
    assert_true(
      advance_managed_provider(active, quantum).unwrap()
      is Continue(work=1L, progress=0L),
    )
    assert_false(state.pending)
    assert_true(state.current is Some(_))
    assert_true(@execution.producer_read_available(read))
    assert_true(cancel_managed_provider(active))
    assert_true(advance_managed_provider(active, 1).unwrap() is Stopped(..))
    assert_true(cleanup_managed_provider(active).unwrap())
    assert_true(@execution.completed_output_available(source))
  }
}
