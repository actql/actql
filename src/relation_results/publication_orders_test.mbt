///|
test "all publication strategies share one inclusive budget and retain every named result" {
  let r = check(
    "{\"first\":{\"from\":\"rows\",\"fields\":[\"id\"]},\"second\":{\"from\":\"rows\",\"fields\":[\"score\",\"ref\"]}}",
  )
  let p = @relation_results.resolve_publication_orders(
    r,
    max_results=2,
    max_work=10000,
    max_text_bytes=10000,
  ).unwrap()
  assert_eq(@relation_results.publication_orders_count(p), 2)
  assert_eq(
    @relation_results.count(@relation_results.publication_orders_results(p)),
    2,
  )
  let mut expected_work = 0
  let mut expected_text = 0
  for i = 0; i < 2; i = i + 1 {
    let order = @relation_results.publication_order_at(p, i).unwrap()
    assert_eq(@relation_results.publication_result_index(order), i)
    let single = @relation_results.resolve_publication_order(
      r,
      i,
      max_work=10000,
      max_text_bytes=10000,
    ).unwrap()
    let (work, text) = @relation_results.publication_order_usage(single)
    expected_work += work
    expected_text += text
    assert_eq(
      @relation_results.publication_strategy(order),
      @relation_results.publication_strategy(single),
    )
  }
  assert_true(@relation_results.publication_order_at(p, -1) is None)
  assert_true(@relation_results.publication_order_at(p, 2) is None)
  assert_eq(
    @relation_results.publication_orders_usage(p),
    (expected_work, expected_text),
  )
  assert_true(
    @relation_results.resolve_publication_orders(
      r,
      max_results=2,
      max_work=expected_work,
      max_text_bytes=expected_text,
    )
    is Ok(_),
  )
  for
    (count, work, text) in [
      (1, expected_work, expected_text),
      (2, expected_work - 1, expected_text),
      (2, expected_work, expected_text - 1),
    ] {
    assert_eq(
      @relation_results.resolve_publication_orders(
        r,
        max_results=count,
        max_work=work,
        max_text_bytes=text,
      ).unwrap_err().kind,
      BudgetExceeded,
    )
  }
}

///|
test "a later unresolved Result rejects the whole publication-order collection" {
  let r = check(
    "{\"first\":{\"from\":\"rows\",\"fields\":[\"id\"]},\"second\":{\"from\":\"rows\",\"fields\":[\"data\"]}}",
  )
  assert_true(
    @relation_results.resolve_publication_order(
      r,
      0,
      max_work=10000,
      max_text_bytes=10000,
    )
    is Ok(_),
  )
  let issue = @relation_results.resolve_publication_orders(
    r,
    max_results=2,
    max_work=10000,
    max_text_bytes=10000,
  ).unwrap_err()
  assert_eq(issue.kind, UnresolvedOrder)
  assert_eq(issue.path, [@source.Key("second")])
  for (count, work, text) in [(-1, 100, 100), (2, -1, 100), (2, 100, -1)] {
    assert_eq(
      @relation_results.resolve_publication_orders(
        r,
        max_results=count,
        max_work=work,
        max_text_bytes=text,
      ).unwrap_err().kind,
      InvalidLimits,
    )
  }
}
