// Internal Native connection acceptance using the existing actual acquisition
// fixture. This is not CLI ingress, public delivery or a restart acceptance.

///|
test "Native Client original Run reaches actual Source Compute Result export and cleanup" {
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
  assert_false(work.close())
  assert_eq(cleanups, 0)
  output.cancel()
  assert_true(work.close())
  assert_true(
    work.publication_invocation(resident_compute_limits(), 1000000, 100000, 100)
    is Err(@client.Observation(@resident.Unavailable)),
  )
  assert_true(work.close())
  assert_eq(acquisitions, 1)
  assert_eq(consumers, 1)
  assert_eq(cleanups, 1)
  let usage = work.usage()
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_transfer_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
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
  database.close_checked().unwrap()
  resident_compute_reclaim(root, name)
}
