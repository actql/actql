///|
test "Journal selection refuses a stock Library before empty-file initialization" {
  let (library, root, path) = existing_database_fixture()
  let name = "journal-no-stock.sqlite3"
  let original = owned_database_file(root, name, b"")
  let failure = match
    library.initialize_owned_journal_database_with_custody(
      path + "/" + name,
      original,
      1024L,
    ) {
    Ok(_) => {
      fail("A stock Library supplied the selected Journal component")
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
test "Journal refusal leaves the explicit generic existing route unchanged" {
  let (library, root, path) = existing_database_fixture()
  let name = "generic-before-journal.sqlite3"
  let original = owned_database_file(root, name, b"")
  let database = library
    .initialize_owned_database_with_custody(path + "/" + name, original, 1024L)
    .unwrap()
  database.insert("original", "key", b"retained").unwrap() |> ignore
  database.close_checked().unwrap()
  let failure = match
    library.open_existing_journal_database_with_custody(
      path + "/" + name,
      1024L,
    ) {
    Ok(_) => {
      fail("Journal selection fell back to the generic Library")
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
