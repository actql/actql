///|
test "adopted canonical vector score emits each exact metric without score reversal" {
  for metric in ["cosine", "dot", "l2"] {
    assert_eq(
      @json.parse(emit("vector_score(a,b,'" + metric + "')")),
      @json.parse(
        "{\"vector_score\":{\"left\":{\"field\":\"a\"},\"right\":{\"field\":\"b\"},\"metric\":\"" +
        metric +
        "\"}}",
      ),
    )
  }
}

///|
test "canonical vector score literal grouping and quoted lookup retain public identity" {
  assert_eq(
    emit("`VeCtOr_ScOrE`(a,b,(('do' 't')))"),
    emit("VECTOR_SCORE(a,b,'dot')"),
  )
  assert_false(
    same_scalar_function(
      scalar_identity_name("vector_score"),
      scalar_identity_name("VECTOR_INNER_PRODUCT"),
      arity=Some(3),
    ),
  )
  assert_eq(
    @json.parse(emit("vector_concat(a,b)")),
    @json.parse(emit("VECTOR_CONCAT(a,b)")),
  )
}

///|
test "canonical vector score refuses nonliteral or inexact metrics at their authored argument" {
  for
    metric in [
      "'DOT'", "'L2'", "''", "NULL", "1", "@metric", "metric", "IF(TRUE,'dot','l2')",
      "'do'||'t'",
    ] {
    let ast = fixture("vector_score(a,b," + metric + ")")
    guard @query.expression_node(ast, @query.expression_root(ast))
      is Some({ kind: Call(_, args), .. }) else {
      fail("score call")
    }
    let expected = @query.expression_origin(ast, args[2])
    match
      lower(
        ast,
        path => Some(path[0].value),
        limits(),
        resolve_parameter=Some(name => Ok(name)),
      ) {
      Err({ issue: InvalidArguments, origin, }) => {
        let actual_origin = origin.unwrap()
        let expected_origin = expected.unwrap()
        assert_eq(@origin.start(actual_origin), @origin.start(expected_origin))
        assert_eq(@origin.end(actual_origin), @origin.end(expected_origin))
      }
      _ => fail("expected an authored literal metric refusal")
    }
  }
}

///|
test "canonical vector score keeps exactly three positional arguments" {
  for text in ["vector_score(a,b)", "vector_score(a,b,'dot',1)"] {
    match lower(fixture(text), path => Some(path[0].value), limits()) {
      Err({ issue: InvalidArguments, .. }) => ()
      _ => fail("expected score arity refusal")
    }
  }
}
