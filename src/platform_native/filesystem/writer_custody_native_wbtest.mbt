///|
fn writer_custody_root() -> Root raise {
  guard filesystem_custody_fixture_path() is Some(path) else {
    fail("selected Writer custody requires an owned fresh Root")
  }
  open_private_root(path).unwrap()
}

///|
test "retaining partial Writer closes only its FD and preserves unsealed bytes" {
  let root = writer_custody_root()
  let name = "writer-retained-partial"
  let writer = root.create_writer_with_custody(name, 16L).unwrap()
  writer.append(b"partial").unwrap()
  let generation = root.inspect_generation(name).unwrap().unwrap()
  writer.close_retaining_files().unwrap()
  writer.close_retaining_files().unwrap()
  assert_true(writer.cleanup_pending())
  assert_false(writer.is_sealed())
  assert_true(writer.append(b"more") is Err(WriterClosed))
  assert_true(writer.seal("never-published") is Err(WriterClosed))
  let reader = root.open_reader(name, generation).unwrap()
  assert_eq(reader.next(16).unwrap().bytes, b"partial")
  reader.finish().unwrap()
  reader.close().unwrap()
  assert_eq(root.inspect_generation("never-published").unwrap(), None)
  root.close().unwrap()
}

///|
test "Writer acquisition failure preserves conflict and never cleans foreign bytes" {
  let root = writer_custody_root()
  let name = "writer-retained-conflict"
  let original = root.create_writer(name, 16L).unwrap()
  original.append(b"foreign").unwrap()
  let generation = root.inspect_generation(name).unwrap().unwrap()
  let failure = match root.create_writer_with_custody(name, 16L) {
    Err(value) => value
    Ok(_) => fail("foreign staging Writer was admitted")
  }
  assert_true(failure.issue() is Conflict)
  failure.retry_cleanup().unwrap()
  failure.retry_cleanup().unwrap()
  assert_true(failure.issue() is Conflict)
  assert_true(root.verify_generation(name, generation))
  original.close_retaining_files().unwrap()
  root.close().unwrap()
}

///|
test "Writer custody rejects malformed inputs without an acquired carrier" {
  let root = writer_custody_root()
  for (name, limit) in [("../escape", 1L), ("writer-negative", -1L)] {
    let failure = match root.create_writer_with_custody(name, limit) {
      Err(value) => value
      Ok(_) => fail("invalid Writer was admitted")
    }
    assert_true(failure.writer is None)
    assert_true(
      failure.issue() is InvalidName || failure.issue() is InvalidLimit,
    )
    failure.retry_cleanup().unwrap()
  }
  root.close().unwrap()
}
