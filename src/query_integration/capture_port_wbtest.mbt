///|
test "common capture port rejects foreign Program and foreign completed material" {
  let (program, sequence) = query_program_fixture()
  let (other_program, _) = query_program_fixture()
  let calls = Ref(0)
  assert_true(@query.query_program_matches(sequence, program))
  assert_false(@query.query_program_matches(sequence, other_program))
  assert_true(
    @query.prepare_trusted_capture_port(sequence, other_program, fn(_ : Unit) {
      calls.val += 1
      None
    })
    is Err(Unavailable),
  )
  assert_eq(calls.val, 0)
  let empty = @query.prepare_trusted_capture_port(sequence, program, fn(
    _ : Unit,
  ) {
    calls.val += 1
    None
  }).unwrap()
  assert_true(@query.capture_verified_source(empty, ()) is Err(Unavailable))
  assert_eq(calls.val, 1)

  // A successful Compute from a different owner is not this query's capture,
  // even when trusted wiring presents it as completed material.
  let (run, _) = captured_graph_fixture()
  captured_graph_local(run, 1).unwrap()
  let output = @strategy.captured_task_output(run, 1, Step(1)).unwrap()
  let foreign = @query.prepare_trusted_capture_port(sequence, program, fn(
    _ : Unit,
  ) {
    Some((output, 0))
  }).unwrap()
  assert_true(@query.capture_verified_source(foreign, ()) is Err(Unavailable))
}
