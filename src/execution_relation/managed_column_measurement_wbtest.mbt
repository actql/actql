///|
test "managed column facts follow checked projection and do not survive revocation" {
  let owner = capture_fixture()
  let live = Ref(true)
  let output = managed_read_fixture(owner, live)
  let receiver = projected_consumer(
    owner,
    "[{\"a\":\"s\"},{\"b\":\"n\"},{\"c\":\"s\"}]",
    "[{\"select\":[\"a\",\"b\",\"c\"]}]",
    target=Step(1),
  )
  let input = prepare_managed_producer_read(
    receiver, 0, owner, output, 1000, 10000,
  ).unwrap()
  let text = managed_producer_read_column_measurement(input, 0).unwrap()
  assert_eq(text.rows, 2)
  assert_eq(text.bytes, 10)
  assert_eq(text.nodes, 2)
  assert_eq(text.max_value_bytes, 6)
  assert_eq(text.null_rows, 0)
  assert_eq(managed_producer_read_column_measurement(input, 2), Some(text))
  let number = managed_producer_read_column_measurement(input, 1).unwrap()
  assert_eq(number.bytes, 2)
  assert_eq(number.max_value_bytes, 1)
  assert_true(managed_producer_read_column_measurement(input, -1) is None)
  assert_true(managed_producer_read_column_measurement(input, 3) is None)
  live.val = false
  assert_true(managed_producer_read_column_measurement(input, 0) is None)
}
