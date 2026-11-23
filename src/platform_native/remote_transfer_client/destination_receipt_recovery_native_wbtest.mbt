///|
test "Native direct destination resumes after its receipt was already committed" {
  let library = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap() +
    "/direct-destination-receipt-recovery.sqlite3"
  let store = @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT").unwrap()
  let root = @filesystem.open_root(store).unwrap()
  let request = native_transfer_request_for(
    [b"original-alpha", b"original-beta"],
    @transfer.DirectStream,
    "direct-destination-receipt-recovery",
  )
  let journal = @journal.open_journal(library, path, 1048576L, 8, 4096, 1024L).unwrap()
  admit_durable_direct_destination(journal, request, 1024L, 8L).unwrap()
  |> ignore
  let generations = [
    write_durable_direct_destination_chunk(
      journal, root, request, 0, b"original-alpha",
    ).unwrap(),
    write_durable_direct_destination_chunk(
      journal, root, request, 1, b"original-beta",
    ).unwrap(),
  ]
  root.sync_directory().unwrap()
  let original = journal.require(request).unwrap()
  assert_eq(
    @transfer.direct_transfer_progress(original),
    @transfer.DirectTransferCopying,
  )
  let revision = @transfer.record_revision(original)
  let held = journal.destination_capacity_usage().unwrap()
  assert_eq(held.reserved_bytes, 27L)
  assert_eq(held.reserved_objects, 2L)
  let receipt = @transfer.prepare_destination_receipt(
    request,
    destination_material_generation(request, generations).unwrap(),
  ).unwrap()
  // Keep the durable boundary a lost receipt reply leaves behind: the receipt
  // is committed, and the enclosing Transfer has not yet advanced.
  journal.commit_destination_receipt(receipt, request).unwrap() |> ignore
  assert_true(journal.close())
  root.close().unwrap()

  let key = @transfer.request_journal_identity(request).unwrap()
  let verify = library.open_database(path, 1048576L).unwrap()
  let prior = verify.read("remote_transfer_destination_receipt", key).unwrap()
  assert_eq(prior.revision, 0L)
  let reopened = @journal.open_journal(library, path, 1048576L, 8, 4096, 1024L).unwrap()
  let root = @filesystem.open_root(store).unwrap()
  assert_eq(
    @transfer.record_revision(reopened.require(request).unwrap()),
    revision,
  )
  let resumed = commit_durable_direct_destination(reopened, root, request).unwrap()
  assert_true(@transfer.record_is_destination_committed(resumed))
  assert_eq(@transfer.record_revision(resumed), revision + 2)
  let again = commit_durable_direct_destination(reopened, root, request).unwrap()
  assert_eq(@transfer.record_revision(again), revision + 2)
  let after = verify.read("remote_transfer_destination_receipt", key).unwrap()
  assert_eq(after.revision, prior.revision)
  assert_eq(after.body, prior.body)
  let still_held = reopened.destination_capacity_usage().unwrap()
  assert_eq(still_held.reserved_bytes, held.reserved_bytes)
  assert_eq(still_held.reserved_objects, held.reserved_objects)
  for index, generation in generations {
    let name = destination_object_name(request, index).unwrap()
    assert_eq(root.inspect_generation(name).unwrap(), Some(generation))
  }
  assert_true(reopened.close())
  root.close().unwrap()
  verify.close_checked().unwrap()
}
