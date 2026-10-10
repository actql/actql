// Actual Native Source/Effect computation for an accepted original Submission.
// This is a Host connection test, not public CLI ingress or Provider apply.

///|
fn local_client_effect_source_original(
  root : String,
  name : String,
) -> (
  @sqlite.Database,
  @client.NativeClientRunJournal,
  @client.NativeClientSubmissionReference,
  @host.ClientRequestIdentity,
  @host.ClientEffectAllowedRun,
  @publication.PublicationContract,
) raise {
  let sqlite = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let crypto = @signature.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
  ).unwrap()
  let database = sqlite
    .open_database(root + "/" + name + ".sqlite3", 131072L)
    .unwrap()
  // Independently authored initial custody in this test-owned fresh DB only.
  // No production adoption/grant or Submission/Run receipt is synthesized.
  // The real epoch Owner issues and authenticates every reference below.
  let key = @base64.encode(crypto.random_bytes(32).unwrap())
  database
  .insert(
    "client_submission_epoch",
    "authority",
    @utf8.encode(
      "{\"authentication_key\":\"" +
      key +
      "\",\"observed_at\":0,\"version\":\"actql-native-submission-epoch-custody/0.1\"}",
    ),
  )
  .unwrap()
  |> ignore
  database.insert("client_run_custody", "issued", b"0").unwrap() |> ignore
  database.insert("client_submitted_intent_custody", "issued", b"0").unwrap()
  |> ignore
  let journal = @client.open_native_client_run_journal(database, 8).unwrap()
  let authority = @client.open_native_client_epoch_authority(
    database, crypto, 100.0,
  ).unwrap()
  let scope = "sha256:" + "a".repeat(64)
  let epoch = authority.issue_epoch(scope, true, 1000.0).unwrap()
  let reference = @client.prepare_native_client_submission_reference(
    epoch, "original-local-effect-source-submit",
  ).unwrap()
  let intent = @host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":" +
    resident_native_effect_document +
    ",\"parameters\":null}",
    65536,
    8192,
    64,
  ).unwrap()
  journal
  .record_submitted_intent(authority, reference, intent, scope, true, 1001.0)
  .unwrap()
  |> ignore
  let environment = @host.admit_client_check_environment(
    resident_effect_source_environment,
    "sha256:feb4443bd80a5e95c14e195113219eeb2e24bdd12e424d1ba00c1295f5c53554",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let preparation = @client.prepare_native_client_submitted_program(
    intent,
    environment,
    None,
    [],
    retained_compute_effect_limits(),
  ).unwrap()
  guard @client.native_client_submitted_preparation(preparation)
    is @client.EffectComputation(prepared) else {
    abort("original submitted Source Effect was not prepared")
  }
  let manifests = @host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).unwrap()
  let compilation = @host.issue_prepared_client_effect_compilation(
    prepared,
    manifests,
    @host.client_standard_values_sequence_limits(),
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  let allowed = @host.issue_client_effect_allowed_run(
    compilation,
    scope,
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @host.issue_client_effect_run_definition(
    allowed, "native-client-effect-fixture", "original-local-effect-source-run",
    "2026-10-10T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let request = @host.prepare_client_effect_request_identity(
    prepared,
    scope,
    @client.native_client_submission_request_id(reference),
    @host.source_free_caller_input_intent_cid(),
  ).unwrap()
  let accepted = journal
    .accept_submitted_effect_run(
      authority, reference, preparation, request, allowed, definition, scope, true,
      1002.0,
    )
    .unwrap()
  assert_eq(
    @client.native_client_submitted_run_definition_cid(
      @client.native_client_submitted_run_admission(accepted).unwrap(),
    ),
    @publication.publication_contract_identity(definition),
  )
  (database, journal, reference, request, allowed, definition)
}

///|
test "Native original accepted Effect Run acquires once computes its Result and retains cleanup pins" {
  guard resident_compute_prerequisites() is Some((library_path, root_path)) else {
    abort("Native Client Effect Source requires its actual DuckDB fixture")
  }
  let library = @duckdb.load_library(library_path).unwrap()
  let name = "native-client-effect-source-" + @env.now().to_string() + ".duckdb"
  let root = @filesystem.open_root(root_path).unwrap()
  let path = root_path + "/" + name
  resident_compute_database(library, path)
  let (database, journal, _, request, allowed, definition) = local_client_effect_source_original(
    root_path, name,
  )
  let configured = resident_compute_configuration(library, path)
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
  let mut authorized = true
  let mut now = "2026-10-10T00:00:01.000Z"
  assert_true(
    @client.open_native_client_effect_source_work(
      journal,
      request,
      allowed,
      definition,
      configuration,
      name,
      () => "2099-01-01T00:00:00.000Z",
      () => true,
    )
    is Err(@client.OriginalRunNotCurrent),
  )
  assert_true(
    @client.open_native_client_effect_source_work(
      journal,
      request,
      allowed,
      definition,
      configuration,
      name,
      () => "2026-10-10T00:00:01.000Z",
      () => false,
    )
    is Err(@client.NativeClientSourceWorkIssue::AuthorizationDenied),
  )
  let work = @client.open_native_client_effect_source_work(
    journal,
    request,
    allowed,
    definition,
    configuration,
    name,
    () => now,
    () => authorized,
    observe=event => {
      match event {
        @resident.AcquisitionEntered => acquisitions += 1
        @resident.ConsumerEntered(_) => consumers += 1
        @resident.CleanupCompleted => cleanups += 1
        _ => ()
      }
      true
    },
  ).unwrap()
  assert_eq(acquisitions, 1)
  assert_eq(consumers, 0)
  // Reclaiming the original file proves the consumer uses retained input.
  resident_compute_reclaim(root, name)
  authorized = false
  assert_true(
    work.execute_task(1)
    is Err(@client.NativeClientSourceWorkIssue::AuthorizationDenied),
  )
  assert_true(
    work.owner_for_capture()
    is Err(@client.NativeClientSourceWorkIssue::AuthorizationDenied),
  )
  assert_eq(consumers, 0)
  authorized = true
  now = "2099-01-01T00:00:00.000Z"
  assert_true(work.execute_task(1) is Err(@client.OriginalRunNotCurrent))
  assert_true(work.owner_for_capture() is Err(@client.OriginalRunNotCurrent))
  assert_true(
    work.prepare_result_export(resident_compute_limits())
    is Err(@client.OriginalRunNotCurrent),
  )
  assert_eq(consumers, 0)
  now = "2026-10-10T00:00:02.000Z"
  work.execute_task(1).unwrap()
  assert_eq(consumers, 1)
  let output = work.prepare_result_export(resident_compute_limits()).unwrap()
  let rows = StringBuilder()
  while output.next().unwrap() is Some(chunk) {
    rows.write_string(chunk)
  }
  rows.write_string(output.finish().unwrap())
  assert_eq(rows.to_string(), "[{\"id\":3}]")
  assert_eq(output.result_fields().unwrap(), ["id"])
  assert_eq(
    output.result_schema_wire().unwrap(),
    "{\"id\":{\"nullable\":false,\"type\":\"number\"}}",
  )
  output.cancel()
  let owner = work.owner_for_capture().unwrap()
  let inputs = @strategy.pin_captured_effect_sources(
    owner.effect_run().unwrap(),
    4,
  ).unwrap()
  assert_false(work.close())
  assert_true(work.usage().held_bytes > 0L)
  assert_eq(cleanups, 0)
  assert_true(@strategy.release_captured_effect_inputs(inputs))
  assert_false(@strategy.release_captured_effect_inputs(inputs))
  authorized = false
  assert_true(work.close())
  assert_true(work.close())
  assert_eq(cleanups, 1)
  assert_eq(work.usage().held_bytes, 0L)
  assert_eq(work.usage().reserved_transfer_bytes, 0L)
  assert_eq(work.usage().reserved_retention_bytes, 0L)
  assert_eq(work.usage().reserved_execution_bytes, 0L)
  authorized = true
  assert_true(
    work.owner_for_capture() is Err(@client.Work(@resident.Unavailable)),
  )
  assert_true(
    @client.open_native_client_effect_source_work(
      journal,
      request,
      allowed,
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
  database.close_checked().unwrap()
}
