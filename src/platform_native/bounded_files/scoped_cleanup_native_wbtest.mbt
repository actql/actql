///|
#borrow(reader)
extern "C" fn mark_bounded_reader_unknown(reader : @filesystem.Reader) -> Bool = "actql_native_filesystem_test_reader_consumed_unknown"

///|
test "unconfirmed Reader keeps its original parent through bounded cleanup retry" {
  let path = bounded_root_custody_fixture()
  let root = @filesystem.open_root(path, diagnostic_ceiling=Some(128)).unwrap()
  let writer = root.create_writer("child-pending-stage", 3L).unwrap()
  writer.append(b"abc").unwrap()
  let generation = writer.seal("child-pending-value").unwrap()
  let reader = root
    .open_reader_with_custody("child-pending-value", generation)
    .unwrap()
  assert_true(mark_bounded_reader_unknown(reader))
  let failure = close_failed_bounded_reader(
    root,
    reader,
    @filesystem.Read("original read failed"),
  )
  assert_true(
    failure.issue() is Cleanup(@filesystem.Read("original read failed"), _),
  )
  assert_true(failure.reader is Some(_))
  assert_true(failure.root is Some(_))
  assert_eq(
    root.inspect_generation("child-pending-value").unwrap(),
    Some(generation),
  )
  assert_true(failure.retry_cleanup() is Err(_))
  assert_true(failure.reader is Some(_))
  assert_true(failure.root is Some(_))
  assert_eq(
    root.inspect_generation("child-pending-value").unwrap(),
    Some(generation),
  )
  assert_true(failure.retry_cleanup() is Err(_))
  assert_eq(
    root.inspect_generation("child-pending-value").unwrap(),
    Some(generation),
  )
  writer.cancel().unwrap()
  // The fixture retains both originals. Process exit is not their cleanup ACK.
}
