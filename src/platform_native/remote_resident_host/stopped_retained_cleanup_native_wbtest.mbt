// Physical journal/receiver integration fixtures. Completion is issued by the
// shared protocol Owner; these tests do not claim Source/Compute execution or
// an OS process stop. The production CLI supplies the real exclusive slot.

///|
#borrow(root)
extern "C" fn cleanup_fail_root_sync(
  root : @filesystem.Root,
  failures : Int,
) -> Unit = "actql_native_filesystem_test_fail_root_sync"

///|
struct StoppedCleanupFixture {
  journal : @journal.Journal
  receiver : @transfer_journal.Journal
  root : @filesystem.Root
  sqlite : @sqlite.Library
  journal_path : String
  receiver_path : String
  site : @site.ExecutionSite
  delegation : @resident.ResidentSiteDelegation
  producer : @remote.DispatchRequest
  consumer : @remote.DispatchRequest
  transfer : @transfer.RemoteTransferRequest
  receipt : @transfer.RemoteTransferDestinationReceipt
}

///|
fn cleanup_cid(fill : String) -> String {
  "sha256:" + fill.repeat(64)
}

///|
fn cleanup_complete(
  journal : @journal.Journal,
  site : @site.ExecutionSite,
  request : @remote.DispatchRequest,
  manifest : @cleanup_manifest.PhysicalManifest,
) -> (
  @remote.DispatchRecord,
  @remote.RemoteExecutionEvidence,
  @remote.RemoteManagedOutputSubject,
) {
  let scope = @remote.dispatch_request_execution_scope(request)
  let record = journal.accept(request).unwrap().1
  let capability = @remote.register_remote_execution_capability(
    site,
    scope[2],
    scope[3],
    scope[4],
    scope[5],
    scope[6],
  ).unwrap()
  journal
  .commit_transition(
    @remote.prepare_begin_provisioning(record, capability).unwrap(),
  )
  .unwrap()
  journal
  .commit_transition(@remote.prepare_begin_remote_execution(record).unwrap())
  .unwrap()
  journal
  .commit_transition(@remote.prepare_confirm_native_settled(record).unwrap())
  .unwrap()
  let generation = "original-completed-material"
  let holding = @remote.remote_output_holding_evidence_cid(
    request,
    generation,
    manifest.referenced_bytes,
  ).unwrap()
  journal
  .commit_transition(
    @remote.prepare_retain_remote_output(record, generation, holding).unwrap(),
  )
  .unwrap()
  let measurement = @remote.prepare_remote_managed_output_measurement(
    1,
    0,
    0,
    0,
    [1],
    [1],
    [1],
    [1],
    [0],
    [1],
  ).unwrap()
  let subject = @remote.prepare_remote_managed_output_subject(
    @remote.dispatch_request_identity(request),
    generation,
    holding,
    cleanup_cid("6"),
    manifest.schema_contract_cid,
    manifest.view_contract_cid,
    manifest.codec_contract_cid,
    @cleanup_manifest.manifest_cid(manifest),
    @remote.remote_managed_output_measurement_cid(measurement),
    manifest.row_count,
    manifest.referenced_bytes,
  ).unwrap()
  let issuer = @remote.register_remote_evidence_issuer(
    site,
    scope[2],
    scope[3],
    scope[4],
    scope[5],
    @remote.remote_managed_output_evidence_kind(),
    scope[7],
  ).unwrap()
  let evidence = @remote.issue_remote_managed_output_evidence(
    issuer, record, subject,
  ).unwrap()
  journal
  .commit_evidence_transition(
    @remote.prepare_durable_execution_evidence(record, evidence).unwrap(),
    evidence,
    subject,
    measurement,
  )
  .unwrap()
  (record, evidence, subject)
}

///|
fn stopped_cleanup_fixture(name : String) -> StoppedCleanupFixture {
  let sqlite_path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap_or_else(() => {
      abort("SQLite required")
    },
  )
  let parent = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap_or_else(() => {
      abort("private SQLite root required")
    },
  )
  let files = @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT").unwrap_or_else(() => {
    abort("private receiver Root required")
  })
  let sqlite = @sqlite.load_library(sqlite_path).unwrap()
  let (admission, producer, wire, producer_binding, _) = resident_source_dispatch_fixture()
  let materials = rebuild_materials(admission, producer, wire).unwrap()
  guard materials.compilation is @host.Tasks(compilation) else {
    abort("checked two-task compilation required")
  }
  let edge = @host.prepare_client_retained_input_edge(
    materials.prepared,
    compilation,
    materials.admission,
    materials.run_definition,
    1,
    0,
  ).unwrap()
  let scope = @remote.dispatch_request_execution_scope(producer)
  let authority = @remote.dispatch_request_journal_key(producer)[0]
  let site = @site.create_site(scope[0], 1, scope[2], 4, 4, 1048576L, 1048576L).unwrap()
  let stem = parent + "/" + name + "-" + @env.now().to_string()
  let journal_path = stem + ".site.sqlite3"
  let receiver_path = stem + ".transfer.sqlite3"
  let journal = @journal.open_journal(
    sqlite,
    journal_path,
    1048576L,
    @remote.create_site_dispatch_journal(site, "actql-remote-site/0.1").unwrap(),
  ).unwrap()
  journal
  .retain_dispatch_envelope(
    producer,
    @remote.remote_poll_dispatch_materials_json(
      producer, producer_binding, wire,
    ).unwrap(),
  )
  .unwrap()
  let chunk = b"[{\"id\":3}]"
  let manifest = @cleanup_manifest.admit(
    "actql-managed-physical-manifest/0.1",
    @host.client_retained_input_edge_schema_cid(edge),
    cleanup_cid("7"),
    cleanup_cid("8"),
    1,
    ["sha256:" + @cleanup_sha.hex(chunk)],
    [chunk.length().to_int64()],
    [1],
    4,
    4096,
    1024L,
  ).unwrap()
  let (record, evidence, subject) = cleanup_complete(
    journal, site, producer, manifest,
  )
  let producer_owner = @host.prepare_client_retained_input_producer(
    edge, record, evidence, subject,
  ).unwrap()
  let transfer = @transfer.prepare_request(
    authority,
    name,
    @transfer.DirectStream,
    scope[0],
    1,
    scope[0],
    1,
    @remote.remote_managed_output_subject_projection(subject)[1],
    manifest,
    manifest.referenced_bytes,
    4102444800000L,
    cleanup_cid("a"),
    cleanup_cid("b"),
    cleanup_cid("c"),
  ).unwrap()
  let receiver = @transfer_journal.open_journal(
    sqlite, receiver_path, 1048576L, 4, 4096, 1024L,
  ).unwrap()
  let root = @filesystem.open_root(files).unwrap()
  @transfer_client.admit_durable_direct_destination(
    receiver, transfer, 1024L, 4L,
  ).unwrap()
  |> ignore
  @transfer_client.write_durable_direct_destination_chunk(
    receiver, root, transfer, 0, chunk,
  ).unwrap()
  |> ignore
  let committed = @transfer_client.commit_durable_direct_destination(
    receiver, root, transfer,
  ).unwrap()
  let receipt = receiver.inspect_destination_receipt(transfer).unwrap().unwrap()
  let current = @host.install_client_retained_input_owner_current(
    (key, generation, bundle) => {
      key == scope[0] && generation == "1" && bundle == scope[2]
    },
    () => authority,
    () => 1791200000000L,
    (_, _) => true,
  )
  let input = @host.prepare_client_retained_task_input(
    producer_owner, committed, receipt, "direct-destination", current, 100000,
  ).unwrap()
  let caller = @host.prepare_source_free_client_request_identity(
    materials.prepared,
    authority,
    "original-caller",
  ).unwrap()
  let consumer = @host.prepare_client_retained_task_dispatch(
    materials.prepared,
    compilation,
    materials.admission,
    materials.run_definition,
    caller,
    1,
    1,
    "original-consumer",
    {
      site_key: scope[0],
      site_generation: 1,
      runtime_bundle_cid: scope[2],
      connector_registration: scope[3],
      connector_revision: scope[4],
      strategy_revision: scope[5],
      obligations_cid: cleanup_cid("2"),
      budget_cid: @remote.dispatch_request_budget_cid(producer),
      grant_cid: scope[6],
      evidence_issuer_capability_cid: scope[7],
    },
    input,
    current,
  ).unwrap()
  journal
  .retain_dispatch_envelope(
    consumer,
    @remote.remote_poll_dispatch_materials_json(
      consumer,
      @host.client_retained_task_input_binding(input),
      wire,
    ).unwrap(),
  )
  .unwrap()
  cleanup_complete(journal, site, consumer, manifest) |> ignore
  receiver
  .acquire_destination_reader(
    transfer,
    receipt,
    @remote.dispatch_request_identity(consumer),
  )
  .unwrap()
  |> ignore
  {
    journal,
    receiver,
    root,
    sqlite,
    journal_path,
    receiver_path,
    site,
    delegation: {
      coordinator_authority: authority,
      site_key: scope[0],
      runtime_bundle_cid: scope[2],
      connector_registration: scope[3],
      connector_revision: scope[4],
      strategy_revision: scope[5],
      grant_cid: scope[6],
      evidence_issuer_capability_cid: scope[7],
      budget_cids: [@remote.dispatch_request_budget_cid(producer)],
    },
    producer,
    consumer,
    transfer,
    receipt,
  }
}

///|
fn stopped_cleanup_apply(
  f : StoppedCleanupFixture,
  current : () -> Bool,
) -> Result[Unit, ResidentStoppedRetainedCleanupIssue] {
  reclaim_stopped_resident_retained_input(
    f.journal,
    f.site,
    f.delegation,
    @remote.dispatch_request_attempt_identity(f.producer).unwrap(),
    @remote.dispatch_request_attempt_identity(f.consumer).unwrap(),
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
fn stopped_cleanup_reopen(
  f : StoppedCleanupFixture,
) -> StoppedCleanupFixture raise {
  assert_true(f.journal.close())
  assert_true(f.receiver.close())
  {
    ..f,
    journal: @journal.open_journal(
      f.sqlite,
      f.journal_path,
      1048576L,
      @remote.create_site_dispatch_journal(f.site, "actql-remote-site/0.1").unwrap(),
    ).unwrap(),
    receiver: @transfer_journal.open_journal(
      f.sqlite,
      f.receiver_path,
      1048576L,
      4,
      4096,
      1024L,
    ).unwrap(),
  }
}

///|
test "stopped retained cleanup keeps borrow before confirmed stop and retries after reopen" {
  let f = stopped_cleanup_fixture("stop-before-return")
  assert_true(stopped_cleanup_apply(f, () => false) is Err(NotCurrent))
  f.receiver
  .validate_destination_reader(
    f.transfer,
    f.receipt,
    @remote.dispatch_request_identity(f.consumer),
  )
  .unwrap()
  assert_eq(
    f.receiver.destination_capacity_usage().unwrap().reserved_bytes,
    10L,
  )
  let f = stopped_cleanup_reopen(f)
  stopped_cleanup_apply(f, () => true).unwrap()
  assert_eq(f.receiver.destination_capacity_usage().unwrap().reserved_bytes, 0L)
  assert_eq(
    f.receiver.destination_capacity_usage().unwrap().reserved_objects,
    0L,
  )
  stopped_cleanup_apply(f, () => true).unwrap()
  // Physical receiver cleanup alone never fabricates formal task release.
  assert_false(
    @remote.remote_runtime_record_released(
      f.journal.require(f.consumer).unwrap(),
    ),
  )
  assert_true(f.journal.close())
  assert_true(f.receiver.close())
}

///|
test "stopped retained cleanup returns only the original reader and retains another borrow" {
  let f = stopped_cleanup_fixture("other-reader")
  f.receiver
  .acquire_destination_reader(f.transfer, f.receipt, "other-original-reader")
  .unwrap()
  |> ignore
  assert_true(
    stopped_cleanup_apply(f, () => true)
    is Err(Transfer(@transfer_client.Durable(@transfer_journal.MaterialInUse))),
  )
  assert_eq(
    f.receiver.destination_capacity_usage().unwrap().reserved_bytes,
    10L,
  )
  f.receiver
  .validate_destination_reader(f.transfer, f.receipt, "other-original-reader")
  .unwrap()
  assert_true(
    f.receiver.validate_destination_reader(
      f.transfer,
      f.receipt,
      @remote.dispatch_request_identity(f.consumer),
    )
    is Err(_),
  )
  let f = stopped_cleanup_reopen(f)
  assert_true(
    f.receiver
    .release_destination_reader(f.transfer, f.receipt, "other-original-reader")
    .unwrap(),
  )
  stopped_cleanup_apply(f, () => true).unwrap()
  assert_eq(f.receiver.destination_capacity_usage().unwrap().reserved_bytes, 0L)
  stopped_cleanup_apply(f, () => true).unwrap()
  assert_true(f.journal.close())
  assert_true(f.receiver.close())
}

///|
test "stopped retained cleanup retains reservation through physical sync failure and retry" {
  let f = stopped_cleanup_fixture("sync-retry")
  cleanup_fail_root_sync(f.root, 1)
  assert_true(
    stopped_cleanup_apply(f, () => true)
    is Err(Transfer(@transfer_client.Destination(_))),
  )
  assert_eq(
    f.receiver.destination_capacity_usage().unwrap().reserved_bytes,
    10L,
  )
  assert_eq(
    f.receiver.destination_capacity_usage().unwrap().reserved_objects,
    1L,
  )
  let f = stopped_cleanup_reopen(f)
  stopped_cleanup_apply(f, () => true).unwrap()
  assert_eq(f.receiver.destination_capacity_usage().unwrap().reserved_bytes, 0L)
  assert_eq(
    f.receiver.destination_capacity_usage().unwrap().reserved_objects,
    0L,
  )
  stopped_cleanup_apply(f, () => true).unwrap()
  assert_true(f.journal.close())
  assert_true(f.receiver.close())
}

///|
test "stopped retained cleanup retries original custody after task release and reconstruction" {
  let f = stopped_cleanup_fixture("released-cleanup-retry")
  stopped_cleanup_apply(f, () => true).unwrap()
  for request in [f.producer, f.consumer] {
    let record = f.journal.require(request).unwrap()
    f.journal
    .commit_transition(@remote.prepare_begin_remote_release(record).unwrap())
    .unwrap()
    f.journal
    .commit_transition(@remote.prepare_confirm_remote_release(record).unwrap())
    .unwrap()
  }
  let f = stopped_cleanup_reopen(f)
  let revisions = [
    @remote.dispatch_record_revision(f.journal.require(f.producer).unwrap()),
    @remote.dispatch_record_revision(f.journal.require(f.consumer).unwrap()),
  ]
  assert_true(stopped_cleanup_apply(f, () => false) is Err(NotCurrent))
  for _ in 0..<2 {
    stopped_cleanup_apply(f, () => true).unwrap()
    assert_eq(
      f.receiver.destination_capacity_usage().unwrap().reserved_bytes,
      0L,
    )
    assert_eq(
      f.receiver.destination_capacity_usage().unwrap().reserved_objects,
      0L,
    )
  }
  assert_eq(
    [
      @remote.dispatch_record_revision(f.journal.require(f.producer).unwrap()),
      @remote.dispatch_record_revision(f.journal.require(f.consumer).unwrap()),
    ],
    revisions,
  )
  assert_true(f.journal.close())
  assert_true(f.receiver.close())
}
