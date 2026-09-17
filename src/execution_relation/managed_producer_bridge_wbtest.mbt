///|
test "managed provider bridge yields a scoped ordinary reader for Local" {
  let producer = capture_fixture()
  let receiver = projected_consumer(
    producer,
    "[{\"renamed\":\"s\"}]",
    "[{\"select\":[\"renamed\"]}]",
    target=Step(1),
  )
  let input = prepare_managed_producer_read(
    receiver,
    0,
    producer,
    managed_read_fixture(producer, Ref(true)),
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
  assert_true(producer_read_available(read))
  assert_eq(producer_read_row_count(read), 2)
  assert_true(producer_read_cell(read, 1, 0) is Some(Text("😀")))
  close_managed_producer_bridge(bridge)
  assert_false(producer_read_available(read))
  assert_true(producer_read_cell(read, 0, 0) is None)
}
