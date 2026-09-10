///|
test "offset transitions are closed-open and cannot extrapolate" {
  let t = @calendar_transition.admit(
    -100L,
    100L,
    0,
    [{ at_ms: 0L, offset_seconds: 3600, }, { at_ms: 50L, offset_seconds: -30, }],
    max_transitions=2,
  ).unwrap()
  for
    (instant, expected) in [
      (-101L, None),
      (-100L, Some(0)),
      (-1L, Some(0)),
      (0L, Some(3600)),
      (49L, Some(3600)),
      (50L, Some(-30)),
      (99L, Some(-30)),
      (100L, None),
    ] {
    assert_eq(@calendar_transition.offset_at(t, instant), expected)
  }
  assert_eq(@calendar_transition.coverage(t), (-100L, 100L))
  assert_eq(@calendar_transition.initial_offset(t), 0)
  assert_eq(@calendar_transition.transition_count(t), 2)
  assert_true(@calendar_transition.transition_at(t, -1) is None)
  assert_true(@calendar_transition.transition_at(t, 2) is None)
}

///|
test "admission rejects unordered redundant and out-of-coverage transitions" {
  for
    (times, offsets) in [
      ([0L], [1]),
      ([100L], [1]),
      ([50L, 50L], [1, 2]),
      ([60L, 50L], [1, 2]),
      ([50L], [0]),
      ([50L, 60L], [1, 1]),
    ] {
    let ts = times.mapi((i, at_ms) => @calendar_transition.Transition::{
      at_ms,
      offset_seconds: offsets[i],
    })
    assert_true(
      @calendar_transition.admit(0L, 100L, 0, ts, max_transitions=2) is Err(_),
    )
  }
  assert_true(
    @calendar_transition.admit(0L, 0L, 0, [], max_transitions=0)
    is Err(InvalidCoverage),
  )
  assert_true(
    @calendar_transition.admit(-9007199254740992L, 0L, 0, [], max_transitions=0)
    is Err(InvalidCoverage),
  )
  assert_true(
    @calendar_transition.admit(0L, 9007199254740992L, 0, [], max_transitions=0)
    is Err(InvalidCoverage),
  )
}

///|
test "limits ownership and signed second offset domain" {
  let ts : Array[@calendar_transition.Transition] = [
    { at_ms: 1L, offset_seconds: 2147483647, },
  ]
  assert_true(
    @calendar_transition.admit(0L, 2L, 0, ts, max_transitions=-1)
    is Err(InvalidLimit),
  )
  assert_true(
    @calendar_transition.admit(0L, 2L, 0, ts, max_transitions=0)
    is Err(TransitionLimit),
  )
  let t = @calendar_transition.admit(0L, 2L, -2147483647, ts, max_transitions=1).unwrap()
  ts[0] = { at_ms: 1L, offset_seconds: 0, }
  assert_eq(@calendar_transition.offset_at(t, 0L), Some(-2147483647))
  assert_eq(@calendar_transition.offset_at(t, 1L), Some(2147483647))
  assert_true(
    @calendar_transition.admit(0L, 2L, -2147483648, [], max_transitions=0)
    is Err(InvalidOffset(-1)),
  )
  assert_true(
    @calendar_transition.admit(
      0L,
      2L,
      0,
      [{ at_ms: 1L, offset_seconds: -2147483648, }],
      max_transitions=1,
    )
    is Err(InvalidOffset(0)),
  )
}

///|
test "binary lookup agrees with independent linear interval selection" {
  let ts : Array[@calendar_transition.Transition] = []
  for i in 1..<1000 {
    ts.push({ at_ms: i.to_int64() * 3L, offset_seconds: i % 17 - 8, })
  }
  let t = @calendar_transition.admit(0L, 3000L, 100, ts, max_transitions=999).unwrap()
  for instant in 0..<3000 {
    let mut expected = 100
    for transition in ts {
      if transition.at_ms <= instant.to_int64() {
        expected = transition.offset_seconds
      }
    }
    assert_eq(
      @calendar_transition.offset_at(t, instant.to_int64()),
      Some(expected),
    )
  }
}
