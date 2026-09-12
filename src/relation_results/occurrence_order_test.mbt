///|
test "Result retains the new sort producer after hidden-field tie resolution" {
  let p = @pipeline.check(
    cursor(
      "[{\"time_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-01T00:00:00.010Z\",\"step\":1},\"as\":\"grid\"},{\"derive\":{\"x\":{\"literal\":1}}},{\"drop\":[\"time\"]},{\"sort\":[{\"x\":\"desc\"}],\"as\":\"sorted\"},{\"take\":1,\"as\":\"taken\"}]",
    ),
    [],
    None,
    None,
    ranking_limits(),
  ).unwrap()
  for name in ["sorted", "taken"] {
    let r = @relation_results.check(
      p,
      cursor("{\"out\":{\"from\":\"" + name + "\",\"fields\":[\"x\"]}}"),
      limits(),
    ).unwrap()
    assert_eq(@relation_results.publication_strategy(resolve(r)), Inherited)
  }
  let order = @pipeline.take_order(p, 4).unwrap()
  assert_eq(@pipeline.order_origin(order), Step(3))
  assert_eq(
    @pipeline.order_origin(@pipeline.order_tie_break(order).unwrap()),
    Step(0),
  )
}

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
    assert_true(@pipeline.order_producer(order).unwrap().operation is Values(_))
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
    assert_true(@pipeline.order_producer(order).unwrap().operation is Event(_))
    let r = @relation_results.check(
      p,
      cursor("{\"out\":{\"from\":\"out\",\"fields\":[\"data\"]}}"),
      limits(),
    ).unwrap()
    assert_eq(@relation_results.publication_strategy(resolve(r)), Inherited)
  }
}
