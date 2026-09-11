///|
test "producer closure rejects an upstream unused order consumer with its original owner" {
  let bad = @pipeline_typing.check(
    cursor("[{\"take\":1,\"as\":\"unused\"}," + count_values(1, "good") + "]"),
    [("raw", schema())],
    None,
    None,
    limits(),
  ).unwrap()
  let good = @pipeline_typing.check_carriers(
    cursor("[" + count_values(1, "good") + "]"),
    [],
    None,
    None,
    limits(),
  ).unwrap()
  let p = @pipeline_typing.check_with_evidence(
    cursor("[]"),
    [
      (
        "selected",
        @pipeline_typing.ProducedInput(
          @pipeline_typing.produced_input(good, Step(0)).unwrap(),
        ),
      ),
      (
        "unused",
        @pipeline_typing.ProducedInput(
          @pipeline_typing.produced_input(bad, Step(1)).unwrap(),
        ),
      ),
    ],
    None,
    Some(cursor("\"selected\"")),
    limits(),
  ).unwrap()
  assert_true(
    @pipeline_typing.resolve_contextual_orders(
      p,
      max_steps=0,
      max_work=0,
      max_text_bytes=0,
    )
    is Ok(_),
  )
  let error = @pipeline_typing.resolve_contextual_closure(
    p,
    max_steps=3,
    max_work=1000,
    max_text_bytes=1000,
  ).unwrap_err()
  assert_true(physical_equal(error.pipeline, bad))
  assert_eq(error.issue.kind, UnresolvedOrder)
  assert_eq(error.issue.path, [@source.Index(0)])
}

///|
test "producer closure shares budgets across repeated owners" {
  let base = @pipeline_typing.check_carriers(
    cursor("[" + count_values(1, "rows") + "]"),
    [],
    None,
    None,
    limits(),
  ).unwrap()
  let input = @pipeline_typing.produced_input(base, Step(0)).unwrap()
  let p = @pipeline_typing.check_with_evidence(
    cursor("[]"),
    [
      ("a", @pipeline_typing.ProducedInput(input)),
      ("b", @pipeline_typing.ProducedInput(input)),
    ],
    None,
    Some(cursor("\"a\"")),
    limits(),
  ).unwrap()
  let closure = @pipeline_typing.resolve_contextual_closure(
    p,
    max_steps=2,
    max_work=9,
    max_text_bytes=0,
  ).unwrap()
  assert_eq(@pipeline_typing.contextual_closure_count(closure), 3)
  assert_eq(@pipeline_typing.contextual_closure_steps(closure), 2)
  assert_eq(@pipeline_typing.contextual_closure_usage(closure), (9, 0))
  assert_true(
    physical_equal(
      @pipeline_typing.contextual_orders_pipeline(
        @pipeline_typing.contextual_closure_root(closure),
      ),
      p,
    ),
  )
  for i in [1, 2] {
    assert_true(
      physical_equal(
        @pipeline_typing.contextual_orders_pipeline(
          @pipeline_typing.contextual_closure_at(closure, i).unwrap(),
        ),
        base,
      ),
    )
  }
  assert_true(@pipeline_typing.contextual_closure_at(closure, -1) is None)
  assert_true(@pipeline_typing.contextual_closure_at(closure, 3) is None)
  assert_true(
    @pipeline_typing.resolve_contextual_closure(
      p,
      max_steps=1,
      max_work=7,
      max_text_bytes=0,
    )
    is Err(_),
  )
  assert_true(
    @pipeline_typing.resolve_contextual_closure(
      p,
      max_steps=2,
      max_work=8,
      max_text_bytes=0,
    )
    is Err(_),
  )
  assert_eq(
    @pipeline_typing.resolve_contextual_closure(
      p,
      max_steps=-1,
      max_work=7,
      max_text_bytes=0,
    ).unwrap_err().issue.kind,
    InvalidLimits,
  )
}

///|
test "producer closure bounds empty forwarding chains without recursion" {
  let mut p = @pipeline_typing.check_carriers(
    cursor("[" + count_values(1, "rows") + "]"),
    [],
    None,
    None,
    limits(),
  ).unwrap()
  let mut target = @pipeline_typing.Step(0)
  let source = cursor("[]")
  for _ in 0..<2000 {
    let input = @pipeline_typing.produced_input(p, target).unwrap()
    p = @pipeline_typing.check_with_evidence(
      source,
      [("rows", @pipeline_typing.ProducedInput(input))],
      None,
      None,
      limits(),
    ).unwrap()
    target = Input(0)
  }
  let closure = @pipeline_typing.resolve_contextual_closure(
    p,
    max_steps=1,
    max_work=4003,
    max_text_bytes=0,
  ).unwrap()
  assert_eq(@pipeline_typing.contextual_closure_count(closure), 2001)
  assert_eq(@pipeline_typing.contextual_closure_usage(closure), (4003, 0))
  let bindings = Array::make(2001, None)
  let bound = @pipeline_typing.bind_contextual_guards(
    closure,
    bindings,
    max_work=2001,
    max_text_bytes=0,
  ).unwrap()
  assert_eq(@pipeline_typing.bound_guard_closure_usage(bound), (2001, 0))
  assert_true(
    @pipeline_typing.bind_contextual_guards(
      closure,
      bindings,
      max_work=2000,
      max_text_bytes=0,
    )
    is Err(_),
  )
  assert_true(
    @pipeline_typing.resolve_contextual_closure(
      p,
      max_steps=1,
      max_work=4002,
      max_text_bytes=0,
    )
    is Err(_),
  )
}

///|
test "producer aggregate resolutions share the text budget" {
  let rows = @carrier.relation(@carrier.typed_rows(schema()))
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), rows, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  let base = @pipeline_typing.check_with_evidence(
    cursor(
      "[{\"group\":{\"by\":[],\"aggregates\":{\"values\":{\"fn\":\"array_agg\",\"field\":\"amount\",\"order_by\":[{\"amount\":\"asc\"}]}}}}]",
    ),
    [("rows", @pipeline_typing.KeyedInput(key))],
    None,
    None,
    limits(),
  ).unwrap()
  let one = @pipeline_typing.resolve_contextual_orders(
    base,
    max_steps=1,
    max_work=10000,
    max_text_bytes=10000,
  ).unwrap()
  let (_, bytes) = @pipeline_typing.contextual_orders_usage(one)
  assert_true(bytes > 0)
  let input = @pipeline_typing.produced_input(base, Step(0)).unwrap()
  let p = @pipeline_typing.check_with_evidence(
    cursor("[]"),
    [
      ("a", @pipeline_typing.ProducedInput(input)),
      ("b", @pipeline_typing.ProducedInput(input)),
    ],
    None,
    Some(cursor("\"a\"")),
    limits(),
  ).unwrap()
  let closure = @pipeline_typing.resolve_contextual_closure(
    p,
    max_steps=2,
    max_work=10000,
    max_text_bytes=bytes * 2,
  ).unwrap()
  assert_eq(@pipeline_typing.contextual_closure_usage(closure).1, bytes * 2)
  assert_true(
    @pipeline_typing.resolve_contextual_closure(
      p,
      max_steps=2,
      max_work=10000,
      max_text_bytes=bytes * 2 - 1,
    )
    is Err(_),
  )
}
