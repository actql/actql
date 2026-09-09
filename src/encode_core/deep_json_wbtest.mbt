///|
test "deep JSON traversal obeys explicit depth rather than target call stack" {
  let depth = 10000
  let mut value = Json::null()
  for _ in 0..<depth {
    value = Json::array([value])
  }
  let out = writer(depth * 2 + 4, depth + 1, depth)
  emit_json(value, out)
  assert_eq(finish(out), "[".repeat(depth) + "null" + "]".repeat(depth))
  let short = writer(depth * 2 + 4, depth + 1, depth - 1)
  assert_true(
    try {
      emit_json(value, short)
      false
    } catch {
      OutputLimit => true
      _ => false
    },
  )
  assert_true(
    try {
      ignore(finish(short))
      false
    } catch {
      ClosedWriter => true
      _ => false
    },
  )
}

///|
test "cyclic JSON is terminated by the node budget even with a large depth allowance" {
  let children : Array[Json] = []
  let value = Json::array(children)
  children.push(value)
  let out = writer(100000, 10000, 20000)
  assert_true(
    try {
      emit_json(value, out)
      false
    } catch {
      OutputLimit => true
      _ => false
    },
  )
  assert_true(
    try {
      ignore(finish(out))
      false
    } catch {
      ClosedWriter => true
      _ => false
    },
  )
  children.clear()
}
