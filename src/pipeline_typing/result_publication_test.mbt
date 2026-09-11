///|
test "publication establishes projected-field order without changing the producer" {
  let p = @pipeline_typing.check(
    cursor("[]"),
    [("rows", schema())],
    None,
    None,
    limits(),
  ).unwrap()
  let projection = producer_select(p, Input(0), "[\"id\"]")
  assert_true(@pipeline_typing.logical_order(p, Input(0)) is None)
  let result = @pipeline_typing.publish_produced_input(
    p,
    Input(0),
    projection,
    None,
    limits(),
  ).unwrap()
  let publication = @pipeline_typing.input_publication(result)
  assert_true(
    physical_equal(@pipeline_typing.publication_pipeline(publication), p),
  )
  assert_eq(@pipeline_typing.publication_target(publication), Input(0))
  assert_eq(@pipeline_typing.publication_term_count(publication), 1)
  assert_eq(
    @pipeline_typing.publication_term_at(publication, 0).unwrap().field,
    Unqualified("id"),
  )
  let input = @pipeline_typing.published_input(result)
  assert_true(
    physical_equal(
      @pipeline_typing.order_publication(
        @pipeline_typing.producer_order(input).unwrap(),
      ).unwrap(),
      publication,
    ),
  )
  let downstream = consume_projection(input, "[{\"take\":1}]")
  assert_true(@pipeline_typing.take_order(downstream, 0) is Some(_))
  assert_true(@pipeline_typing.logical_order(p, Input(0)) is None)
  // Authored terms without a key or inherited tie order cannot fabricate one.
  assert_true(
    @pipeline_typing.publish_produced_input(
      p,
      Input(0),
      projection,
      Some(cursor("[{\"id\":\"asc\"}]")),
      limits(),
    )
    is Err({ kind: UnresolvedOrder, .. }),
  )
}

///|
test "publication retains hidden authored order and charges exact shared budgets" {
  let p = @pipeline_typing.check_carriers(
    cursor(
      "[" +
      count_values(3, "seed") +
      ",{\"derive\":{\"extra\":{\"literal\":42}}}]",
    ),
    [],
    None,
    None,
    limits(),
  ).unwrap()
  let projection = producer_select(p, Step(1), "[\"extra\"]")
  let source = cursor("[{\"id\":\"desc\"}]")
  let result = @pipeline_typing.publish_produced_input(
    p,
    Step(1),
    projection,
    Some(source),
    limits(),
  ).unwrap()
  let publication = @pipeline_typing.input_publication(result)
  assert_true(
    physical_equal(
      @pipeline_typing.publication_order_source(publication).unwrap(),
      source,
    ),
  )
  assert_eq(
    @pipeline_typing.publication_term_at(publication, 0).unwrap().field,
    Unqualified("id"),
  )
  assert_true(@pipeline_typing.publication_prior_order(publication) is Some(_))
  let downstream = consume_projection(
    @pipeline_typing.published_input(result),
    "[{\"take\":1}]",
  )
  assert_eq(
    @schema.field_count(
      @pipeline_typing.schema_at(downstream, Input(0)).unwrap(),
    ),
    1,
  )
  assert_true(@pipeline_typing.take_order(downstream, 0) is Some(_))
  let used = @pipeline_typing.published_input_usage(result)
  let exact = {
    ..limits(),
    max_work: used.work,
    max_nodes: used.nodes,
    max_text_bytes: used.text_bytes,
  }
  assert_true(
    @pipeline_typing.publish_produced_input(
      p,
      Step(1),
      projection,
      Some(source),
      exact,
    )
    is Ok(_),
  )
  for
    cap in [
      { ..exact, max_work: used.work - 1, },
      { ..exact, max_nodes: used.nodes - 1, },
      { ..exact, max_text_bytes: used.text_bytes - 1, },
    ] {
    assert_true(
      @pipeline_typing.publish_produced_input(
        p,
        Step(1),
        projection,
        Some(source),
        cap,
      )
      is Err(_),
    )
  }
  for invalid in ["[]", "[{\"missing\":\"asc\"}]", "[{\"id\":\"invalid\"}]"] {
    assert_true(
      @pipeline_typing.publish_produced_input(
        p,
        Step(1),
        projection,
        Some(cursor(invalid)),
        limits(),
      )
      is Err(_),
    )
  }
  let renamed = producer_select(p, Step(1), "[{\"renamed\":\"extra\"}]")
  assert_true(
    @pipeline_typing.publish_produced_input(p, Step(1), renamed, None, limits())
    is Err({ kind: InvalidBody, .. }),
  )
}
