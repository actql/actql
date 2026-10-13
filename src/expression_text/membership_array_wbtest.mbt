///|
test "general ARRAY membership source 1" {
  assert_tree("2 IN xs", "{\"in\":[{\"literal\":2},{\"field\":\"xs\"}]}")
}

///|
test "general ARRAY membership source 2" {
  assert_tree(
    "2 IN if(TRUE, $xs, $ys)", "{\"in\":[{\"literal\":2},{\"if\":[{\"literal\":true},{\"$param\":\"xs\"},{\"$param\":\"ys\"}]}]}",
  )
}

///|
test "general ARRAY membership source 3" {
  assert_tree(
    "2 NOT IN coalesce(xs, [2])", "{\"not_in\":[{\"literal\":2},{\"coalesce\":[{\"field\":\"xs\"},{\"array\":[{\"literal\":2}]}]}]}",
  )
}

///|
test "general ARRAY membership source 4" {
  assert_tree(
    "2 IN CASE WHEN TRUE THEN xs ELSE ys END", "{\"in\":[{\"literal\":2},{\"case\":{\"when\":[{\"when\":{\"literal\":true},\"then\":{\"field\":\"xs\"}}],\"else\":{\"field\":\"ys\"}}}]}",
  )
}

///|
test "general ARRAY membership source 5" {
  assert_tree(
    "2 IN record.xs", "{\"in\":[{\"literal\":2},{\"property\":{\"value\":{\"field\":\"record\"},\"name\":\"xs\"}}]}",
  )
}

///|
test "general ARRAY membership source 6" {
  assert_tree(
    "2 IN arrays[0]", "{\"in\":[{\"literal\":2},{\"subscript\":{\"value\":{\"field\":\"arrays\"},\"index\":{\"literal\":0}}}]}",
  )
}

///|
test "general ARRAY membership source 7" {
  assert_tree(
    "2 IN [1, 2]", "{\"in\":[{\"literal\":2},{\"array\":[{\"literal\":1},{\"literal\":2}]}]}",
  )
}

///|
test "general ARRAY membership source 8" {
  assert_tree(
    "2 IN coalesce(if(FALSE, ys, xs), [2])", "{\"in\":[{\"literal\":2},{\"coalesce\":[{\"if\":[{\"literal\":false},{\"field\":\"ys\"},{\"field\":\"xs\"}]},{\"array\":[{\"literal\":2}]}]}]}",
  )
}
