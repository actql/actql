///|
test "fixed SQL intervals lower exact integers to the shared temporal operation" {
  for
    (text, expected) in [
      (
        "TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)", "{\"timestamp_sub\":[{\"current_timestamp\":[]},{\"literal\":\"1\"},{\"literal\":\"d\"}]}",
      ),
      (
        "stamp + INTERVAL 9007199254740993 MICROSECOND", "{\"timestamp_add\":[{\"field\":\"stamp\"},{\"literal\":\"9007199254740993\"},{\"literal\":\"us\"}]}",
      ),
      (
        "stamp - INTERVAL @amount MINUTE", "{\"timestamp_sub\":[{\"field\":\"stamp\"},{\"$param\":\"amount\"},{\"literal\":\"m\"}]}",
      ),
    ] {
    assert_eq(emit(text), expected)
  }
  for
    text in [
      "INTERVAL 1 DAY", "CONCAT(INTERVAL 1 DAY)", "TIMESTAMP_ADD(stamp,1)",
    ] {
    assert_true(
      lower(fixture(text), path => Some(path[0].value), limits()) is Err(_),
    )
  }
}

///|
test "fixed SQL interval grouping and unsupported value positions retain their roles" {
  assert_eq(
    emit("stamp + ((INTERVAL 1 DAY))"),
    "{\"timestamp_add\":[{\"field\":\"stamp\"},{\"literal\":\"1\"},{\"literal\":\"d\"}]}",
  )
  for
    text in [
      "CONCAT((INTERVAL 1 DAY))", "stamp + INTERVAL 1 DAY + INTERVAL 1 HOUR",
    ] {
    let result = lower(fixture(text), path => Some(path[0].value), limits())
    if text.has_prefix("CONCAT") {
      assert_true(result is Err(_))
    } else {
      assert_true(result is Ok(_))
    }
  }
}
