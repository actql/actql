///|
fn writer_custody_root() -> Root raise {
  guard filesystem_custody_fixture_path() is Some(path) else {
    fail("selected Writer custody requires an owned fresh Root")
  }
  open_private_root(path).unwrap()
}

///|
test "Writer failure retains original conflict under the Root diagnostic bound" {
  let path = filesystem_custody_fixture_path().unwrap()
  let root = open_private_root(path, diagnostic_ceiling=Some(8)).unwrap()
  let first = root.create_writer("writer-bounded-conflict", 1L).unwrap()
  first.append(b"x").unwrap()
  let generation = root
    .inspect_generation("writer-bounded-conflict")
    .unwrap()
    .unwrap()
  let failed = match
    root.create_writer_with_custody("writer-bounded-conflict", 1L) {
    Err(original) => original
    Ok(_) => fail("second Writer acquired an existing original name")
  }
  let retained = failed.writer.unwrap()
  let detail_bytes = writer_error_ffi(retained).length()
  let original_conflict = failed.issue() is Conflict
  failed.retry_cleanup().unwrap()
  let original_unchanged = root.verify_generation(
    "writer-bounded-conflict", generation,
  )
  first.cancel().unwrap()
  root.close().unwrap()
  // Complete all actual original cleanup even while this counter is red.
  assert_true(original_conflict)
  assert_true(original_unchanged)
  assert_true(detail_bytes <= 8)
}

///|
test "Writer seal failure keeps the original generation with bounded diagnostics" {
  let path = filesystem_custody_fixture_path().unwrap()
  let root = open_private_root(path, diagnostic_ceiling=Some(8)).unwrap()
  let writer = root
    .create_writer_with_custody("writer-bounded-seal", 1L)
    .unwrap()
  writer.append(b"y").unwrap()
  test_fail_root_sync(root, 1)
  let terminal_result = writer.seal("writer-bounded-terminal")
  let detail_bytes = writer_error_ffi(writer).length()
  let pending = writer.cleanup_pending()
  let generation = root.inspect_generation("writer-bounded-terminal").unwrap()
  let not_sealed = !writer.is_sealed()
  writer.cancel().unwrap()
  let removed = root.inspect_generation("writer-bounded-terminal").unwrap()
    is None
  root.close().unwrap()
  assert_true(terminal_result is Err(Seal(_)))
  assert_true(detail_bytes <= 8)
  assert_true(pending && not_sealed)
  assert_true(generation is Some(original) && original.size == 1L)
  assert_true(removed)
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
