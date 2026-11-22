///|
test "array concat adds the original array item ceilings and propagates whole-array nullability" {
  assert_type(
    "{\"array_concat\":[{\"array\":[{\"literal\":1}]},{\"array\":[{\"literal\":2}]}]}",
    "{}", "null", "{\"type\":\"array\",\"nullable\":false,\"max_items\":2,\"items\":{\"type\":\"number\",\"nullable\":false}}",
  )
  assert_type(
    "{\"array_concat\":[{\"literal\":null},{\"array\":[{\"literal\":2}]}]}", "{}",
    "null", "{\"type\":\"array\",\"nullable\":true,\"max_items\":1,\"items\":{\"type\":\"number\",\"nullable\":false}}",
  )
}
