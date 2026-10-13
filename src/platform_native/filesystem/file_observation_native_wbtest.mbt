///|
#borrow(root, name)
extern "C" fn test_observation_mutation(root : Root, name : Bytes, length : Int, kind : Int) -> Bool = "actql_native_filesystem_test_observation_mutation"

///|
fn observed_fixture_path(name : String) -> String raise {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_FILE_OBSERVATION_ROOT") is Some(path) else {
    fail("selected observation case requires its owned fixture Root")
  }
  path + "/" + name
}

///|
test "file observation keeps original mode generation and same Reader" {
  let root = open_root(observed_fixture_path("exact")).unwrap()
  let original = root.observe_file("file").unwrap()
  assert_eq(original.mode().unwrap(), 0o644)
  assert_eq(original.generation().unwrap().size, 3L)
  original.check_current().unwrap()
  let reader = original.open_reader_with_custody().unwrap()
  assert_eq(reader.next(3).unwrap().bytes, b"abc")
  original.check_reader(reader).unwrap()
  reader.finish().unwrap()
  original.check_current().unwrap()
  root.close().unwrap()
  assert_true(original.check_current() is Err(GenerationMismatch))
}

///|
test "observed file refuses mode change and same size overwrite" {
  for (name, kind) in [("mode", 1), ("overwrite", 2)] {
    let root = open_root(observed_fixture_path(name)).unwrap()
    let original = root.observe_file("file").unwrap()
    assert_true(test_observation_mutation(root, b"file", 4, kind))
    assert_eq(root.inspect_generation("file").unwrap().unwrap(), original.generation().unwrap())
    assert_true(original.check_current() is Err(GenerationMismatch))
    guard original.open_reader_with_custody() is Err(failure) else {
      fail("changed observation admitted a Reader")
    }
    assert_true(failure.issue() is GenerationMismatch)
    failure.retry_cleanup().unwrap()
    root.close().unwrap()
  }
}

///|
test "file observation refuses missing symlink and directory names" {
  for name in ["missing", "symlink", "directory"] {
    let root = open_root(observed_fixture_path(name)).unwrap()
    assert_true(root.observe_file("file") is Err(GenerationMismatch))
    root.close().unwrap()
  }
}

///|
test "observed Reader cannot be borrowed from another same path Root" {
  let root = open_root(observed_fixture_path("exact")).unwrap()
  let other = open_root(observed_fixture_path("exact")).unwrap()
  let original = root.observe_file("file").unwrap()
  let foreign = other.open_reader("file", original.generation().unwrap()).unwrap()
  assert_true(original.check_reader(foreign) is Err(GenerationMismatch))
  foreign.close().unwrap()
  root.close().unwrap()
  other.close().unwrap()
}
