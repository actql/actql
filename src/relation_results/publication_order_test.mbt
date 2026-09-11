///|
fn resolve(
  r : @relation_results.CheckedResults,
) -> @relation_results.PublicationOrder {
  @relation_results.resolve_publication_order(
    r,
    0,
    max_work=10000,
    max_text_bytes=10000,
  ).unwrap()
}

///|
test "publication fallback uses projected field order and permits nullable canonical scalars" {
  let r = check(
    "{\"out\":{\"from\":\"rows\",\"fields\":[\"score\",\"id\",\"ref\"]}}",
  )
  let p = resolve(r)
  assert_eq(@relation_results.publication_strategy(p), ProjectedFields)
  assert_eq(@relation_results.publication_term_count(p), 3)
  for (i, name) in [(0, "score"), (1, "id"), (2, "ref")] {
    let term = @relation_results.publication_term_at(p, i).unwrap()
    assert_eq(term.field, Unqualified(name))
    assert_eq(term.direction, Asc)
    assert_eq(term.nulls, Last)
    assert_false(term.authored)
  }
  assert_eq(@relation_results.publication_result_index(p), 0)
  assert_eq(
    @relation_results.count(@relation_results.publication_results(p)),
    1,
  )
  let (work, text) = @relation_results.publication_order_usage(p)
  assert_true(
    @relation_results.resolve_publication_order(
      r,
      0,
      max_work=work,
      max_text_bytes=text,
    )
    is Ok(_),
  )
  assert_eq(
    @relation_results.resolve_publication_order(
      r,
      0,
      max_work=work - 1,
      max_text_bytes=text,
    ).unwrap_err().kind,
    BudgetExceeded,
  )
  assert_eq(
    @relation_results.resolve_publication_order(
      r,
      0,
      max_work=work,
      max_text_bytes=text - 1,
    ).unwrap_err().kind,
    BudgetExceeded,
  )
  for
    body in [
      "{\"out\":{\"from\":\"rows\",\"fields\":[\"data\"]}}", "{\"out\":{\"from\":\"rows\",\"fields\":[\"id\"],\"order_by\":[{\"score\":\"desc\"}]}}",
    ] {
    assert_eq(
      @relation_results.resolve_publication_order(
        check(body),
        0,
        max_work=10000,
        max_text_bytes=10000,
      ).unwrap_err().kind,
      UnresolvedOrder,
    )
  }
}

///|
test "publication inherited order outranks key fallback but never authored order" {
  let p = @pipeline.check_carriers(
    cursor(
      "[{\"time_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-01T00:00:00.010Z\",\"step\":1},\"as\":\"grid\"},{\"derive\":{\"x\":{\"literal\":1}},\"as\":\"extended\"}]",
    ),
    [],
    None,
    None,
    {
      max_steps: 10,
      max_work: 100000,
      max_nodes: 100000,
      max_text_bytes: 100000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
  for
    (body, expected) in [
      (
        "{\"out\":{\"from\":\"extended\",\"fields\":[\"x\"]}}",
        @relation_results.Inherited,
      ),
      (
        "{\"out\":{\"from\":\"extended\",\"fields\":[\"x\"],\"order_by\":[{\"x\":\"desc\"}]}}",
        @relation_results.Authored,
      ),
    ] {
    let r = @relation_results.check(p, cursor(body), limits()).unwrap()
    let order = resolve(r)
    assert_eq(@relation_results.publication_strategy(order), expected)
    if expected == Inherited {
      assert_eq(
        @pipeline.order_origin(
          @relation_results.publication_inherited_order(order).unwrap(),
        ),
        Step(0),
      )
      assert_eq(@relation_results.publication_term_count(order), 0)
    } else {
      assert_true(@relation_results.publication_inherited_order(order) is None)
      assert_true(@relation_results.publication_key(order) is Some(_))
      assert_eq(@relation_results.publication_term_count(order), 2)
      assert_eq(
        @relation_results.publication_term_at(order, 0).unwrap().direction,
        Desc,
      )
      assert_eq(
        @relation_results.publication_term_at(order, 1).unwrap().field,
        Unqualified("time"),
      )
      assert_false(
        @relation_results.publication_term_at(order, 1).unwrap().authored,
      )
    }
  }
}

///|
test "authored publication order uses retained positions only for ties" {
  let p = @pipeline.check_carriers(
    cursor(
      "[{\"values\":{\"schema\":{\"x\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"x\":2},{\"x\":1},{\"x\":1}]},\"as\":\"rows\"}]",
    ),
    [],
    None,
    None,
    ranking_limits(),
  ).unwrap()
  for direction in ["asc", "desc"] {
    let r = @relation_results.check(
      p,
      cursor(
        "{\"out\":{\"from\":\"rows\",\"fields\":[\"x\"],\"order_by\":[{\"x\":\"" +
        direction +
        "\"}]}}",
      ),
      limits(),
    ).unwrap()
    let order = resolve(r)
    assert_eq(@relation_results.publication_strategy(order), Authored)
    assert_true(@relation_results.publication_key(order) is None)
    assert_eq(@relation_results.publication_term_count(order), 1)
    let term = @relation_results.publication_term_at(order, 0).unwrap()
    assert_true(term.authored)
    assert_eq(term.direction, if direction == "asc" { Asc } else { Desc })
    assert_eq(
      @pipeline.order_origin(
        @relation_results.publication_inherited_order(order).unwrap(),
      ),
      Step(0),
    )
    let (work, text) = @relation_results.publication_order_usage(order)
    assert_true(
      @relation_results.resolve_publication_order(
        r,
        0,
        max_work=work,
        max_text_bytes=text,
      )
      is Ok(_),
    )
    assert_eq(
      @relation_results.resolve_publication_order(
        r,
        0,
        max_work=work - 1,
        max_text_bytes=text,
      ).unwrap_err().kind,
      BudgetExceeded,
    )
    assert_eq(
      @relation_results.resolve_publication_order(
        r,
        0,
        max_work=work,
        max_text_bytes=text - 1,
      ).unwrap_err().kind,
      BudgetExceeded,
    )
  }
}
