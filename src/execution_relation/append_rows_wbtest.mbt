///|
test "checked append aligns columns and preserves left then right order" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"tag\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"id\":1,\"tag\":{\"literal\":\"left\"}}]},\"as\":\"left_rows\"},{\"values\":{\"schema\":{\"tag\":{\"type\":\"string\",\"nullable\":false},\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"tag\":{\"literal\":\"right\"},\"id\":2}]},\"as\":\"right_rows\"},{\"from\":\"left_rows\",\"append\":{\"with\":\"right_rows\"},\"as\":\"out\"}]",
  )
  let sequence = prepared_sequence(owner)
  assert_true(@lower.sequence_step(sequence, 2) is Some(@lower.AppendStep(_)))
  let writer = @encode.writer(100000, 10000, 100)
  @lower.emit_sequence_steps(sequence, writer)
  assert_eq(
    @encode.finish(writer),
    "[{\"id\":\"values_0\",\"in\":[],\"op\":\"REL.values\",\"params\":{\"rows\":[{\"id\":1,\"tag\":\"left\"}],\"schema\":{\"id\":{\"nullable\":false,\"type\":\"number\"},\"tag\":{\"nullable\":false,\"type\":\"string\"}}}},{\"id\":\"values_1\",\"in\":[],\"op\":\"REL.values\",\"params\":{\"rows\":[{\"id\":2,\"tag\":\"right\"}],\"schema\":{\"id\":{\"nullable\":false,\"type\":\"number\"},\"tag\":{\"nullable\":false,\"type\":\"string\"}}}},{\"id\":\"append_2\",\"in\":[\"values_0\",\"values_1\"],\"op\":\"REL.unionAll\",\"params\":{}}]",
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    sequence,
    [],
    ["append_2"],
    100000,
    10000,
  ).unwrap()
  let result = execute_generated_sequence(generated, [], {
    rows: run_limits(),
    max_work: 100000,
    max_frames: 100,
  }).unwrap()
  let table = test_row_output(completed_output(result, Step(2)).unwrap())
  assert_eq(table.names, ["id", "tag"])
  assert_eq(table.rows.length(), 2)
  assert_true(table.rows[0][0] is Number(1))
  assert_true(table.rows[0][1] is Text("left"))
  assert_true(table.rows[1][0] is Number(2))
  assert_true(table.rows[1][1] is Text("right"))
}

///|
test "append enforces the cumulative output row ceiling" {
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1}]},\"as\":\"left_rows\"},{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":2}]},\"as\":\"right_rows\"},{\"from\":\"left_rows\",\"append\":{\"with\":\"right_rows\"}}]",
  )
  let generated = prepare_generated_sequence(
    registered_relation_contracts(),
    prepared_sequence(owner),
    [],
    ["append_2"],
    100000,
    10000,
  ).unwrap()
  assert_true(
    execute_generated_sequence(generated, [], {
      rows: { ..run_limits(), max_rows: 1, },
      max_work: 100000,
      max_frames: 100,
    })
    is Err(_),
  )
}
