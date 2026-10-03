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
}
