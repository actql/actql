///|
test "public UTF8_TRUNCATE retains original input and byte-limit expressions" {
  for name in ["UTF8_TRUNCATE", "utf8_truncate", "`UtF8_TrUnCaTe`"] {
    assert_eq(
      emit(name + "('é😀x', (6))"),
      "{\"utf8_truncate\":{\"max_bytes\":{\"literal\":6},\"value\":{\"literal\":\"é😀x\"}}}",
    )
    assert_eq(
      emit(name + "(payload, @bytes)"),
      "{\"utf8_truncate\":{\"max_bytes\":{\"$param\":\"bytes\"},\"value\":{\"field\":\"payload\"}}}",
    )
  }
}

///|
test "public UTF8_TRUNCATE preserves function namespace arity and construction limits" {
  for text in ["UTF8_TRUNCATE('a')", "UTF8_TRUNCATE('a', 1, 2)"] {
    assert_true(
      lower(fixture(text), _ => None, limits())
      is Err({ issue: InvalidArguments, .. }),
    )
  }
  assert_true(
    lower(fixture("ACTQL.UTF8_TRUNCATE('a', 1)"), _ => None, limits())
    is Err({ issue: UnsupportedFunction, .. }),
  )
  assert_true(
    lower(fixture("UTF8_TRUNCATE(missing, 1)"), _ => None, limits())
    is Err({ issue: UnknownReference, .. }),
  )
  assert_true(
    lower(fixture("UTF8_TRUNCATE('a', 1)"), _ => None, {
      ..limits(),
      max_work: 0,
    })
    is Err({ issue: WorkLimit, .. }),
  )
}
