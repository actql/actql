///|
test "lag calculation order is separate from output sequence and shares pipeline budgets" {
  let relation = @carrier.relation(@carrier.typed_rows(schema()))
  let declaration = @evidence.declare_primary_key(
    cursor("[\"id\"]"),
    relation,
    { max_fields: 1, max_name_bytes: 2, },
  ).unwrap()
  let inputs = [("rows", @pipeline_typing.KeyedInput(declaration))]
  let source = cursor(
    "[{\"lag\":{\"partition_by\":[],\"order_by\":[{\"amount\":\"desc\"}],\"field\":\"amount\",\"output\":\"previous\"}}]",
  )
  let p = @pipeline_typing.check_with_evidence(
    source,
    inputs,
    None,
    None,
    limits(),
  ).unwrap()
  assert_true(@pipeline_typing.logical_order(p, Step(0)) is None)
  let c = @pipeline_typing.lag_order_completion(p, 0).unwrap()
  assert_eq(@pipeline_typing.sort_completion_count(c), 1)
  assert_eq(
    @pipeline_typing.sort_completion_field(c, 0),
    Some(Unqualified("id")),
  )
  assert_true(@pipeline_typing.lag_order_completion(p, -1) is None)
  assert_true(@pipeline_typing.lag_order_completion(p, 1) is None)
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
  assert_true(@pipeline_typing.lag_order_completion(raw, 0) is None)
}

///|
test "lag preserves generator sequence but does not replace its candidate-key requirement" {
  let p = @pipeline_typing.check_carriers(
    cursor(
      "[{\"values\":{\"schema\":{\"x\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"x\":1},{\"x\":1}]},\"as\":\"seed\"},{\"lag\":{\"partition_by\":[],\"order_by\":[{\"x\":\"asc\"}],\"field\":\"x\",\"output\":\"previous\"}}]",
    ),
    [],
    None,
    None,
    limits(),
  ).unwrap()
  assert_eq(
    @pipeline_typing.order_origin(
      @pipeline_typing.logical_order(p, Step(1)).unwrap(),
    ),
    Step(0),
  )
  assert_true(@pipeline_typing.lag_order_completion(p, 1) is None)
  for term in ["a", "b", "x"] {
    let p = @pipeline_typing.check_carriers(
      cursor(
        "[{\"time_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-01T00:00:00.010Z\",\"step\":1},\"as\":\"seed\"},{\"derive\":{\"x\":{\"literal\":1}}},{\"select\":[{\"a\":\"time\"},{\"b\":\"time\"},\"x\"]},{\"lag\":{\"partition_by\":[\"x\",\"x\"],\"order_by\":[{\"" +
        term +
        "\":\"desc\"}],\"field\":\"x\",\"output\":\"previous\"}}]",
      ),
      [],
      None,
      None,
      limits(),
    ).unwrap()
    let c = @pipeline_typing.lag_order_completion(p, 3).unwrap()
    assert_eq(
      @pipeline_typing.sort_completion_count(c),
      if term == "x" {
        1
      } else {
        0
      },
    )
    assert_eq(
      @pipeline_typing.order_origin(
        @pipeline_typing.logical_order(p, Step(3)).unwrap(),
      ),
      Step(0),
    )
  }
}
