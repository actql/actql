///|
test "window aggregate expressions retain source work spans and original owners" {
  let prefix = "window_group(by:[r.cohort],aggregates:{total:{fn:'sum',expr:"
  let source = prefix + "COALESCE(r.amount,0)+@p,filter:r.amount IS NOT NULL}})"
  let call = parse_sga_call(source, query_limits(), source_path="window.aql").unwrap()
  guard call.arguments[1].1 is ObjectValue(aggregates) &&
    aggregates[0].1 is ObjectValue(fields) &&
    fields[1].1 is ExpressionValue(owner) else {
    fail("original aggregate expression")
  }
  let expression = sga_predicate_expression(owner)
  let origin = expression_origin(expression, expression_root(expression)).unwrap()
  assert_eq(@origin.kind(origin), Authored)
  assert_eq(@origin.start(origin).utf16_offset, prefix.length())
  assert_eq(
    @origin.end(origin).utf16_offset,
    prefix.length() + "COALESCE(r.amount,0)+@p".length(),
  )
  assert_true(expression_work(expression) > 0)
  assert_true(
    Array::makei(expression_node_count(expression), i => {
      expression_node(expression, i).unwrap()
    }).any(node => node.kind is ParameterReference(_)),
  )
  let parsed = parse_query_script("FROM records |> " + source, query_limits()).unwrap()
    |> script_query
  guard operation_at(parsed, 0) is Some(GraphCall(before)) &&
    operation_at(parsed, 0) is Some(GraphCall(again)) else {
    fail("original aggregate call")
  }
  assert_eq(before, again)
  guard operation_at(parsed, 0) is Some(GraphCall(copied)) &&
    copied.arguments[0].1 is ListValue(by) &&
    by[0] is FieldReference(path) else {
    fail("copied field reference")
  }
  path.clear()
  guard operation_at(parsed, 0) is Some(GraphCall(retained)) &&
    retained.arguments[0].1 is ListValue(by) &&
    by[0] is FieldReference(path) else {
    fail("retained field reference")
  }
  assert_eq(path.length(), 2)
}

///|
test "window aggregate output names use reserved and quoted output roles" {
  for name in ["SELECT", "NULL"] {
    assert_true(
      parse_sga_call(
        "window_group(by:[],aggregates:{" + name + ":{fn:'count'}})",
        query_limits(),
      )
      is Err({ issue: Syntax(_), .. }),
    )
    let parsed = parse_sga_call(
      "window_group(by:[],aggregates:{`" + name + "`:{fn:'count'}})",
      query_limits(),
    ).unwrap()
    guard parsed.arguments[1].1 is ObjectValue(aggregates) else {
      fail("quoted aggregate output")
    }
    assert_eq(aggregates[0].0, name)
  }
  assert_true(
    parse_sga_call(
      "window_group(by:[],aggregates:{n:{fn:'count'},n:{fn:'count'}})",
      query_limits(),
    )
    is Err({ issue: Syntax(_), .. }),
  )
  assert_true(
    parse_sga_call(
      "window_group(by:[],aggregates:{n:{fn:'sum',field:'amount'}})",
      query_limits(),
    )
    is Err({ issue: Syntax(_), .. }),
  )
}

///|
test "window expressions consume the containing expression budgets" {
  let source = "window_group(by:[],aggregates:{total:{fn:'sum',expr:((amount+1))}})"
  for
    limits in [
      {
        ..query_limits(),
        expression: { ..query_limits().expression, max_nodes: 2, },
      },
      {
        ..query_limits(),
        expression: { ..query_limits().expression, max_depth: 1, },
      },
    ] {
    assert_true(
      parse_sga_call(source, limits)
      is Err({ issue: Syntax(_), span: Some(_), }),
    )
  }
}
