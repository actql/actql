///|
test "values occurrence order includes empty and repeated rows without inventing keys" {
  for rows in ["[]", "[{\"id\":1},{\"id\":1}]"] {
    let p = @pipeline.check(
      cursor(
        "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":" +
        rows +
        "},\"as\":\"seed\"},{\"select\":[\"id\"]},{\"take\":1,\"as\":\"out\"}]",
      ),
      [],
      None,
      None,
      ranking_limits(),
    ).unwrap()
    let order = @pipeline.take_order(p, 2).unwrap()
    assert_eq(@pipeline.order_origin(order), Step(0))
    assert_eq(@pipeline.order_dependency_count(order), 0)
    assert_true(@pipeline.order_key_completion(order) is None)
    assert_true(@pipeline.order_producer(order).operation is Values(_))
    let r = @relation_results.check(
      p,
      cursor("{\"out\":{\"from\":\"out\",\"fields\":[\"id\"]}}"),
      limits(),
    ).unwrap()
    assert_eq(@relation_results.publication_strategy(resolve(r)), Inherited)
  }
}

///|
test "event dedupe establishes partition order before explicit Relation exposure" {
  for by in ["[]", "[\"id\"]", "[\"id\",\"id\"]"] {
    let p = @pipeline.check(
      cursor(
        "[{\"derive\":{\"time\":{\"literal\":0}}},{\"to_events\":{\"id\":\"id\",\"time\":\"time\"}},{\"dedupe_events\":{\"by\":" +
        by +
        ",\"order_by\":[{\"score\":\"desc\"}]}},{\"events\":true},{\"select\":[\"data\"]},{\"take\":1,\"as\":\"out\"}]",
      ),
      [("rows", @schema.from_object(input()).unwrap())],
      None,
      None,
      ranking_limits(),
    ).unwrap()
    assert_true(@pipeline.logical_order(p, Step(1)) is None)
    let order = @pipeline.take_order(p, 5).unwrap()
    assert_eq(@pipeline.order_origin(order), Step(2))
    assert_eq(@pipeline.order_dependency_count(order), 0)
    assert_true(@pipeline.order_producer(order).operation is Event(_))
    let r = @relation_results.check(
      p,
      cursor("{\"out\":{\"from\":\"out\",\"fields\":[\"data\"]}}"),
      limits(),
    ).unwrap()
    assert_eq(@relation_results.publication_strategy(resolve(r)), Inherited)
  }
}
