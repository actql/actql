///|
test "general membership precise ARRAY result 1" {
  assert_type(
    "{\"in\":[{\"literal\":2},{\"field\":\"xs\"}]}", "{\"xs\":{\"type\":\"array\",\"nullable\":false,\"max_items\":2,\"items\":{\"type\":\"number\",\"nullable\":false}},\"ys\":{\"type\":\"array\",\"nullable\":false,\"max_items\":2,\"items\":{\"type\":\"number\",\"nullable\":false}}}",
    "null", "{\"type\":\"boolean\",\"nullable\":false}",
  )
}

///|
test "general membership precise ARRAY result 2" {
  assert_type(
    "{\"in\":[{\"literal\":2},{\"if\":[{\"literal\":true},{\"$param\":\"xs\"},{\"$param\":\"ys\"}]}]}",
    "{}", "{\"xs\":{\"type\":\"array\",\"nullable\":false,\"max_items\":2,\"items\":{\"type\":\"number\",\"nullable\":false}},\"ys\":{\"type\":\"array\",\"nullable\":false,\"max_items\":2,\"items\":{\"type\":\"number\",\"nullable\":false}}}",
    "{\"type\":\"boolean\",\"nullable\":false}",
  )
}

///|
test "general membership scalar RHS remains a typing error" {
  for
    source in [
      "2 IN scalar", "2 IN if(TRUE, 1, 2)", "2 IN -1", "2 IN NULL", "2 IN TRUE",
      "2 IN 'text'",
    ] {
    assert_true(
      @expression_typing.check(
        syntax("\"" + source + "\""),
        env(fields="{\"scalar\":{\"type\":\"number\",\"nullable\":false}}"),
        test_limits(),
      )
      is Err(_),
    )
  }
}

///|
test "general membership nullability boundary 1" {
  assert_type(
    "{\"in\":[{\"literal\":2},{\"field\":\"xs\"}]}", "{\"xs\":{\"type\":\"array\",\"nullable\":true,\"max_items\":2,\"items\":{\"type\":\"number\",\"nullable\":false}}}",
    "null", "{\"type\":\"boolean\",\"nullable\":false}",
  )
}

///|
test "general membership nullability boundary 2" {
  assert_type(
    "{\"in\":[{\"literal\":2},{\"field\":\"xs\"}]}", "{\"xs\":{\"type\":\"array\",\"nullable\":false,\"max_items\":2,\"items\":{\"type\":\"number\",\"nullable\":true}}}",
    "null", "{\"type\":\"boolean\",\"nullable\":true}",
  )
}

///|
test "general membership nullability boundary 3" {
  assert_type(
    "{\"in\":[{\"literal\":null},{\"field\":\"xs\"}]}", "{\"xs\":{\"type\":\"array\",\"nullable\":true,\"max_items\":0,\"items\":{\"type\":\"number\",\"nullable\":true}}}",
    "null", "{\"type\":\"boolean\",\"nullable\":false}",
  )
}

///|
test "general membership nullability boundary 4" {
  assert_type(
    "{\"in\":[{\"literal\":null},{\"field\":\"xs\"}]}", "{\"xs\":{\"type\":\"array\",\"nullable\":false,\"max_items\":2,\"items\":{\"type\":\"number\",\"nullable\":false}}}",
    "null", "{\"type\":\"boolean\",\"nullable\":true}",
  )
}

///|
test "typed empty ARRAY RHS keeps nonnullable membership despite NULL left" {
  assert_type(
    "{\"in\":[{\"literal\":null},{\"empty_array\":{\"items\":{\"type\":\"number\",\"nullable\":false}}}]}",
    "{}", "null", "{\"type\":\"boolean\",\"nullable\":false}",
  )
}

///|
test "general ARRAY membership rejects incompatible item domains even when empty" {
  assert_true(
    @expression_typing.check(
      syntax(
        "{\"in\":[{\"literal\":2},{\"empty_array\":{\"items\":{\"type\":\"string\",\"nullable\":false}}}]}",
      ),
      env(),
      test_limits(),
    )
    is Err(_),
  )
}
