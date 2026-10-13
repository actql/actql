///|
test "IN UNNEST retains an array operand rather than a singleton list or expansion" {
  assert_eq(
    emit("amount IN UNNEST((@xs))"),
    "{\"in\":[{\"field\":\"amount\"},{\"$param\":\"xs\"}]}",
  )
  assert_eq(
    emit("amount NOT IN UNNEST((@xs))"),
    "{\"not_in\":[{\"field\":\"amount\"},{\"$param\":\"xs\"}]}",
  )
}

///|
test "general array expression membership retains the common ARRAY operand" {
  assert_eq(
    emit("2 IN UNNEST(xs)"),
    "{\"in\":[{\"literal\":2},{\"field\":\"xs\"}]}",
  )
  assert_eq(
    emit("2 IN UNNEST(IF(TRUE, @xs, @ys))"),
    "{\"in\":[{\"literal\":2},{\"if\":[{\"literal\":true},{\"$param\":\"xs\"},{\"$param\":\"ys\"}]}]}",
  )
}
