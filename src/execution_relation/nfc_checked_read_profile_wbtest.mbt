///|
test "checked producer and managed bridge NFC diagnostic" {
  guard @env.get_env_var("ACTQL_NFC_READ_DIAGNOSTIC") == Some("1") else {
    return
  }
  // Repeated immutable reads isolate per-cell validation cost. This is not a
  // claim about full producer setup, transfer, or allocation counts.
  let owner = capture_fixture()
  let receiver = typed_receiver(owner, "[{\"select\":[\"s\"]}]", target=Step(1))
  let input = prepare_managed_producer_read(
    receiver,
    0,
    owner,
    managed_read_fixture(owner, Ref(true)),
    1000,
    10000,
  ).unwrap()
  let bridge = prepare_managed_producer_bridge(
    input,
    2,
    stream_value_limits(),
    1000,
    10000,
  ).unwrap()
  for row in ["{\"n\":1,\"s\":\"é\"}", "{\"n\":2,\"s\":\"😀\"}"] {
    append_managed_producer_bridge_wire(bridge, row, retained_row_test_limits()).unwrap()
  }
  let read = finish_managed_producer_bridge(bridge, 1000, 10000).unwrap()
  let japanese_owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"s\":{\"type\":\"string\",\"nullable\":false}}," +
    "\"rows\":[{\"s\":\"日本語の文章\"},{\"s\":\"かなと漢字\"}]},\"as\":\"v\"}]",
  )
  let japanese_completion = evaluate_sequence_components(
    registered_relation_contracts(),
    prepared_sequence(japanese_owner),
    [],
    ["values_0"],
    run_limits(),
    { remaining: 10000, max_frames: 100, },
  ).unwrap()
  let japanese_receiver = typed_receiver(
    japanese_owner,
    "[{\"select\":[\"s\"]}]",
    target=Step(0),
  )
  let japanese_bound = bind_completed_input(
    japanese_receiver,
    0,
    japanese_owner,
    completed_output(japanese_completion, Step(0)).unwrap(),
  ).unwrap()
  let japanese_read = prepare_producer_read(
    japanese_receiver, japanese_bound, 1000, 1000,
  ).unwrap()
  let limits : @admitted.Limits = {
    max_nodes: 8,
    max_depth: 4,
    max_text_bytes: 64,
  }
  for (kind, current) in [("bridge", read), ("producer", japanese_read)] {
    assert_true(producer_read_checked_cell(current, 0, 0, limits) is Some(_))
    for pair in 0..<8 {
      let clock = @bench.monotonic_clock_start()
      let mut accepted = 0
      for index in 0..<100000 {
        if producer_read_checked_cell(current, index % 2, 0, limits) is Some(_) {
          accepted += 1
        }
      }
      let elapsed = @bench.monotonic_clock_end(clock)
      assert_eq(accepted, 100000)
      if pair > 0 {
        println(
          "NFC_CHECKED_READ kind=" +
          kind +
          " pair=" +
          pair.to_string() +
          " cells=100000 elapsed_us=" +
          elapsed.to_string(),
        )
      }
    }
  }
  close_managed_producer_bridge(bridge)
  assert_false(producer_read_available(read))
}
