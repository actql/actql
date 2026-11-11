///|
fn import_usage_bridge_fixture() -> (ManagedProducerBridge[Int], Ref[Bool]) raise {
  let producer = capture_fixture()
  let receiver = projected_consumer(
    producer,
    "[{\"renamed\":\"s\"}]",
    "[{\"select\":[\"renamed\"]}]",
    target=Step(1),
  )
  let live = Ref(true)
  let input = prepare_managed_producer_read(
    receiver,
    0,
    producer,
    managed_read_fixture(producer, live),
    1000,
    10000,
  ).unwrap()
  (
    prepare_managed_producer_bridge(
      input,
      2,
      stream_value_limits(),
      1000,
      10000,
      deferred_reclamation=true,
    ).unwrap(),
    live,
  )
}

///|
test "managed import usage borrows complete successful admission quantities" {
  let (bridge, _) = import_usage_bridge_fixture()
  assert_eq(
    managed_producer_bridge_import_usage(bridge),
    Some({ nodes: 0, text_bytes: 0, work: 0, }),
  )
  append_managed_producer_bridge_wire(
    bridge,
    "{\"n\":1,\"s\":\"é\"}",
    retained_row_test_limits(),
  ).unwrap()
  // Full producer n+s, not just receiving projection s; decoded UTF-8 bytes,
  // not JSON syntax/escape bytes, and no second measure/parse is requested.
  assert_eq(
    managed_producer_bridge_import_usage(bridge),
    Some({ nodes: 3, text_bytes: 4, work: 7, }),
  )
  append_managed_producer_bridge_wire(
    bridge,
    "{\"n\":2,\"s\":\"\\ud83d\\ude00\"}",
    retained_row_test_limits(),
  ).unwrap()
  assert_eq(
    managed_producer_bridge_import_usage(bridge),
    Some({ nodes: 6, text_bytes: 10, work: 16, }),
  )
  let read = finish_managed_producer_bridge(bridge, 1000, 10000).unwrap()
  assert_true(managed_producer_bridge_import_usage(bridge) is None)
  assert_eq(producer_read_row_count(read), 2)
  close_managed_producer_bridge(bridge)
  assert_true(managed_producer_bridge_import_usage(bridge) is None)
}

///|
test "managed import failed append cannot issue successful geometry" {
  let (bridge, _) = import_usage_bridge_fixture()
  append_managed_producer_bridge_wire(
    bridge,
    "{\"n\":1,\"s\":\"é\"}",
    retained_row_test_limits(),
  ).unwrap()
  assert_true(
    append_managed_producer_bridge_wire(
      bridge,
      "{\"n\":\"wrong\",\"s\":\"value\"}",
      retained_row_test_limits(),
    )
    is Err(Wire(_)),
  )
  assert_true(managed_producer_bridge_import_usage(bridge) is None)
  // The same failed buffer and debit survive for the original cleanup owner.
  assert_eq(bridge.admitted.buffer.rows.length(), 1)
  assert_eq(bridge.admitted.buffer.budget.nodes, 3)
  assert_eq(bridge.admitted.buffer.budget.text, 4)
  assert_true(advance_close_managed_producer_bridge(bridge, 64))
}

///|
test "managed import geometry DATA cannot reopen an unavailable producer" {
  let (bridge, live) = import_usage_bridge_fixture()
  append_managed_producer_bridge_wire(
    bridge,
    "{\"n\":1,\"s\":\"é\"}",
    retained_row_test_limits(),
  ).unwrap()
  live.val = false
  // No current probe is added to a quantity read. Existing append still owns
  // the full availability fence and refuses this same revoked producer.
  assert_true(managed_producer_bridge_import_usage(bridge) is Some(_))
  assert_true(
    append_managed_producer_bridge_wire(
      bridge,
      "{\"n\":2,\"s\":\"text\"}",
      retained_row_test_limits(),
    )
    is Err(Unavailable),
  )
  assert_true(managed_producer_bridge_import_usage(bridge) is None)
  close_managed_producer_bridge(bridge)
  assert_true(advance_close_managed_producer_bridge(bridge, 64))
}
