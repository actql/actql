///|
test "group orders resolve every entry sequence under one inclusive budget" {
  let rows = @carrier.relation(@carrier.typed_rows(schema()))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), rows, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  let p = @pipeline_typing.check_with_evidence(
    cursor(
      "[{\"group\":{\"by\":[],\"aggregates\":{\"a_first\":{\"fn\":\"first\",\"field\":\"amount\",\"order_by\":[{\"amount\":\"desc\"}]},\"m_count\":{\"fn\":\"count\"},\"z_array\":{\"fn\":\"array_agg\",\"field\":\"amount\",\"order_by\":[{\"id\":\"asc\"}]}}}}]",
    ),
    [("rows", @pipeline_typing.KeyedInput(key))],
    None,
    None,
    limits(),
  ).unwrap()
  let r = @pipeline_typing.resolve_group_orders(
    p,
    0,
    max_work=10000,
    max_text_bytes=10000,
  ).unwrap()
  assert_eq(@pipeline_typing.group_orders_input(r), Input(0))
  assert_eq(@pipeline_typing.group_orders_count(r), 3)
  assert_true(@pipeline_typing.group_order_at(r, 1) is None)
  assert_true(@pipeline_typing.group_order_at(r, -1) is None)
  assert_true(@pipeline_typing.group_order_at(r, 3) is None)
  for (i, count) in [(0, 1), (2, 0)] {
    let entry = @pipeline_typing.group_order_at(r, i).unwrap()
    assert_true(@pipeline_typing.aggregate_order_inherited(entry) is None)
    let c = @pipeline_typing.aggregate_order_completion(entry).unwrap()
    assert_eq(@pipeline_typing.sort_completion_count(c), count)
    let aggregate = @pipeline_typing.aggregate_order_source(entry)
    assert_eq(@relation.aggregate_order_count(aggregate), 1)
    assert_true(@relation.aggregate_order_at(aggregate, 1) is None)
  }
  let (work, text) = @pipeline_typing.group_orders_usage(r)
  assert_true(
    @pipeline_typing.resolve_group_orders(
      p,
      0,
      max_work=work,
      max_text_bytes=text,
    )
    is Ok(_),
  )
  assert_true(
    @pipeline_typing.resolve_group_orders(
      p,
      0,
      max_work=work - 1,
      max_text_bytes=text,
    )
    is Err(_),
  )
  assert_true(
    @pipeline_typing.resolve_group_orders(
      p,
      0,
      max_work=work,
      max_text_bytes=text - 1,
    )
    is Err(_),
  )
  assert_eq(
    @pipeline_typing.resolve_group_orders(
      p,
      -1,
      max_work=work,
      max_text_bytes=text,
    ).unwrap_err().kind,
    InvalidBody,
  )
  assert_eq(
    @pipeline_typing.resolve_group_orders(
      p,
      0,
      max_work=-1,
      max_text_bytes=text,
    ).unwrap_err().kind,
    InvalidLimits,
  )
}

///|
test "array aggregate cannot replace its required candidate key with input occurrence order" {
  for function in ["first", "last", "array_agg"] {
    let p = @pipeline_typing.check_carriers(
      cursor(
        "[{\"values\":{\"schema\":{\"x\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"x\":2},{\"x\":1},{\"x\":1}]},\"as\":\"seed\"},{\"group\":{\"by\":[],\"aggregates\":{\"v\":{\"fn\":\"" +
        function +
        "\",\"field\":\"x\",\"order_by\":[{\"x\":\"desc\"}]}}}}]",
      ),
      [],
      None,
      None,
      limits(),
    ).unwrap()
    let result = @pipeline_typing.resolve_group_orders(
      p,
      1,
      max_work=10000,
      max_text_bytes=10000,
    )
    if function == "array_agg" {
      let issue = result.unwrap_err()
      assert_eq(issue.kind, UnresolvedOrder)
      assert_eq(issue.path, [
        @source.Index(1),
        Key("group"),
        Key("aggregates"),
        Key("v"),
      ])
    } else {
      let r = result.unwrap()
      let entry = @pipeline_typing.group_order_at(r, 0).unwrap()
      assert_true(@pipeline_typing.aggregate_order_completion(entry) is None)
      assert_eq(
        @pipeline_typing.order_origin(
          @pipeline_typing.aggregate_order_inherited(entry).unwrap(),
        ),
        Step(0),
      )
    }
    assert_eq(
      @pipeline_typing.order_origin(
        @pipeline_typing.logical_order(p, Step(1)).unwrap(),
      ),
      Step(1),
    )
  }
}

///|
test "window group entry order uses its input witness rather than canonical group output" {
  let p = @pipeline_typing.check_carriers(
    cursor(
      "[{\"values\":{\"schema\":{\"at\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"at\":1}]},\"as\":\"seed\"},{\"row_window\":{\"kind\":\"fixed\",\"time\":\"at\",\"size\":10}},{\"window_group\":{\"by\":[],\"aggregates\":{\"first\":{\"fn\":\"first\",\"field\":\"at\",\"order_by\":[{\"at\":\"desc\"}]}}}}]",
    ),
    [],
    None,
    None,
    limits(),
  ).unwrap()
  let r = @pipeline_typing.resolve_group_orders(
    p,
    2,
    max_work=10000,
    max_text_bytes=10000,
  ).unwrap()
  assert_eq(@pipeline_typing.group_orders_input(r), Step(1))
  let entry = @pipeline_typing.group_order_at(r, 0).unwrap()
  assert_eq(
    @pipeline_typing.order_origin(
      @pipeline_typing.aggregate_order_inherited(entry).unwrap(),
    ),
    Step(1),
  )
  assert_eq(
    @pipeline_typing.order_origin(
      @pipeline_typing.logical_order(p, Step(2)).unwrap(),
    ),
    Step(2),
  )
}
