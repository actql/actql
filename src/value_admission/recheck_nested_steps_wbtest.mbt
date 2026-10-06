///|
test "runtime vector recheck yields between components with exact node usage" {
  let contract = @contract.vector_contract(257.0, nullable=false).unwrap()
  let value = Vector({ values: Array::make(257, 1.0), })
  let limits : Limits = { max_nodes: 258, max_depth: 1, max_text_bytes: 0, }
  assert_true(recheck_runtime_value(value, contract, limits) is Some(_))
  let cursor = start_recheck_runtime_value(value, contract, limits).unwrap()
  // One node, 257 components, an exhausted-items poll and a terminal poll.
  for _ in 0..<259 {
    assert_true(advance_recheck_runtime_value(cursor) is RecheckContinue)
  }
  assert_true(
    advance_recheck_runtime_value(cursor) is RecheckComplete(_, 258, 0),
  )
  for short in [{ ..limits, max_nodes: 257, }, { ..limits, max_depth: 0, }] {
    assert_true(recheck_runtime_value(value, contract, short) is None)
    let active = start_recheck_runtime_value(value, contract, short).unwrap()
    assert_true(advance_recheck_runtime_value(active) is RecheckFailed)
  }
  for invalid in [-0.0, 0.0 / 0.0, 1.0 / 0.0] {
    for index in [0, 256] {
      let components = Array::make(257, 1.0)
      components[index] = invalid
      let invalid_value = Vector({ values: components, })
      assert_true(
        recheck_runtime_value(invalid_value, contract, limits) is None,
      )
      let active = start_recheck_runtime_value(invalid_value, contract, limits).unwrap()
      for _ in 0..<(index + 1) {
        assert_true(advance_recheck_runtime_value(active) is RecheckContinue)
      }
      assert_true(advance_recheck_runtime_value(active) is RecheckFailed)
      assert_true(active.stack.is_empty())
    }
  }
  let stopped = start_recheck_runtime_value(value, contract, limits).unwrap()
  for _ in 0..<129 {
    assert_true(advance_recheck_runtime_value(stopped) is RecheckContinue)
  }
  cancel_recheck_runtime_value(stopped)
  assert_true(stopped.stack.is_empty())
  assert_true(advance_recheck_runtime_value(stopped) is RecheckFailed)
}

///|
test "runtime JSON recheck yields within nested data Text without normalization" {
  let text = "a".repeat(130) + "e\u{0301}\r\n"
  let value = Object({
    values: [("payload", Array({ values: [Text(text)], }))],
  })
  let contract = @contract.primitive(@contract.JsonType, nullable=false)
  // Three nodes: object, array, Text. Seven key bytes plus 135 data bytes.
  let limits : Limits = { max_nodes: 3, max_depth: 2, max_text_bytes: 142, }
  let expected = recheck_runtime_value_usage(value, contract, limits).unwrap()
  assert_eq(expected.1, 3)
  assert_eq(expected.2, 142)
  let cursor = start_recheck_runtime_value(value, contract, limits).unwrap()
  // Object, field, array, item, Text node, three Text chunks,
  // exhausted item/field continuations, terminal: eleven polls.
  for _ in 0..<10 {
    assert_true(advance_recheck_runtime_value(cursor) is RecheckContinue)
  }
  match advance_recheck_runtime_value(cursor) {
    RecheckComplete(checked, nodes, bytes) => {
      assert_true(physical_equal(checked.value, value))
      assert_eq(nodes, 3)
      assert_eq(bytes, 142)
    }
    _ => assert_true(false)
  }
  for
    short in [
      { ..limits, max_nodes: 2, },
      { ..limits, max_depth: 1, },
      { ..limits, max_text_bytes: 141, },
    ] {
    assert_true(recheck_runtime_value(value, contract, short) is None)
    let active = start_recheck_runtime_value(value, contract, short).unwrap()
    let mut failed = false
    for _ in 0..<11 {
      if !failed {
        match advance_recheck_runtime_value(active) {
          RecheckContinue => ()
          RecheckFailed => failed = true
          _ => assert_true(false)
        }
      }
    }
    assert_true(failed)
    assert_true(active.stack.is_empty())
  }
  let stopped = start_recheck_runtime_value(value, contract, limits).unwrap()
  for _ in 0..<6 {
    assert_true(advance_recheck_runtime_value(stopped) is RecheckContinue)
  }
  cancel_recheck_runtime_value(stopped)
  assert_true(stopped.stack.is_empty())
  assert_true(advance_recheck_runtime_value(stopped) is RecheckFailed)
}
