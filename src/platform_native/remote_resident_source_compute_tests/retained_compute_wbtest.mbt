// Real DuckDB acquisition, filesystem Transfer and Native Compute. The producer
// protocol record below is an explicit fixture, not durable remote execution
// evidence. Public Cloud dispatch and formal Run release remain separate gates.

///|
fn retained_compute_cid(unit : String) -> String {
  "sha256:" + unit.repeat(64)
}

///|
fn retained_compute_run(
  prepared : @host.PreparedClientProgram,
) -> (
  @host.ClientTaskCompilation,
  @host.ClientCompiledRun,
  @publication.PublicationContract,
  @host.ClientRequestIdentity,
) {
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
  let allowed = @host.issue_client_task_compiled_run(
    prepared,
    compilation,
    retained_compute_cid("a"),
    retained_compute_cid("b"),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @host.issue_client_compiled_run_definition(
    allowed, "retained-compute", "original-run", "2026-10-05T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let request = @host.prepare_source_free_client_request_identity(
    prepared,
    retained_compute_cid("c"),
    "retained-compute-caller",
  ).unwrap()
  (compilation, allowed, definition, request)
}

///|
fn retained_compute_selection() -> @host.ClientValuesSiteSelection {
  {
    site_key: "retained-native",
    site_generation: 1,
    runtime_bundle_cid: retained_compute_cid("a"),
    connector_registration: "local",
    connector_revision: "local/1",
    strategy_revision: "strategy/1",
    obligations_cid: retained_compute_cid("2"),
    budget_cid: retained_compute_cid("3"),
    evidence_issuer_capability_cid: retained_compute_cid("4"),
    grant_cid: retained_compute_cid("5"),
  }
}

///|
fn retained_compute_producer_fixture(
  edge : @host.ClientRetainedInputEdge,
  request : @remote.DispatchRequest,
  physical : @manifest.PhysicalManifest,
) -> (@host.ClientRetainedInputProducer, @site.ExecutionSite) {
  let site = @site.create_site(
    "retained-native",
    1,
    retained_compute_cid("a"),
    4,
    4,
    536870912L,
    536870912L,
  ).unwrap()
  let journal = @remote.create_site_dispatch_journal(
    site, "actql-remote-site/0.1",
  ).unwrap()
  let record = @remote.commit_dispatch_acceptance(
      @remote.prepare_dispatch_acceptance(journal, request).unwrap(),
      true,
    ).unwrap().1
  let holding = @remote.remote_output_holding_evidence_cid(
    request,
    "original-source-material",
    physical.referenced_bytes,
  ).unwrap()
  @remote.restore_dispatch_record(
    record, 4, 3, 1, 0, true, false, "original-source-material", holding, "",
  ).unwrap()
  let subject = @remote.prepare_remote_managed_output_subject(
    @remote.dispatch_request_identity(request),
    "original-source-material",
    holding,
    retained_compute_cid("6"),
    physical.schema_contract_cid,
    physical.view_contract_cid,
    physical.codec_contract_cid,
    physical.manifest_cid,
    retained_compute_cid("b"),
    physical.row_count,
    physical.referenced_bytes,
  ).unwrap()
  let issuer = @remote.register_remote_evidence_issuer(
    site,
    retained_compute_cid("a"),
    "local",
    "local/1",
    "strategy/1",
    @remote.remote_managed_output_evidence_kind(),
    retained_compute_cid("4"),
  ).unwrap()
  let evidence = @remote.issue_remote_managed_output_evidence(
    issuer, record, subject,
  ).unwrap()
  @remote.commit_dispatch_transition(
    @remote.prepare_durable_execution_evidence(record, evidence).unwrap(),
    true,
  ).unwrap()
  |> ignore
  (
    @host.prepare_client_retained_input_producer(
      edge, record, evidence, subject,
    ).unwrap(),
    site,
  )
}

///|
fn retained_compute_input_limits() -> @output.NativeRemoteStandardTransferSourceLimits {
  {
    max_rows: 10,
    max_wire_bytes: 1000,
    max_read_bytes: 3,
    max_entries: 100,
    max_name_bytes: 10000,
    values: {
      max_nodes: 10000,
      max_text_bytes: 100000,
      max_depth: 10,
      max_work: 200000,
    },
    wire: { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
  }
}

///|
fn retained_compute_case(cancel_before_start : Bool) -> Unit raise {
  guard resident_compute_prerequisites() is Some((library_path, root_path)) else {
    return
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(sqlite_path) else {
    abort("retained Native diagnostic requires SQLite")
  }
  let library = @duckdb.load_library(library_path).unwrap()
  let root = @filesystem.open_root(root_path).unwrap()
  let name = "retained-compute-" + @env.now().to_string() + ".duckdb"
  let path = root_path + "/" + name
  resident_compute_database(library, path)
  let prepared = resident_compute_prepared()
  let configuration = resident_compute_configuration(library, path)
  let configuration = {
    ..configuration,
    source: {
      ..configuration.source,
      ledger: {
        ..configuration.source.ledger,
        retained_bytes: 536870912L,
        execution_bytes: 536870912L,
      },
    },
  }
  let acquisitions = Ref(0)
  let producer_captures = Ref(0)
  let source_owner = match
    @resident.open_resident_source_compute(prepared, configuration, name, observe=event => {
      match event {
        AcquisitionEntered => acquisitions.val += 1
        ProducerCaptured => producer_captures.val += 1
        _ => ()
      }
      true
    }) {
    Ok(value) => value
    Err((_, failure)) => {
      @output.retry_native_remote_standard_input_failure_cleanup(failure)
      |> ignore
      fail("actual producer Source acquisition failed")
    }
  }
  let source_export = source_owner
    .prepare_source_export(resident_compute_limits())
    .unwrap()
  let chunks : Array[Bytes] = []
  while @execution.next_completed_output_export_canonical_row(
          source_export, 100, 20, 4,
        ).unwrap()
        is Some((_, wire, _)) {
    // The export documents its leading array/comma framing separately from
    // the canonical row. The installed Transfer codec stores that exact row.
    chunks.push(@utf8.encode(wire[1:].to_owned()))
  }
  let (receipt, _) = @execution.finish_completed_relation_export(source_export).unwrap()
  assert_eq(chunks.length(), 3)
  assert_eq(acquisitions.val, 1)
  assert_eq(producer_captures.val, 1)
  let (compilation, allowed, definition, caller) = retained_compute_run(
    prepared,
  )
  let admission = @host.client_compiled_run_admission(allowed)
  let edge = @host.prepare_client_retained_input_edge(
    prepared, compilation, admission, definition, 1, 0,
  ).unwrap()
  let ports = @host.client_retained_input_edge_projection(edge)
  let bytes = chunks.fold(init=0L, (sum, chunk) => {
    sum + chunk.length().to_int64()
  })
  // These codec/view pins register the existing one-canonical-row-per-chunk
  // Native input implementation. They do not authorize producer completion.
  let physical = @manifest.admit(
    "actql-managed-physical-manifest/0.1",
    ports[4],
    retained_compute_cid("7"),
    retained_compute_cid("8"),
    chunks.length(),
    chunks.map(chunk => "sha256:" + @sha.hex(chunk)),
    chunks.map(chunk => chunk.length().to_int64()),
    chunks.map(_ => 1),
    8,
    4096,
    bytes,
  ).unwrap()
  let selected = retained_compute_selection()
  let producer_dispatch = @host.prepare_client_task_dispatch(
    prepared, compilation, admission, definition, caller, 0, 1, "producer", selected,
  ).unwrap()
  let (producer, site) = retained_compute_producer_fixture(
    edge, producer_dispatch, physical,
  )
  let current = @output.install_native_remote_retained_input_current(
    () => site,
    () => retained_compute_cid("c"),
    () => 1791158400000L,
    (_, _) => true,
  )
  let request = @transfer.prepare_request(
    retained_compute_cid("c"),
    "same-run-transfer",
    @transfer.DirectStream,
    "retained-native",
    1,
    "retained-native",
    1,
    "original-source-material",
    physical,
    bytes,
    4102444800000L,
    retained_compute_cid("4"),
    retained_compute_cid("5"),
    retained_compute_cid("6"),
  ).unwrap()
  let sqlite = @sqlite.load_library(sqlite_path).unwrap()
  let journal_path = root_path + "/" + name + ".destination.sqlite"
  let journal = @journal.open_journal(
    sqlite, journal_path, 1048576L, 8, 4096, 1024L,
  ).unwrap()
  @transfer_client.admit_durable_direct_destination(
    journal, request, 536870912L, 8L,
  ).unwrap()
  |> ignore
  for index, chunk in chunks {
    @transfer_client.write_durable_direct_destination_chunk(
      journal, root, request, index, chunk,
    ).unwrap()
    |> ignore
  }
  @transfer_client.commit_durable_direct_destination(journal, root, request).unwrap()
  |> ignore
  assert_eq(journal.destination_capacity_usage().unwrap().reserved_bytes, bytes)
  assert_true(source_owner.usage().held_bytes > 0L)
  assert_true(journal.close())
  // Reconstruct after commit, before borrowing. No Source owner is reopened.
  let journal = @journal.open_journal(
    sqlite, journal_path, 1048576L, 8, 4096, 1024L,
  ).unwrap()
  let committed = @transfer_client.commit_durable_direct_destination(
    journal, root, request,
  ).unwrap()
  let destination = journal
    .inspect_destination_receipt(request)
    .unwrap()
    .unwrap()
  let input = @output.prepare_native_remote_retained_task_input(
    producer, committed, destination, "direct-destination", current, 262144,
  ).unwrap()
  let common_current = @host.install_client_retained_input_current(
    () => site,
    () => retained_compute_cid("c"),
    () => 1791158400000L,
    (_, _) => true,
  )
  let common_input = @host.prepare_client_retained_task_input(
    producer, committed, destination, "direct-destination", common_current, 262144,
  ).unwrap()
  let dispatch = @host.prepare_client_retained_task_dispatch(
    prepared, compilation, admission, definition, caller, 1, 1, "consumer", selected,
    common_input, common_current,
  ).unwrap()
  let material = @transfer_client.pin_durable_direct_destination_material(
    journal,
    root,
    request,
    @remote.dispatch_request_identity(dispatch),
    @transfer.destination_receipt_cid(destination),
  ).unwrap()
  @transfer_client.validate_destination_material_use(material).unwrap()
  assert_true(journal.close())
  // A durable borrow acquired before interruption can be reattached by the
  // same consumer identity without increasing the physical reservation.
  let journal = @journal.open_journal(
    sqlite, journal_path, 1048576L, 8, 4096, 1024L,
  ).unwrap()
  let material = @transfer_client.pin_durable_direct_destination_material(
    journal,
    root,
    request,
    @remote.dispatch_request_identity(dispatch),
    @transfer.destination_receipt_cid(destination),
  ).unwrap()
  @transfer_client.validate_destination_material_use(material).unwrap()
  assert_eq(journal.destination_capacity_usage().unwrap().reserved_bytes, bytes)
  let saved_binding = @output.native_remote_retained_task_input_binding(input)
  let restored_binding = @remote.prepare_remote_input_binding(
    @remote.remote_input_binding_body(saved_binding),
    262144,
  ).unwrap()
  assert_eq(
    @remote.remote_input_binding_cid(restored_binding),
    @remote.remote_input_binding_cid(saved_binding),
  )
  let input = @output.admit_native_remote_retained_task_input(
    restored_binding, producer, committed, destination, "direct-destination", current,
    262144,
  ).unwrap()
  let cleanup_owner = @transfer_client.pin_durable_direct_destination_material(
    journal,
    root,
    request,
    "destination-cleanup-owner",
    @transfer.destination_receipt_cid(destination),
  ).unwrap()
  let codec = @output.register_native_remote_standard_row_codec(
    physical.schema_contract_cid,
    physical.view_contract_cid,
    physical.codec_contract_cid,
  ).unwrap()
  // Delete only the fixture's Source pathname. The receiver must consume its
  // independent physical holding; opening the configured database now fails.
  resident_compute_reclaim(root, name)
  let foreign_site = @site.create_site(
    "retained-native",
    2,
    retained_compute_cid("a"),
    4,
    4,
    536870912L,
    536870912L,
  ).unwrap()
  let stale = @output.install_native_remote_retained_input_current(
    () => foreign_site,
    () => retained_compute_cid("c"),
    () => 1791158400000L,
    (_, _) => true,
  )
  let (issue, failed) = @resident.open_resident_retained_compute(
    prepared,
    configuration,
    input,
    material,
    dispatch,
    codec,
    retained_compute_input_limits(),
    stale,
  ).unwrap_err()
  assert_true(
    issue is RetainedInput(@output.Input(@output.StaleSiteGeneration)),
  )
  assert_true(
    @output.retry_native_remote_standard_input_failure_cleanup(failed),
  )
  assert_true(@transfer_client.destination_material_use_available(material))
  assert_eq(journal.destination_capacity_usage().unwrap().reserved_bytes, bytes)
  let entries = Ref(0)
  let consumer = match
    @resident.open_resident_retained_compute(
      prepared,
      configuration,
      input,
      material,
      dispatch,
      codec,
      retained_compute_input_limits(),
      current,
      observe=event => {
        match event {
          AcquisitionEntered =>
            abort("retained consumer attempted Source acquisition")
          ConsumerEntered(1) => entries.val += 1
          _ => ()
        }
        true
      },
    ) {
    Ok(value) => value
    Err((issue, failure)) => {
      @output.retry_native_remote_standard_input_failure_cleanup(failure)
      |> ignore
      let code = match issue {
        RetainedInput(@output.Source(input_failure)) =>
          @output.native_remote_standard_input_failure_code(input_failure)
        RetainedInput(@output.ForeignCapture) => "foreign-capture"
        RetainedInput(@output.ForeignConsumer) => "foreign-consumer"
        RetainedInput(@output.Input(_)) => "retained-input"
        Capacity(_) => "capacity"
        Run(_) => "captured-run"
        Dispatch(_) => "dispatch"
        Compute(_) => "native-compute"
        _ => "other"
      }
      fail("Native retained consumer preparation failed: " + code)
    }
  }
  // The existing destination cleanup Owner must wait for the consumer's
  // durable borrow, including a pre-start interruption.
  assert_true(
    @transfer_client.reclaim_durable_destination_material(cleanup_owner)
    is Err(Durable(@journal.MaterialInUse)),
  )
  assert_eq(journal.destination_capacity_usage().unwrap().reserved_bytes, bytes)
  if cancel_before_start {
    assert_true(consumer.close())
    assert_true(consumer.close())
    assert_true(consumer.execute_task(1) is Err(Unavailable))
    assert_eq(entries.val, 0)
    assert_eq(consumer.usage().held_bytes, 0L)
    assert_eq(
      journal.destination_capacity_usage().unwrap().reserved_bytes,
      bytes,
    )
    assert_true(
      @transfer_client.reclaim_durable_destination_material(cleanup_owner).unwrap(),
    )
    assert_false(
      @transfer_client.reclaim_durable_destination_material(cleanup_owner).unwrap(),
    )
    assert_eq(journal.destination_capacity_usage().unwrap().reserved_bytes, 0L)
    @execution.cancel_completed_relation_export_receipt(receipt)
    @execution.cancel_completed_output_export(source_export)
    assert_true(source_owner.close())
    assert_eq(source_owner.usage().held_bytes, 0L)
    assert_eq(acquisitions.val, 1)
    assert_eq(producer_captures.val, 1)
    assert_true(journal.close())
    return
  }
  resident_compute_execute(consumer) |> ignore
  let source_usage = source_owner.usage()
  let consumer_usage = consumer.usage()
  let overlapping_bytes = source_usage.held_bytes +
    source_usage.reserved_retention_bytes +
    source_usage.reserved_execution_bytes +
    consumer_usage.held_bytes +
    consumer_usage.reserved_retention_bytes +
    consumer_usage.reserved_execution_bytes +
    bytes
  assert_true(
    overlapping_bytes <= 536870912L,
    msg=overlapping_bytes.to_string(),
  )
  assert_true(consumer.execute_task(1) is Err(Unavailable))
  assert_eq(entries.val, 1)
  let output = consumer
    .prepare_result_export(resident_compute_limits())
    .unwrap()
  let rows = StringBuilder()
  while output.next().unwrap() is Some(chunk) {
    rows.write_string(chunk)
  }
  rows.write_string(output.finish().unwrap())
  assert_eq(rows.to_string(), "[{\"id\":3}]")
  assert_eq(
    output.result_schema_wire().unwrap(),
    "{\"id\":{\"nullable\":false,\"type\":\"number\"}}",
  )
  assert_false(consumer.close())
  assert_true(consumer.usage().held_bytes > 0L)
  assert_eq(journal.destination_capacity_usage().unwrap().reserved_bytes, bytes)
  output.cancel()
  assert_true(consumer.close())
  assert_true(consumer.close())
  assert_eq(consumer.usage().held_bytes, 0L)
  assert_eq(consumer.usage().reserved_execution_bytes, 0L)
  assert_false(@transfer_client.destination_material_use_available(material))
  // Borrow return frees neither physical holding nor producer capture.
  assert_eq(journal.destination_capacity_usage().unwrap().reserved_bytes, bytes)
  assert_true(source_owner.usage().held_bytes > 0L)
  assert_true(
    @transfer_client.reclaim_durable_destination_material(cleanup_owner).unwrap(),
  )
  assert_false(
    @transfer_client.reclaim_durable_destination_material(cleanup_owner).unwrap(),
  )
  assert_eq(journal.destination_capacity_usage().unwrap().reserved_bytes, 0L)
  assert_eq(journal.destination_capacity_usage().unwrap().reserved_objects, 0L)
  @execution.cancel_completed_relation_export_receipt(receipt)
  @execution.cancel_completed_output_export(source_export)
  assert_true(source_owner.close())
  assert_true(source_owner.close())
  assert_eq(source_owner.usage().held_bytes, 0L)
  assert_eq(source_owner.usage().reserved_execution_bytes, 0L)
  assert_eq(acquisitions.val, 1)
  assert_eq(producer_captures.val, 1)
  assert_eq(entries.val, 1)
  assert_true(journal.close())
}

///|
test "retained Direct holding survives journal reconstruction and feeds Native consumer without Source IO" {
  retained_compute_case(false)
}

///|
test "retained Native cancellation before consumer start returns borrow before each holding cleanup" {
  retained_compute_case(true)
}
