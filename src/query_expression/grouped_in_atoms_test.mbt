///|
test "grouped IN parameters retain immediate scalar parameter holes" {
  assert_eq(
    emit("x IN ((1), ((@p)), -(2))"),
    "{\"in\":[{\"field\":\"x\"},{\"literal\":[1,{\"$param\":\"p\"},-2]}]}",
  )
  assert_eq(
    emit("x NOT IN (((@p)), NULL, -(2))"),
    "{\"not_in\":[{\"field\":\"x\"},{\"literal\":[{\"$param\":\"p\"},null,-2]}]}",
  )
}

///|
test "grouped signed numeric IN atoms preserve values without expanding expressions" {
  assert_eq(
    emit("x IN (-(1), +((2)), (-3), -(-4), (NULL), (TRUE), ('s'))"),
    "{\"in\":[{\"field\":\"x\"},{\"literal\":[-1,2,-3,4,null,true,\"s\"]}]}",
  )
  for text in ["x IN ((y))", "x IN ((1 + 2))", "x IN (-(@p))"] {
    assert_true(
      lower(fixture(text), _ => Some("x"), limits())
      is Err({ issue: InvalidArguments, .. }),
      msg=text,
    )
  }
}

///|
test "grouped atoms retain numeric and work limits" {
  for text in ["x IN (-(0))", "x IN ((9007199254740992))", "x IN (-(1e99999))"] {
    assert_true(
      lower(fixture(text), _ => Some("x"), limits())
      is Err({ issue: InvalidNumber, .. }),
      msg=text,
    )
  }
  let ast = fixture("x IN (((@p)))")
  assert_true(
    lower(ast, _ => Some("x"), {
      ..limits(),
      max_work: @query.expression_node_count(ast) - 1,
    })
    is Err({ issue: WorkLimit, .. }),
  )
}
