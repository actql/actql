///|
test "current degree supplies a typed Relation to scalar selection" {
  let checked = @pipeline.check_carriers(
    cursor(
      "[{\"degree\":{\"direction\":\"both\"}},{\"select\":[{\"id\":\"node\"}],\"as\":\"out\"}]",
    ),
    [("g", property_query_graph())],
    None,
    None,
    ranking_limits(),
  ).unwrap()
  assert_true(@pipeline.output_carrier(checked) is Some(@carrier.Relation(_)))
  assert_true(@pipeline.candidate_key(checked, Step(0)) is None)
  assert_eq(
    @pipeline.order_origin(@pipeline.logical_order(checked, Step(0)).unwrap()),
    Step(0),
  )
  let result = @relation_results.check(
    checked,
    cursor("{\"out\":{\"from\":\"out\",\"fields\":[\"id\"]}}"),
    limits(),
  ).unwrap()
  let publication = resolve(result)
  assert_eq(@relation_results.publication_strategy(publication), Inherited)
  assert_eq(
    @pipeline.order_origin(
      @relation_results.publication_inherited_order(publication).unwrap(),
    ),
    Step(0),
  )
  assert_eq(@relation_results.publication_term_count(publication), 0)
}
