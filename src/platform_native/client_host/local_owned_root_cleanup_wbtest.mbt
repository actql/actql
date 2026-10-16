///|
#borrow(database)
extern "C" fn local_owned_roots_checked_close_count(
  database : @sqlite.Database,
) -> Int = "actql_native_sqlite_test_checked_close_count"

///|
#borrow(root)
extern "C" fn local_owned_roots_fail_census_close(
  root : @filesystem.Root,
  failures : Int,
) -> Unit = "actql_native_filesystem_test_fail_census_close"

///|
test "installed owned Root descriptor cleanup extends the existing Host close without new work" {
  let host = local_journal_test_connection("local-owned-root-close")
  host.close().unwrap()
  // Existing close acknowledges the journal/session, not these directory fds.
  host.session.parent.private_ownership().unwrap() |> ignore
  host.session.source_root.private_ownership().unwrap() |> ignore
  host.session.root.private_ownership().unwrap() |> ignore
  let before = local_owned_roots_checked_close_count(host.database)
  host.close_owned_root_descriptors().unwrap()
  assert_true(host.session.parent.private_ownership() is Err(_))
  assert_true(host.session.source_root.private_ownership() is Err(_))
  assert_true(host.session.root.private_ownership() is Err(_))
  assert_true(host.configuration() is Err(Closed))
  host.close_owned_root_descriptors().unwrap()
  assert_eq(local_owned_roots_checked_close_count(host.database), before)
}

///|
test "installed owned Root cleanup closes equal path distinct originals without closing a borrowed Root" {
  let (path, name, borrowed, _) = local_selected_source(
    "local-owned-root-managed",
  )
  let host = begin_native_local_host_adoption(
      path,
      "local-owned-root-managed.host",
      path,
      name,
      "operator",
      epoch_test_crypto(),
      managed_root_path=Some(path),
    )
    .unwrap()
    .open_journal(
      local_journal_test_library(),
      epoch_test_crypto(),
      100.0,
      8,
      8388608L,
    )
    .unwrap()
  let managed = host.session.settings.managed.unwrap().root
  assert_false(physical_equal(managed, borrowed))
  assert_false(physical_equal(host.session.source_root, host.session.parent))
  assert_eq(
    managed.private_ownership().unwrap(),
    borrowed.private_ownership().unwrap(),
  )
  host.close_owned_root_descriptors().unwrap()
  assert_true(managed.private_ownership() is Err(_))
  assert_true(host.session.parent.private_ownership() is Err(_))
  assert_true(host.session.source_root.private_ownership() is Err(_))
  assert_true(host.session.root.private_ownership() is Err(_))
  // Same ownership DATA never authorizes closing another opened descriptor.
  borrowed.private_ownership().unwrap() |> ignore
  borrowed.close().unwrap()
}

///|
test "installed owned Root cleanup retains every Root until original DB cleanup succeeds" {
  let host = local_journal_test_connection("local-owned-root-db-pending")
  local_test_fail_close(host.database, 1)
  assert_true(host.close_owned_root_descriptors() is Err(Physical(_)))
  assert_false(host.database_closed)
  assert_false(host.session_closed)
  assert_true(host.configuration() is Err(Closed))
  host.session.parent.private_ownership().unwrap() |> ignore
  host.session.source_root.private_ownership().unwrap() |> ignore
  host.session.root.private_ownership().unwrap() |> ignore
  host.close_owned_root_descriptors().unwrap()
  let acknowledged = local_owned_roots_checked_close_count(host.database)
  host.close_owned_root_descriptors().unwrap()
  assert_eq(local_owned_roots_checked_close_count(host.database), acknowledged)
}

///|
test "installed owned Root cleanup preserves the same sticky Unknown and does not close later Roots" {
  let host = local_journal_test_connection("local-owned-root-unknown")
  let source = host.session.source_root
  local_owned_roots_fail_census_close(source, 1)
  assert_true(source.check_directory_members([]) is Err(@filesystem.Cleanup(_)))
  assert_true(
    host.close_owned_root_descriptors()
    is Err(Filesystem(@filesystem.Cleanup(_))),
  )
  assert_true(host.database_closed && host.session_closed)
  assert_true(physical_equal(host.session.source_root, source))
  assert_true(host.session.root.private_ownership() is Err(_))
  // No fall-through to another descriptor or reinterpretation as cleanup ACK.
  host.session.parent.private_ownership().unwrap() |> ignore
  assert_true(
    host.close_owned_root_descriptors()
    is Err(Filesystem(@filesystem.Cleanup(_))),
  )
  assert_true(physical_equal(host.session.source_root, source))
  host.session.parent.private_ownership().unwrap() |> ignore
  // Separate test-owned parent descriptor retirement is not the failed Root's ACK.
  host.session.parent.close().unwrap()
}

///|
test "installed owned Root descriptor ACK does not retire an already borrowed Reader" {
  let host = local_journal_test_connection("local-owned-root-reader")
  let reader = host.session.source_root
    .open_reader(host.session.source_name, host.session.source_generation)
    .unwrap()
  host.close_owned_root_descriptors().unwrap()
  // Reader owns its separate opened fd and cleanup. Directory close cannot
  // supply its stop or acknowledge the surrounding read-context/loan lifetime.
  let chunk = reader.next(1).unwrap()
  assert_eq(chunk.bytes, b"{")
  reader.close().unwrap()
  host.close_owned_root_descriptors().unwrap()
}
