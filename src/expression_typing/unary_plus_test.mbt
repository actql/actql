///|
test "composed numeric identity preserves decimal precision scale and nullability" {
  for
    (field, contract) in [
      ("n", "{\"type\":\"number\",\"nullable\":false}"),
      ("n", "{\"type\":\"number\",\"nullable\":true}"),
      (
        "n", "{\"type\":\"decimal\",\"nullable\":false,\"precision\":8,\"scale\":3}",
      ),
      (
        "n", "{\"type\":\"decimal\",\"nullable\":true,\"precision\":38,\"scale\":9}",
      ),
    ] {
    assert_type(
      "{\"negate\":{\"negate\":{\"field\":\"" + field + "\"}}}",
      "{\"" + field + "\":" + contract + "}",
      "null",
      contract,
    )
  }
  for
    contract in [
      "{\"type\":\"string\",\"nullable\":false}", "{\"type\":\"boolean\",\"nullable\":true}",
    ] {
    assert_rejected(
      "{\"negate\":{\"negate\":{\"field\":\"n\"}}}",
      "{\"n\":" + contract + "}",
      "null",
      "TypeMismatch",
    )
  }
}
