///|
fn lowered(text : String) -> @lower.Expression {
  let raw = "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"seed\"},{\"derive\":{\"v\":" +
    text +
    "}}]"
  @lower.lower_expression(bound_pipeline(raw), 1, 0, {
    max_nodes: 10000,
    max_work: 100000,
    max_depth: 3000,
    max_literal_nodes: 10000,
    max_literal_text_bytes: 100000,
  }).unwrap()
}

///|
fn bound_pipeline(raw : String) -> @lower.BoundPrepared {
  let tree = @decode.admit(
    @source.parse_json(
      raw,
      { max_input_bytes: 100000, max_nodes: 10000, max_depth: 4000, },
      source_path="execution-test.aql",
    ).unwrap(),
    {
      max_nodes: 10000,
      max_depth: 4000,
      max_string_bytes: 100000,
      max_total_string_bytes: 100000,
    },
  ).unwrap()
  let pipeline = @pipeline.check(tree, [], None, None, {
    max_steps: 100,
    max_work: 100000,
    max_text_bytes: 100000,
    max_nodes: 10000,
    max_tokens: 10000,
    max_depth: 4000,
  }).unwrap()
  let prepared = @lower.prepare(pipeline, {
    max_nodes: 100,
    max_references: 100,
    max_work: 1000,
    max_identifier_bytes: 1000,
  }).unwrap()
  @lower.bind_parameters(prepared, None, max_parameters=0, max_name_bytes=0).unwrap()
}

///|
fn run_expr(text : String) -> Result[Value, EvalIssue] {
  evaluate_expression(lowered(text), {}, [], {
    remaining: 10000,
    max_frames: 1000,
  })
}

///|
test "lazy coalesce charges its view copy but does not demand later children" {
  let expr = lowered(
    "{\"coalesce\":[{\"literal\":7},{\"divide\":[{\"literal\":1},{\"literal\":0}]}]}",
  )
  assert_eq(@lower.expression_view_entries(expr), 2)
  // Four transitions to return the first child and two copied child entries.
  assert_true(
    evaluate_expression(expr, {}, [], { remaining: 6, max_frames: 1, }).unwrap()
    is Number(7.0),
  )
  guard evaluate_expression(expr, {}, [], { remaining: 2, max_frames: 1, })
    is Err(issue) else {
    fail("copy preflight missing")
  }
  assert_eq(issue.kind, ControlLimit)
  assert_true(physical_equal(issue.expression, expr))
}

///|
test "text comparison charges UTF-8 size in addition to control transitions" {
  let expr = lowered(
    "{\"eq\":[{\"literal\":\"é😀\"},{\"literal\":\"é😀\"}]}",
  )
  // Six control transitions and six UTF-8 bytes for each operand.
  assert_true(
    evaluate_expression(expr, {}, [], { remaining: 18, max_frames: 1, }).unwrap()
    is Boolean(true),
  )
  guard evaluate_expression(expr, {}, [], { remaining: 17, max_frames: 1, })
    is Err(issue) else {
    fail("comparison work missing")
  }
  assert_eq(issue.kind, ControlLimit)
}

///|
test "selected branches only execute; eager boolean still evaluates failure" {
  assert_true(run_expr("\"if(true, 7, 1 / 0)\"").unwrap() is Number(7.0))
  assert_true(run_expr("\"coalesce(7, 1 / 0)\"").unwrap() is Number(7.0))
  guard run_expr("\"false AND (1 / 0 > 0)\"") is Err(issue) else {
    fail("eager AND must evaluate RHS")
  }
  assert_eq(issue.kind, Scalar(ArithmeticFailure))
  assert_true(
    @lower.expression_body(issue.expression)
    is @lower.Binary(@lower.Divide, _, _),
  )
  assert_true(run_expr("\"if(NULL, 1 / 0, 8)\"").unwrap() is Number(8.0))
}

///|
test "CASE skips later conditions and unused results; implicit ELSE is null" {
  assert_true(
    run_expr(
      "{\"case\":{\"when\":[{\"when\":{\"literal\":true},\"then\":{\"literal\":9}},{\"when\":{\"gt\":[{\"divide\":[{\"literal\":1},{\"literal\":0}]},{\"literal\":0}]},\"then\":{\"literal\":2}}]}}",
    ).unwrap()
    is Number(9.0),
  )
  assert_true(
    run_expr(
      "{\"case\":{\"when\":[{\"when\":{\"literal\":false},\"then\":{\"literal\":9}}]}}",
    ).unwrap()
    is Null,
  )
}

///|
test "control budget is cumulative across roots and independent on fresh invocation" {
  let expr = lowered("{\"literal\":7}")
  let budget = { remaining: 4, max_frames: 0, }
  assert_true(evaluate_expression(expr, {}, [], budget).unwrap() is Number(7.0))
  assert_eq(budget.remaining, 2)
  assert_true(evaluate_expression(expr, {}, [], budget).unwrap() is Number(7.0))
  assert_eq(budget.remaining, 0)
  guard evaluate_expression(expr, {}, [], budget) is Err(issue) else {
    fail("expected exhausted budget")
  }
  assert_eq(issue.kind, ControlLimit)
  assert_true(
    evaluate_expression(expr, {}, [], { remaining: 2, max_frames: 0, }).unwrap()
    is Number(7.0),
  )
  guard evaluate_expression(expr, {}, [], { remaining: 1, max_frames: 0, })
    is Err(short) else {
    fail("one transition short")
  }
  assert_eq(short.kind, ControlLimit)
}

///|
test "deep expression uses bounded continuation stack rather than host recursion" {
  let mut text = "{\"literal\":1}"
  for _i = 0; _i < 512; _i = _i + 1 {
    text = "{\"negate\":" + text + "}"
  }
  let expr = lowered(text)
  assert_true(
    evaluate_expression(expr, {}, [], { remaining: 1026, max_frames: 512, }).unwrap()
    is Number(1.0),
  )
  guard evaluate_expression(expr, {}, [], { remaining: 1026, max_frames: 511, })
    is Err(issue) else {
    fail("expected frame limit")
  }
  assert_eq(issue.kind, ControlLimit)
}

///|
test "binary evaluates left before right; missing value is never a null" {
  guard run_expr("\"id + 1 / 0\"") is Err(issue) else { fail("missing id") }
  assert_eq(issue.kind, MissingValue)
  let expr = lowered("\"id + 2\"")
  assert_true(
    evaluate_expression(expr, { "id": Number(3) }, [], {
      remaining: 100,
      max_frames: 10,
    }).unwrap()
    is Number(5.0),
  )
}
