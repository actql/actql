///|
test "public scalar conversions retain the exact existing CAST bodies" {
  for
    (name, target, value) in [
      ("to_string", "STRING", "12.5"),
      ("to_boolean", "BOOLEAN", "'true'"),
      ("to_timestamp", "TIMESTAMP", "'2026-10-19T00:00:00.000Z'"),
    ] {
    for child in [value, "NULL", "@input", "value", "1 / 0"] {
      assert_eq(
        emit(name + "(" + child + ")"),
        emit("CAST(" + child + " AS " + target + ")"),
      )
    }
    assert_eq(
      emit("`" + name + "`(" + value + ")"),
      emit(name + "(" + value + ")"),
    )
    assert_eq(
      emit(name + "('not-convertible')"),
      emit("CAST('not-convertible' AS " + target + ")"),
    )
  }
}

///|
test "public scalar conversions retain namespaces arity budgets and canonical targets" {
  for name in ["to_string", "to_boolean", "to_timestamp"] {
    for args in ["", "'1', '2'"] {
      assert_true(
        lower(fixture(name + "(" + args + ")"), _ => None, limits())
        is Err({ issue: InvalidArguments, .. }),
      )
    }
    assert_true(
      lower(fixture("ACTQL." + name + "('1')"), _ => None, limits())
      is Err({ issue: UnsupportedFunction, .. }),
    )
    assert_true(
      lower(fixture(name + "('1')"), _ => None, { ..limits(), max_work: 0, })
      is Err({ issue: WorkLimit, .. }),
    )
  }
  assert_eq(
    emit("To_StRiNg(@input)"),
    "{\"cast\":{\"target\":{\"type\":\"string\"},\"value\":{\"$param\":\"input\"}}}",
  )
  assert_eq(
    emit("To_BoOlEaN(@input)"),
    "{\"cast\":{\"target\":{\"type\":\"boolean\"},\"value\":{\"$param\":\"input\"}}}",
  )
  assert_eq(
    emit("To_TiMeStAmP(@input)"),
    "{\"cast\":{\"target\":{\"type\":\"timestamp\"},\"value\":{\"$param\":\"input\"}}}",
  )
}
