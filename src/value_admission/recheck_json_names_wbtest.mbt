///|
test "opaque JSON name recheck yields before its child" {
  let name = "x".repeat(130) + "e\u{0301}\r\n"
  let value = JsonData(Object({ values: [(name, Number(7.0))], }))
  let contract = @contract.primitive(@contract.JsonType, nullable=false)
  let limits : Limits = { max_nodes: 2, max_depth: 1, max_text_bytes: 135, }
  let cursor = start_recheck_runtime_value(value, contract, limits).unwrap()
  // Root, field setup, three scalar-safe name chunks, child, end, finish.
  for _ in 0..<3 {
    assert_true(advance_recheck_runtime_value(cursor) is RecheckContinue)
  }
  assert_eq(cursor.budget.nodes, 1)
  assert_eq(cursor.budget.text, 71)
  for _ in 0..<4 {
    assert_true(advance_recheck_runtime_value(cursor) is RecheckContinue)
  }
  match advance_recheck_runtime_value(cursor) {
    RecheckComplete(checked, nodes, bytes) => {
      assert_eq(nodes, 2)
      assert_eq(bytes, 135)
      assert_true(physical_equal(checked.value, value))
    }
    _ => assert_true(false)
  }
}

///|
test "opaque JSON name limits cancellation and surrogate boundaries stay exact" {
  let name = "x".repeat(63) + "😀" + "e\u{0301}\r\n" + "x".repeat(65)
  // 63 ASCII + four-byte supplementary scalar + five data bytes + 65 ASCII.
  let value = JsonData(Object({ values: [(name, Number(7.0))], }))
  let contract = @contract.primitive(@contract.JsonType, nullable=false)
  let limits : Limits = { max_nodes: 2, max_depth: 1, max_text_bytes: 137, }
  let complete = start_recheck_runtime_value(value, contract, limits).unwrap()
  for _ in 0..<7 {
    assert_true(advance_recheck_runtime_value(complete) is RecheckContinue)
  }
  match advance_recheck_runtime_value(complete) {
    RecheckComplete(checked, nodes, bytes) => {
      assert_eq(nodes, 2)
      assert_eq(bytes, 137)
      assert_true(physical_equal(checked.value, value))
    }
    _ => assert_true(false)
  }
  for
    short in [
      { ..limits, max_nodes: 1, },
      { ..limits, max_text_bytes: 136, },
      { ..limits, max_depth: 0, },
    ] {
    assert_true(recheck_runtime_value(value, contract, short) is None)
    let cursor = start_recheck_runtime_value(value, contract, short).unwrap()
    let mut refused = false
    for _ in 0..<10 {
      if !refused {
        match advance_recheck_runtime_value(cursor) {
          RecheckContinue => ()
          RecheckFailed => refused = true
          _ => assert_true(false)
        }
      }
    }
    assert_true(refused)
    assert_true(cursor.stack.is_empty())
  }
  let cursor = start_recheck_runtime_value(value, contract, limits).unwrap()
  for _ in 0..<3 {
    assert_true(advance_recheck_runtime_value(cursor) is RecheckContinue)
  }
  assert_eq(cursor.budget.nodes, 1)
  assert_eq(cursor.budget.text, 70)
  cancel_recheck_runtime_value(cursor)
  cancel_recheck_runtime_value(cursor)
  assert_true(cursor.stack.is_empty())
  assert_true(advance_recheck_runtime_value(cursor) is RecheckFailed)
  assert_true(
    recheck_runtime_value_usage(value, contract, limits) is Some((_, 2, 137)),
  )
  for
    malformed in [
      "x".repeat(64) + "😀".unsafe_substring(start=0, end=1),
      "x".repeat(64) + "😀".unsafe_substring(start=1, end=2),
    ] {
    let invalid = JsonData(Object({ values: [(malformed, Number(7.0))], }))
    let active = start_recheck_runtime_value(invalid, contract, limits).unwrap()
    for _ in 0..<3 {
      assert_true(advance_recheck_runtime_value(active) is RecheckContinue)
    }
    assert_true(advance_recheck_runtime_value(active) is RecheckFailed)
    assert_true(active.stack.is_empty())
  }
}
