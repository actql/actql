///|
test "selected Local Store refuses stock Library before creating schema" {
  let (library, root, path) = existing_database_fixture()
  let name = "local-store-no-stock.sqlite3"
  let original = owned_database_file(root, name, b"")
  let failure = match
    library.open_local_store_database_with_custody(path + "/" + name, 1024L) {
    Ok(_) => {
      fail("stock Library supplied selected Local Store facility")
      return
    }
    Err(value) => value
  }
  assert_true(failure.issue() is DatabaseOpen(_))
  failure.retry_cleanup().unwrap()
  let current = root.inspect_generation(name).unwrap().unwrap()
  assert_eq(current.size, 0L)
  assert_eq(current.device, original.device)
  assert_eq(current.inode, original.inode)
  root.close().unwrap()
}

///|
test "selected Store restore refuses stock while generic existing data remains exact" {
  let (library, root, path) = existing_database_fixture()
  let name = "local-store-generic-retained.sqlite3"
  let original = owned_database_file(root, name, b"")
  let database = library
    .initialize_owned_database_with_custody(path + "/" + name, original, 1024L)
    .unwrap()
  database.insert("original", "key", b"retained").unwrap() |> ignore
  database.close_checked().unwrap()
  let failure = match
    library.open_existing_local_store_database_with_custody(
      path + "/" + name,
      1024L,
    ) {
    Ok(_) => {
      fail("selected Store fell back to stock SQLite")
      return
    }
    Err(value) => value
  }
  failure.retry_cleanup().unwrap()
  let reopened = library
    .open_existing_database(path + "/" + name, 1024L)
    .unwrap()
  assert_eq(reopened.read("original", "key").unwrap().body, b"retained")
  reopened.close_checked().unwrap()
  root.close().unwrap()
}
