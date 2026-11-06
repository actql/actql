///|
test "rejected native Reader custody preserves generation refusal" {
  guard filesystem_custody_fixture_path() is Some(path) else {
    fail("selected physical Reader custody case requires owned Store root")
  }
  let root = open_root(path).unwrap()
  let token = @env.now().to_string()
  let writer = root.create_writer("reader-custody-stage-" + token, 3L).unwrap()
  writer.append(b"abc").unwrap()
  let name = "reader-custody-object-" + token
  let generation = writer.seal(name).unwrap()
  let wrong = { ..generation, size: 2L, }
  guard root.open_reader_with_custody(name, wrong) is Err(failure) else {
    fail("wrong original generation admitted")
  }
  assert_true(failure.issue() is GenerationMismatch)
  failure.retry_cleanup().unwrap()
  failure.retry_cleanup().unwrap()
  assert_true(failure.issue() is GenerationMismatch)
  writer.cancel().unwrap()
  root.close().unwrap()
  root.close().unwrap()
}

///|
test "directory acknowledgement is not child Reader stop" {
  guard filesystem_custody_fixture_path() is Some(path) else {
    fail("selected physical Reader custody case requires owned Store root")
  }
  let root = open_root(path).unwrap()
  let token = @env.now().to_string()
  let writer = root.create_writer("reader-child-stage-" + token, 3L).unwrap()
  writer.append(b"abc").unwrap()
  let name = "reader-child-object-" + token
  let generation = writer.seal(name).unwrap()
  let reader = root.open_reader_with_custody(name, generation).unwrap()
  writer.cancel().unwrap()
  root.close().unwrap()
  assert_eq(reader.next(3).unwrap().bytes, b"abc")
  reader.finish().unwrap()
  reader.close().unwrap()
}
