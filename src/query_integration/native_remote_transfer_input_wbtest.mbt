///|
fn remote_transfer_input_cid(unit : String) -> String {
  "sha256:" + unit.repeat(64)
}

///|
fn remote_transfer_input_request(
  chunks : Array[Bytes],
) -> @transfer.RemoteTransferRequest {
  let mut referenced_bytes = 0L
  for chunk in chunks {
    referenced_bytes = referenced_bytes + chunk.length().to_int64()
  }
  let manifest = @manifest.admit(
    "actql-managed-physical-manifest/0.1",
    remote_transfer_input_cid("1"),
    remote_transfer_input_cid("2"),
    remote_transfer_input_cid("3"),
    chunks.length(),
    chunks.map(chunk => "sha256:" + @sha.hex(chunk)),
    chunks.map(chunk => chunk.length().to_int64()),
    chunks.map(_ => 1),
    8,
    4096,
    referenced_bytes,
  ).unwrap()
  @transfer.prepare_request(
    "native-coordinator",
    "standard-input-transfer-1",
    @transfer.TransferStore,
    "native-source",
    2,
    "native-destination",
    3,
    "standard-input-source-material",
    manifest,
    referenced_bytes,
    4102444800000L,
    remote_transfer_input_cid("4"),
    remote_transfer_input_cid("5"),
    remote_transfer_input_cid("6"),
  ).unwrap()
}

///|
test "standard Local reads the exact committed Transfer destination" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY") is Some(http_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_URL") is Some(origin) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CA") is Some(ca) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CERT") is Some(cert) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_KEY") is Some(key) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(sqlite_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(sqlite_root) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") is Some(store_root) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY")
    is Some(crypto_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_REMOTE_TRANSFER_STANDARD_ROOT")
    is Some(runtime_root_path) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_TARGET")
    is Some(runtime_target) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_PUBLIC_KEY")
    is Some(runtime_public_key) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_BODY")
    is Some(runtime_bundle_body) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_CID")
    is Some(runtime_bundle_cid) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_REMOTE_RUNTIME_SIGNATURE")
    is Some(runtime_signature) else {
    return
  }
  let http = @native_http.load_library(http_path).unwrap()
  let client = http.create_client(ca, cert, key, 4096L, 2000, 5000).unwrap()
  let sqlite = @native_sqlite.load_library(sqlite_path).unwrap()
  let source_journal = @native_transfer_journal.open_journal(
    sqlite,
    sqlite_root + "/standard-input-source.sqlite",
    1048576L,
    8,
    4096,
    1024L,
  ).unwrap()
  let destination_journal = @native_transfer_journal.open_journal(
    sqlite,
    sqlite_root + "/standard-input-destination.sqlite",
    1048576L,
    8,
    4096,
    1024L,
  ).unwrap()
  let root = @native_filesystem.open_root(store_root).unwrap()
  let chunks = [@utf8.encode("{\"id\":3}"), @utf8.encode("{\"id\":2}")]
  let request = remote_transfer_input_request(chunks)
  ignore(
    @native_transfer.send_durable_store_upload(
      source_journal, client, origin, request, chunks,
    ).unwrap(),
  )
  let destination_use_id = "standard-input-use"
  let transferred = @native_transfer.receive_durable_store_transfer(
    destination_journal, client, root, origin, request, destination_use_id, 1048576L,
    8L,
  ).unwrap()
  assert_true(@transfer.record_is_destination_committed(transferred))
  let receipt = destination_journal
    .inspect_destination_receipt(request)
    .unwrap()
    .unwrap()
  let input = @native_remote_standard.prepare_native_remote_standard_transfer_input(
    request,
    destination_use_id,
    @transfer.destination_receipt_cid(receipt),
    131072,
  ).unwrap()
  let codec = @native_remote_standard.register_native_remote_standard_row_codec(
    remote_transfer_input_cid("1"),
    remote_transfer_input_cid("2"),
    remote_transfer_input_cid("3"),
  ).unwrap()
  let program = query_checked_program_fixture(dag=true)
  let sequence = query_checked_sequence(program)
  let foreign = @native_remote_standard.prepare_native_remote_standard_transfer_input(
    request,
    destination_use_id,
    remote_transfer_input_cid("f"),
    131072,
  ).unwrap()
  assert_true(
    @native_remote_standard.acquire_native_remote_standard_transfer_source(
      destination_journal,
      root,
      foreign,
      codec,
      sequence,
      @program_check.source_identity(program),
      {
        max_rows: 10,
        max_wire_bytes: 1000,
        max_read_bytes: 4,
        max_entries: 100,
        max_name_bytes: 10000,
        values: {
          max_nodes: 10000,
          max_text_bytes: 100000,
          max_depth: 10,
          max_work: 200000,
        },
        wire: {
          max_bytes: 100,
          max_nodes: 20,
          max_depth: 4,
          max_text_bytes: 100,
        },
      },
    )
    is Err(_),
  )
  let owners = physical_graph_owners(program)
  owners[0] = @query.query_sequence_owner(sequence)
  let graph = @strategy.prepare_checked_dag(
    program,
    owners,
    @program_check.unit_count(program),
    1000,
  ).unwrap()
  let crypto = @native_signature.load_library(crypto_path).unwrap()
  let runtime_root = @native_filesystem.open_root(runtime_root_path).unwrap()
  let runtime_component = b"native-runtime"
  let runtime_writer = runtime_root
    .create_writer("runtime-stage", runtime_component.length().to_int64())
    .unwrap()
  runtime_writer.append(runtime_component).unwrap()
  let runtime_generation = runtime_writer.seal("runtime-component").unwrap()
  let bundles = @native_runtime_bundle.open_runtime_bundle_store(
    sqlite,
    crypto,
    runtime_root_path,
    [
      {
        issuer_authority: "bundle-authority-a",
        key_id: "key-a",
        public_key_pem: runtime_public_key,
      },
    ],
    runtime_target,
    runtime_component.length().to_int64(),
    4,
    8,
    262144L,
  ).unwrap()
  bundles
  .adopt(
    "actql-remote-runtime-bundle-signature/0.1", "key-a", runtime_bundle_cid, runtime_bundle_body,
    runtime_signature, "runtime-component", runtime_generation,
  )
  .unwrap()
  |> ignore
  bundles.activate(runtime_bundle_cid).unwrap() |> ignore
  let active_runtime = bundles
    .acquire_active_component(
      "sha256:" + @sha.hex(runtime_component),
      runtime_target,
      "runtime-process:standard-transfer-input",
    )
    .unwrap()
  let site = @site.create_site(
    "native-standard-transfer-site", 1, runtime_bundle_cid, 2, 2, 1048576L, 268435456L,
  ).unwrap()
  let journal_control = @remote.create_site_dispatch_journal(
    site, "actql-remote-site/0.1",
  ).unwrap()
  let remote_journal = @native_remote_journal.open_journal(
    sqlite,
    runtime_root_path + "/standard-transfer-journal.sqlite3",
    262144L,
    journal_control,
  ).unwrap()
  let captured_runs : Array[@strategy.CapturedDAG] = []
  let executor = @native_remote_standard.install_native_remote_standard_task_executor(
    @strategy.graph_program_definition_cid(graph),
    "task-1-transfer-local",
    1,
    (dispatch, binding) => {
      @native_remote_standard.resolve_native_remote_standard_transfer_run(
        dispatch,
        binding,
        destination_journal,
        root,
        codec,
        sequence,
        @program_check.source_identity(program),
        {
          max_binding_bytes: 131072,
          max_chunks: 8,
          max_manifest_bytes: 4096,
          max_referenced_bytes: 1048576L,
        },
        {
          max_rows: 10,
          max_wire_bytes: 1000,
          max_read_bytes: 4,
          max_entries: 100,
          max_name_bytes: 10000,
          values: {
            max_nodes: 10000,
            max_text_bytes: 100000,
            max_depth: 10,
            max_work: 200000,
          },
          wire: {
            max_bytes: 100,
            max_nodes: 20,
            max_depth: 4,
            max_text_bytes: 100,
          },
        },
        captured_source => {
          try {
            let ledger = @resources.create_ledger({
              planning_work: 10000,
              attempts: 10,
              holdings: 10,
              transfer_bytes: 300000L,
              retained_bytes: 32000000L,
              execution_bytes: 134217728L,
            }).unwrap()
            let captured = @strategy.open_captured_dag(
              graph, captured_source, ledger,
            ).unwrap()
            let registry = search_registry()
            ignore(channel_test_selection(captured, registry))
            let host = @dbhost.configure_strategy_dispatch(
              captured,
              registry,
              @connector.capability_registration_at(registry, 0).unwrap(),
              @connector.capability_registration_at(registry, 1).unwrap(),
              dispatch_test_generated(captured),
              dispatch_test_limits(),
            ).unwrap()
            let run = @native_host.open_native_standard_strategy_run(
              host,
              native_compute_import_limits(),
              100000L,
              1000000L,
            ).unwrap()
            captured_runs.push(captured)
            Ok(run)
          } catch {
            _ => Err(())
          }
        },
      )
    },
    {
      output_export: native_publication_export_limits(),
      max_manifest_bytes: 65536,
      max_retained_bytes: 1048576L,
    },
  ).unwrap()
  let operation_capability = native_publication_cid(
    "remote-standard-transfer-operation-capability",
  )
  let issuer_capability = native_publication_cid(
    "remote-standard-transfer-issuer-capability",
  )
  let budget = @remote.prepare_remote_dispatch_budget(1048576L, 1048576L).unwrap()
  let runtime = @native_remote_standard.open_native_remote_standard_site_runtime(
    site,
    active_runtime,
    operation_capability,
    issuer_capability,
    [executor],
    remote_journal,
    bundles,
    [budget],
  ).unwrap()
  let (connector_registration, connector_revision, strategy_revision) = @native_runtime_bundle.native_active_runtime_connector_scope(
    active_runtime,
  )
  let input_binding = @native_remote_standard.native_remote_standard_transfer_binding(
    input,
  )
  let dispatch = @remote.prepare_dispatch_request(
    "native-standard-transfer-coordinator",
    @strategy.graph_program_definition_cid(graph),
    "task-1-transfer-local",
    1,
    "native-standard-transfer-dispatch-1",
    "native-standard-transfer-site",
    1,
    runtime_bundle_cid,
    connector_registration,
    connector_revision,
    strategy_revision,
    @remote.remote_input_binding_cid(input_binding),
    native_publication_cid("remote-standard-transfer-obligations"),
    @remote.remote_dispatch_budget_cid(budget),
    issuer_capability,
    operation_capability,
  ).unwrap()
  let dispatch_operation = @remote.remote_poll_dispatch_json(
    dispatch, input_binding,
  ).unwrap()
  let queued = client
    .post_json(
      origin + "/standard-transfer/queue",
      @utf8.encode(dispatch_operation),
    )
    .unwrap()
  assert_eq(queued.status, 201)
  guard @native_remote_agent.run_native_outbound_site_occurrence(
      runtime,
      remote_journal,
      client,
      origin + "/standard-transfer/poll",
      origin + "/standard-transfer/observation",
    )
    is Ok(@native_remote_agent.DispatchObserved(dispatch_identity, _)) else {
    fail("standard Transfer dispatch was not observed over HTTPS")
  }
  assert_eq(dispatch_identity, @remote.dispatch_request_identity(dispatch))
  let observed = remote_journal.observation(dispatch).unwrap()
  let subject = @native_remote_journal.recovered_site_dispatch_subject(observed).unwrap()
  let material_generation = @remote.remote_managed_output_subject_projection(
      subject,
    )[1]
  let output_reader = runtime
    .open_output_reader(dispatch, material_generation, 7)
    .unwrap()
  let output_bytes : Array[Byte] = []
  while true {
    let chunk = output_reader.next().unwrap()
    for byte in chunk.bytes {
      output_bytes.push(byte)
    }
    if chunk.eof {
      break
    }
  }
  assert_eq(@utf8.decode_lossy(Bytes::from_array(output_bytes)), "[{\"id\":3}]")
  assert_true(output_reader.finish().unwrap())
  let release_operation = @remote.remote_poll_release_json(dispatch).unwrap()
  let release_queued = client
    .post_json(
      origin + "/standard-transfer/queue",
      @utf8.encode(release_operation),
    )
    .unwrap()
  assert_eq(release_queued.status, 201)
  guard @native_remote_agent.run_native_outbound_site_occurrence(
      runtime,
      remote_journal,
      client,
      origin + "/standard-transfer/poll",
      origin + "/standard-transfer/observation",
    )
    is Ok(@native_remote_agent.ReleaseObserved(released_identity, _)) else {
    fail("standard Transfer release was not observed over HTTPS")
  }
  assert_eq(released_identity, @remote.dispatch_request_identity(dispatch))
  assert_eq(captured_runs.length(), 1)
  assert_true(runtime.close().unwrap())
  assert_true(remote_journal.close())
  assert_true(bundles.close().unwrap())
  for captured in captured_runs {
    for task = @strategy.graph_task_count(graph) - 1; task > 0; task = task - 1 {
      @strategy.close_captured_task_output(captured, task)
    }
    let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(captured))
    assert_eq(usage.reserved_execution_bytes, 0L)
    assert_eq(usage.reserved_retention_bytes, 0L)
    assert_eq(usage.held_bytes, 0L)
  }
  let cleanup = @native_transfer.pin_durable_store_destination_material(
    destination_journal,
    root,
    request,
    destination_use_id,
    "standard-input-cleanup",
    @transfer.destination_receipt_cid(receipt),
  ).unwrap()
  @native_transfer.validate_destination_material_use(cleanup).unwrap()
  assert_true(
    @native_transfer.reclaim_durable_store_destination_material(cleanup).unwrap(),
  )
  assert_true(destination_journal.close())
  assert_true(source_journal.close())
  assert_true(client.close())
}
