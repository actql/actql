// Internal Native connection acceptance using the existing actual acquisition
// and publication/delivery owners. Store reopen is not a separate-process
// restart, and this fixture is not public CLI ingress or read authorization.

///|
fn local_client_source_publication_case(
  race : Bool,
  cancel_before_start? : Bool = false,
  delivery_handoff? : Bool = false,
  original_normalization? : Bool = false,
  reject_original_completion? : Bool = false,
) -> Unit raise {
  guard resident_compute_prerequisites() is Some((library_path, root_path)) else {
    abort("Native Client Source acceptance requires its actual DuckDB fixture")
  }
  let sqlite = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let library = @duckdb.load_library(library_path).unwrap()
  let name = if delivery_handoff {
    "native-client-source-delivery-process.duckdb"
  } else {
    "native-client-source-" + @env.now().to_string() + ".duckdb"
  }
  let path = root_path + "/" + name
  let root = @filesystem.open_root(root_path).unwrap()
  resident_compute_database(library, path)
  let mut database = sqlite
    .open_database(root_path + "/" + name + ".sqlite3", 131072L)
    .unwrap()
  // This is an independently authored test-owned initial row, not production
  // bootstrap or a repair of an adopted Host. No Submission receipt is faked.
  database.begin_immediate().unwrap()
  database.install_client_run_definition_schema(8L).unwrap()
  database.insert("client_run_custody", "issued", b"0").unwrap() |> ignore
  database.insert("client_cancel_custody", "issued", b"0").unwrap() |> ignore
  database.insert("client_submitted_intent_custody", "issued", b"0").unwrap()
  |> ignore
  database.insert("client_submitted_intent_usage", "retained", b"0:0").unwrap()
  |> ignore
  database
  .insert(
    "client_submission_epoch", "authority", b"{\"authentication_key\":\"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\",\"observed_at\":0,\"version\":\"actql-native-submission-epoch-custody/0.1\"}",
  )
  .unwrap()
  |> ignore
  database.commit().unwrap()
  let mut journal = @client.open_native_client_run_journal(database, 8).unwrap()
  let crypto = @signature.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
  ).unwrap()
  let mut authority = @client.open_native_client_epoch_authority(
    database, crypto, 100.0,
  ).unwrap()
  let scope = "sha256:" + "a".repeat(64)
  let reference = @client.prepare_native_client_submission_reference(
    authority.issue_epoch(scope, true, 1000.0).unwrap(),
    "original-source-request",
  ).unwrap()
  let environment = @host.admit_client_check_environment(
    resident_effect_source_environment,
    resident_effect_source_bundle_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document = if original_normalization {
    resident_compute_document.replace(
      old="\"resource\":\"r\"",
      new="\"resource\":\"r\",\"view\":\"v\"",
    )
  } else {
    resident_compute_document
  }
  let intent = @host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":" + document + ",\"parameters\":null}",
    65536,
    8192,
    64,
  ).unwrap()
  let preparation = @client.prepare_native_client_submitted_program(
    intent,
    environment,
    None,
    [],
    @host.client_standard_effect_computation_limits(),
  ).unwrap()
  guard @client.native_client_submitted_preparation(preparation)
    is @client.Computation(prepared) else {
    fail("Native frontend did not prepare the ordinary Source Program")
  }
  assert_true(@resident.resident_source_compute_shape_supported(prepared))
  let manifests = @host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).unwrap()
  let compilation = @host.issue_prepared_client_task_compilation(
    prepared,
    manifests,
    @host.client_standard_values_sequence_limits(),
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  let compiled = @host.issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @host.issue_client_compiled_run_definition(
    compiled, "native-client-fixture", "original-source-run", "2026-10-10T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let request = @host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    @client.native_client_submission_request_id(reference),
  ).unwrap()
  let configured = resident_compute_configuration(library, path)
  // Keep the representative execution inside a declared 512 MiB envelope;
  // use the existing task/acquisition quantities without inflating a bound.
  let configuration : @resident.ResidentSourceComputeConfiguration = {
    ..configured,
    source: {
      ..configured.source,
      ledger: {
        ..configured.source.ledger,
        retained_bytes: 536870912L,
        execution_bytes: 536870912L,
      },
    },
  }
  let mut acquisitions = 0
  let mut consumers = 0
  let mut cleanups = 0
  let mut permitted = true
  let mut clock_calls = 0
  let store_name = name + "-publication"
  root.create_directory(store_name).unwrap() |> ignore
  let store_root = root_path + "/" + store_name
  let initial_store = @store.open_store(
    sqlite,
    store_root,
    local_client_publication_cid("native-client-original-store"),
    128L,
    8L,
    1000000L,
  ).unwrap()
  journal
  .record_submitted_intent(authority, reference, intent, scope, true, 1001.0)
  .unwrap()
  |> ignore
  journal
  .accept_submitted_run(
    authority, reference, preparation, request, compiled, definition, scope, true,
    1002.0,
  )
  .unwrap()
  |> ignore
  let installed = @client.install_native_client_cancellation_publication(
    initial_store, "native-client-fixture", 1000000, 100000, 100,
  ).unwrap()
  journal.bind_installed_publication(request, installed, () => true).unwrap()
  if cancel_before_start {
    guard journal.lookup(request, true) is Ok(@client.Retained(before_start)) else {
      fail("accepted original Run missing")
    }
    let original = journal
      .cancel_operation(
        request,
        "native-client-fixture",
        "before-source-start",
        @client.native_client_run_record_revision(before_start).to_int(),
        () => true,
        installed,
      )
      .unwrap()
    assert_eq(
      @client.native_client_cancellation_action(original),
      @host.AcceptCancellation,
    )
    assert_true(
      @client.open_native_client_source_work(
        journal,
        request,
        prepared,
        compiled,
        definition,
        configuration,
        name,
        () => "2026-10-10T00:00:01.000Z",
        () => true,
        observe=event => {
          match event {
            @resident.AcquisitionEntered => acquisitions += 1
            @resident.ConsumerEntered(_) => consumers += 1
            @resident.CleanupCompleted => cleanups += 1
            _ => ()
          }
          true
        },
      )
      is Err(@client.NeedsOriginalReconciliation),
    )
    assert_eq(acquisitions, 0)
    assert_eq(consumers, 0)
    assert_eq(cleanups, 0)
    assert_eq(initial_store.capacity_usage().unwrap().reserved_bytes, 0L)
    assert_true(initial_store.close().unwrap())
    database.close_checked().unwrap()
    resident_compute_reclaim(root, name)
    return
  }
  if reject_original_completion {
    let key = @host.client_request_scope_cid(request)
    let before = database.read("client_runs", key).unwrap().body
    assert_true(
      @client.open_native_client_local_source_work(
        journal,
        request,
        prepared,
        compiled,
        definition,
        configuration,
        name,
        () => "2026-10-10T00:00:01.000Z",
        () => true,
        observe=event => {
          match event {
            @resident.AcquisitionEntered => acquisitions += 1
            @resident.ConsumerEntered(_) => consumers += 1
            @resident.CleanupCompleted => cleanups += 1
            _ => ()
          }
          true
        },
      )
      is Err(
        @client.Normalization(
          @host.CommonInventory(@checked.CompletionObserved)
        )
      ),
    )
    // No dispatch/start claim may be persisted by a rejected original audit.
    assert_eq(database.read("client_runs", key).unwrap().body, before)
    assert_eq(acquisitions, 0)
    assert_eq(consumers, 0)
    assert_eq(cleanups, 0)
    assert_eq(initial_store.capacity_usage().unwrap().reserved_bytes, 0L)
    assert_true(initial_store.close().unwrap())
    database.close_checked().unwrap()
    resident_compute_reclaim(root, name)
    return
  }
  assert_true(initial_store.close().unwrap())
  let current_time = () => {
    clock_calls += 1
    if clock_calls == 1 {
      "2026-10-10T00:00:01.000Z"
    } else {
      "2026-10-10T00:00:02.000Z"
    }
  }
  let current_authorization = () => permitted
  let observe = event => {
    match event {
      @resident.AcquisitionEntered => acquisitions += 1
      @resident.ConsumerEntered(_) => consumers += 1
      @resident.CleanupCompleted => cleanups += 1
      _ => ()
    }
    true
  }
  let work = if original_normalization {
    @client.open_native_client_local_source_work(
      journal,
      request,
      prepared,
      compiled,
      definition,
      configuration,
      name,
      current_time,
      current_authorization,
      observe~,
    ).unwrap()
  } else {
    @client.open_native_client_source_work(
      journal,
      request,
      prepared,
      compiled,
      definition,
      configuration,
      name,
      current_time,
      current_authorization,
      observe~,
    ).unwrap()
  }
  let original = work
    .publication_invocation(resident_compute_limits(), 1000000, 100000, 100)
    .unwrap()
  let repeated = work
    .publication_invocation(resident_compute_limits(), 1000000, 100000, 100)
    .unwrap()
  assert_eq(clock_calls, 2)
  assert_eq(
    @publication.run_evidence_value_json(original.0),
    @publication.run_evidence_value_json(repeated.0),
  )
  assert_eq(
    @publication.publication_contract_identity(original.3),
    @publication.publication_contract_identity(repeated.3),
  )
  assert_true(
    @publication.admit_completed_source_observation_binding(
      original.0,
      original.1,
      "connector://crm/main/r#v",
      "sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3",
      "sha256:" + "a".repeat(64),
      "sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf",
      1000000,
      100000,
      100,
    )
    is Ok(_),
  )
  permitted = false
  assert_true(
    work.publication_invocation(resident_compute_limits(), 1000000, 100000, 100)
    is Err(@client.AuthorizationDenied),
  )
  permitted = true
  work.execute_task(1).unwrap()
  let output = work.prepare_result_export(resident_compute_limits()).unwrap()
  let body = StringBuilder()
  while output.next().unwrap() is Some(chunk) {
    body.write_string(chunk)
  }
  body.write_string(output.finish().unwrap())
  // Static independent expected value/schema/column order for this Program.
  assert_eq(body.to_string(), "[{\"id\":3}]")
  assert_eq(output.result_fields().unwrap(), ["id"])
  assert_eq(output.row_count().unwrap(), 1)
  assert_eq(
    output.result_schema_wire().unwrap(),
    "{\"id\":{\"nullable\":false,\"type\":\"number\"}}",
  )
  let store = local_client_publication_context(
    work,
    compiled,
    definition,
    request,
    original.1,
    sqlite,
    store_root,
    value => permitted = value,
    journal,
    race,
    original_normalization~,
  )
  if !race {
    local_client_read_committed_result(
      store, definition, request, "original-read",
    )
  }
  assert_false(work.close())
  assert_eq(cleanups, 0)
  output.cancel()
  assert_true(work.close())
  if race {
    assert_true(
      work.publication_invocation(
        resident_compute_limits(),
        1000000,
        100000,
        100,
      )
      is Err(@client.NeedsOriginalReconciliation),
    )
  } else {
    assert_true(
      work.publication_invocation(
        resident_compute_limits(),
        1000000,
        100000,
        100,
      )
      is Err(@client.Observation(@resident.Unavailable)),
    )
  }
  assert_true(work.close())
  assert_eq(acquisitions, 1)
  assert_eq(consumers, 1)
  assert_eq(cleanups, 1)
  let usage = work.usage()
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_transfer_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  // Temporary Compute holds are gone; the Named Result has independent
  // durable retention and can be reread without reopening Source or Compute.
  if race {
    assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
  } else {
    assert_true(store.capacity_usage().unwrap().reserved_bytes > 0L)
  }
  assert_true(store.close().unwrap())
  let store = @store.open_store(
    sqlite,
    store_root,
    local_client_publication_cid("native-client-original-store"),
    128L,
    8L,
    1000000L,
  ).unwrap()
  if !race {
    local_client_read_committed_result(
      store, definition, request, "new-read-after-reopen",
    )
  }
  if !race {
    guard journal.lookup(request, true)
      is Ok(@client.Retained(original_after_reopen)) else {
      fail("original Run missing after Store reopen")
    }
    let observed = journal
      .cancel_operation(
        request,
        "native-client-fixture",
        "after-store-reopen",
        @client.native_client_run_record_revision(original_after_reopen).to_int(),
        () => true,
        @client.install_native_client_cancellation_publication(
          store, "native-client-fixture", 1000000, 100000, 100,
        ).unwrap(),
      )
      .unwrap()
    assert_eq(
      @client.native_client_cancellation_action(observed),
      @host.AlreadyTerminal,
    )
  }
  if !race {
    // Reopen actual admission custody as well as the Result Store. This is
    // same-process restoration, not the final separate-process CLI acceptance.
    database.close_checked().unwrap()
    database = sqlite
      .open_database(root_path + "/" + name + ".sqlite3", 131072L)
      .unwrap()
    journal = @client.open_native_client_run_journal(database, 8).unwrap()
    authority = @client.open_native_client_epoch_authority(
      database, crypto, 100.0,
    ).unwrap()
    let restored_reference = @client.admit_native_client_submission_reference(
      @client.native_client_submission_reference_wire(reference),
    ).unwrap()
    local_client_read_result_sink(
      journal, authority, restored_reference, store, definition, request, "native-cli-sink-after-reopen",
    )
    assert_eq(acquisitions, 1)
    assert_eq(consumers, 1)
    assert_eq(cleanups, 1)
  }
  assert_true(store.close().unwrap())
  guard journal.lookup(request, true)
    is Ok(@client.Retained(before_failed_observation)) else {
    fail("original Run missing before closed Store observation")
  }
  let original_revision = @client.native_client_run_record_revision(
    before_failed_observation,
  ).to_int()
  assert_true(
    journal.cancel_operation(
      request,
      "native-client-fixture",
      "closed-store-cancel",
      original_revision,
      () => true,
      @client.install_native_client_cancellation_publication(
        store, "native-client-fixture", 1000000, 100000, 100,
      ).unwrap(),
    )
    is Err(@client.PublicationObservation(@store.Closed)),
  )
  assert_true(
    journal.lookup_cancellation(
      request,
      "native-client-fixture",
      "closed-store-cancel",
      original_revision,
      () => true,
    )
    is Ok(@client.UnresolvedCancellationHistory),
  )
  // Repetition keeps the original Run and cannot acquire/compute again. These
  // facts do not mark an unpublished Run as succeeded or a cancellation done.
  assert_true(
    @client.open_native_client_source_work(
      journal,
      request,
      prepared,
      compiled,
      definition,
      configuration,
      name,
      () => "2026-10-10T00:00:03.000Z",
      () => true,
    )
    is Err(@client.NeedsOriginalReconciliation),
  )
  assert_eq(acquisitions, 1)
  assert_eq(consumers, 1)
  assert_eq(cleanups, 1)
  if delivery_handoff {
    let status = initial_store.inspect_result_delivery(
      "native-cli-sink-after-reopen",
    )
    // The original Store was closed. Reopen its exact adopted file only to
    // collect already-issued reference facts; never create replacement data.
    assert_true(status is Err(@store.Closed))
    let retained_store = @store.open_store(
      sqlite,
      store_root,
      local_client_publication_cid("native-client-original-store"),
      128L,
      8L,
      1000000L,
    ).unwrap()
    let status = retained_store
      .inspect_result_delivery("native-cli-sink-after-reopen")
      .unwrap()
    for
      (key, value) in [
        (
          "submission",
          @client.native_client_submission_reference_wire(reference),
        ),
        ("scope", scope),
        ("run", @publication.publication_contract_identity(definition)),
        ("attempt", status.delivery_attempt_cid),
        ("record", status.delivery_record_cid),
        ("receipt", status.result_delivery_receipt_cid.unwrap()),
        ("acquisitions", acquisitions.to_string()),
        ("consumers", consumers.to_string()),
        ("cleanups", cleanups.to_string()),
      ] {
      database
      .insert("test_source_delivery_reference", key, @utf8.encode(value))
      .unwrap()
      |> ignore
    }
    let lost_admissions = Ref(0)
    let lost_authority = @access.install_native_result_access_authority(
      requested => {
        requested.run_definition_cid ==
        @publication.publication_contract_identity(definition) &&
        requested.principal_id == "fixture-principal"
      },
      _ => {
        lost_admissions.val += 1
        Some({
          authorization_context_cid: local_client_publication_cid(
            "lost-open-auth",
          ),
          data_ceiling_cid: local_client_publication_cid("lost-open-ceiling"),
          egress_admission_cid: local_client_publication_cid("lost-open-egress"),
          expires_at: "2099-01-01T00:00:00.000Z",
          max_bytes: 128,
          max_uses: 1,
        })
      },
      _ => true,
    )
    let lost_service = @access.install_native_result_access_service(
      retained_store,
      lost_authority,
      () => "2026-10-10T00:00:09.000Z",
      1000000,
      100000,
      16,
      128,
      3,
    ).unwrap()
    // Durable opening has completed. Its response is deliberately not handed
    // to a reader and no byte is requested. Physical close cannot complete it.
    let lost = journal
      .open_submitted_result(
        authority,
        reference,
        scope,
        () => true,
        1104.0,
        lost_service,
        {
          namespace_id: "native-client-fixture",
          principal_id: "fixture-principal",
          purpose: "inspect",
          result_name: "answer",
          format: "jsonl",
          attempt_id: "native-cli-open-response-lost",
        },
      )
      .unwrap()
    assert_eq(lost_admissions.val, 1)
    lost.close().unwrap()
    let lost_status = retained_store
      .inspect_result_delivery("native-cli-open-response-lost")
      .unwrap()
    assert_eq(lost_status.state, "streaming")
    assert_eq(lost_status.confirmed_bytes, 0L)
    assert_true(lost_status.result_delivery_receipt_cid is None)
    for
      (key, value) in [
        ("lost_attempt", lost_status.delivery_attempt_cid),
        ("lost_record", lost_status.delivery_record_cid),
      ] {
      database
      .insert("test_source_delivery_reference", key, @utf8.encode(value))
      .unwrap()
      |> ignore
    }
    assert_true(retained_store.close().unwrap())
  }
  database.close_checked().unwrap()
  resident_compute_reclaim(root, name)
}

///|
test "Native Client original Run reaches actual Source Compute Result export and cleanup" {
  local_client_source_publication_case(false)
}

///|
test "Native original publication and cancellation cannot both win the same admission fence" {
  local_client_source_publication_case(true)
}

///|
test "Native installed original Store permits public cancellation before Source start" {
  local_client_source_publication_case(false, cancel_before_start=true)
}

///|
test "Native Local original explicit-view audit reaches the same Source Result and cleanup owners" {
  local_client_source_publication_case(false, original_normalization=true)
}

///|
test "Native Local original sole-view completion is refused before acquisition or durable start claim" {
  local_client_source_publication_case(false, reject_original_completion=true)
}
