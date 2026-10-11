///|
fn owned_database_file(
  root : @filesystem.Root,
  name : String,
  body : Bytes,
) -> @filesystem.NativeFileOwnership {
  let writer = root.create_writer(name + ".stage", 4096L).unwrap()
  writer.append(body).unwrap()
  let original = writer.seal(name).unwrap()
  { device: original.device, inode: original.inode, }
}

///|
test "Native owned initialization preserves the exact claimed file and reopens retained values" {
  let (library, root, path) = existing_database_fixture()
  let ownership = owned_database_file(root, "owned-new.sqlite3", b"")
  let database = library
    .initialize_owned_database(path + "/owned-new.sqlite3", ownership, 1024L)
    .unwrap()
  database.insert("original", "request", b"e\xcc\x81\r\n").unwrap() |> ignore
  database.close_checked().unwrap()
  let retained = root.inspect_generation("owned-new.sqlite3").unwrap().unwrap()
  assert_eq(retained.device, ownership.device)
  assert_eq(retained.inode, ownership.inode)
  assert_true(
    library.initialize_owned_database(
      path + "/owned-new.sqlite3",
      ownership,
      1024L,
    )
    is Err(DatabaseOpen(_)),
  )
  let restored = library
    .open_existing_database(path + "/owned-new.sqlite3", 1024L)
    .unwrap()
  assert_eq(
    restored.read("original", "request").unwrap().body,
    b"e\xcc\x81\r\n",
  )
  restored.close_checked().unwrap()
}

///|
test "Native owned initialization refuses absent wrong-identity and nonempty files without repair" {
  let (library, root, path) = existing_database_fixture()
  let ownership = owned_database_file(root, "owned-claimed.sqlite3", b"")
  assert_true(
    library.initialize_owned_database(
      path + "/owned-absent.sqlite3",
      ownership,
      1024L,
    )
    is Err(DatabaseOpen(_)),
  )
  assert_eq(root.inspect_generation("owned-absent.sqlite3").unwrap(), None)
  let foreign = owned_database_file(root, "owned-foreign.sqlite3", b"")
  assert_true(foreign != ownership)
  let generation = root.inspect_generation("owned-foreign.sqlite3").unwrap()
  assert_true(
    library.initialize_owned_database(
      path + "/owned-foreign.sqlite3",
      ownership,
      1024L,
    )
    is Err(DatabaseOpen(_)),
  )
  assert_eq(
    root.inspect_generation("owned-foreign.sqlite3").unwrap(),
    generation,
  )
  assert_eq(root.inspect_generation("owned-foreign.sqlite3-wal").unwrap(), None)
  let nonempty = owned_database_file(
    root, "owned-nonempty.sqlite3", b"retained raw bytes",
  )
  let generation = root.inspect_generation("owned-nonempty.sqlite3").unwrap()
  assert_true(
    library.initialize_owned_database(
      path + "/owned-nonempty.sqlite3",
      nonempty,
      1024L,
    )
    is Err(DatabaseOpen(_)),
  )
  assert_eq(
    root.inspect_generation("owned-nonempty.sqlite3").unwrap(),
    generation,
  )
}
