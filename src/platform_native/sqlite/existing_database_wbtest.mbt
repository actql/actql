///|
fn existing_database_fixture() -> (Library, @filesystem.Root, String) {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  (
    load_library(@env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap()).unwrap(),
    @filesystem.open_root(path).unwrap(),
    path,
  )
}

///|
#borrow(database)
extern "C" fn test_drop_capacity(database : Database) -> Bool = "actql_native_sqlite_test_drop_capacity"

///|
test "Native existing journal open refuses lost schema without repair" {
  let (library, _, path) = existing_database_fixture()
  let selected = path + "/existing-schema-lost.sqlite3"
  let original = library.open_database(selected, 1024L).unwrap()
  original.insert("original", "input", b"unchanged").unwrap() |> ignore
  assert_true(test_drop_capacity(original))
  original.close_checked().unwrap()
  assert_true(
    library.open_existing_database(selected, 1024L) is Err(DatabaseOpen(_)),
  )
  let inspection = library.open_inspection_database(selected, 1024L)
  assert_true(inspection.inspection_status() is Err(DatabaseOpen(_)))
  assert_eq(inspection.read("original", "input").unwrap().body, b"unchanged")
  inspection.close_checked().unwrap()
}

///|
test "Native existing journal open rejects nonabsolute URI and altered paths" {
  let (library, root, path) = existing_database_fixture()
  let selected = path + "/existing-paths.sqlite3"
  let original = library.open_database(selected, 1024L).unwrap()
  original.close_checked().unwrap()
  let generation = root.inspect_generation("existing-paths.sqlite3").unwrap()
  for
    invalid in [
      "existing-paths.sqlite3",
      ":memory:",
      "file:" + selected,
      selected + "\u{0000}ignored",
      "/" + "x".repeat(4096),
    ] {
    assert_true(
      library.open_existing_database(invalid, 1024L) is Err(DatabaseOpen(_)),
    )
  }
  assert_true(
    library.open_existing_database(selected, -1L) is Err(InvalidLimit),
  )
  assert_eq(
    root.inspect_generation("existing-paths.sqlite3").unwrap(),
    generation,
  )
}

///|
test "Native existing journal open never creates a missing database" {
  let (library, root, path) = existing_database_fixture()
  assert_eq(root.inspect_generation("existing-missing.sqlite3").unwrap(), None)
  assert_true(
    library.open_existing_database(path + "/existing-missing.sqlite3", 1024L)
    is Err(DatabaseOpen(_)),
  )
  assert_eq(root.inspect_generation("existing-missing.sqlite3").unwrap(), None)
}

///|
test "Native existing journal open does not initialize an empty file" {
  let (library, root, path) = existing_database_fixture()
  let writer = root.create_writer("existing-empty.stage", 0L).unwrap()
  let generation = writer.seal("existing-empty.sqlite3").unwrap()
  assert_true(
    library.open_existing_database(path + "/existing-empty.sqlite3", 1024L)
    is Err(DatabaseOpen(_)),
  )
  assert_eq(
    root.inspect_generation("existing-empty.sqlite3").unwrap(),
    Some(generation),
  )
  assert_eq(
    root.inspect_generation("existing-empty.sqlite3-wal").unwrap(),
    None,
  )
  assert_eq(
    root.inspect_generation("existing-empty.sqlite3-shm").unwrap(),
    None,
  )
}

///|
test "Native existing journal open preserves original values and reservations" {
  let (library, _, path) = existing_database_fixture()
  let selected = path + "/existing-retained.sqlite3"
  let first = library.open_database(selected, 1024L).unwrap()
  first.insert("original", "input", b"e\xcc\x81\r\n").unwrap() |> ignore
  assert_true(
    first.reserve_capacity("original", "holding", 7L, 1L, 32L, 2L).unwrap(),
  )
  first.close_checked().unwrap()
  let restored = library.open_existing_database(selected, 1024L).unwrap()
  assert_eq(restored.read("original", "input").unwrap().body, b"e\xcc\x81\r\n")
  assert_eq(restored.capacity_usage("original").unwrap().reserved_bytes, 7L)
  assert_eq(restored.capacity_usage("original").unwrap().reserved_objects, 1L)
  assert_eq(
    restored.compare_exchange("original", "input", 0L, b"retained").unwrap(),
    1L,
  )
  restored.close_checked().unwrap()
  let observed = library.open_inspection_database(selected, 1024L)
  observed.inspection_status().unwrap()
  assert_eq(observed.read("original", "input").unwrap().body, b"retained")
  observed.close_checked().unwrap()
}
