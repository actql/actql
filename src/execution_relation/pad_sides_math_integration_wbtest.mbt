// Independently rebuilt integration diagnostic; requires verified math/extrema predecessors.

///|
test "padding and side slices compose with SAFE ROUND extrema and transcendental children" {
  for
    (source, expected) in [
      ("left('abc',round(1.55,0))", "ab"),
      ("right('abc',trunc(2.99,0))", "bc"),
      ("lpad('a',greatest(2,pow(2,2)),'x')", "xxxa"),
      ("rpad('a',least(8,log(16,2)),'x')", "axxx"),
      ("left('abc',exp(0))", "a"),
      ("right('abc',ln(1))", ""),
      ("lpad('a',safe_add(1,3),'x')", "xxxa"),
    ] {
    guard run_expr("\"" + source + "\"") is Ok(Text(actual)) else {
      fail(source)
    }
    assert_eq(actual, expected)
  }
  for
    source in [
      "lpad('x',safe_divide(1,0),'')", "right('x',greatest(NULL,2))", "lpad(NULL,round(1.25,1),'')",
    ] {
    assert_true(run_expr("\"" + source + "\"") is Ok(Null))
  }
  for
    source in [
      "left(NULL,pow(-2,0.5))", "rpad('x',-1,to_string(pow(2,1024)))", "lpad(NULL,least(NULL,pow(-2,0.5)),'')",
    ] {
    guard run_expr("\"" + source + "\"") is Err(issue) else { fail(source) }
    assert_true(issue.kind is Scalar(ArithmeticFailure))
    assert_true(
      @lower.expression_body(issue.expression)
      is @lower.Binary(@lower.Pow, _, _),
    )
  }
  assert_true(
    run_expr("\"if(false,lpad('x',pow(2,1024),'x'),'safe')\"")
    is Ok(Text("safe")),
  )
}
