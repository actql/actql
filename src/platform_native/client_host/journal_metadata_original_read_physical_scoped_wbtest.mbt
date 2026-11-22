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
fn journal_metadata_original_read_fixture(
  retained_limit? : Int64 = 4194304L,
) -> JournalMetadataOriginalReadFixture raise {
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
      retained_bytes: retained_limit,
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
    account_construction_issue: None,
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
    // This fixture installs a fresh one-shot journal schema. The scoped runner
    // issues this private physical namespace per case, even when the legacy
    // SQLite input namespace is shared by adjacent cases.
    let path = @env.get_env_var("ACTQL_TEST_INSTALLED_PROCESS_ROOT").unwrap() +
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
    checkpoint_companion: false,
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

///|
fn effect_route_original_read_quote_case(
  one_short : Bool,
  signing? : Bool = false,
) -> Unit raise {
  let limit = 4194304L // Existing fixture default, not a product allowance.
  let initial = 65536L + 65536L // Original bootstrap + initial Read consumer.
  // Independent routing 64H/160R/16W plus signing wrapper 24H/64R/32W.
  let controls = if signing { 3584L } else { 2432L }
  let fixture = journal_metadata_original_read_fixture(retained_limit=limit)
  // The absolute construction entrance adds the original 65536-byte consumer
  // to metadata; its same ledger also retains the 65536-byte bootstrap. Reserve
  // the remaining prefix on this Owner before recording it. No payload is copied.
  let previous = limit - initial - controls + (if one_short { 1L } else { 0L })
  fixture.original
  .stage(@arena.HostRead, fn() {
    fixture.host
    .prepare_domain_original_read_construction(
      fixture.read,
      previous,
      previous,
      controls,
    )
    .map_err(issue => OriginalResources(@arena.Read(issue)))
  })
  .unwrap()
  fixture.original.metadata_retained = previous
  let result = fixture.original.stage(@arena.HostRead, fn() {
    if signing {
      fixture.original.retain_initial_signing_journal_controls()
    } else {
      fixture.original.retain_effect_journal_route_controls()
    }
  })
  if one_short {
    assert_true(result is Err(OriginalResources(_)))
    assert_eq(fixture.original.metadata_retained, previous)
  } else {
    result.unwrap()
    assert_eq(fixture.original.metadata_retained, limit - initial)
    assert_true(physical_equal(fixture.original.read, fixture.read))
    // Outside the actual entered phase, another route cannot allocate.
    assert_true(
      fixture.original.retain_effect_journal_route_controls()
      is Err(OriginalResourceScopePending),
    )
    assert_eq(fixture.original.metadata_retained, limit - initial)
  }
  // Actual original cleanup, after all route aliases are gone. No synthetic
  // physical ACK or allowance refund is made by the metadata admission.
  account_original_read_close_fixture(fixture)
}

///|
test "Effect Journal routing controls fit the exact same real Read retained boundary" {
  effect_route_original_read_quote_case(false)
}

///|
test "Effect Journal routing one short refuses before retained controls change" {
  effect_route_original_read_quote_case(true)
}

///|
test "Initial signing Journal routing fits the exact same real Read retained boundary" {
  effect_route_original_read_quote_case(false, signing=true)
}

///|
test "Initial signing Journal routing one short refuses before retained controls change" {
  effect_route_original_read_quote_case(true, signing=true)
}

///|
// The Read and its retained-byte ledger are real. Private fixture records
// present mismatched preparation inputs, without issuing a signing use or
// claiming that the test has an installed approval path.
test "Host attestation refuses mismatched preparation before entering its captured Read route" {
  let fixture = journal_metadata_original_read_fixture()
  let foreign_db = epoch_test_database("attestation-prequote-checkpoint")
  let (_, request, waiting) = checkpoint_test_waiting(foreign_db, [])
  let artifact = waiting.checkpoint.unwrap().artifact
  let run_definition_cid = artifact.checkpoint.run_definition_cid().unwrap()
  let name = "attestation-prequote"
  let (host, file) = initial_reviewer_fixture(
    name,
    account=installed_host_subject_account,
    host_signing_subject=Some(
      ("host-machine", "host-cli", "key/initial-host-attestation"),
    ),
  )
  let crypto = host.epoch.crypto
  let installed = installed_subject_reviewer(host, file)
  let account = host.restore_initial_host_signing_account(installed).unwrap()
  let key = host
    .acquire_initial_reviewer_signing_key(account.original.reviewer, installed)
    .unwrap()
  let capture = prepare_native_local_journal_capture_with_original_resources(
    host.session,
    fixture.host,
    fixture.pair,
    fixture.read,
    crypto,
    100.0,
    8,
    8388608L,
  )
  capture.opening = JournalAcquired(host)
  capture.read_callback_active = true
  capture.read_facts_valid = true
  let material = host.adopted_current_material().unwrap()
  let account = {
    ..account,
    original: {
      ..account.original,
      reviewer: {
        ..account.original.reviewer,
        original_read: Some((capture, material)),
      },
    },
  }
  let reference = prepare_native_client_submission_reference(
    host.epoch
    .issue_epoch(key.fields.authority_scope_cid, true, 1000.0)
    .unwrap(),
    "prequote-refusal",
  ).unwrap()
  let library = local_journal_test_library()
  let store = @publication_store.open_store(
    library,
    observed_state_store_fixture(name + ".store"),
    "sha256:" + "c".repeat(64),
    65536L,
    8L,
    131072L,
  ).unwrap()
  let selected : NativeLocalCheckpointSelection = {
    reference,
    request,
    checkpoint_id: artifact.checkpoint.checkpoint_id,
    checkpoint_cid: artifact.checkpoint_cid,
  }
  let saved = {
    capture,
    store,
    selected,
    principal: "machine-user",
    connection: "cli",
    namespace_id: "prequote-fixture",
    attempted: false,
    retired: false,
    approval_attempted: false,
    approval_original: None,
    retained_persisted: None,
    _retained_checkpoint: None,
    _retained_continuation: None,
    _retained_original: None,
    _retained_store_location: None,
    _retained_restoration: None,
    _retained_file_entry_control: None,
    _retained_publication_construction: None,
    _retained_constructor_bytes: 0L,
  }
  let state = native_client_run_checkpoint_state(waiting).unwrap()
  let current_calls = Ref(0)
  let binding : NativeLocalEffectReviewerBinding = {
    host,
    crypto,
    principal: "machine-user",
    connection: "cli",
    reference,
    request,
    original: {
      checkpoint_cid: artifact.checkpoint_cid,
      run_definition_cid,
      revision: waiting.revision,
      cancellation_requested: false,
      state,
    },
    approval_scope: SavedApproval(saved),
    installed,
    now: () => {
      current_calls.val += 1
      1001.0
    },
  }
  let limits = native_checkpoint_limits()
  let writer = @encode.writer(
    limits.max_wire_bytes,
    limits.max_nodes,
    limits.max_depth,
  )
  emit_saved_effect_resolution(
    writer,
    artifact,
    "machine-user",
    "rejected",
    artifact.checkpoint.created_at,
  )
  let proof = @checkpoint.prepare_resolution_proof(
    artifact,
    @encode.finish(writer),
    limits,
  ).unwrap()
  let registration : @effect_resolution.NativeEffectReviewerRegistration = {
    selection: {
      principal_id: binding.principal,
      checkpoint_cid: artifact.checkpoint_cid,
    },
    key_id: installed.reviewer.key_id,
    reviewer_id: installed.reviewer.reviewer_id,
    public_key_pem: installed.reviewer.public_key_pem,
    approval_authority_scope_cid: key.fields.authority_scope_cid,
    authority_context_cid: key.fields.authority_scope_cid,
    policy_cid: key.fields.account_configuration_cid,
  }
  let materials : NativeLocalReviewerProofMaterials = {
    key: InitialReviewerKey(key),
    reviewer: binding,
    registration,
    original: {
      artifact,
      revision: waiting.revision,
      cancellation_requested: false,
      state,
      reported_unknown_effect_count: 0,
      settlement_only: false,
    },
    proof: ResolutionOriginal(proof),
  }
  let authenticated : NativeLocalAuthenticatedEffectReviewer = {
    binding,
    registration,
    limits,
    resolution_wire: "",
    authentication: {
      key_id: registration.key_id,
      reviewer_id: registration.reviewer_id,
      expected_authority_scope_cid: registration.approval_authority_scope_cid,
      authority_context_cid: registration.authority_context_cid,
      policy_cid: registration.policy_cid,
      proof_preimage: proof.preimage(),
    },
  }
  let mismatch = {
    ..authenticated,
    authentication: {
      ..authenticated.authentication,
      proof_preimage: "foreign preimage",
    },
  }
  let foreign_host = checkpoint_lookup_host_fixture(
    "attestation-foreign-receiver",
  )
  let foreign = {
    ..authenticated,
    binding: { ..binding, host: foreign_host, },
  }
  let original = capture.original_resources.unwrap()
  for receiver in [mismatch, foreign] {
    let retained = original.metadata_retained
    let route = native_timing_counter_value(33)
    let refused = original
      .stage(@arena.HostRead, fn() {
        Ok(
          receiver.prepare_initial_host_attestation(
            account, materials, "refused",
          )
          is Err(HostAttestationUnavailable),
        )
      })
      .unwrap()
    assert_eq(original.metadata_retained, retained)
    assert_eq(native_timing_counter_value(33), route)
    assert_eq(current_calls.val, 0)
    assert_true(
      capture.read_material is None && capture.read_operation_issue is None,
    )
    assert_true(refused)
  }
  capture.read_callback_active = false
  capture.read_facts_valid = false
  // The fixture lent this old Host to the negative input. Close it through
  // its actual owner, independently from the separately entered Read.
  capture.opening = JournalNotAttempted
  assert_true(store.close().unwrap())
  host.close().unwrap()
  crypto.close_checked().unwrap()
  let foreign_crypto = foreign_host.epoch.crypto
  foreign_host.close().unwrap()
  foreign_crypto.close_checked().unwrap()
  foreign_db.close_checked().unwrap()
  account_original_read_close_fixture(fixture)
}

///|
fn saved_capture_probe_quote_case(one_short : Bool) -> Unit raise {
  let limit = 4194304L
  let initial = 65536L + 65536L
  let (retained, _, raw) = saved_effect_capture_probe_construction().unwrap()
  assert_true(retained > 0L)
  let fixture = journal_metadata_original_read_fixture(retained_limit=limit)
  let previous = limit - initial - retained + (if one_short { 1L } else { 0L })
  fixture.original
  .stage(@arena.HostRead, fn() {
    fixture.host
    .prepare_domain_original_read_construction(
      fixture.read,
      previous,
      previous,
      raw,
    )
    .map_err(issue => OriginalResources(@arena.Read(issue)))
  })
  .unwrap()
  assert_true(
    prepare_saved_effect_capture_probe(fixture.original, previous)
    is Err(OriginalResourceScopePending),
  )
  let result = fixture.original.stage(@arena.HostRead, fn() {
    prepare_saved_effect_capture_probe(fixture.original, previous)
  })
  if one_short {
    assert_true(result is Err(OriginalResources(_)))
  } else {
    assert_eq(result.unwrap(), limit - initial)
  }
  account_original_read_close_fixture(fixture)
}

///|
test "Saved Capture probe fits the exact same real Read retained boundary" {
  saved_capture_probe_quote_case(false)
}

///|
test "Saved Capture probe refuses a one-short real Read retained boundary" {
  saved_capture_probe_quote_case(true)
}

///|
test "Saved Capture keeps the typed Store failure for its exact retained identity" {
  let fixture = journal_metadata_original_read_fixture()
  let (host, reference, request, checkpoint) = local_checkpoint_lookup_fixture(
    "saved-capture-store-current",
    waiting=false,
  )
  let crypto = host.epoch.crypto
  let capture = prepare_native_local_journal_capture_with_original_resources(
    host.session,
    fixture.host,
    fixture.pair,
    fixture.read,
    crypto,
    100.0,
    8,
    8388608L,
  )
  capture.opening = JournalAcquired(host)
  let store = @publication_store.open_store(
    local_journal_test_library(),
    observed_state_store_fixture("saved-capture-store-current.store"),
    "sha256:" + "c".repeat(64),
    65536L,
    8L,
    131072L,
  ).unwrap()
  let selected : NativeLocalCheckpointSelection = {
    reference,
    request,
    checkpoint_id: checkpoint.checkpoint.checkpoint_id,
    checkpoint_cid: checkpoint.checkpoint_cid,
  }
  let original = capture.original_resources.unwrap()
  let review = original
    .stage(@arena.HostRead, fn() {
      capture.prepare_saved_effect_review(
        store, selected, "operator", "cli", "saved-capture-store-current",
      )
    })
    .unwrap()
  let location = store.custody_location().unwrap()
  review._retained_store_location = Some(location)
  original
  .stage(@arena.HostRead, fn() { review.saved_capture_store_current() })
  .unwrap()
  assert_true(store.close().unwrap())
  let (closed, foreign) = original
    .stage(@arena.HostRead, fn() {
      let closed = review.saved_capture_store_current()
        is Err(Journal(PublicationObservation(@publication_store.Closed)))
      let (authority, device, inode) = location
      review._retained_store_location = Some((authority, device, inode ^ 1UL))
      let foreign = review.saved_capture_store_current()
        is Err(Journal(CustodyLost))
      Ok((closed, foreign))
    })
    .unwrap()
  assert_true(closed)
  assert_true(foreign)
  review.retire_read_aliases()
  capture.opening = JournalNotAttempted
  host.close().unwrap()
  crypto.close_checked().unwrap()
  account_original_read_close_fixture(fixture)
}
