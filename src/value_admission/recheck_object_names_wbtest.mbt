///|
fn object_name_contract(name : String) -> @contract.Contract {
  @contract.object_contract(
    [(name, @contract.primitive(@contract.NumberType, nullable=false))],
    nullable=false,
    max_fields=1,
    max_name_bytes=1024,
  ).unwrap()
}

///|
test "typed Object name recheck steps before visiting the child" {
  let name = String::make(130, 'x')
  let contract = object_name_contract(name)
  let value = object_value([(name, Number(1.0))]).unwrap()
  let limits : Limits = { max_nodes: 2, max_depth: 1, max_text_bytes: 130, }
  let cursor = start_recheck_runtime_value(value, contract, limits).unwrap()
  // Root, field setup, three name fragments, child, exhausted fields, finish.
  for _ in 0..<7 {
    assert_true(advance_recheck_runtime_value(cursor) is RecheckContinue)
  }
  assert_true(
    advance_recheck_runtime_value(cursor) is RecheckComplete(_, 2, 130),
  )
  assert_true(
    recheck_runtime_value_usage(value, contract, limits) is Some((_, 2, 130)),
  )
  for short in [{ ..limits, max_nodes: 1, }, { ..limits, max_text_bytes: 129, }] {
    assert_true(recheck_runtime_value(value, contract, short) is None)
    let active = start_recheck_runtime_value(value, contract, short).unwrap()
    let mut failed = false
    for _ in 0..<8 {
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
  let stopping = start_recheck_runtime_value(value, contract, limits).unwrap()
  for _ in 0..<3 {
    assert_true(advance_recheck_runtime_value(stopping) is RecheckContinue)
  }
  assert_eq(stopping.budget.nodes, 1)
  assert_eq(stopping.budget.text, 66)
  cancel_recheck_runtime_value(stopping)
  assert_true(stopping.stack.is_empty())
  assert_true(advance_recheck_runtime_value(stopping) is RecheckFailed)
  assert_true(recheck_runtime_value(value, contract, limits) is Some(_))
}

///|
test "Object identifier refusal stays separate from opaque JSON member data" {
  let contract = @contract.primitive(@contract.JsonType, nullable=false)
  for name in ["e\u{0301}", "a\rb", "a\r\nb"] {
    // The declared Object builder owns identifier admission. The same keys
    // inside JsonData belong to the opaque data domain and must remain exact.
    let value = Object({ values: [(name, Number(1.0))], })
    let limits : Limits = { max_nodes: 2, max_depth: 1, max_text_bytes: 100, }
    assert_true(object_value([(name, Number(1.0))]) is None)
    assert_true(recheck_runtime_value(value, contract, limits) is None)
    let cursor = start_recheck_runtime_value(value, contract, limits).unwrap()
    assert_true(advance_recheck_runtime_value(cursor) is RecheckFailed)
    assert_true(cursor.stack.is_empty())
    let json = JsonData(value)
    let (_, nodes, bytes) = recheck_runtime_value_usage(json, contract, limits).unwrap()
    assert_eq(nodes, 2)
    assert_eq(bytes, @utf8.encode(name).length())
    let json_cursor = start_recheck_runtime_value(json, contract, limits).unwrap()
    for _ in 0..<4 {
      assert_true(advance_recheck_runtime_value(json_cursor) is RecheckContinue)
    }
    guard advance_recheck_runtime_value(json_cursor)
      is RecheckComplete(checked, actual_nodes, actual_bytes) else {
      abort("opaque JSON recheck must complete without normalizing keys")
    }
    assert_eq(actual_nodes, nodes)
    assert_eq(actual_bytes, bytes)
    guard checked.value is JsonData(Object(fields)) else {
      abort("opaque JSON member data must retain its domain")
    }
    assert_eq(fields.values[0].0, name)
  }
}

///|
test "typed Object names preserve Unicode bytes and reject a late mismatch" {
  let name = String::make(63, 'a') + "😀" + String::make(65, 'é')
  let contract = object_name_contract(name)
  let value = object_value([(name, Number(1.0))]).unwrap()
  let limits : Limits = { max_nodes: 2, max_depth: 1, max_text_bytes: 197, }
  let cursor = start_recheck_runtime_value(value, contract, limits).unwrap()
  for _ in 0..<7 {
    assert_true(advance_recheck_runtime_value(cursor) is RecheckContinue)
    assert_true(cursor.stack.length() <= 2)
  }
  assert_true(
    advance_recheck_runtime_value(cursor) is RecheckComplete(_, 2, 197),
  )
  let short = start_recheck_runtime_value(value, contract, {
    ..limits,
    max_text_bytes: 196,
  }).unwrap()
  for _ in 0..<4 {
    assert_true(advance_recheck_runtime_value(short) is RecheckContinue)
  }
  assert_true(advance_recheck_runtime_value(short) is RecheckFailed)
  assert_eq(short.budget.nodes, 1)
  assert_true(short.stack.is_empty())
  let foreign = object_value([(String::make(129, 'x') + "y", Number(1.0 / 0.0))]).unwrap()
  let bad = start_recheck_runtime_value(
    foreign,
    object_name_contract(String::make(130, 'x')),
    { ..limits, max_text_bytes: 130, },
  ).unwrap()
  // Four polls reach only the first two fragments; the final-name mismatch
  // fails before the independently invalid child Number is inspected.
  for _ in 0..<4 {
    assert_true(advance_recheck_runtime_value(bad) is RecheckContinue)
  }
  assert_true(advance_recheck_runtime_value(bad) is RecheckFailed)
  assert_eq(bad.budget.nodes, 1)
  assert_true(bad.stack.is_empty())
}
