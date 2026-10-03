///|
test "retired degree cannot supply scalar Result key evidence for Property Graph" {
  assert_true(
    @pipeline.check_carriers(
      cursor(
        "[{\"degree\":{\"direction\":\"both\"}},{\"select\":[{\"id\":\"node\"}],\"as\":\"out\"}]",
      ),
      [("g", property_query_graph())],
      None,
      None,
      ranking_limits(),
    )
    is Err({ kind: Graph(@graph.UnsupportedGraphOperation), .. }),
  )
}
