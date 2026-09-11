///|
test "analytic position key completion preserves authored peers and shared budgets" {
  let relation = @carrier.relation(@carrier.typed_rows(schema()))
  let declaration = @evidence.declare_primary_key(
    cursor("[\"id\"]"),
    relation,
    { max_fields: 1, max_name_bytes: 2, },
  ).unwrap()
  let inputs = [("rows", @pipeline_typing.KeyedInput(declaration))]
  let source = cursor(
    "[{\"analytic\":{\"partition_by\":[],\"order_by\":[{\"amount\":\"desc\"}],\"functions\":{\"position\":{\"fn\":\"row_number\"},\"peer\":{\"fn\":\"rank\"}}}}]",
  )
  let p = @pipeline_typing.check_with_evidence(
    source,
    inputs,
    None,
    None,
    limits(),
  ).unwrap()
  let order = @pipeline_typing.analytic_position_order(p, 0).unwrap()
  assert_eq(@pipeline_typing.analytic_order_input(order), Input(0))
  assert_true(@pipeline_typing.analytic_order_retained(order) is None)
  let c = @pipeline_typing.analytic_order_completion(order).unwrap()
  assert_eq(@pipeline_typing.sort_completion_count(c), 1)
  assert_eq(
    @pipeline_typing.sort_completion_field(c, 0),
    Some(Unqualified("id")),
  )
  let step = @pipeline_typing.analytic_order_consumer(order)
  guard step.operation is @pipeline_typing.Unary(op) else {
    abort("expected analytic")
  }
  assert_eq(@relation.analytic_term_count(op), 1)
  assert_eq(
    @relation.analytic_term_at(op, 0).unwrap().field,
    Unqualified("amount"),
  )
  assert_true(@relation.analytic_term_at(op, -1) is None)
  assert_true(@relation.analytic_term_at(op, 1) is None)
  assert_true(@pipeline_typing.logical_order(p, Step(0)) is None)
  assert_true(@pipeline_typing.analytic_position_order(p, -1) is None)
  assert_true(@pipeline_typing.analytic_position_order(p, 1) is None)
  let u = @pipeline_typing.usage(p)
  let exact = {
    ..limits(),
    max_work: u.work,
    max_text_bytes: u.text_bytes,
    max_nodes: u.nodes,
  }
  assert_true(
    @pipeline_typing.check_with_evidence(source, inputs, None, None, exact)
    is Ok(_),
  )
  assert_true(
    @pipeline_typing.check_with_evidence(source, inputs, None, None, {
      ..exact,
      max_work: u.work - 1,
    })
    is Err(_),
  )
  assert_true(
    @pipeline_typing.check_with_evidence(source, inputs, None, None, {
      ..exact,
      max_text_bytes: u.text_bytes - 1,
    })
    is Err(_),
  )
  let raw = @pipeline_typing.check_carriers(
    source,
    [("rows", relation)],
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(@pipeline_typing.analytic_position_order(raw, 0) is None)
}

///|
test "analytic reuses existing positions without manufacturing keys or publication order" {
  let p = @pipeline_typing.check_carriers(
    cursor(
      "[{\"values\":{\"schema\":{\"x\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"x\":1},{\"x\":1}]},\"as\":\"seed\"},{\"analytic\":{\"partition_by\":[\"x\",\"x\"],\"order_by\":[{\"x\":\"desc\"}],\"functions\":{\"position\":{\"fn\":\"row_number\"},\"peer\":{\"fn\":\"dense_rank\"}}}}]",
    ),
    [],
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(@pipeline_typing.analytic_position_order(p, 0) is None)
  let order = @pipeline_typing.analytic_position_order(p, 1).unwrap()
  assert_eq(@pipeline_typing.analytic_order_input(order), Step(0))
  assert_true(@pipeline_typing.analytic_order_completion(order) is None)
  assert_eq(
    @pipeline_typing.order_origin(
      @pipeline_typing.analytic_order_retained(order).unwrap(),
    ),
    Step(0),
  )
  assert_eq(
    @pipeline_typing.order_origin(
      @pipeline_typing.logical_order(p, Step(1)).unwrap(),
    ),
    Step(0),
  )
}

///|
test "analytic key completion recognizes aliases and does not rewrite peer terms" {
  for term in ["a", "b", "x"] {
    let p = @pipeline_typing.check_carriers(
      cursor(
        "[{\"time_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-01T00:00:00.010Z\",\"step\":1},\"as\":\"seed\"},{\"derive\":{\"x\":{\"literal\":1}}},{\"select\":[{\"a\":\"time\"},{\"b\":\"time\"},\"x\"]},{\"analytic\":{\"partition_by\":[\"x\",\"x\"],\"order_by\":[{\"" +
        term +
        "\":\"desc\"}],\"functions\":{\"position\":{\"fn\":\"row_number\"}}}}]",
      ),
      [],
      None,
      None,
      limits(),
    ).unwrap()
    let order = @pipeline_typing.analytic_position_order(p, 3).unwrap()
    let c = @pipeline_typing.analytic_order_completion(order).unwrap()
    assert_eq(
      @pipeline_typing.sort_completion_count(c),
      if term == "x" {
        1
      } else {
        0
      },
    )
    assert_true(@pipeline_typing.analytic_order_retained(order) is None)
    assert_eq(
      @pipeline_typing.order_origin(
        @pipeline_typing.logical_order(p, Step(3)).unwrap(),
      ),
      Step(0),
    )
  }
}

///|
test "analytic follows resolved branch and rank alone needs no position witness" {
  for function in ["rank", "dense_rank", "row_number"] {
    let p = @pipeline_typing.check_carriers(
      cursor(
        "[{\"values\":{\"schema\":{\"x\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[]},\"as\":\"unrelated\"},{\"from\":\"rows\",\"analytic\":{\"partition_by\":[],\"order_by\":[{\"amount\":\"desc\"}],\"functions\":{\"r\":{\"fn\":\"" +
        function +
        "\"}}}}]",
      ),
      [("rows", @carrier.relation(@carrier.typed_rows(schema())))],
      None,
      None,
      limits(),
    ).unwrap()
    assert_true(@pipeline_typing.logical_order(p, Step(0)) is Some(_))
    assert_true(@pipeline_typing.logical_order(p, Step(1)) is None)
    assert_true(@pipeline_typing.analytic_position_order(p, 1) is None)
    let step = @pipeline_typing.step_at(p, 1).unwrap()
    guard step.operation is @pipeline_typing.Unary(op) else {
      abort("expected analytic")
    }
    assert_eq(
      @relation.pending_validations(op).any(v => {
        v.kind == @relation.AnalyticPositionOrder
      }),
      function == "row_number",
    )
    assert_true(
      @relation.pending_validations(op).any(v => {
        v.kind == @relation.AnalyticPeerOrder
      }),
    )
  }
}
