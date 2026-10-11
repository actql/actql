///|
test "Exponential and logarithmic SQL forms lower to canonical unary or binary nodes" {
  for
    (name, tag) in [
      ("EXP", "exp"),
      ("LN", "ln"),
      ("LOG", "ln"),
      ("LOG10", "log10"),
      ("`LoG`", "ln"),
    ] {
    assert_eq(emit(name + "(x)"), "{\"" + tag + "\":{\"field\":\"x\"}}")
    assert_eq(emit(name + "(NULL)"), "{\"" + tag + "\":{\"literal\":null}}")
  }
  assert_eq(
    emit("LOG(x, @p)"),
    "{\"log\":[{\"field\":\"x\"},{\"$param\":\"p\"}]}",
  )
  assert_eq(
    emit("LOG(NULL, 1 / 0)"),
    "{\"log\":[{\"literal\":null},{\"divide\":[{\"literal\":1},{\"literal\":0}]}]}",
  )
}

///|
test "Only unary LOG LN identity is added to the existing function registry" {
  fn path(name : String) -> Array[@query.NamePart] {
    [{ value: name, quoted: false, }]
  }
  for arity in [None, Some(0), Some(2), Some(3)] {
    assert_false(
      @query_expression.same_scalar_function(path("LOG"), path("LN"), arity~),
    )
  }
  assert_true(
    @query_expression.same_scalar_function(
      path("LOG"),
      path("LN"),
      arity=Some(1),
    ),
  )
  assert_true(
    @query_expression.same_scalar_function(
      path("ln"),
      path("log"),
      arity=Some(1),
    ),
  )
  for arity in [None, Some(0), Some(1), Some(2), Some(3)] {
    assert_true(
      @query_expression.same_scalar_function(path("POW"), path("POWER"), arity~),
    )
    assert_true(
      @query_expression.same_scalar_function(
        path("CEIL"),
        path("CEILING"),
        arity~,
      ),
    )
    assert_false(
      @query_expression.same_scalar_function(
        path("LENGTH"),
        path("CHAR_LENGTH"),
        arity~,
      ),
    )
    assert_false(
      @query_expression.same_scalar_function(
        path("IFNULL"),
        path("COALESCE"),
        arity~,
      ),
    )
    assert_false(
      @query_expression.same_scalar_function(
        path("ROUND"),
        path("TRUNC"),
        arity~,
      ),
    )
    assert_false(
      @query_expression.same_scalar_function(
        path("TRIM"),
        path("LTRIM"),
        arity~,
      ),
    )
  }
}
