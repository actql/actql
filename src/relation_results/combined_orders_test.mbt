///|
test "aggregate and publication order checks share their text budget" {
  let rows = @carrier.relation(
    @carrier.typed_rows(@schema.from_object(input()).unwrap()),
  )
  let key = @evidence.declare_primary_key(cursor("[\"id\"]"), rows, {
    max_fields: 1,
    max_name_bytes: 2,
  }).unwrap()
  let p = @pipeline.check_with_evidence(
    cursor(
      "[{\"group\":{\"by\":[],\"aggregates\":{\"v\":{\"fn\":\"array_agg\",\"field\":\"score\",\"order_by\":[{\"score\":\"asc\"}]}}},\"as\":\"unused\"}]",
    ),
    [("rows", @pipeline.KeyedInput(key))],
    None,
    None,
    ranking_limits(),
  ).unwrap()
  let results = @relation_results.check(
    p,
    cursor("{\"out\":{\"from\":\"rows\",\"fields\":[\"id\"]}}"),
    limits(),
  ).unwrap()
  let caps : @relation_results.OrderCheckLimits = {
    max_steps: 1,
    max_results: 1,
    max_work: 10000,
    max_text_bytes: 10000,
  }
  let orders = @relation_results.resolve_all_orders(results, caps).unwrap()
  let (sw, st) = @pipeline.contextual_closure_usage(
    @relation_results.checked_producer_orders(orders),
  )
  let (rw, rt) = @relation_results.publication_orders_usage(
    @relation_results.checked_publication_orders(orders),
  )
  assert_true(st > 0 && rt > 0)
  let exact = { ..caps, max_work: sw + rw, max_text_bytes: st + rt, }
  assert_true(@relation_results.resolve_all_orders(results, exact) is Ok(_))
  assert_true(
    @relation_results.resolve_all_orders(results, {
      ..exact,
      max_text_bytes: st + rt - 1,
    })
    is Err(_),
  )
  assert_true(
    @relation_results.resolve_all_orders(results, {
      ..exact,
      max_work: sw + rw - 1,
    })
    is Err(_),
  )
}

///|
test "combined order checking shares work across all steps and all Results" {
  let results = check(
    "{\"first\":{\"from\":\"rows\",\"fields\":[\"id\"]},\"second\":{\"from\":\"rows\",\"fields\":[\"score\",\"ref\"]}}",
  )
  let caps : @relation_results.OrderCheckLimits = {
    max_steps: 2,
    max_results: 2,
    max_work: 10000,
    max_text_bytes: 10000,
  }
  let checked = @relation_results.resolve_all_orders(results, caps).unwrap()
  let context = @relation_results.checked_contextual_orders(checked)
  let published = @relation_results.checked_publication_orders(checked)
  assert_eq(@pipeline.contextual_orders_count(context), 2)
  assert_eq(@relation_results.publication_orders_count(published), 2)
  assert_true(
    physical_equal(
      @pipeline.contextual_orders_pipeline(context),
      @relation_results.pipeline(
        @relation_results.publication_orders_results(published),
      ),
    ),
  )
  let (sw, st) = @pipeline.contextual_closure_usage(
    @relation_results.checked_producer_orders(checked),
  )
  let (rw, rt) = @relation_results.publication_orders_usage(published)
  assert_eq(@relation_results.checked_orders_usage(checked), (sw + rw, st + rt))
  let exact = { ..caps, max_work: sw + rw, max_text_bytes: st + rt, }
  assert_true(@relation_results.resolve_all_orders(results, exact) is Ok(_))
  for
    cap in [
      { ..exact, max_steps: 1, },
      { ..exact, max_results: 1, },
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
    ] {
    assert_true(@relation_results.resolve_all_orders(results, cap) is Err(_))
  }
  // Each phase fits this work budget independently; their composition does not.
  assert_true(sw > 0 && rw > 0)
  assert_true(
    @relation_results.resolve_all_orders(results, { ..exact, max_work: rw, })
    is Err(_),
  )
  for
    cap in [
      { ..exact, max_steps: -1, },
      { ..exact, max_results: -1, },
      { ..exact, max_work: -1, },
      { ..exact, max_text_bytes: -1, },
    ] {
    guard @relation_results.resolve_all_orders(results, cap)
      is Err(ResultOrder(e)) else {
      fail("invalid limits accepted")
    }
    assert_eq(e.kind, InvalidLimits)
  }
}

///|
test "combined order checking rejects unused unresolved steps before publication" {
  let p = @pipeline.check(
    cursor("[{\"take\":1,\"as\":\"unused\"}]"),
    [("rows", @schema.from_object(input()).unwrap())],
    None,
    None,
    ranking_limits(),
  ).unwrap()
  let results = @relation_results.check(
    p,
    cursor("{\"out\":{\"from\":\"rows\",\"fields\":[\"id\"]}}"),
    limits(),
  ).unwrap()
  assert_true(
    @relation_results.resolve_publication_orders(
      results,
      max_results=1,
      max_work=10000,
      max_text_bytes=10000,
    )
    is Ok(_),
  )
  guard @relation_results.resolve_all_orders(results, {
      max_steps: 1,
      max_results: 1,
      max_work: 10000,
      max_text_bytes: 10000,
    })
    is Err(PipelineOrder(e)) else {
    fail("unused unresolved take bypassed")
  }
  assert_eq(e.kind, UnresolvedOrder)
  assert_eq(e.path, [@source.Index(0)])
}

///|
test "combined order checking rejects later unresolved Results atomically" {
  let results = check(
    "{\"first\":{\"from\":\"rows\",\"fields\":[\"id\"]},\"second\":{\"from\":\"rows\",\"fields\":[\"data\"]}}",
  )
  guard @relation_results.resolve_all_orders(results, {
      max_steps: 2,
      max_results: 2,
      max_work: 10000,
      max_text_bytes: 10000,
    })
    is Err(ResultOrder(e)) else {
    fail("later unresolved Result bypassed")
  }
  assert_eq(e.kind, UnresolvedOrder)
  assert_eq(e.path, [@source.Key("second")])
}
