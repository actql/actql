// Real SQLite and receiver cleanup integration. The fixture's protocol Owner
// issues execution evidence; these cases do not establish an OS process stop
// or public Cloud cancellation acceptance.

///|
fn cancelled_receiver_cleanup(
  f : StoppedCleanupFixture,
  current : () -> Bool,
) -> Result[
  () -> Result[Unit, ResidentStoppedRetainedCleanupIssue],
  ResidentStoppedRetainedCleanupIssue,
] {
  prepare_resident_cancelled_receiver_cleanup(
    f.journal,
    f.site,
    f.delegation,
    f.cleanup_graph,
    f.consumer,
    f.intent,
    f.plan,
    f.receiver,
    f.root,
    {
      max_binding_bytes: 100000,
      max_chunks: 4,
      max_manifest_bytes: 4096,
      max_referenced_bytes: 1024L,
    },
    current,
  )
}

///|
test "saved cancelled receiver restores only the original producer graph without a consumer envelope" {
  let f = stopped_cleanup_fixture(
    "cancelled-receiver-saved",
    deliver_consumer=false,
    borrow_input=false,
  )
  f.journal.request_cancellation(f.consumer).unwrap() |> ignore
  let f = stopped_cleanup_reopen(f)
  let retry = prepare_resident_saved_cancelled_receiver_cleanup(
    f.journal,
    f.admission,
    f.recorded,
    f.site,
    f.delegation,
    f.consumer,
    f.intent,
    f.plan,
    f.receiver,
    f.root,
    {
      max_binding_bytes: 100000,
      max_chunks: 4,
      max_manifest_bytes: 4096,
      max_referenced_bytes: 1024L,
    },
    () => true,
  ).unwrap()
  retry().unwrap()
  retry().unwrap()
  assert_eq(f.receiver.destination_capacity_usage().unwrap().reserved_bytes, 0L)
  assert_eq(
    f.journal
    .dispatch_envelope(
      @remote.dispatch_request_attempt_identity(f.consumer).unwrap(),
    )
    .unwrap(),
    None,
  )
  assert_eq(f.journal.start_claimant(f.consumer).unwrap(), None)
  assert_true(f.journal.close())
  assert_true(f.receiver.close())
}

///|
test "cancelled undelivered receiver requires durable cancellation and current stop authority" {
  let f = stopped_cleanup_fixture(
    "cancelled-receiver-current",
    deliver_consumer=false,
    borrow_input=false,
  )
  assert_true(cancelled_receiver_cleanup(f, () => true) is Err(NotCurrent))
  f.journal.request_cancellation(f.consumer).unwrap() |> ignore
  assert_eq(
    @remote.dispatch_record_state_codes(f.journal.require(f.consumer).unwrap())[0],
    5,
  )
  assert_eq(
    @remote.dispatch_record_state_codes(f.journal.require(f.consumer).unwrap())[2],
    2,
  )
  assert_eq(
    f.journal
    .dispatch_envelope(
      @remote.dispatch_request_attempt_identity(f.consumer).unwrap(),
    )
    .unwrap(),
    None,
  )
  assert_true(cancelled_receiver_cleanup(f, () => false) is Err(NotCurrent))
  let changed_site = @site.create_site(
    @site.site_key(f.site),
    2,
    @remote.dispatch_request_execution_scope(f.producer)[2],
    4,
    4,
    1048576L,
    1048576L,
  ).unwrap()
  assert_true(
    cancelled_receiver_cleanup({ ..f, site: changed_site, }, () => true)
    is Err(NotCurrent),
  )
  assert_eq(
    f.receiver.destination_capacity_usage().unwrap().reserved_bytes,
    10L,
  )
  let current = Ref(true)
  let retry = cancelled_receiver_cleanup(f, () => current.val).unwrap()
  current.val = false
  assert_true(retry() is Err(NotCurrent))
  assert_eq(
    f.receiver.destination_capacity_usage().unwrap().reserved_bytes,
    10L,
  )
  current.val = true
  retry().unwrap()
  retry().unwrap()
  assert_eq(f.receiver.destination_capacity_usage().unwrap().reserved_bytes, 0L)
  assert_true(f.journal.close())
  assert_true(f.receiver.close())
}

///|
test "cancelled undelivered receiver retains capacity on cleanup failure and retries after reopen" {
  let f = stopped_cleanup_fixture(
    "cancelled-receiver-sync",
    deliver_consumer=false,
    borrow_input=false,
  )
  f.journal.request_cancellation(f.consumer).unwrap() |> ignore
  let f = stopped_cleanup_reopen(f)
  let original_revision = @remote.dispatch_record_revision(
    f.journal.require(f.consumer).unwrap(),
  )
  let retry = cancelled_receiver_cleanup(f, () => true).unwrap()
  cleanup_fail_root_sync(f.root, 1)
  assert_true(retry() is Err(Transfer(@transfer_client.Destination(_))))
  assert_eq(
    f.receiver.destination_capacity_usage().unwrap().reserved_bytes,
    10L,
  )
  assert_eq(
    f.receiver.destination_capacity_usage().unwrap().reserved_objects,
    1L,
  )
  let f = stopped_cleanup_reopen(f)
  cancelled_receiver_cleanup(f, () => true).unwrap()().unwrap()
  assert_eq(f.receiver.destination_capacity_usage().unwrap().reserved_bytes, 0L)
  assert_eq(
    f.receiver.destination_capacity_usage().unwrap().reserved_objects,
    0L,
  )
  assert_eq(
    @remote.dispatch_record_revision(f.journal.require(f.consumer).unwrap()),
    original_revision,
  )
  assert_true(f.journal.close())
  assert_true(f.receiver.close())
}

///|
test "cancelled undelivered receiver never returns another consumer reader" {
  let f = stopped_cleanup_fixture(
    "cancelled-receiver-reader",
    deliver_consumer=false,
    borrow_input=false,
  )
  f.journal.request_cancellation(f.consumer).unwrap() |> ignore
  f.receiver
  .acquire_destination_reader(f.transfer, f.receipt, "other-reader")
  .unwrap()
  |> ignore
  let retry = cancelled_receiver_cleanup(f, () => true).unwrap()
  assert_true(
    retry()
    is Err(Transfer(@transfer_client.Durable(@transfer_journal.MaterialInUse))),
  )
  assert_eq(
    f.receiver.destination_capacity_usage().unwrap().reserved_bytes,
    10L,
  )
  f.receiver
  .validate_destination_reader(f.transfer, f.receipt, "other-reader")
  .unwrap()
  f.receiver
  .release_destination_reader(f.transfer, f.receipt, "other-reader")
  .unwrap()
  |> ignore
  retry().unwrap()
  retry().unwrap()
  assert_eq(f.receiver.destination_capacity_usage().unwrap().reserved_bytes, 0L)
  assert_true(f.journal.close())
  assert_true(f.receiver.close())
}
