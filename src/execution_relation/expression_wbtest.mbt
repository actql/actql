///|
fn evaluate_expression(
  root : @lower.Expression,
  input : Map[String, Value],
  slots : Array[Value],
  budget : ControlBudget,
) -> Result[Value, EvalIssue] {
  evaluate_expression_with_workspace(root, input, slots, budget, {
    limit: 100000,
    live: 0,
    peak: 0,
  })
}

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
fn lowered_vector_score(metric : String) -> @lower.Expression {
  let vectors = @carrier.relation(
    @carrier.rows(
      [
        (
          @schema.Unqualified("left"),
          Some(@contract.vector_contract(4.0, nullable=false).unwrap()),
        ),
        (
          @schema.Unqualified("right"),
          Some(@contract.vector_contract(4.0, nullable=false).unwrap()),
        ),
      ],
      field_set=@carrier.Closed,
      max_fields=2,
      max_name_bytes=9,
    ).unwrap(),
  )
  let checked = @pipeline.check_carriers(
    input_cursor(
      "[{\"from\":\"rows\",\"derive\":{\"score\":{\"vector_score\":{\"left\":{\"field\":\"left\"},\"right\":{\"field\":\"right\"},\"metric\":\"" +
      metric +
      "\"}}}}]",
    ),
    [("rows", vectors)],
    None,
    None,
    {
      max_steps: 10,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let owner = @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 10,
      max_references: 10,
      max_work: 1000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
    expression_profiles={ text_time: false, veca: true, },
  ).unwrap()
  @lower.lower_expression(owner, 0, 0, {
    max_nodes: 100,
    max_work: 1000,
    max_depth: 100,
    max_literal_nodes: 100,
    max_literal_text_bytes: 1000,
  }).unwrap()
}

///|
fn runtime_vector(values : Array[Double]) -> Value {
  let builder = @admitted.prepare_vector_value(values.length()).unwrap()
  for value in values {
    if !@admitted.append_vector_component(builder, value) {
      abort("invalid test vector")
    }
  }
  let contract = @contract.vector_contract(
    values.length().to_double(),
    nullable=false,
  ).unwrap()
  let checked = @admitted.finish_checked_vector_value(builder, contract).unwrap()
  capture(checked.value)
}

///|
test "nested expression views share row workspace and release on success" {
  // Outer coalesce retains two child references and one frame while the
  // inner coalesce retains its own two references and frame: six entries.
  let expr = lowered("\"coalesce(coalesce(NULL, 7), 1 / 0)\"")
  let workspace = { limit: 11, live: 5, peak: 5, }
  let value = evaluate_expression_with_workspace(
    expr,
    Map([]),
    [],
    { remaining: 1000, max_frames: 10, },
    workspace,
  ).unwrap()
  assert_true(value is Number(7.0))
  assert_eq(workspace.peak, 11)
  assert_eq(workspace.live, 5)
  assert_true(
    evaluate_expression_with_workspace(
      expr,
      Map([]),
      [],
      { remaining: 1000, max_frames: 10, },
      { limit: 10, live: 5, peak: 5, },
    )
    is Err({ kind: WorkspaceLimit, .. }),
  )
  // Sequential expressions reuse released space, without resetting work.
  let control = { remaining: 1000, max_frames: 10, }
  let before = control.remaining
  assert_true(
    evaluate_expression_with_workspace(expr, Map([]), [], control, workspace).unwrap()
    is Number(7.0),
  )
  assert_eq(workspace.live, 5)
  assert_true(control.remaining < before)
}

///|
test "vector score is exact, eager, and resumable by component" {
  let values : Map[String, Value] = {
    "left": runtime_vector([1.0, 2.0, 3.0, 4.0]),
    "right": runtime_vector([4.0, 3.0, 2.0, 1.0]),
  }
  let dot = lowered_vector_score("dot")
  assert_true(
    evaluate_expression(dot, values, [], { remaining: 1000, max_frames: 10, }).unwrap()
    is Number(20.0),
  )
  let workspace = { limit: 100, live: 3, peak: 3, }
  let frame = expression_frame(
    dot,
    values,
    [],
    { remaining: 1000, max_frames: 10, },
    workspace,
    None,
  ).unwrap()
  let mut yielded = 0
  let mut result : EvaluatedValue? = None
  while result is None {
    match advance_expression_frame(frame) {
      Ok(None) => yielded += 1
      Ok(Some(value)) => result = Some(value)
      Err(_) => fail("vector score frame failed")
    }
  }
  assert_true(yielded >= 4)
  assert_true(result.unwrap().value is Number(20.0))
  assert_eq(workspace.live, 3)

  let missing : Map[String, Value] = { "left": Null }
  assert_true(
    evaluate_expression(dot, missing, [], { remaining: 1000, max_frames: 10, })
    is Err({ kind: MissingValue, .. }),
  )
  let nulls : Map[String, Value] = { "left": Null, "right": values["right"] }
  assert_true(
    evaluate_expression(dot, nulls, [], { remaining: 1000, max_frames: 10, }).unwrap()
    is Null,
  )

  let unit : Map[String, Value] = {
    "left": runtime_vector([1.0, 0.0, 0.0, 0.0]),
    "right": runtime_vector([1.0, 0.0, 0.0, 0.0]),
  }
  assert_true(
    evaluate_expression(lowered_vector_score("cosine"), unit, [], {
      remaining: 1000,
      max_frames: 10,
    }).unwrap()
    is Number(1.0),
  )
  assert_true(
    evaluate_expression(lowered_vector_score("l2"), unit, [], {
      remaining: 1000,
      max_frames: 10,
    }).unwrap()
    is Number(0.0),
  )
}

///|
test "vector score failure releases its continuation workspace" {
  let values : Map[String, Value] = {
    "left": runtime_vector([1.0, 2.0, 3.0, 4.0]),
    "right": runtime_vector([1.0, 2.0, 3.0]),
  }
  let workspace = { limit: 100, live: 5, peak: 5, }
  let frame = expression_frame(
    lowered_vector_score("dot"),
    values,
    [],
    { remaining: 1000, max_frames: 10, },
    workspace,
    None,
  ).unwrap()
  let mut failed = false
  while !failed {
    match advance_expression_frame(frame) {
      Ok(None) => ()
      Ok(Some(_)) => fail("dimension mismatch was accepted")
      Err(issue) => {
        assert_true(issue.kind is Scalar(InvalidOperand))
        failed = true
      }
    }
  }
  assert_eq(workspace.live, 5)
}

///|
test "expression workspace releases branch frames and case views" {
  for
    source in [
      "\"if(true, -(1 + 2), 1 / 0)\"", "{\"case\":{\"when\":[{\"when\":{\"literal\":false},\"then\":{\"literal\":9}}]}}",
      "{\"case\":{\"when\":[{\"when\":{\"literal\":true},\"then\":{\"literal\":9}}]}}",
      "\"true AND false AND true\"",
    ] {
    let workspace = { limit: 100, live: 5, peak: 5, }
    let result = evaluate_expression_with_workspace(
      lowered(source),
      Map([]),
      [],
      { remaining: 1000, max_frames: 10, },
      workspace,
    )
    assert_true(result is Ok(_))
    assert_eq(workspace.live, 5)
    assert_true(workspace.peak > 5)
  }
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
