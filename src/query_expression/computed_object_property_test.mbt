///|
test "computed object properties lower as ordinary typed property expressions" {
  assert_eq(
    emit("COALESCE(payload, fallback).score"),
    "{\"property\":{\"name\":\"score\",\"value\":{\"coalesce\":[{\"field\":\"payload\"},{\"field\":\"fallback\"}]}}}",
  )
  assert_eq(
    emit("(@payload).nested.`score`"),
    "{\"property\":{\"name\":\"score\",\"value\":{\"property\":{\"name\":\"nested\",\"value\":{\"$param\":\"payload\"}}}}}",
  )
  assert_eq(
    emit("(CASE WHEN id > 0 THEN payload ELSE fallback END).score"),
    "{\"property\":{\"name\":\"score\",\"value\":{\"case\":{\"else\":{\"field\":\"fallback\"},\"when\":[{\"then\":{\"field\":\"payload\"},\"when\":{\"gt\":[{\"field\":\"id\"},{\"literal\":0}]}}]}}}}",
  )
}
