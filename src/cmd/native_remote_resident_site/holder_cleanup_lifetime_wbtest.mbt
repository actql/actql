///|
/// Caller-lifetime/fault-model fixtures. They do not claim actual Reader/FD,
/// Native process-stop, Provider, profile or public Effect acceptance.
test "pending original Reader model keeps same payload and later Owners untouched" {
  let original = Ref([1, 7])
  let ready = Ref(false)
  let position = Ref(0)
  let calls = [0, 0, 0]
  let facts = Ref(true)
  let unexpected_waits = Ref(0)
  let received = retain_holder_cleanup_lifetime(
    original,
    value => {
      advance_holder_cleanup_pass(value, position, 3, (same, step) => {
        facts.val = facts.val &&
          same.val[0] == 1 &&
          same.val[1] == (if ready.val { 8 } else { 7 })
        calls[step] += 1
        step != 0 || ready.val
      })
    },
    () => {
      facts.val = facts.val && position.val == 0 && calls == [1, 0, 0]
      original.val[1] = 8
      ready.val = true
      CleanupProgress
    },
    () => unexpected_waits.val += 1,
    (_, ended) => facts.val = facts.val && !ended,
  )
  assert_true(facts.val)
  assert_eq(unexpected_waits.val, 0)
  received.val[0] = 2
  assert_eq(original.val, [2, 8])
  assert_eq(calls, [2, 1, 1])
}

///|
test "process holding release failure keeps prior ACKs and executor slot" {
  let original = Ref(99)
  let position = Ref(0)
  let release_ready = Ref(false)
  let calls = Array::make(9, 0)
  let facts = Ref(true)
  let unexpected_waits = Ref(0)
  let returned = retain_holder_cleanup_lifetime(
    original,
    value => {
      advance_holder_cleanup_pass(value, position, 9, (same, step) => {
        facts.val = facts.val && same.val == 99
        calls[step] += 1
        step != 6 || release_ready.val
      })
    },
    () => {
      facts.val = facts.val &&
        position.val == 6 &&
        calls[7] == 0 &&
        calls[8] == 0
      release_ready.val = true
      CleanupProgress
    },
    () => unexpected_waits.val += 1,
    (_, _) => (),
  )
  assert_true(facts.val)
  assert_eq(unexpected_waits.val, 0)
  assert_eq(returned.val, 99)
  assert_eq(calls, [1, 1, 1, 1, 1, 1, 2, 1, 1])
}

///|
test "EOF disables rereads and is not cleanup or slot release" {
  let original = Ref(11)
  let close_ready = Ref(false)
  let reads = Ref(0)
  let waits = Ref(0)
  let closes = Ref(0)
  let facts = Ref(true)
  let returned = retain_holder_cleanup_lifetime(
    original,
    same => {
      facts.val = facts.val && same.val == 11
      closes.val += 1
      close_ready.val
    },
    () => {
      reads.val += 1
      facts.val = facts.val && reads.val == 1
      CleanupInputEnded
    },
    () => {
      waits.val += 1
      facts.val = facts.val && reads.val == 1 && closes.val == 2
      close_ready.val = true
    },
    (_, _) => (),
  )
  assert_true(facts.val)
  assert_eq(returned.val, 11)
  assert_eq(reads.val, 1)
  assert_eq(waits.val, 1)
  assert_eq(closes.val, 3)
}

///|
test "known termination does not bypass the supplied blocking wait" {
  let termination_requested = Ref(true)
  let wakes = Ref(0)
  let ready = Ref(false)
  let facts = Ref(true)
  ignore(
    retain_holder_cleanup_lifetime(
      termination_requested,
      _ => ready.val,
      () => CleanupInputEnded,
      () => {
        facts.val = facts.val && termination_requested.val
        wakes.val += 1
        ready.val = true
      },
      (_, _) => (),
    ),
  )
  assert_true(facts.val)
  assert_eq(wakes.val, 1)
  assert_true(termination_requested.val)
}

///|
test "cancel and restoration frames cannot restart work or discharge pending custody" {
  assert_false(holder_cleanup_progress_frame("cancel original"))
  assert_false(holder_cleanup_progress_frame("consumer original"))
  assert_false(holder_cleanup_progress_frame("effect-resume original"))
  assert_false(holder_cleanup_progress_frame("release foreign"))
  assert_true(holder_cleanup_progress_frame("effect-review"))
  let original = Ref(8)
  let reads = Ref(0)
  let closes = Ref(0)
  let facts = Ref(true)
  let unexpected_waits = Ref(0)
  ignore(
    retain_holder_cleanup_lifetime(
      original,
      same => {
        facts.val = facts.val && same.val == 8
        closes.val += 1
        closes.val == 2
      },
      () => {
        reads.val += 1
        if reads.val < 3 {
          CleanupOther
        } else {
          CleanupProgress
        }
      },
      () => unexpected_waits.val += 1,
      (_, _) => (),
    ),
  )
  assert_true(facts.val)
  assert_eq(unexpected_waits.val, 0)
  assert_eq(reads.val, 3)
  assert_eq(closes.val, 2)
}

///|
test "completed close cursor does not call any Owner a second time" {
  let original = Ref(4)
  let position = Ref(0)
  let calls = Array::make(9, 0)
  let close = (_, step) => {
    calls[step] += 1
    true
  }
  assert_true(advance_holder_cleanup_pass(original, position, 9, close))
  assert_true(advance_holder_cleanup_pass(original, position, 9, close))
  assert_eq(calls, Array::make(9, 1))
}

///|
test "unopened resources preserve original environment through release pending" {
  let original = Ref(77)
  let unopened : Ref[Int]? = None
  let position = Ref(holder_cleanup_initial_position(unopened))
  assert_eq(position.val, 7)
  assert_eq(holder_cleanup_initial_position(Some(original)), 0)
  let release_ready = Ref(false)
  let calls = Array::make(11, 0)
  let facts = Ref(true)
  let reads = Ref(0)
  let waits = Ref(0)
  let returned = retain_holder_cleanup_lifetime(
    original,
    value => {
      advance_holder_cleanup_pass(value, position, 11, (same, step) => {
        facts.val = facts.val && physical_equal(same, original)
        calls[step] += 1
        step != 8 || release_ready.val
      })
    },
    () => {
      // No Host reservation exists for a channel read. EOF is not a release
      // ACK; the same environment/slot is retained through a signal wait.
      reads.val += 1
      CleanupInputEnded
    },
    () => {
      waits.val += 1
      facts.val = facts.val && position.val == 8 && calls[10] == 0
      release_ready.val = true
    },
    (_, _) => (),
  )
  assert_true(facts.val)
  assert_true(physical_equal(returned, original))
  assert_eq(reads.val, 1)
  assert_eq(waits.val, 1)
  assert_eq(calls, [0, 0, 0, 0, 0, 0, 0, 1, 3, 1, 1])
}

///|
test "unopened resources do not turn missing process hold into slot release" {
  let original = Ref(88)
  let unopened : Ref[Int]? = None
  let position = Ref(holder_cleanup_initial_position(unopened))
  let calls = Array::make(11, 0)
  let same_owner = Ref(true)
  let close = (same, step) => {
    same_owner.val = same_owner.val && physical_equal(same, original)
    calls[step] += 1
    // The existing Bundle Owner did not confirm the original release.
    step != 8
  }
  assert_false(advance_holder_cleanup_pass(original, position, 11, close))
  assert_false(advance_holder_cleanup_pass(original, position, 11, close))
  assert_true(same_owner.val)
  assert_eq(position.val, 8)
  assert_eq(calls, [0, 0, 0, 0, 0, 0, 0, 1, 2, 0, 0])
}
