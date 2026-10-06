///|
test "checked Graph Delta producer retains singleton publication order" {
  let graph = property_query_graph()
  for right in ["a", "b"] {
    let checked = @pipeline.check_carriers(
      cursor(
        "[{\"graph_diff\":{\"with\":\"" +
        right +
        "\"},\"from\":\"a\"},{\"select\":[\"delta\"]},{\"filter\":{\"literal\":false}},{\"take\":1,\"as\":\"out\"}]",
      ),
      [("a", graph), ("b", graph)],
      None,
      None,
      ranking_limits(),
    ).unwrap()
    let result = @relation_results.check(
      checked,
      cursor("{\"answer\":{\"from\":\"out\",\"fields\":[\"delta\"]}}"),
      limits(),
    ).unwrap()
    assert_eq(@relation_results.count(result), 1)
    assert_true(
      @pipeline.row_count(checked, Step(0)) is Some({ upper: 1L, exact: true, }),
    )
    let order = @pipeline.take_order(checked, 3).unwrap()
    assert_eq(@pipeline.order_origin(order), Step(0))
    assert_eq(@pipeline.order_predecessor(order), Some(Step(2)))
    guard @pipeline.order_producer(order) is Some(producer) else {
      fail("order must retain the checked Delta producer")
    }
    guard producer.operation is @pipeline.GraphDelta(checked=delta, ..) else {
      fail("order must not come from an unrelated row ceiling")
    }
    assert_eq(@graph.delta_operation(delta), @graph.Difference)
    assert_true(@pipeline.candidate_key(checked, Step(0)) is None)
    assert_true(
      @relation_results.resolve_publication_order(
        result,
        0,
        max_work=10000,
        max_text_bytes=10000,
      )
      is Ok(_),
    )
  }
}

///|
test "a one-row ceiling does not establish arbitrary JSON publication order" {
  let checked = @pipeline.check(
    cursor("[{\"from\":\"rows\",\"take\":1,\"as\":\"out\"}]"),
    [("rows", @schema.from_object(input()).unwrap())],
    None,
    None,
    ranking_limits(),
  ).unwrap()
  assert_true(
    @pipeline.row_count(checked, Step(0)) is Some({ upper: 1L, exact: false, }),
  )
  assert_true(@pipeline.logical_order(checked, Step(0)) is None)
  let result = @relation_results.check(
    checked,
    cursor("{\"answer\":{\"from\":\"out\",\"fields\":[\"data\"]}}"),
    limits(),
  ).unwrap()
  assert_eq(
    @relation_results.resolve_publication_order(
      result,
      0,
      max_work=10000,
      max_text_bytes=10000,
    ).unwrap_err().kind,
    UnresolvedOrder,
  )
}

///|
test "Graph equality can publish its Boolean result after Relation steps" {
  let graph = property_query_graph()
  for right in ["a", "b"] {
    let checked = @pipeline.check_carriers(
      cursor(
        "[{\"graphs_equal\":{\"with\":\"" +
        right +
        "\"},\"from\":\"a\",\"as\":\"comparison\"},{\"select\":[\"equal\"],\"as\":\"out\"}]",
      ),
      [("a", graph), ("b", graph)],
      None,
      None,
      ranking_limits(),
    ).unwrap()
    assert_true(@pipeline.candidate_key(checked, Step(0)) is None)
    guard @pipeline.output_carrier(checked) is Some(@carrier.Relation(rows)) else {
      fail("Graph equality must produce Relation rows")
    }
    guard @carrier.complete_schema(rows) is Some(schema) else {
      fail("Graph equality must produce a complete schema")
    }
    assert_true(
      @schema.lookup(schema, Unqualified("equal"))
      is Some({ shape: Boolean, nullable: false, }),
    )
    let result = @relation_results.check(
      checked,
      cursor("{\"answer\":{\"from\":\"out\",\"fields\":[\"equal\"]}}"),
      limits(),
    ).unwrap()
    assert_eq(@relation_results.count(result), 1)
  }
}
