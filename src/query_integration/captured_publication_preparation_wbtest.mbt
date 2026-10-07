///|
test "captured cell Result publication polls and transfers its exact pin" {
  for quantum in [1, 7, 64] {
    let (run, issuer) = captured_graph_fixture()
    let graph = @strategy.captured_dag_graph(run)
    for task in 1..<@strategy.graph_task_count(graph) {
      captured_graph_local(run, task).unwrap()
    }
    let task = @strategy.graph_result_task(graph, 0).unwrap()
    let limits = native_publication_export_limits()
    let cancelled = @publication_host.start_captured_result_publication_export(
      run,
      0,
      limits,
      max_pins=1,
    ).unwrap()
    assert_true(cancelled.finish() is Err(Transform(Output(NotFinished))))
    let (done, used) = cancelled.advance(1).unwrap()
    assert_false(done)
    assert_eq(used, 1)
    cancelled.cancel()
    cancelled.cancel()
    assert_true(cancelled.advance(1) is Err(InvalidState))
    // The cancelled preparation returns its only pin; it does not revoke the
    // producer or require acquisition/Compute to run again.
    let pending = @publication_host.start_captured_result_publication_export(
      run,
      0,
      limits,
      max_pins=1,
    ).unwrap()
    @strategy.close_captured_task_output(run, task)
    while true {
      let (done, used) = pending.advance(quantum).unwrap()
      assert_true(used <= quantum)
      if done {
        break
      }
      assert_true(used > 0)
    }
    let exported = pending.finish().unwrap()
    pending.cancel()
    assert_true(pending.finish() is Err(InvalidState))
    let text = StringBuilder()
    while exported.next().unwrap() is Some(chunk) {
      text.write_string(chunk)
    }
    text.write_string(exported.finish().unwrap())
    assert_eq(text.to_string(), "[{\"id\":3},{\"id\":2}]")
    assert_eq(exported.result_fields().unwrap(), ["id"])
    exported.cancel()
    for index in 0..<@strategy.graph_task_count(graph) {
      @strategy.close_captured_task_output(run, index)
    }
    @mock.close_mock_query_issuer(issuer)
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)).held_bytes,
      0L,
    )
  }
}

///|
test "captured Source publication polls under the existing acquisition pin" {
  let (run, issuer) = resident_source_captured_fixture()
  let limits = native_publication_export_limits()
  let limited = @publication_host.start_captured_result_publication_export(
    run,
    0,
    { ..limits, max_rows: 1, },
    max_pins=1,
  ).unwrap()
  assert_true(
    limited.advance(1000) is Err(Transform(Output(Admission(CaptureLimit)))),
  )
  limited.cancel()
  let pending = @publication_host.start_captured_result_publication_export(
    run,
    0,
    limits,
    max_pins=1,
  ).unwrap()
  assert_eq(@strategy.next_captured_task(run), None)
  @strategy.close_captured_task_output(run, 0)
  while true {
    let (done, used) = pending.advance(1).unwrap()
    assert_true(used <= 1)
    if done {
      break
    }
  }
  let exported = pending.finish().unwrap()
  pending.cancel()
  let text = StringBuilder()
  while exported.next().unwrap() is Some(chunk) {
    text.write_string(chunk)
  }
  text.write_string(exported.finish().unwrap())
  assert_eq(text.to_string(), "[{\"id\":2},{\"id\":3}]")
  assert_eq(@strategy.next_captured_task(run), None)
  exported.cancel()
  @strategy.stop_captured_dag(run)
  @mock.close_mock_query_issuer(issuer)
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).held_bytes,
    0L,
  )
}
