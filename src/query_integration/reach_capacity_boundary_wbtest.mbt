///|
test "Reach refuses output beyond the supplied ceiling and retains cleanup" {
  let rows =
    #|[{"id":1,"src":1,"dst":2,"node_name":"one","weight":10},{"id":2,"src":2,"dst":2,"node_name":"two","weight":20}]
  let source_owner = carrier_graph_source_owner_with_rows(rows)
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_graph_reach_owner(source_owner, 1, "out", 2)
  let sequence = prepared_sequence(owner)
  let external = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let construction = @local_bridge.start_rows_to_graph(
    @bounded.control(),
    sequence,
    0,
    [external, external],
    carrier_graph_storage_limits(),
    4096L,
    100,
    fn() { true },
  ).unwrap()
  let graph = finish_rows_to_graph(construction)
  assert_eq(@local_bridge.cleanup_rows_to_graph(construction), Ok(true))
  for maximum in [1, 2] {
    let execution = @local_sga.start_reach(
      @bounded.control(),
      task_test_completion(owner),
      sequence,
      1,
      @graphs.prepare_step_read(owner, 1, 0, graph).unwrap(),
      maximum,
      { max_nodes: 1000, max_text_bytes: 1000, max_depth: 10, max_work: 10000, },
      100,
      1000,
      1000,
      [external],
    ).unwrap()
    if maximum == 1 {
      assert_true(
        finish_reach(execution)
        is Err(@local_sga.ReachOutput(@execution.CaptureLimit)),
      )
    } else {
      let output = finish_reach(execution).unwrap()
      assert_eq(@execution.completed_row_count(output), 2)
    }
    assert_eq(@local_sga.cleanup_reach(execution), Ok(true))
    assert_false(@local_sga.reach_cleanup_pending(execution))
  }
}
