///|
// Only this test owns these finite fixture limits. The real component, domains,
// Read claim, SQL phase exchanges and constructor callbacks remain production.
priv struct JournalMetadataOriginalReadFixture {
  host : @arena.InstalledArenaHost
  read_domain : @arena.InstalledArenaDomain
  sqlite_domain : @arena.InstalledArenaDomain
  read : @arena.InstalledArenaOriginalRead
  pair : @arena.InstalledArenaLocalHostResources
  original : NativeLocalJournalOriginalResources
  database : Ref[@sqlite.Database?]
  journal : Ref[NativeClientRunJournal?]
}

///|
suberror JournalMetadataFixtureDomainFailure {
  JournalMetadataFixtureDomainFailure(
    String,
    @bootstrap.NativeBackedExecutionIssue
  )
}

///|
impl Show for JournalMetadataFixtureDomainFailure with fn output(self, logger) {
  let JournalMetadataFixtureDomainFailure(stage, issue) = self
  logger.write_string("Journal metadata fixture ")
  logger.write_string(stage)
  logger.write_string(" domain pending: ")
  logger.write_string(@debug.to_string(issue))
}

///|
fn journal_metadata_original_read_fixture() -> JournalMetadataOriginalReadFixture raise {
  let mib = 1048576L
  let host = @arena.prepare_installed_arena_host(
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
    256L * mib,
    {
      planning_work: 4096,
      attempts: 2048,
      holdings: 1024,
      transfer_bytes: 32L * mib,
      retained_bytes: 0L,
      execution_bytes: 256L * mib,
    },
    65536L,
  ).unwrap()
  host.acquire().unwrap()
  let backing = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(backing).unwrap()
  let read_domain = match
    host
    .prepare_domain_in_process(backing, 128L * mib, {
      planning_work: 1024,
      attempts: 512,
      holdings: 256,
      transfer_bytes: 16L * mib,
      retained_bytes: 4L * mib,
      execution_bytes: 64L * mib,
    })
    .unwrap() {
    @arena.PreparedDomain(value) => value
    @arena.PendingDomain(_, issue) =>
      raise JournalMetadataFixtureDomainFailure("Read", issue)
  }
  host.transfer_domain(read_domain).unwrap()
  let sqlite_domain = match
    host
    .prepare_domain_in_process(backing, 32L * mib, {
      planning_work: 16,
      attempts: 8,
      holdings: 4,
      transfer_bytes: 4L * mib,
      retained_bytes: 0L,
      execution_bytes: 16L * mib,
    })
    .unwrap() {
    @arena.PreparedDomain(value) => value
    @arena.PendingDomain(_, issue) =>
      raise JournalMetadataFixtureDomainFailure("SQLite", issue)
  }
  host.transfer_domain(sqlite_domain).unwrap()
  host.leave_backing_borrow_scope(backing).unwrap()
  host.return_backing_borrow(backing).unwrap()
  host.prepare_domain_read(read_domain).unwrap()
  host.prepare_domain_read(sqlite_domain).unwrap()
  let read = match
    host
    .prepare_domain_original_read(read_domain, {
      bootstrap_retained: 65536L,
      bootstrap_execution: 65536L,
      workspace_execution: mib,
      read_retained: 65536L,
      read_execution: mib,
    })
    .unwrap() {
    @arena.ReadyOriginalRead(value) => value
    @arena.PendingOriginalRead(_, _) => fail("metadata original Read pending")
  }
  let component = @env.get_env_var("ACTQL_TEST_SQLITE_COMPONENT").unwrap()
  let sqlite = match
    host
    .prepare_sqlite_library(sqlite_domain, component, 8L * mib, 256)
    .unwrap() {
    @arena.ReadySqlite(value) => value
    @arena.PendingSqlite(_, _) =>
      fail("metadata selected SQLite component pending")
  }
  let pair = host.bind_local_host_resources(read, sqlite).unwrap()
  host.prepare_local_host_read_consumer(pair, 65536L, mib).unwrap() |> ignore
  let original : NativeLocalJournalOriginalResources = {
    host,
    pair,
    read,
    metadata_retained: 0L,
    active_phase: None,
    interrupted: false,
    store_operation: None,
  }
  let database : Ref[@sqlite.Database?] = Ref(None)
  let journal : Ref[NativeClientRunJournal?] = Ref(None)
  original
  .stage(@arena.HostSqlite, fn() {
    let library = host
      .borrow_local_host_sqlite(pair)
      .map_err(issue => OriginalResources(issue))
      .unwrap()
    let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap() +
      "/journal-metadata-original-read.sqlite3"
    match library.open_database_with_custody(path, 2097152L) {
      Ok(value) => database.val = Some(value)
      Err(failure) => {
        // A failed open stays an actual failed setup, never an executed case.
        failure.retry_cleanup().unwrap()
        return Err(CustodyLost)
      }
    }
    let db = database.val.unwrap()
    initialize_native_client_run_journal(db)
    .map_err(issue => NativeLocalAdoptionIssue::Journal(issue))
    .unwrap()
    journal.val = Some(
      open_native_client_run_journal(db, 256)
      .map_err(issue => NativeLocalAdoptionIssue::Journal(issue))
      .unwrap(),
    )
    Ok(())
  })
  .unwrap()
  { host, read_domain, sqlite_domain, read, pair, original, database, journal, }
}

///|
// Fixture input is issued once by the real checked owner before entering the
// measured Read. No legacy Database, raw Plan factory or admission stub is used.
fn journal_metadata_original_row(ordinal : Int) -> (String, Bytes) {
  let suffix = ordinal.to_string()
  let (request, prepared, compiled, definition) = journal_test_run(
    "metadata-request-" + ordinal.to_string(),
    "metadata-run-" + ordinal.to_string(),
    scope="sha256:" + "0".repeat(64 - suffix.length()) + suffix,
  )
  let plan = capture_native_run_plan_original(prepared, compiled, definition).unwrap()
  let observation = capture_native_run_observation_originals(
    compiled, definition,
  ).unwrap()
  let record : NativeClientRunRecord = {
    request,
    definition,
    dispatch_reserved: false,
    physical_start_claimed: false,
    cancellation_requested: false,
    publication_binding: None,
    publication_policy_originals: None,
    effect_material_originals: None,
    task_materials_cid: None,
    local_run_policy_originals: None,
    run_observation_originals: Some(
      native_run_observation_originals_wire(
        observation,
        plan=Some(plan.original),
      ).unwrap(),
    ),
    observation_original: None,
    revision: 0L,
    checkpoint: None,
  }
  (@host.client_request_scope_cid(request), run_record_body(record).unwrap())
}

///|
fn journal_metadata_decode_original(
  fixture : JournalMetadataOriginalReadFixture,
  key : String,
) -> Result[NativeClientRunRecord, NativeLocalAdoptionIssue] {
  fixture.original.stage(@arena.HostRead, fn() {
    // A new router for each decode must not reset the original Read's retained
    // output. The SQL query leaves/reenters the SAME bound physical pair.
    let queries : NativeLocalJournalReadQueries = {
      original: fixture.original,
      database: fixture.database.val.unwrap(),
      failure: None,
      invalidate_snapshot: _ => (),
    }
    let reads = queries.access()
    let decoded : Result[NativeClientRunRecord, NativeLocalAdoptionIssue] = match
      read_client_journal_value(reads.database, "client_runs", key, Some(reads)) {
      Err(issue) => Err(NativeLocalAdoptionIssue::Physical(issue))
      Ok(row) =>
        fixture.journal.val
        .unwrap()
        .admit_retained_record(key, row, reads=Some(reads))
        .map_err(issue => NativeLocalAdoptionIssue::Journal(issue))
    }
    match queries.failure {
      Some(primary) => Err(primary)
      None => decoded
    }
  })
}

///|
test "Journal metadata retains multiple decoded originals on one real Read through refusal and retirement" {
  let fixture = journal_metadata_original_read_fixture()
  let held : Ref[Array[NativeClientRunRecord]] = Ref([])
  let mut previous = 0L
  let mut refused = false
  for ordinal in 0..<128 {
    let (key, body) = journal_metadata_original_row(ordinal)
    fixture.original
    .stage(@arena.HostSqlite, fn() {
      fixture.database.val
      .unwrap()
      .insert_with_body_extent(
        "client_runs",
        key,
        body,
        body.length().to_int64(),
      )
      .map(_ => ())
      .map_err(issue => Physical(issue))
    })
    .unwrap()
    match journal_metadata_decode_original(fixture, key) {
      Ok(record) => {
        assert_true(fixture.original.metadata_retained > previous)
        previous = fixture.original.metadata_retained
        assert_eq(@host.client_request_scope_cid(record.request), key)
        assert_true(record.observation_original is Some(_))
        held.val.push(record)
        assert_true(physical_equal(fixture.original.read, fixture.read))
        fixture.host
        .require_local_host_consuming_read_current(fixture.pair, fixture.read)
        .unwrap()
      }
      Err(
        OriginalResources(
          @arena.Read(
            @arena.Domain(
              @bootstrap.Accounting(
                @resources.Resource(@resources.InvalidLimits)
              )
            )
          )
        )
      ) => {
        assert_true(held.val.length() >= 2)
        // Earlier callbacks in this refused decode may already have returned
        // live partials. They are not refunded or exposed as a completed row.
        assert_true(fixture.original.metadata_retained >= previous)
        refused = true
        break
      }
      Err(_) =>
        fail(
          "metadata decode failed before the actual original capacity refusal",
        )
    }
  }
  assert_true(refused)
  assert_true(
    fixture.host.require_local_host_consuming_read_current(
      fixture.pair,
      fixture.read,
    )
    is Err(_),
  )
  // Real aliases still belong to this Read after the refused constructor.
  assert_true(fixture.host.close_domain_original_read(fixture.read) is Err(_))
  held.val = []
  fixture.journal.val = None
  fixture.original
  .stage(
    @arena.HostSqlite,
    fn() {
      fixture.database.val
      .unwrap()
      .close_checked()
      .map_err(issue => Physical(issue))
    },
    cleanup=true,
  )
  .unwrap()
  fixture.database.val = None
  fixture.host.close_local_host_resources(fixture.pair).unwrap()
  fixture.host.close_domain_after_owner_ack(fixture.sqlite_domain).unwrap()
  fixture.host.close_domain_after_owner_ack(fixture.read_domain).unwrap()
  fixture.host.try_close().unwrap()
}
