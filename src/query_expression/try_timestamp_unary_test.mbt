///|
test "public unary TRY_TIMESTAMP retains original argument without a manufactured pattern" {
  assert_eq(
    emit("TRY_TIMESTAMP(@stamp)"),
    "{\"try_timestamp\":{\"value\":{\"$param\":\"stamp\"}}}",
  )
  assert_eq(
    emit("try_timestamp(NULL)"),
    "{\"try_timestamp\":{\"value\":{\"literal\":null}}}",
  )
  assert_eq(
    emit("TRY_TIMESTAMP(stamp,'yyyy-MM-dd')"),
    "{\"try_timestamp\":{\"pattern\":{\"literal\":\"yyyy-MM-dd\"},\"value\":{\"field\":\"stamp\"}}}",
  )
  for
    source in [
      "TRY_TIMESTAMP()", "TRY_TIMESTAMP(1,2,3)", "ACTQL.TRY_TIMESTAMP('x')",
    ] {
    assert_true(lower(fixture(source), _ => None, limits()) is Err(_))
  }
}
