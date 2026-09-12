///|
test "analytic obligation reads preserve source positions and inclusive scan budgets" {
  let p = @pipeline_typing.check(
    cursor(
      "[{\"analytic\":{\"partition_by\":[],\"order_by\":[{\"amount\":\"asc\"}],\"functions\":{\"rank\":{\"fn\":\"rank\"}}}}]",
    ),
    [("rows", schema())],
    None,
    None,
    limits(),
  ).unwrap()
  guard @pipeline_typing.step_at(p, 0).unwrap().operation
    is @pipeline_typing.Unary(op) else {
    abort("analytic expected")
  }
  let pending = @relation.pending_validations(op)
  let count = @relation.pending_validation_count(op)
  assert_eq(count, pending.length())
  assert_true(count > 0)
  for i in 0..<count {
    let item = @relation.pending_validation_at(op, i).unwrap()
    assert_eq(item.kind, pending[i].kind)
    assert_true(physical_equal(item.source, pending[i].source))
  }
  pending.clear()
  assert_eq(@relation.pending_validation_count(op), count)
  assert_true(@relation.pending_validation_at(op, -1) is None)
  assert_true(@relation.pending_validation_at(op, count) is None)
  let checked = @pipeline_typing.resolve_contextual_orders(
    p,
    max_steps=1,
    max_work=count + 1,
    max_text_bytes=0,
  ).unwrap()
  assert_eq(@pipeline_typing.contextual_orders_usage(checked), (count + 1, 0))
  for budget in 1..<(count + 1) {
    let issue = @pipeline_typing.resolve_contextual_orders(
      p,
      max_steps=1,
      max_work=budget,
      max_text_bytes=0,
    ).unwrap_err()
    assert_eq(issue.kind, BudgetExceeded)
    assert_eq(
      issue.path,
      @decode.cursor_path(
        @relation.pending_validation_at(op, budget - 1).unwrap().source,
      ),
    )
  }
}

///|
test "contextual orders inspect unused branches and reject unresolved consumers" {
  for
    body in [
      "\"lag\":{\"partition_by\":[],\"order_by\":[{\"amount\":\"asc\"}],\"field\":\"amount\",\"output\":\"previous\"}",
      "\"analytic\":{\"partition_by\":[],\"order_by\":[{\"amount\":\"asc\"}],\"functions\":{\"position\":{\"fn\":\"row_number\"}}}",
      "\"take\":1", "\"sort\":[{\"amount\":\"asc\"}]", "\"watermark_rows\":{\"time\":\"amount\",\"max_skew\":1,\"late_policy\":\"mark\"}",
    ] {
    let p = @pipeline_typing.check(
      cursor(
        "[{" + body + ",\"as\":\"unused\"},{\"from\":\"rows\",\"derive\":{}}]",
      ),
      [("rows", schema())],
      None,
      None,
      limits(),
    ).unwrap()
    assert_eq(
      @pipeline_typing.resolve_contextual_orders(
        p,
        max_steps=2,
        max_work=1000,
        max_text_bytes=1000,
      ).unwrap_err().kind,
      UnresolvedOrder,
    )
  }
}

///|
test "rank-only analytic and empty sort do not invent position requirements" {
  let p = @pipeline_typing.check(
    cursor(
      "[{\"sort\":[]},{\"analytic\":{\"partition_by\":[],\"order_by\":[{\"amount\":\"asc\"}],\"functions\":{\"rank\":{\"fn\":\"rank\"}}}}]",
    ),
    [("rows", schema())],
    None,
    None,
    limits(),
  ).unwrap()
  let r = @pipeline_typing.resolve_contextual_orders(
    p,
    max_steps=2,
    max_work=1000,
    max_text_bytes=0,
  ).unwrap()
  for i in 0..<2 {
    assert_eq(@pipeline_typing.contextual_orders_at(r, i).unwrap().length(), 0)
  }
  let empty = @pipeline_typing.check(
    cursor("[]"),
    [("rows", schema())],
    None,
    None,
    limits(),
  ).unwrap()
  let empty_orders = @pipeline_typing.resolve_contextual_orders(
    empty,
    max_steps=0,
    max_work=0,
    max_text_bytes=0,
  ).unwrap()
  assert_eq(@pipeline_typing.contextual_orders_count(empty_orders), 0)
  assert_eq(@pipeline_typing.contextual_orders_usage(empty_orders), (0, 0))
}

///|
test "contextual orders retain every step and enforce inclusive collection budgets" {
  let rows = @carrier.relation(@carrier.typed_rows(schema()))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), rows, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  let p = @pipeline_typing.check_with_evidence(
    cursor("[{\"sort\":[{\"amount\":\"asc\"}]},{\"take\":1},{\"sort\":[]}]"),
    [("rows", @pipeline_typing.KeyedInput(key))],
    None,
    None,
    limits(),
  ).unwrap()
  let r = @pipeline_typing.resolve_contextual_orders(
    p,
    max_steps=3,
    max_work=1000,
    max_text_bytes=1000,
  ).unwrap()
  assert_eq(@pipeline_typing.contextual_orders_count(r), 3)
  assert_eq(
    @pipeline_typing.step_count(@pipeline_typing.contextual_orders_pipeline(r)),
    3,
  )
  let first = @pipeline_typing.contextual_orders_at(r, 0).unwrap()
  assert_true(first[0] is SortSequence(_))
  first.clear()
  assert_eq(@pipeline_typing.contextual_orders_at(r, 0).unwrap().length(), 1)
  assert_true(
    @pipeline_typing.contextual_orders_at(r, 1).unwrap()[0] is TakeSequence(_),
  )
  assert_eq(@pipeline_typing.contextual_orders_at(r, 2).unwrap().length(), 0)
  assert_true(@pipeline_typing.contextual_orders_at(r, -1) is None)
  assert_true(@pipeline_typing.contextual_orders_at(r, 3) is None)
  let (work, text) = @pipeline_typing.contextual_orders_usage(r)
  assert_true(
    @pipeline_typing.resolve_contextual_orders(
      p,
      max_steps=3,
      max_work=work,
      max_text_bytes=text,
    )
    is Ok(_),
  )
  assert_eq(
    @pipeline_typing.resolve_contextual_orders(
      p,
      max_steps=3,
      max_work=work - 1,
      max_text_bytes=text,
    ).unwrap_err().kind,
    BudgetExceeded,
  )
  assert_eq(
    @pipeline_typing.resolve_contextual_orders(
      p,
      max_steps=2,
      max_work=work,
      max_text_bytes=text,
    ).unwrap_err().kind,
    BudgetExceeded,
  )
  assert_eq(
    @pipeline_typing.resolve_contextual_orders(
      p,
      max_steps=3,
      max_work=work,
      max_text_bytes=-1,
    ).unwrap_err().kind,
    InvalidLimits,
  )
}

///|
test "aggregate resolution budgets are shared across separately named branches" {
  let rows = @carrier.relation(@carrier.typed_rows(schema()))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), rows, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  let body = "\"from\":\"rows\",\"group\":{\"by\":[],\"aggregates\":{\"v\":{\"fn\":\"array_agg\",\"field\":\"amount\",\"order_by\":[{\"amount\":\"asc\"}]}}}"
  let p = @pipeline_typing.check_with_evidence(
    cursor("[{" + body + "},{" + body + "}]"),
    [("rows", @pipeline_typing.KeyedInput(key))],
    None,
    None,
    limits(),
  ).unwrap()
  let single = @pipeline_typing.resolve_group_orders(
    p,
    0,
    max_work=10000,
    max_text_bytes=10000,
  ).unwrap()
  let (w, t) = @pipeline_typing.group_orders_usage(single)
  let r = @pipeline_typing.resolve_contextual_orders(
    p,
    max_steps=2,
    max_work=2 * w + 2,
    max_text_bytes=2 * t,
  ).unwrap()
  assert_eq(@pipeline_typing.contextual_orders_usage(r), (2 * w + 2, 2 * t))
  for i in 0..<2 {
    assert_true(
      @pipeline_typing.contextual_orders_at(r, i).unwrap()[0] is Aggregates(_),
    )
  }
  assert_eq(
    @pipeline_typing.resolve_contextual_orders(
      p,
      max_steps=2,
      max_work=2 * w + 1,
      max_text_bytes=2 * t,
    ).unwrap_err().kind,
    BudgetExceeded,
  )
  assert_eq(
    @pipeline_typing.resolve_contextual_orders(
      p,
      max_steps=2,
      max_work=2 * w + 2,
      max_text_bytes=2 * t - 1,
    ).unwrap_err().kind,
    BudgetExceeded,
  )
}
