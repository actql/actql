///|
test "a missing contextual strategy is never treated as a runtime-only obligation" {
  let empty = empty_operation_orders()
  for
    demand in [
      @pipeline.CompleteOrder,
      StableSequence,
      LagKey,
      PrefixSequence,
      AnalyticPositions,
      NestedRows,
    ] {
    assert_true(select_operation_order(empty, demand) is None)
  }
}
