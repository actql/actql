///|
fn bounded_root_custody_fixture() -> String raise {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_BOUNDED_FILES_ROOT") is Some(root) &&
    root.has_prefix("/") else {
    fail("mandatory fresh bounded-file Root fixture missing")
  }
  root
}

///|
test "failed bounded Root constructor retains the same Owner through cleanup" {
  let path = bounded_root_custody_fixture() + "/missing-root"
  let failure = match
    read_bounded_text_file_with_custody(
      path,
      "value",
      32L,
      diagnostic_ceiling=Some(8),
    ) {
    Err(value) => value
    Ok(_) => fail("missing Root admitted")
  }
  assert_true(failure.issue() is Filesystem(@filesystem.RootOpen(_)))
  assert_true(failure.root is None)
  assert_true(failure.reader is None)
  assert_true(failure.rejected_reader is None)
  assert_true(failure.rejected_root is Some(_))
  let original = failure.rejected_root.unwrap()
  assert_true(original.issue() is @filesystem.RootOpen(_))
  failure.retry_cleanup().unwrap()
  assert_true(failure.rejected_root is None)
  failure.retry_cleanup().unwrap()
  assert_true(failure.issue() is Filesystem(@filesystem.RootOpen(_)))
}

///|
test "bounded Root cleanup does not reacquire a later available input" {
  let parent_path = bounded_root_custody_fixture()
  let name = "late-root"
  let path = parent_path + "/" + name
  let failure = match read_bounded_text_file_with_custody(path, "value", 32L) {
    Err(value) => value
    Ok(_) => fail("missing original Root admitted")
  }
  assert_true(failure.rejected_root is Some(_))
  let parent = @filesystem.open_root(parent_path).unwrap()
  let directory = parent.create_directory(name).unwrap()
  let child = parent.open_child(name).unwrap()
  let writer = child.create_writer("stage", 5L).unwrap()
  writer.append(b"later").unwrap()
  let generation = writer.seal("value").unwrap()
  // The original failure is not replaced by a read from the new directory.
  failure.retry_cleanup().unwrap()
  failure.retry_cleanup().unwrap()
  assert_true(failure.rejected_root is None)
  assert_true(failure.issue() is Filesystem(@filesystem.RootOpen(_)))
  assert_eq(child.inspect_generation("value").unwrap(), Some(generation))
  writer.cancel().unwrap()
  child.close().unwrap()
  assert_true(parent.remove_directory(name, directory).unwrap())
  parent.close().unwrap()
}

///|
test "normal bounded UTF8 read remains unchanged after Root custody connection" {
  let path = bounded_root_custody_fixture()
  let root = @filesystem.open_root(path).unwrap()
  let writer = root.create_writer("normal-stage", 5L).unwrap()
  writer.append(b"hello").unwrap()
  writer.seal("normal-value").unwrap() |> ignore
  assert_eq(
    read_bounded_text_file_with_custody(
      path,
      "normal-value",
      5L,
      diagnostic_ceiling=Some(8),
    ).unwrap(),
    "hello",
  )
  writer.cancel().unwrap()
  root.close().unwrap()
}
