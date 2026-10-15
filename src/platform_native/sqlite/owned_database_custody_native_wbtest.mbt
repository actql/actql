///|
test "owned initialization custody preserves original file schema and binary CAS rows" {
  let (library, root, path) = existing_database_fixture()
  let name = "owned-custody-original.sqlite3"
  let original = owned_database_file(root, name, b"")
  let database = match
    library.initialize_owned_database_with_custody(
      path + "/" + name,
      original,
      1024L,
    ) {
    Ok(database) => database
    Err(failure) => {
      match failure.issue() {
        DatabaseOpen(message) =>
          fail("original owned initialization: " + message)
        _ => fail("original owned initialization rejected before DatabaseOpen")
      }
      return
    }
  }
  assert_eq(database.insert("原本", "e\u0301", b"\x00\xff\r\n").unwrap(), 0L)
  assert_eq(
    database.compare_exchange("原本", "e\u0301", 0L, b"second").unwrap(),
    1L,
  )
  database.close_checked().unwrap()
  let restored = library
    .open_existing_database_with_custody(path + "/" + name, 1024L)
    .unwrap()
  let retained = restored.read("原本", "e\u0301").unwrap()
  assert_eq(retained.revision, 1L)
  assert_eq(retained.body, b"second")
  restored.close_checked().unwrap()
  let generation = root.inspect_generation(name).unwrap().unwrap()
  assert_eq(generation.device, original.device)
  assert_eq(generation.inode, original.inode)
  root.close().unwrap()
}

///|
test "owned initialization failure keeps exact partial handle without schema repair" {
  let (library, root, path) = existing_database_fixture()
  let original = owned_database_file(root, "owned-custody-source.sqlite3", b"")
  let foreign = owned_database_file(
    root, "owned-custody-foreign.sqlite3", b"retained raw bytes",
  )
  let before = root.inspect_generation("owned-custody-foreign.sqlite3").unwrap()
  let failure = match
    library.initialize_owned_database_with_custody(
      path + "/owned-custody-foreign.sqlite3",
      original,
      1024L,
    ) {
    Err(failure) => failure
    Ok(_) => {
      fail("Foreign nonempty file was initialized")
      return
    }
  }
  assert_true(failure.issue() is DatabaseOpen(_))
  let handle = failure.database.unwrap()
  // Identity rejection happens before SQLite open: there is no acquired
  // sqlite3* to inject close failure into. Data cleanup is still explicit.
  failure.retry_cleanup().unwrap()
  assert_true(failure.database is None)
  assert_true(failure.issue() is DatabaseOpen(_))
  assert_eq(open_cleanup_close_count(handle), 0)
  failure.retry_cleanup().unwrap()
  assert_eq(open_cleanup_close_count(handle), 0)
  assert_eq(
    root.inspect_generation("owned-custody-foreign.sqlite3").unwrap(),
    before,
  )
  assert_eq(before.unwrap().device, foreign.device)
  assert_eq(before.unwrap().inode, foreign.inode)
  assert_eq(
    root.inspect_generation("owned-custody-foreign.sqlite3-wal").unwrap(),
    None,
  )
  root.close().unwrap()
}

///|
test "owned initialized handle retains same failed-open cleanup across injected close refusal" {
  let (library, root, path) = existing_database_fixture()
  let name = "owned-custody-cleanup.sqlite3"
  let ownership = owned_database_file(root, name, b"")
  let database = library
    .initialize_owned_database_with_custody(path + "/" + name, ownership, 1024L)
    .unwrap()
  database.insert("original", "input", b"retained").unwrap() |> ignore
  // Inject on the actual handle created by the owned initialization path.
  // Two failures leave one pending after the existing failed-open attempt.
  fail_open_close(database, 2)
  fail_open_cleanup(database)
  let failure = match sqlite_open_result_with_custody(database) {
    Err(failure) => failure
    Ok(_) => {
      fail("Failed-open initialized handle became usable")
      return
    }
  }
  assert_true(
    failure.database is Some(value) && physical_equal(value, database),
  )
  assert_true(failure.retry_cleanup() is Err(Physical(_)))
  assert_true(
    failure.database is Some(value) && physical_equal(value, database),
  )
  failure.retry_cleanup().unwrap()
  assert_true(failure.database is None)
  assert_eq(open_cleanup_close_count(database), 2)
  failure.retry_cleanup().unwrap()
  assert_eq(open_cleanup_close_count(database), 2)
  assert_true(
    failure.issue() is DatabaseOpen("injected original database open failure"),
  )
  let retained = library
    .open_existing_database_with_custody(path + "/" + name, 1024L)
    .unwrap()
  assert_eq(retained.read("original", "input").unwrap().body, b"retained")
  retained.close_checked().unwrap()
  root.close().unwrap()
}

///|
test "owned initialization invalid limit and missing file never create a database" {
  let (library, root, path) = existing_database_fixture()
  let original = owned_database_file(root, "owned-custody-limit.sqlite3", b"")
  let failure = match
    library.initialize_owned_database_with_custody(
      path + "/owned-custody-limit.sqlite3",
      original,
      -1L,
    ) {
    Err(failure) => failure
    Ok(_) => {
      fail("Invalid limit initialized a database")
      return
    }
  }
  assert_true(failure.issue() is InvalidLimit)
  assert_true(failure.database is None)
  failure.retry_cleanup().unwrap()
  assert_eq(
    root.inspect_generation("owned-custody-limit.sqlite3").unwrap().unwrap().size,
    0L,
  )
  let missing = match
    library.initialize_owned_database_with_custody(
      path + "/owned-custody-absent.sqlite3",
      original,
      1024L,
    ) {
    Err(failure) => failure
    Ok(_) => {
      fail("Missing file was created")
      return
    }
  }
  missing.retry_cleanup().unwrap()
  assert_eq(
    root.inspect_generation("owned-custody-absent.sqlite3").unwrap(),
    None,
  )
  root.close().unwrap()
}
