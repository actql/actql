///|
fn record_stopped_input(values : Array[Int], value : Int) -> Bool {
  values.push(value)
  true
}

///|
test "managed input stop slices revocation without dropping input custody" {
  let cursor = local_managed_input_stop()
  let bridges = Array::makei(70, index => Ref(Some(index)))
  let imports = Array::makei(3, index => Ref(Some(index + 70)))
  let closed = []
  let cancelled = []
  assert_false(
    advance_local_managed_input_stop(
      cursor,
      bridges,
      imports,
      bridge => record_stopped_input(closed, bridge),
      importer => record_stopped_input(cancelled, importer),
    ),
  )
  assert_eq(closed, Array::makei(64, index => index))
  assert_true(cancelled.is_empty())
  // Stop requests leave roots in the original owner until physical cleanup.
  assert_eq(
    bridges.map(handle => handle.val),
    Array::makei(70, index => Some(index)),
  )
  assert_eq(imports.map(handle => handle.val), [Some(70), Some(71), Some(72)])
  assert_true(
    advance_local_managed_input_stop(
      cursor,
      bridges,
      imports,
      bridge => record_stopped_input(closed, bridge),
      importer => record_stopped_input(cancelled, importer),
    ),
  )
  assert_eq(closed, Array::makei(70, index => index))
  assert_eq(cancelled, [70, 71, 72])
  assert_true(
    advance_local_managed_input_stop(
      cursor,
      bridges,
      imports,
      bridge => record_stopped_input(closed, bridge),
      importer => record_stopped_input(cancelled, importer),
    ),
  )
  assert_eq(closed.length(), 70)
  assert_eq(cancelled.length(), 3)
}

///|
test "managed input stop counts absent handles and both phase boundaries" {
  for count in [62, 63] {
    let cursor = local_managed_input_stop()
    let bridges : Array[Ref[Int?]] = Array::makei(count, _ => Ref(None))
    let imports : Array[Ref[Int?]] = []
    let calls = Ref(0)
    assert_eq(
      advance_local_managed_input_stop(
        cursor,
        bridges,
        imports,
        _ => {
          calls.val += 1
          true
        },
        _ => {
          calls.val += 1
          true
        },
      ),
      count + 2 <= 64,
    )
    assert_eq(calls.val, 0)
    assert_true(
      advance_local_managed_input_stop(
        cursor,
        bridges,
        imports,
        _ => {
          calls.val += 1
          true
        },
        _ => {
          calls.val += 1
          true
        },
      ),
    )
    assert_eq(calls.val, 0)
  }
}

///|
test "managed input stop keeps a shared owner occurrence at each port" {
  let cursor = local_managed_input_stop()
  let input = Ref(Some(7))
  let bridges = [input, input, Ref(None)]
  let imports = [Ref(Some(8)), Ref(None)]
  let closed = []
  let cancelled = []
  assert_true(
    advance_local_managed_input_stop(
      cursor,
      bridges,
      imports,
      bridge => record_stopped_input(closed, bridge),
      importer => record_stopped_input(cancelled, importer),
    ),
  )
  assert_eq(closed, [7, 7])
  assert_eq(cancelled, [8])
  assert_eq(input.val, Some(7))
}

///|
test "managed input stop rejects reentrant advancement until callback returns" {
  let cursor = local_managed_input_stop()
  let bridges = [Ref(Some(7)), Ref(Some(8))]
  let imports = [Ref(Some(9))]
  let observations = []
  let closed = []
  let cancelled = []
  assert_true(
    advance_local_managed_input_stop(
      cursor,
      bridges,
      imports,
      bridge => {
        closed.push(bridge)
        observations.push(
          advance_local_managed_input_stop(
            cursor,
            bridges,
            imports,
            value => record_stopped_input(closed, value),
            value => record_stopped_input(cancelled, value),
          ),
        )
        true
      },
      importer => record_stopped_input(cancelled, importer),
    ),
  )
  assert_eq(observations, [false, false])
  assert_eq(closed, [7, 8])
  assert_eq(cancelled, [9])
  assert_false(cursor.advancing)
  assert_eq(bridges.map(handle => handle.val), [Some(7), Some(8)])
}

///|
test "managed input stop keeps the same cursor on a pending buffer" {
  let cursor = local_managed_input_stop()
  let bridges = [Ref(Some(7)), Ref(Some(8))]
  let imports = [Ref(Some(9))]
  let remaining = Ref(100)
  let closed = []
  let cancelled = []
  let close = fn(value) {
    if value == 7 && remaining.val > 0 {
      remaining.val -= 1
      false
    } else {
      record_stopped_input(closed, value)
    }
  }
  assert_false(
    advance_local_managed_input_stop(cursor, bridges, imports, close, value => {
      record_stopped_input(cancelled, value)
    }),
  )
  assert_eq(cursor.index, 0)
  assert_eq(remaining.val, 36)
  assert_true(closed.is_empty())
  assert_true(cancelled.is_empty())
  assert_true(
    advance_local_managed_input_stop(cursor, bridges, imports, close, value => {
      record_stopped_input(cancelled, value)
    }),
  )
  assert_eq(remaining.val, 0)
  assert_eq(closed, [7, 8])
  assert_eq(cancelled, [9])
  assert_eq(bridges[0].val, Some(7))
}
