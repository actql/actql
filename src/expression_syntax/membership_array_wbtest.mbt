///|
test "general ARRAY membership canonical source 1" {
  assert_tree(
    "{\"in\":[{\"literal\":2},{\"field\":\"xs\"}]}", "{\"in\":[{\"literal\":2},{\"field\":\"xs\"}]}",
  )
  assert_tree("\"2 IN xs\"", "{\"in\":[{\"literal\":2},{\"field\":\"xs\"}]}")
}

///|
test "general ARRAY membership canonical source 2" {
  assert_tree(
    "{\"in\":[{\"literal\":2},{\"if\":[{\"literal\":true},{\"$param\":\"xs\"},{\"$param\":\"ys\"}]}]}",
    "{\"in\":[{\"literal\":2},{\"if\":[{\"literal\":true},{\"$param\":\"xs\"},{\"$param\":\"ys\"}]}]}",
  )
  assert_tree(
    "\"2 IN if(TRUE, $xs, $ys)\"", "{\"in\":[{\"literal\":2},{\"if\":[{\"literal\":true},{\"$param\":\"xs\"},{\"$param\":\"ys\"}]}]}",
  )
}

///|
test "general ARRAY membership canonical source 3" {
  assert_tree(
    "{\"not_in\":[{\"literal\":2},{\"coalesce\":[{\"field\":\"xs\"},{\"array\":[{\"literal\":2}]}]}]}",
    "{\"not_in\":[{\"literal\":2},{\"coalesce\":[{\"field\":\"xs\"},{\"array\":[{\"literal\":2}]}]}]}",
  )
  assert_tree(
    "\"2 NOT IN coalesce(xs, [2])\"", "{\"not_in\":[{\"literal\":2},{\"coalesce\":[{\"field\":\"xs\"},{\"array\":[{\"literal\":2}]}]}]}",
  )
}

///|
test "general ARRAY membership canonical source 4" {
  assert_tree(
    "{\"in\":[{\"literal\":2},{\"case\":{\"when\":[{\"when\":{\"literal\":true},\"then\":{\"field\":\"xs\"}}],\"else\":{\"field\":\"ys\"}}}]}",
    "{\"in\":[{\"literal\":2},{\"case\":{\"when\":[{\"when\":{\"literal\":true},\"then\":{\"field\":\"xs\"}}],\"else\":{\"field\":\"ys\"}}}]}",
  )
  assert_tree(
    "\"2 IN CASE WHEN TRUE THEN xs ELSE ys END\"", "{\"in\":[{\"literal\":2},{\"case\":{\"when\":[{\"when\":{\"literal\":true},\"then\":{\"field\":\"xs\"}}],\"else\":{\"field\":\"ys\"}}}]}",
  )
}

///|
test "general ARRAY membership canonical source 5" {
  assert_tree(
    "{\"in\":[{\"literal\":2},{\"property\":{\"value\":{\"field\":\"record\"},\"name\":\"xs\"}}]}",
    "{\"in\":[{\"literal\":2},{\"property\":{\"value\":{\"field\":\"record\"},\"name\":\"xs\"}}]}",
  )
  assert_tree(
    "\"2 IN record.xs\"", "{\"in\":[{\"literal\":2},{\"property\":{\"value\":{\"field\":\"record\"},\"name\":\"xs\"}}]}",
  )
}

///|
test "general ARRAY membership canonical source 6" {
  assert_tree(
    "{\"in\":[{\"literal\":2},{\"subscript\":{\"value\":{\"field\":\"arrays\"},\"index\":{\"literal\":0}}}]}",
    "{\"in\":[{\"literal\":2},{\"subscript\":{\"value\":{\"field\":\"arrays\"},\"index\":{\"literal\":0}}}]}",
  )
  assert_tree(
    "\"2 IN arrays[0]\"", "{\"in\":[{\"literal\":2},{\"subscript\":{\"value\":{\"field\":\"arrays\"},\"index\":{\"literal\":0}}}]}",
  )
}

///|
test "general ARRAY membership canonical source 7" {
  assert_tree(
    "{\"in\":[{\"literal\":2},{\"array\":[{\"literal\":1},{\"literal\":2}]}]}", "{\"in\":[{\"literal\":2},{\"array\":[{\"literal\":1},{\"literal\":2}]}]}",
  )
  assert_tree(
    "\"2 IN [1, 2]\"", "{\"in\":[{\"literal\":2},{\"array\":[{\"literal\":1},{\"literal\":2}]}]}",
  )
}

///|
test "general ARRAY membership canonical source 8" {
  assert_tree(
    "{\"in\":[{\"literal\":2},{\"coalesce\":[{\"if\":[{\"literal\":false},{\"field\":\"ys\"},{\"field\":\"xs\"}]},{\"array\":[{\"literal\":2}]}]}]}",
    "{\"in\":[{\"literal\":2},{\"coalesce\":[{\"if\":[{\"literal\":false},{\"field\":\"ys\"},{\"field\":\"xs\"}]},{\"array\":[{\"literal\":2}]}]}]}",
  )
  assert_tree(
    "\"2 IN coalesce(if(FALSE, ys, xs), [2])\"", "{\"in\":[{\"literal\":2},{\"coalesce\":[{\"if\":[{\"literal\":false},{\"field\":\"ys\"},{\"field\":\"xs\"}]},{\"array\":[{\"literal\":2}]}]}]}",
  )
}

///|
test "general membership retains both IF parameter occurrences" {
  let expression = admit(
    source_cursor("\"2 IN if(TRUE, $xs, $ys)\""),
    test_limits(),
  ).unwrap()
  assert_eq(parameter_references(expression).map(r => r.name), ["xs", "ys"])
}

///|
test "typed empty ARRAY RHS retains structured roundtrip" {
  assert_tree(
    "{\"in\":[{\"literal\":null},{\"empty_array\":{\"items\":{\"type\":\"number\",\"nullable\":false}}}]}",
    "{\"in\":[{\"literal\":null},{\"empty_array\":{\"items\":{\"type\":\"number\",\"nullable\":false}}}]}",
  )
}

///|
test "non-ARRAY literals reach the existing type owner" {
  assert_tree("\"2 IN -1\"", "{\"in\":[{\"literal\":2},{\"literal\":-1}]}")
  assert_tree("\"2 IN NULL\"", "{\"in\":[{\"literal\":2},{\"literal\":null}]}")
  assert_tree("\"2 IN TRUE\"", "{\"in\":[{\"literal\":2},{\"literal\":true}]}")
  assert_tree(
    "\"2 IN 'text'\"", "{\"in\":[{\"literal\":2},{\"literal\":\"text\"}]}",
  )
}
