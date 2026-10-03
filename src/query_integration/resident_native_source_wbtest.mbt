///|
// Physical paths live only in Site preparation. The Program fixture retains
// the logical crm/main/r Source and its independently authored filter/select.
fn resident_native_source_setup(
  nullable? : Bool = false,
  evidence_members? : Bool = false,
) -> (
  @strategy.CheckedDAG,
  @acquisition_host.NativeHostConfiguration,
  @planning.QueryRequirement,
) raise {
  let catalog = if evidence_members {
    Some(resident_native_source_evidence_catalog())
  } else {
    None
  }
  let program = query_checked_program_fixture(nullable~, catalog~)
  let sequence = query_checked_sequence(program)
  let owners = physical_graph_owners(program)
  owners[0] = @query.query_sequence_owner(sequence)
  let graph = @strategy.prepare_checked_dag(program, owners, 10, 1000).unwrap()
  let requirement = @planning.prepare_query_requirement(
    @planning.prepare_query_material(sequence, query_material_limits()).unwrap(),
    @program_check.source_identity(program),
    { max_rows: 2, max_value_bytes: 100, },
    query_material_limits(),
  ).unwrap()
  let registry = @connector.prepare_capability_registry(
    [{ name: "duckdb", acquisition: true, fixed_compute: true, effect: false, }],
    1,
    6,
  ).unwrap()
  let preparation = @duckdb_query.prepare_duckdb_query(
    requirement,
    "main",
    "records",
    10,
    native_compile_limits(),
  ).unwrap()
  let candidate = @duckdb_query.duckdb_native_candidate(
    @connector.capability_registration_at(registry, 0).unwrap(),
    preparation,
    [
      {
        work_slots: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
        milliseconds: Some(10L),
      },
    ],
    { transfer_bytes: None, retained_bytes: None, money_units: None, },
    100,
  ).unwrap()
  guard @planning.choose_acquisition_candidate(
      registry,
      requirement,
      [@planning.prepared_acquisition_candidate(candidate)],
      None,
      100,
    ).unwrap()
    is Proposed(choice) else {
    fail("native Source candidate not selected")
  }
  let (query_body, evidence_body) = query_evidence_test_bodies()
  let dependencies = @planning.admit_query_evidence_contracts(
    query_body,
    evidence_body,
    query_capture_limits(),
  ).unwrap()
  let contract = @planning.admit_query_two_receipt_contract(
    dependencies,
    query_two_receipt_test_body(),
    query_capture_limits(),
  ).unwrap()
  (
    graph,
    @acquisition_host.configure_native_host(
      contract,
      requirement,
      choice,
      candidate,
      native_runtime_limits(),
    ),
    requirement,
  )
}

///|
fn resident_native_source_evidence_catalog() -> @environment.SourceRequestContracts {
  let snapshot =
    #|[{"carrier_schema_contract_cid":"sha256:19f617653f557bcc5e2d851a889101df45e60326a4192a6fe5b109ccef4d0a1e","data_classification":"unknown","output_carrier":"relation","read_mode":"snapshot","source_contract_cid":"sha256:1f5ce9a50072a24f9cf0673d174f4f0639a216cc5537277e15299fef59db921f","source_data_policy_cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","source_ref":"connector://crm/main/r#v","source_view_contract_cid":"sha256:1f5ce9a50072a24f9cf0673d174f4f0639a216cc5537277e15299fef59db921f"}]
  let capabilities =
    #|[{"capability_contract_cids":["sha256:7d9eec132b742aca27b78a801c6bea187a251b7423967950e285755c50e853d8"],"read_mode":"snapshot","source_contract_cid":"sha256:1f5ce9a50072a24f9cf0673d174f4f0639a216cc5537277e15299fef59db921f","source_ref":"connector://crm/main/r#v","source_view_contract_cid":"sha256:1f5ce9a50072a24f9cf0673d174f4f0639a216cc5537277e15299fef59db921f"}]
  query_program_catalog_fixture(
    schema_snapshots=snapshot,
    connector_capabilities=capabilities,
  )
}

///|
test "resident Source exports a preconfigured read-only DuckDB acquisition" {
  guard native_resident_test_prerequisites() is Some((library_path, root_path)) else {
    return
  }
  let name = "resident-source-" + @env.now().to_string() + ".duckdb"
  let path = root_path + "/" + name
  let root = @native_filesystem.open_root(root_path).unwrap()
  let library = @native_duckdb.load_library(library_path).unwrap()
  // Test setup alone creates the dedicated database. Acquisition opens the
  // already configured file read-only with external access disabled.
  let database = library
    .open_database(@native_duckdb.restricted_open_limits(134217728L), path~)
    .unwrap()
  native_runtime_command(database, "CREATE TABLE records(id DOUBLE)")
  native_runtime_command(
    database, "INSERT INTO records VALUES (3.0), (1.0), (2.0)",
  )
  database.close()
  let database = library
    .open_database(
      { ..@native_duckdb.restricted_open_limits(134217728L), read_only: true, },
      path~,
    )
    .unwrap()
  assert_true(
    database.stream_query("DELETE FROM records", 1, 1L, 1, 256) is Err(_),
  )
  let (graph, setup, requirement) = resident_native_source_setup(
    evidence_members=true,
  )
  assert_eq(@strategy.graph_task_count(graph), 1)
  database.close()
  let binding = @native_host.prepare_native_read_only_source_binding(
    setup, path, 134217728L,
  ).unwrap()
  let (_, foreign_setup, _) = resident_native_source_setup(nullable=true)
  let foreign_path = root_path + "/unconfigured-source.duckdb"
  let foreign_binding = @native_host.prepare_native_read_only_source_binding(
    foreign_setup, foreign_path, 134217728L,
  ).unwrap()
  assert_true(
    @native_host.open_native_read_only_source_acquisition(
      foreign_binding, setup, library, "foreign-source",
    )
    is Err(ForeignSource),
  )
  assert_eq(
    root.inspect_generation("unconfigured-source.duckdb").unwrap(),
    None,
  )
  let runtime = @native_host.open_native_read_only_source_acquisition(
    binding, setup, library, "resident-native-source",
  ).unwrap()
  assert_true(
    @native_host.native_acquisition_runtime_source_capture(runtime) is Err(_),
  )
  @native_host.execute_native_acquisition_runtime(runtime).unwrap() |> ignore
  let capture = @native_host.native_acquisition_runtime_source_capture(runtime).unwrap()
  let source = @acquisition_host.native_host_source_capture_source(capture).unwrap()
  let limits = native_publication_export_limits()
  let identity = @query.identify_captured_source_relation(
    source,
    limits.max_rows,
    limits.values,
    limits.payload_wire,
    limits.logical_wire,
    limits.schema,
    limits.max_batch_bytes,
  ).unwrap()
  let logical = @publication_host.issue_captured_source_input_logical(
    graph, source, identity, requirement,
  ).unwrap()
  let source_context = @acquisition_host.prepare_native_source_evidence_context(
    requirement,
  ).unwrap()
  let scope = "sha256:" + "a".repeat(64)
  let policy = "sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf"
  let source_evidence = @acquisition_host.issue_native_host_source_evidence(
    capture, source_context, identity, logical, scope, policy, "2026-10-03T00:00:01.000Z",
  ).unwrap()
  assert_true(
    @publication.admit_completed_source_observation_binding(
      source_evidence, logical, "connector://crm/main/r#v", "sha256:1f5ce9a50072a24f9cf0673d174f4f0639a216cc5537277e15299fef59db921f",
      scope, policy, 32768, 256, 16,
    )
    is Ok(_),
  )
  assert_true(
    @acquisition_host.issue_native_host_source_evidence(
      capture,
      source_context,
      identity,
      logical,
      scope,
      "sha256:" + "b".repeat(64),
      "2026-10-03T00:00:01.000Z",
    )
    is Err(InvalidPolicy),
  )
  assert_true(
    @publication.run_evidence_value_json(logical).contains(
      "actql-source-input-logical/0.1",
    ),
  )
  assert_true(
    @publication_host.issue_captured_source_input_logical(
      graph,
      source,
      identity,
      requirement,
      task=1,
    )
    is Err(ForeignPrepared),
  )
  let (_, _, foreign_requirement) = resident_native_source_setup()
  assert_true(
    @publication_host.issue_captured_source_input_logical(
      graph, source, identity, foreign_requirement,
    )
    is Err(ForeignRequirement),
  )
  let ledger = @resources.create_ledger({
    planning_work: 10000,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 300000L,
    retained_bytes: 32000000L,
    execution_bytes: 134217728L,
  }).unwrap()
  let run = @strategy.open_captured_dag(graph, source, ledger).unwrap()
  let output = @publication_host.prepare_captured_result_publication_export(
    run,
    0,
    native_publication_export_limits(),
  ).unwrap()
  @strategy.close_captured_task_output(run, 0)
  let body = StringBuilder()
  while output.next().unwrap() is Some(chunk) {
    body.write_string(chunk)
  }
  body.write_string(output.finish().unwrap())
  // Logical filter id > 1 and projection id, followed by the checked
  // publication order (id ascending), independent from physical arrival.
  assert_eq(body.to_string(), "[{\"id\":2},{\"id\":3}]")
  assert_eq(output.result_fields().unwrap(), ["id"])
  assert_eq(output.row_count().unwrap(), 2)
  assert_eq(@strategy.next_captured_task(run), None)
  output.cancel()
  @strategy.stop_captured_dag(run)
  @native_host.close_native_acquisition_runtime(runtime)
  @native_host.close_native_acquisition_runtime(runtime)
  assert_true(
    @acquisition_host.issue_native_host_source_evidence(
      capture, source_context, identity, logical, scope, policy, "2026-10-03T00:00:01.000Z",
    )
    is Err(ObservationMismatch),
  )
  assert_true(
    @native_host.native_acquisition_runtime_source_capture(runtime) is Err(_),
  )
  assert_true(
    @acquisition_host.native_host_source_capture_source(capture) is Err(_),
  )
  assert_true(@native_host.native_acquisition_runtime_output(runtime) is Err(_))
  assert_native_resident_ledger_released(run)
  // Reclaim only this test's exact file generation after the owner stopped.
  let generation = root.inspect_generation(name).unwrap().unwrap()
  root.reclaim_generation(name, generation).unwrap()
  root.sync_directory().unwrap()
  assert_eq(root.inspect_generation(name).unwrap(), None)
}
