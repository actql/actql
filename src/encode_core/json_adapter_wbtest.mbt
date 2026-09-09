///|
test "borrowed JSON emission preserves exact values without retaining aliases" {
  let repr_out = writer(10, 1, 0)
  emit_json(Json::number(1.0, repr="},\"forged\":true"), repr_out)
  assert_eq(finish(repr_out), "1")
  let children : Array[Json] = [
    Json::string("e\u0301\r\n😀"),
    Json::number(1.0000000000000002),
  ]
  let fields : Map[String, Json] = Map([])
  fields["z"] = Json::array(children)
  fields["a"] = Json::boolean(false)
  let value = Json::object(fields)
  let expected = value.stringify()
  let out = writer(1024, 10, 3)
  emit_json(value, out)
  // Mutation before finish cannot alter bytes already emitted.
  children.clear()
  fields.clear()
  assert_eq(finish(out), expected)
  assert_eq(
    expected, "{\"z\":[\"e\u0301\\r\\n😀\",1.0000000000000002],\"a\":false}",
  )
}

///|
test "JSON traversal consumes parent budgets and rejects cycles and invalid scalars" {
  let cyclic_items : Array[Json] = []
  let cyclic = Json::array(cyclic_items)
  cyclic_items.push(cyclic)
  let out = writer(1024, 20, 3)
  assert_true(
    try {
      emit_json(cyclic, out)
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
  for limits in [(3, 10, 3), (1024, 1, 3), (1024, 10, 0)] {
    let out = writer(limits.0, limits.1, limits.2)
    assert_true(
      try {
        emit_json([true], out)
        false
      } catch {
        OutputLimit => true
        _ => false
      },
    )
  }
  let bad = "😀".unsafe_substring(start=0, end=1)
  let out = writer(1024, 10, 3)
  assert_true(
    try {
      emit_json(Json::string(bad), out)
      false
    } catch {
      InvalidUnicode => true
      _ => false
    },
  )
  let out = writer(1024, 10, 3)
  assert_true(
    try {
      emit_json(Json::number(0.0 / 0.0), out)
      false
    } catch {
      InvalidNumber => true
      _ => false
    },
  )
}
