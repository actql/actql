///|
fn ordinary_file_fixture() -> String raise {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_ORDINARY_FILE_ROOT") is Some(path) else {
    fail("selected ordinary File cases require their own original Root")
  }
  path
}

///|
test "Mock replacement keeps the new target through original writer cleanup" {
  let root = open_root(ordinary_file_fixture()).unwrap()
  let initial = root.create_writer("mock-original-stage", 3L).unwrap()
  initial.append(b"old").unwrap()
  ignore(initial.seal_file("mock-target.json").unwrap())
  initial.close_retaining_files().unwrap()
  let observed = root.observe_file("mock-target.json").unwrap()
  let lock = root.acquire_lock("mock-target.json.actql-write.lock").unwrap()
  let writer = root.create_writer("mock-replacement-stage", 3L).unwrap()
  writer.append(b"new").unwrap()
  let generation = writer.replace_observed_file(observed, lock).unwrap()
  assert_true(observed.check_current() is Err(GenerationMismatch))
  assert_true(writer.replace_observed_file(observed, lock) is Err(WriterClosed))
  writer.cancel().unwrap()
  writer.cancel().unwrap()
  assert_false(writer.cleanup_pending())
  assert_eq(
    root.inspect_file_generation("mock-target.json").unwrap(),
    Some(generation),
  )
  let reader = root
    .open_file_reader_with_custody("mock-target.json", generation)
    .unwrap()
  assert_eq(reader.next(3).unwrap().bytes, b"new")
  reader.finish().unwrap()
  reader.close().unwrap()
  lock.close_checked().unwrap()
  root.close().unwrap()
}

///|
test "Mock replacement refuses stale observations and a foreign or retired lock" {
  let root = open_root(ordinary_file_fixture()).unwrap()
  let initial = root.create_writer("mock-fence-original", 1L).unwrap()
  initial.append(b"a").unwrap()
  ignore(initial.seal_file("mock-fence.json").unwrap())
  initial.close_retaining_files().unwrap()
  let observed = root.observe_file("mock-fence.json").unwrap()
  let other = open_root(ordinary_file_fixture()).unwrap()
  let foreign = other.acquire_lock("mock-fence.json.actql-write.lock").unwrap()
  let first = root.create_writer("mock-fence-first", 1L).unwrap()
  first.append(b"b").unwrap()
  assert_true(
    first.replace_observed_file(observed, foreign) is Err(GenerationMismatch),
  )
  foreign.close_checked().unwrap()
  other.close().unwrap()
  let retired = root.acquire_lock("mock-fence.json.actql-write.lock").unwrap()
  retired.close_checked().unwrap()
  assert_true(
    first.replace_observed_file(observed, retired) is Err(GenerationMismatch),
  )
  let unrelated = root.acquire_lock("unrelated.lock").unwrap()
  assert_true(
    first.replace_observed_file(observed, unrelated) is Err(GenerationMismatch),
  )
  unrelated.close_checked().unwrap()
  let lock = root.acquire_lock("mock-fence.json.actql-write.lock").unwrap()
  let original = first.replace_observed_file(observed, lock).unwrap()
  first.cancel().unwrap()
  let second = root.create_writer("mock-fence-second", 1L).unwrap()
  second.append(b"c").unwrap()
  assert_true(
    second.replace_observed_file(observed, lock) is Err(GenerationMismatch),
  )
  second.cancel().unwrap()
  assert_true(root.verify_file_generation("mock-fence.json", original))
  lock.close_checked().unwrap()
  root.close().unwrap()
}

///|
test "Mock replacement sync failure never replays or removes the replaced target" {
  let root = open_root(ordinary_file_fixture()).unwrap()
  let initial = root.create_writer("mock-sync-original", 1L).unwrap()
  initial.append(b"a").unwrap()
  ignore(initial.seal_file("mock-sync.json").unwrap())
  initial.close_retaining_files().unwrap()
  let observed = root.observe_file("mock-sync.json").unwrap()
  let lock = root.acquire_lock("mock-sync.json.actql-write.lock").unwrap()
  let writer = root.create_writer("mock-sync-replacement", 1L).unwrap()
  writer.append(b"b").unwrap()
  test_fail_root_sync(root, 1)
  assert_true(writer.replace_observed_file(observed, lock) is Err(Write(_)))
  assert_false(writer.is_sealed())
  assert_true(writer.replace_observed_file(observed, lock) is Err(WriterClosed))
  writer.cancel().unwrap()
  assert_false(writer.cleanup_pending())
  let generation = root
    .inspect_file_generation("mock-sync.json")
    .unwrap()
    .unwrap()
  let reader = root
    .open_file_reader_with_custody("mock-sync.json", generation)
    .unwrap()
  assert_eq(reader.next(1).unwrap().bytes, b"b")
  reader.finish().unwrap()
  reader.close().unwrap()
  lock.close_checked().unwrap()
  root.close().unwrap()
}

///|
test "ordinary File keeps exact names beyond the internal object domain" {
  let root = open_root(ordinary_file_fixture()).unwrap()
  let names = [
    "answer with spaces.json", "結果😀.json", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.json",
  ]
  for index = 0; index < names.length(); index = index + 1 {
    let name = names[index]
    assert_true(root.inspect_generation(name) is Err(InvalidName))
    assert_eq(root.inspect_file_generation(name).unwrap(), None)
    let writer = root
      .create_writer("ordinary-stage-" + index.to_string(), 3L)
      .unwrap()
    writer.append(b"abc").unwrap()
    assert_true(writer.seal(name) is Err(InvalidName))
    let generation = writer.seal_file(name).unwrap()
    assert_eq(writer.seal_file(name).unwrap(), generation)
    assert_eq(root.inspect_file_generation(name).unwrap(), Some(generation))
    assert_true(root.verify_file_generation(name, generation))
    assert_false(root.verify_generation(name, generation))
    let wrong = { ..generation, size: 2L, }
    assert_false(root.verify_file_generation(name, wrong))
    guard root.open_file_reader_with_custody(name, wrong) is Err(failure) else {
      fail("ordinary Reader accepted a different original generation")
    }
    assert_true(failure.issue() is GenerationMismatch)
    failure.retry_cleanup().unwrap()
    failure.retry_cleanup().unwrap()
    let reader = root.open_file_reader_with_custody(name, generation).unwrap()
    writer.close_retaining_files().unwrap()
    assert_eq(reader.next(3).unwrap().bytes, b"abc")
    reader.finish().unwrap()
    reader.close().unwrap()
    assert_true(reader.next(1) is Err(ReaderClosed))
    assert_true(root.verify_file_generation(name, generation))
  }
  root.close().unwrap()
  root.close().unwrap()
}

///|
test "ordinary File refuses traversal NUL conflicts and symlinks" {
  let root = open_root(ordinary_file_fixture()).unwrap()
  let writer = root.create_writer("ordinary-invalid-stage", 1L).unwrap()
  writer.append(b"x").unwrap()
  let ownership = writer.ownership()
  let generation : NativeFileGeneration = {
    device: ownership.device,
    inode: ownership.inode,
    size: 1L,
  }
  for name in ["", ".", "..", "a/b", "/absolute", "a\u{0}b"] {
    assert_true(root.inspect_file_generation(name) is Err(InvalidName))
    assert_false(root.verify_file_generation(name, generation))
    assert_true(writer.seal_file(name) is Err(InvalidName))
    guard root.open_file_reader_with_custody(name, generation) is Err(failure) else {
      fail("ordinary Reader accepted an invalid basename")
    }
    assert_true(failure.issue() is InvalidName)
    failure.retry_cleanup().unwrap()
  }
  writer.cancel().unwrap()
  let first = root.create_writer("ordinary-conflict-first", 1L).unwrap()
  first.append(b"a").unwrap()
  let original = first.seal_file("conflict result.json").unwrap()
  first.close_retaining_files().unwrap()
  let second = root.create_writer("ordinary-conflict-second", 1L).unwrap()
  second.append(b"b").unwrap()
  assert_true(second.seal_file("conflict result.json") is Err(Conflict))
  assert_true(root.verify_file_generation("conflict result.json", original))
  second.cancel().unwrap()
  let reader = root
    .open_file_reader_with_custody("conflict result.json", original)
    .unwrap()
  assert_eq(reader.next(1).unwrap().bytes, b"a")
  reader.finish().unwrap()
  reader.close().unwrap()
  // The fresh fixture supplies a foreign symlink to an unchanged sentinel.
  assert_true(root.inspect_file_generation("foreign link.json") is Err(_))
  assert_false(root.verify_file_generation("foreign link.json", original))
  guard root.open_file_reader_with_custody("foreign link.json", original)
    is Err(failure) else {
    fail("ordinary Reader followed a foreign symlink")
  }
  failure.retry_cleanup().unwrap()
  let third = root.create_writer("ordinary-conflict-link", 1L).unwrap()
  third.append(b"c").unwrap()
  assert_true(third.seal_file("foreign link.json") is Err(Conflict))
  third.cancel().unwrap()
  root.close().unwrap()
}

///|
test "Mock replacement refuses same-inode writes after its original observation" {
  let root = open_root(ordinary_file_fixture()).unwrap()
  let initial = root.create_writer("mock-inplace-original", 3L).unwrap()
  initial.append(b"abc").unwrap()
  ignore(initial.seal_file("mock-inplace.json").unwrap())
  initial.close_retaining_files().unwrap()
  let observed = root.observe_file("mock-inplace.json").unwrap()
  let generation = observed.generation().unwrap()
  let name = @utf8.encode("mock-inplace.json")
  assert_true(stream_test_mutate(root, name, name.length(), 2))
  // The device/inode/size DATA still matches; full observation must refuse.
  assert_true(root.verify_file_generation("mock-inplace.json", generation))
  let writer = root.create_writer("mock-inplace-replacement", 3L).unwrap()
  writer.append(b"new").unwrap()
  let lock = root.acquire_lock("mock-inplace.json.actql-write.lock").unwrap()
  assert_true(
    writer.replace_observed_file(observed, lock) is Err(GenerationMismatch),
  )
  writer.cancel().unwrap()
  lock.close_checked().unwrap()
  root.close().unwrap()
}
