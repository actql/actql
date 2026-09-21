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
  let source_owner = @native_remote_standard.acquire_native_remote_standard_transfer_source(
    destination_journal,
    root,
    input,
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
  ).unwrap()
  let owners = physical_graph_owners(program)
  owners[0] = @query.query_sequence_owner(sequence)
  let graph = @strategy.prepare_checked_dag(
    program,
    owners,
    @program_check.unit_count(program),
    1000,
  ).unwrap()
  let ledger = @resources.create_ledger({
    planning_work: 10000,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 300000L,
    retained_bytes: 32000000L,
    execution_bytes: 134217728L,
  }).unwrap()
  let run = @strategy.open_captured_dag(
    graph,
    @native_remote_standard.native_remote_standard_transfer_captured_source(
      source_owner,
    ),
    ledger,
  ).unwrap()
  captured_graph_local(run, 1).unwrap()
  let output = @strategy.captured_task_output(run, 1, @pipeline.Step(1)).unwrap()
  assert_eq(@execution.completed_row_count(output), 1)
  assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(3)))
  assert_true(
    @native_remote_standard.finish_native_remote_standard_transfer_source(
      source_owner,
    ),
  )
  assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(3)))
  @strategy.stop_captured_dag(run)
  for task in 0..<@program_check.unit_count(program) {
    @strategy.close_captured_task_output(run, task)
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
