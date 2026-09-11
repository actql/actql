///|
test "Result publication retains the actual imported order owner" {
  let producer = @pipeline.check_carriers(
    cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":2},{\"id\":1}]},\"as\":\"seed\"}]",
    ),
    [],
    None,
    None,
    ranking_limits(),
  ).unwrap()
  let input = @pipeline.produced_input(producer, Step(0)).unwrap()
  let p = @pipeline.check_with_evidence(
    cursor("[{\"take\":1,\"as\":\"first\"}]"),
    [("rows", @pipeline.ProducedInput(input))],
    None,
    None,
    ranking_limits(),
  ).unwrap()
  let results = @relation_results.check(
    p,
    cursor("{\"out\":{\"from\":\"first\",\"fields\":[\"id\"]}}"),
    limits(),
  ).unwrap()
  let orders = @relation_results.resolve_all_orders(results, {
    max_steps: 2,
    max_results: 1,
    max_work: 1000,
    max_text_bytes: 1000,
  }).unwrap()
  let publication = @relation_results.publication_order_at(
    @relation_results.checked_publication_orders(orders),
    0,
  ).unwrap()
  assert_eq(@relation_results.publication_strategy(publication), Inherited)
  let inherited = @relation_results.publication_inherited_order(publication).unwrap()
  assert_eq(@pipeline.order_origin(inherited), Input(0))
  assert_true(@pipeline.order_producer(inherited) is None)
  let owner = @pipeline.order_input_producer(inherited).unwrap()
  assert_true(physical_equal(owner, input))
  assert_true(physical_equal(@pipeline.producer_pipeline(owner), producer))
  assert_true(
    @pipeline.order_producer(@pipeline.producer_order(owner).unwrap()).unwrap().operation
    is Values(_),
  )
}

///|
test "combined Result checking rejects unresolved upstream branches" {
  let producer = @pipeline.check(
    cursor(
      "[{\"take\":1,\"as\":\"unused\"},{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"good\"}]",
    ),
    [("raw", @schema.from_object(input()).unwrap())],
    None,
    None,
    ranking_limits(),
  ).unwrap()
  let p = @pipeline.check_with_evidence(
    cursor("[]"),
    [
      (
        "rows",
        @pipeline.ProducedInput(
          @pipeline.produced_input(producer, Step(1)).unwrap(),
        ),
      ),
    ],
    None,
    None,
    ranking_limits(),
  ).unwrap()
  let results = @relation_results.check(
    p,
    cursor("{\"out\":{\"from\":\"rows\",\"fields\":[\"id\"]}}"),
    limits(),
  ).unwrap()
  guard @relation_results.resolve_all_orders(results, {
      max_steps: 2,
      max_results: 1,
      max_work: 1000,
      max_text_bytes: 1000,
    })
    is Err(ProducerOrder(error)) else {
    abort("upstream order must fail")
  }
  assert_true(physical_equal(error.pipeline, producer))
  assert_eq(error.issue.kind, UnresolvedOrder)
  assert_eq(error.issue.path, [@source.Index(0)])
}
