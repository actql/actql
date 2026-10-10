// Internal Native connection acceptance using the existing actual acquisition
// and publication/delivery owners. Store reopen is not a separate-process
// restart, and this fixture is not public CLI ingress or read authorization.

///|
fn local_client_source_publication_case(
  race : Bool,
  cancel_before_start? : Bool = false,
) -> Unit raise {
  guard resident_compute_prerequisites() is Some((library_path, root_path)) else {
    abort("Native Client Source acceptance requires its actual DuckDB fixture")
  }
  let sqlite = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let library = @duckdb.load_library(library_path).unwrap()
  let name = "native-client-source-" + @env.now().to_string() + ".duckdb"
  let path = root_path + "/" + name
  let root = @filesystem.open_root(root_path).unwrap()
  resident_compute_database(library, path)
  let database = sqlite
    .open_database(root_path + "/" + name + ".sqlite3", 131072L)
    .unwrap()
  // This is an independently authored test-owned initial row, not production
  // bootstrap or a repair of an adopted Host. No Submission receipt is faked.
  database.insert("client_run_custody", "issued", b"0").unwrap() |> ignore
  database.insert("client_cancel_custody", "issued", b"0").unwrap() |> ignore
  let journal = @client.open_native_client_run_journal(database, 8).unwrap()
  let environment = @host.admit_client_check_environment(
    resident_effect_source_environment,
    "sha256:feb4443bd80a5e95c14e195113219eeb2e24bdd12e424d1ba00c1295f5c53554",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  guard @client.prepare_native_client_program(
      resident_compute_document,
      Json,
      environment,
      None,
      None,
      [],
      @host.client_standard_effect_computation_limits(),
    )
    is Ok(@client.Computation(prepared)) else {
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
    "original-source-request",
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
  journal.bind_run(request, prepared, compiled, definition, true).unwrap()
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
  assert_true(initial_store.close().unwrap())
  let work = @client.open_native_client_source_work(
    journal,
    request,
    prepared,
    compiled,
    definition,
    configuration,
    name,
    () => {
      clock_calls = clock_calls + 1
      if clock_calls == 1 {
        "2026-10-10T00:00:01.000Z"
      } else {
        "2026-10-10T00:00:02.000Z"
      }
    },
    () => permitted,
    observe=event => {
      match event {
        @resident.AcquisitionEntered => acquisitions = acquisitions + 1
        @resident.ConsumerEntered(_) => consumers = consumers + 1
        @resident.CleanupCompleted => cleanups = cleanups + 1
        _ => ()
      }
      true
    },
  ).unwrap()
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
