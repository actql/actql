///|
test "window group lowering keeps boundary keys out of authored AoA params" {
  let owner = expression_pipeline(
    ",{\"row_window\":{\"kind\":\"fixed\",\"time\":\"id\",\"size\":10}}," +
    "{\"window_group\":{\"by\":[\"id\",\"window_start\"]," +
    "\"aggregates\":{\"n\":{\"fn\":\"count\"}}}}",
  )
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 2)
    is Some(@lowering_relation.RowStep(kernel)) &&
    @lowering_relation.kernel_group(kernel) is Some(group) else {
    fail("window group kernel")
  }
  assert_true(@lowering_relation.group_is_window(group))
  assert_eq(@lowering_relation.group_key_count(group), 3)
  assert_eq(
    [0, 1, 2].map(i => {
      @schema.reference_name(@lowering_relation.group_key_at(group, i).unwrap())
    }),
    ["window_start", "window_end", "id"],
  )
  let writer = @encode.writer(100000, 10000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"values_0\",\"in\":[],\"op\":\"REL.values\",\"params\":{\"rows\":[{\"id\":1}],\"schema\":{\"id\":{\"nullable\":false,\"type\":\"number\"}}}},{\"id\":\"window_1\",\"in\":[\"values_0\"],\"op\":\"REL.window.fixed\",\"params\":{\"offset_ms\":0,\"size_ms\":10,\"time\":\"id\"}},{\"id\":\"window_group_2\",\"in\":[\"window_1\"],\"op\":\"REL.window.project\",\"params\":{\"aggs\":{\"n\":{\"fn\":\"count\"}},\"by\":[\"id\"]}}]",
  )
}

///|
test "window group lowering preserves empty authored grouping" {
  let owner = expression_pipeline(
    ",{\"row_window\":{\"kind\":\"sliding\",\"time\":\"id\",\"size\":10,\"step\":3}}," +
    "{\"window_group\":{\"by\":[],\"aggregates\":{}}}",
  )
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 2)
    is Some(@lowering_relation.RowStep(kernel)) &&
    @lowering_relation.kernel_group(kernel) is Some(group) else {
    fail("window group kernel")
  }
  assert_true(@lowering_relation.group_is_window(group))
  assert_eq(@lowering_relation.group_key_count(group), 2)
  assert_eq(@lowering_relation.group_aggregate_count(group), 0)
}
