///|
fn ordinary_file_fixture() -> String raise {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_ORDINARY_FILE_ROOT") is Some(path) else {
    fail("selected ordinary File cases require their own original Root")
  }
  path
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
