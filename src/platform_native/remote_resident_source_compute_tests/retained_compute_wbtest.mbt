// Real DuckDB acquisition, filesystem Transfer and Native Compute. The producer
// protocol record below is an explicit fixture, not durable remote execution
// evidence. Public Cloud dispatch and formal Run release remain separate gates.

///|
fn retained_compute_cid(unit : String) -> String {
  "sha256:" + unit.repeat(64)
}

///|
fn retained_compute_effect_retention() -> @publication.PublicationContract {
  @publication.seal_publication_contract(
    "result_retention_policy",
    "{\"version\":\"actql-result-retention-policy/0.1\",\"retention_contract_cid\":\"" +
    retained_effect_retention_dependency_cid("retention_contract") +
    "\",\"effective_data_policy_cid\":\"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf\",\"available_until\":\"2026-10-10T01:00:00.000Z\",\"delete_by\":\"2026-10-10T02:00:00.000Z\",\"extension_ceiling_at\":\"2026-10-10T03:00:00.000Z\",\"metadata_retention_policy_cid\":\"" +
    retained_effect_retention_dependency_cid("metadata_retention_policy") +
    "\",\"metadata_delete_by\":\"2026-10-10T04:00:00.000Z\",\"clock_contract_cid\":\"" +
    retained_effect_retention_dependency_cid("clock_contract") +
    "\"}",
    32768,
    1000,
    32,
  ).unwrap()
}

///|
fn retained_compute_acquired_evidence(
  owner : @resident.ResidentSourceCompute,
  policy? : String = "sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf",
  max_bytes? : Int = 65536,
) -> Result[
  (@host.ClientEffectAcquiredEvidence, (String, String)),
  @resident.ResidentEffectSourceEvidenceIssue,
] {
  owner.prepare_effect_acquired_evidence(
    retained_compute_cid("a"),
    policy,
    "2026-10-09T01:00:01.000Z",
    retained_compute_effect_retention(),
    resident_compute_limits(),
    max_bytes,
    4096,
    64,
  )
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
fn retained_compute_selection(
  bundle_cid? : String = retained_compute_cid("a"),
  budget_cid? : String = retained_compute_cid("3"),
) -> @host.ClientValuesSiteSelection {
  {
    site_key: "retained-native",
    site_generation: 1,
    runtime_bundle_cid: bundle_cid,
    connector_registration: "local",
    connector_revision: "local/1",
    strategy_revision: "strategy/1",
    obligations_cid: retained_compute_cid("2"),
    budget_cid,
    evidence_issuer_capability_cid: retained_compute_cid("4"),
    grant_cid: retained_compute_cid("5"),
  }
}

///|
fn retained_compute_producer_fixture(
  edge : @host.ClientRetainedInputEdge,
  request : @remote.DispatchRequest,
  physical : @manifest.PhysicalManifest,
) -> (
  @host.ClientRetainedInputProducer,
  @site.ExecutionSite,
  @remote.DispatchRecord,
) {
  let site = @site.create_site(
    "retained-native",
    1,
    @remote.dispatch_request_execution_scope(request)[2],
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
    @remote.dispatch_request_execution_scope(request)[2],
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
    record,
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
fn retained_compute_effect_limits() -> @host.ClientEffectComputationLimits {
  {
    program: @host.client_standard_program_preparation_limits(),
    max_members: 1,
    max_header_work: 1000,
    mapping: {
      max_bytes: 20000,
      max_nodes: 2000,
      max_depth: 100,
      max_members: 100,
    },
    max_mapping_work: 1000,
    effects: {
      max_members: 1,
      max_work: 1000,
      max_admission_nodes: 100,
      max_admission_depth: 10,
      max_admission_text_bytes: 1000,
    },
  }
}

///|
fn retained_compute_effect_materials(
  provider? : Bool = false,
) -> (@host.ClientEffectRunMaterials, @host.ClientRequestIdentity) raise {
  let (wire_environment, environment_cid, document) = if provider {
    resident_provider_environment()
  } else {
    (
      resident_effect_source_environment, resident_effect_source_bundle_cid, resident_native_effect_document,
    )
  }
  if provider {
    println("native-effect-provider: admitting environment")
    match
      @environment.read(@utf8.encode(wire_environment), environment_cid, {
        max_bytes: 65536,
        max_nodes: 4096,
        max_depth: 64,
        max_members: 256,
      }) {
      Ok(_) => ()
      Err(issue) =>
        fail("Provider Check Environment: " + @debug.to_string(issue))
    }
  }
  let environment = @host.admit_client_check_environment(
    wire_environment,
    environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  if provider {
    println("native-effect-provider: preparing checked Program")
  }
  let prepared = @host.prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    retained_compute_effect_limits(),
  ).unwrap()
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
    retained_compute_cid("a"),
    retained_compute_cid("b"),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @host.issue_client_effect_run_definition(
    allowed, "retained-effect", "original-effect-run", "2026-10-09T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let environment = @host.admit_client_check_environment(
    wire_environment,
    environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let limits = retained_compute_effect_limits()
  let caller = @host.prepare_client_effect_request_identity(
    prepared,
    retained_compute_cid("c"),
    "original-effect-caller",
    @host.source_free_caller_input_intent_cid(),
  ).unwrap()
  let wire = @host.issue_client_effect_run_materials(
    allowed,
    definition,
    environment,
    wire_environment,
    document,
    None,
    limits,
    request=Some(caller),
  ).unwrap()
  let materials = @host.admit_client_effect_run_materials(
    wire,
    @publication.publication_contract_identity(definition),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    manifests,
    {
      preparation: @host.client_standard_program_preparation_limits(),
      sequence: @host.client_standard_values_sequence_limits(),
      max_sequence_steps: 1000,
      max_sequence_work: 1000,
      max_evidence_bytes: 1000000,
      max_evidence_nodes: 100000,
      max_evidence_depth: 100,
    },
    limits,
  ).unwrap()
  assert_eq(materials.request, Some(caller))
  (materials, caller)
}

///|
fn retained_compute_case(
  cancel_before_start : Bool,
  through_runtime? : Bool = false,
  effect? : Bool = false,
  through_saved_effect? : Bool = false,
  expire_at_start? : Bool = false,
  probe_proposals? : Bool = false,
  provider? : Bool = false,
  deny_provider? : Bool = false,
  checkpoint_custody? : Bool = false,
) -> Unit raise {
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
  let effect_materials = if effect {
    Some(retained_compute_effect_materials(provider~))
  } else {
    None
  }
  let selected = if through_runtime {
    retained_compute_selection(
      bundle_cid=retained_runtime_required_env(
        "ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_CID",
      ),
      budget_cid=@remote.remote_dispatch_budget_cid(
        @remote.prepare_remote_dispatch_budget(1048576L, 1048576L).unwrap(),
      ),
    )
  } else {
    retained_compute_selection()
  }
  let effect_producer_dispatch = effect_materials.map(pair => {
    @host.prepare_client_effect_source_dispatch(
      pair.0.allowed,
      pair.0.run_definition,
      pair.1,
      1,
      "producer",
      selected,
    ).unwrap()
  })
  let acquisitions = Ref(0)
  let producer_captures = Ref(0)
  let source_observe = event => {
    match event {
      @resident.AcquisitionEntered => acquisitions.val += 1
      @resident.ProducerCaptured => producer_captures.val += 1
      _ => ()
    }
    true
  }
  let source_open = match effect_materials {
    Some((materials, _)) =>
      @resident.open_resident_effect_source_compute(
        @host.bind_client_effect_source_dispatch(
          materials,
          effect_producer_dispatch.unwrap(),
          @host.prepare_client_effect_source_input_binding(
            materials.compilation,
          ).unwrap(),
        ).unwrap(),
        configuration,
        name,
        observe=source_observe,
      )
    None =>
      @resident.open_resident_source_compute(
        prepared,
        configuration,
        name,
        observe=source_observe,
      )
  }
  let source_owner = match source_open {
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
  let acquired = if effect {
    let (evidence, bodies) = retained_compute_acquired_evidence(source_owner).unwrap()
    // Logical Source identity preserves the fixture's (3, 1, 2) acquired
    // sequence. The checked Result projection sorts its exported root view;
    // that view must not silently replace the acquisition observation.
    assert_eq(
      bodies.0,
      "{\"sort\":\"relation\",\"value\":[{\"id\":3},{\"id\":1},{\"id\":2}]}",
    )
    assert_eq(bodies.1, "{\"id\":{\"nullable\":false,\"type\":\"number\"}}")
    let dependencies = @host.client_effect_acquired_dependency_bodies(evidence)
    assert_eq(dependencies.length(), 6)
    let observations = dependencies.filter(entry => entry.0 == "source_evidence")
    assert_eq(observations.length(), 1)
    assert_true(observations[0].1.contains("\"completeness\":\"complete\""))
    assert_true(observations[0].1.contains("\"snapshot_ref\":\"sha256:"))
    assert_true(
      @host.client_effect_acquired_catalog_bodies(evidence, 65536, 4096, 64)
      .unwrap()
      .length() >
      0,
    )
    // A failed evidence projection retains the same acquisition and capacity.
    assert_true(
      retained_compute_acquired_evidence(
        source_owner,
        policy=retained_compute_cid("f"),
      )
      is Err(Observation(InvalidPolicy)),
    )
    assert_true(
      retained_compute_acquired_evidence(source_owner, max_bytes=1)
      is Err(Capture(DependencyBodyLimit)),
    )
    assert_true(source_owner.usage().held_bytes > 0L)
    Some((evidence, bodies))
  } else {
    assert_true(
      retained_compute_acquired_evidence(source_owner) is Err(Unavailable),
    )
    None
  }
  let (compilation, allowed, definition, caller) = retained_compute_run(
    prepared,
  )
  let admission = @host.client_compiled_run_admission(allowed)
  let edge = match effect_materials {
    Some((materials, _)) =>
      @host.prepare_client_effect_retained_input_edge(
        materials.allowed,
        materials.run_definition,
      ).unwrap()
    None =>
      @host.prepare_client_retained_input_edge(
        prepared, compilation, admission, definition, 1, 0,
      ).unwrap()
  }
  let bytes = chunks.fold(init=0L, (sum, chunk) => {
    sum + chunk.length().to_int64()
  })
  // These codec/view pins register the existing one-canonical-row-per-chunk
  // Native input implementation. They do not authorize producer completion.
  let physical = @manifest.admit(
    "actql-managed-physical-manifest/0.1",
    @host.client_retained_input_edge_schema_cid(edge),
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
  let producer_dispatch = match effect_materials {
    Some(_) => effect_producer_dispatch.unwrap()
    None =>
      @host.prepare_client_task_dispatch(
        prepared, compilation, admission, definition, caller, 0, 1, "producer", selected,
      ).unwrap()
  }
  let (producer, site, producer_record) = retained_compute_producer_fixture(
    edge, producer_dispatch, physical,
  )
  let current = @output.install_native_remote_retained_input_current(
    () => site,
    () => retained_compute_cid("c"),
    () => 1791504000000L,
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
    () => 1791504000000L,
    (_, _) => true,
  )
  let common_input = @host.prepare_client_retained_task_input(
    producer, committed, destination, "direct-destination", common_current, 262144,
  ).unwrap()
  let dispatch = match effect_materials {
    Some((materials, caller)) =>
      @host.prepare_client_effect_retained_task_dispatch(
        materials.allowed,
        materials.run_definition,
        caller,
        1,
        "consumer",
        selected,
        common_input,
        common_current,
      ).unwrap()
    None =>
      @host.prepare_client_retained_task_dispatch(
        prepared, compilation, admission, definition, caller, 1, 1, "consumer", selected,
        common_input, common_current,
      ).unwrap()
  }
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
    selected.runtime_bundle_cid,
    4,
    4,
    536870912L,
    536870912L,
  ).unwrap()
  let stale = @output.install_native_remote_retained_input_current(
    () => foreign_site,
    () => retained_compute_cid("c"),
    () => 1791504000000L,
    (_, _) => true,
  )
  let open_consumer = (selected_current, observe) => {
    match effect_materials {
      Some((materials, _)) =>
        @resident.open_resident_effect_retained_compute(
          materials,
          configuration,
          input,
          material,
          dispatch,
          codec,
          retained_compute_input_limits(),
          selected_current,
          observe~,
        )
      None =>
        @resident.open_resident_retained_compute(
          prepared,
          configuration,
          input,
          material,
          dispatch,
          codec,
          retained_compute_input_limits(),
          selected_current,
          observe~,
        )
    }
  }
  let (issue, failed) = open_consumer(stale, _ => true).unwrap_err()
  assert_true(
    issue is RetainedInput(@output.Input(@output.StaleSiteGeneration)),
  )
  assert_true(
    @output.retry_native_remote_standard_input_failure_cleanup(failed),
  )
  assert_true(@transfer_client.destination_material_use_available(material))
  assert_eq(journal.destination_capacity_usage().unwrap().reserved_bytes, bytes)
  if through_runtime {
    retained_compute_through_runtime(
      {
        prepared,
        compilation: @host.Tasks(compilation),
        admission,
        run_definition: definition,
      },
      configuration,
      input,
      material,
      dispatch,
      match effect_materials {
        Some((materials, caller)) =>
          @host.prepare_client_effect_retained_task_dispatch(
            materials.allowed,
            materials.run_definition,
            caller,
            2,
            "different-consumer-attempt",
            selected,
            common_input,
            common_current,
          ).unwrap()
        None =>
          @host.prepare_client_retained_task_dispatch(
            prepared, compilation, admission, definition, caller, 1, 2, "different-consumer-attempt",
            selected, common_input, common_current,
          ).unwrap()
      },
      codec,
      current,
      site,
      root_path,
      name,
      sqlite,
      journal,
      cleanup_owner,
      bytes,
      effect_materials=effect_materials.map(pair => pair.0),
      through_resident=through_saved_effect,
      expire_at_start~,
      restore_effect_input=(rebuilt, saved) => {
        let rebuilt_edge = match
          @host.prepare_client_effect_retained_input_edge(
            rebuilt.allowed,
            rebuilt.run_definition,
          ) {
          Ok(value) => value
          Err(_) => return Err(@output.InvalidBinding)
        }
        if @host.client_retained_input_edge_projection(rebuilt_edge) !=
          @host.client_retained_input_edge_projection(edge) ||
          @host.client_retained_input_edge_schema_cid(rebuilt_edge) !=
          @host.client_retained_input_edge_schema_cid(edge) {
          return Err(@output.InvalidBinding)
        }
        let restored_producer = match
          @host.prepare_client_retained_input_producer(
            rebuilt_edge,
            producer_record,
            @host.client_retained_input_producer_evidence(producer),
            @host.client_retained_input_producer_subject(producer),
          ) {
          Ok(value) => value
          Err(_) => return Err(@output.ProducerUnavailable)
        }
        @output.admit_native_remote_retained_task_input(
          saved, restored_producer, committed, destination, "direct-destination",
          current, 262144,
        )
      },
    )
    @execution.cancel_completed_relation_export_receipt(receipt)
    @execution.cancel_completed_output_export(source_export)
    assert_true(source_owner.close())
    assert_true(source_owner.close())
    assert_eq(source_owner.usage().held_bytes, 0L)
    assert_eq(source_owner.usage().reserved_execution_bytes, 0L)
    assert_eq(acquisitions.val, 1)
    assert_eq(producer_captures.val, 1)
    assert_true(journal.close())
    return
  }
  let stop_custodies : Array[
    (@resident.ResidentEffectSourceCustody, @store.Store),
  ] = []
  let entries = Ref(0)
  let consumer = match
    open_consumer(current, event => {
      match event {
        @resident.AcquisitionEntered =>
          abort("retained consumer attempted Source acquisition")
        @resident.ConsumerEntered(1) => entries.val += 1
        _ => ()
      }
      true
    }) {
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
  let producer_dependency = match effect_materials {
    Some((materials, _)) =>
      Some(
        retained_effect_producer_dependency(
          source_owner,
          materials,
          acquired.unwrap().0,
        ),
      )
    None => None
  }
  assert_eq(entries.val, 0)
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
  if provider {
    assert_eq(rows.to_string(), "[{\"id\":3,\"record\":\"001000000000001\"}]")
    // The fixed 15-byte ASCII literal has the Checker's exact finite bound.
    assert_eq(
      output.result_schema_wire().unwrap(),
      "{\"id\":{\"nullable\":false,\"type\":\"number\"},\"record\":{\"max_utf8_bytes\":15,\"nullable\":false,\"type\":\"string\"}}",
    )
  } else {
    assert_eq(rows.to_string(), "[{\"id\":3}]")
    assert_eq(
      output.result_schema_wire().unwrap(),
      "{\"id\":{\"nullable\":false,\"type\":\"number\"}}",
    )
  }
  let effect_inputs = if effect {
    let effect_run = consumer.effect_run().unwrap()
    let foreign_run = resident_native_effect_bound_run()
    let foreign_occurrence = @strategy.graph_result_occurrence(
      @strategy.checked_effect_run_graph(
        @host.prepared_client_effect_run_graph(foreign_run),
      ),
      0,
    ).unwrap()
    // Equal schema and rows from another checked Owner cannot borrow this
    // receiver's input or consume one of its bounded pin slots.
    assert_true(
      @strategy.borrow_captured_any_result_output(
        @strategy.captured_effect_run_dag(effect_run),
        1,
        foreign_occurrence,
        4,
      )
      is Err(ForeignCandidate),
    )
    Some(@strategy.pin_captured_effect_sources(effect_run, 4).unwrap())
  } else {
    None
  }
  let provider_artifact_bound = Ref(false)
  let pending_effect_export = if provider && effect_inputs is Some(inputs) {
    let facts = resident_provider_observe(
      consumer,
      effect_materials.unwrap().0,
      inputs,
      acquired.unwrap().0,
      dispatch,
      effect_materials.unwrap().1,
      root_path,
      name,
      deny_provider~,
    )
    if facts is Some(facts) {
      let mut effect_index = -1
      let mut root_index = -1
      for index in 0..<@strategy.captured_effect_local_result_count(inputs) {
        if @strategy.captured_effect_local_result_matches_member(
            inputs, index, 0,
          ) {
          effect_index = index
        } else {
          root_index = index
        }
      }
      assert_true(effect_index >= 0 && root_index >= 0)
      let (earlier, earlier_bodies) = acquired.unwrap()
      let (again, again_bodies) = retained_compute_acquired_evidence(
        source_owner,
      ).unwrap()
      assert_eq(again_bodies, earlier_bodies)
      retained_effect_transferred_artifact(
        consumer,
        effect_materials.unwrap().0,
        inputs,
        root_index,
        effect_index,
        earlier,
        earlier_bodies,
        @host.client_effect_acquired_invocation(again),
        producer_dependency.unwrap().0,
        producer_dependency.unwrap().1,
        producer_dependency.unwrap().2,
        producer_dependency.unwrap().4,
        common_input,
        site,
        output,
        stop_custodies,
        provider=Some(facts),
        checkpoint_custody~,
      )
      provider_artifact_bound.val = true
    }
    assert_eq(acquisitions.val, 1)
    assert_eq(producer_captures.val, 1)
    assert_eq(entries.val, 1)
    None
  } else if effect_inputs is Some(inputs) {
    // Independent receiver Cells do not grant the original Native observation.
    assert_true(
      retained_compute_acquired_evidence(consumer) is Err(Unavailable),
    )
    let (earlier, earlier_bodies) = acquired.unwrap()
    let (again, again_bodies) = retained_compute_acquired_evidence(source_owner).unwrap()
    assert_eq(again_bodies, earlier_bodies)
    assert_eq(
      @host.client_effect_acquired_dependency_bodies(again),
      @host.client_effect_acquired_dependency_bodies(earlier),
    )
    assert_eq(acquisitions.val, 1)
    let limits = resident_compute_limits()
    let plan = @strategy.prepare_captured_effect_proposal_plan(
      inputs, 0, 16, 10000,
    ).unwrap()
    let mut effect_local_index = -1
    let mut root_local_index = -1
    for index in 0..<@strategy.captured_effect_local_result_count(inputs) {
      if @strategy.captured_effect_local_result_matches_member(inputs, index, 0) {
        effect_local_index = index
      } else {
        root_local_index = index
      }
    }
    assert_true(effect_local_index >= 0 && root_local_index >= 0)
    if probe_proposals {
      retained_effect_proposal_inputs(
        consumer, source_owner, inputs, effect_local_index, root_local_index,
      )
    }
    let root_result = @strategy.captured_effect_local_result_at(
      inputs, root_local_index,
    ).unwrap()
    let root_output = @strategy.captured_any_result_borrow_cell_output(
      @strategy.captured_effect_local_result_borrow(root_result),
    ).unwrap()
    // A producer completion in this same Run cannot stand in for the
    // consumer's pinned Result, even though both have the same schema.
    assert_true(
      @strategy.start_captured_effect_local_result_export(
        inputs,
        effect_local_index,
        {
          max_fields: limits.max_result_fields,
          max_mapping_work: limits.max_result_mapping_work,
          max_order_work: limits.max_result_order_work,
          max_workspace_entries: limits.max_result_workspace_entries,
        },
        limits.max_rows,
        limits.values,
        limits.payload_wire,
        limits.logical_wire,
        limits.schema,
        limits.max_batch_bytes,
        converted_output=root_output,
      )
      is Err(
        @strategy.CapturedEffectLocalResultExportIssue::Export(ForeignMaterial)
      ),
    )
    for index in 0..<@strategy.captured_effect_local_result_count(inputs) {
      let exported = consumer
        .prepare_effect_result_export(inputs, index, limits)
        .unwrap()
      let preparation = @strategy.captured_effect_local_result_export_preparation(
        exported,
      )
      while !@execution.advance_completed_result_relation_export(
              preparation, 16,
            ).unwrap().0 {
        continue
      }
      let stream = @execution.finish_completed_result_relation_export_preparation(
        preparation,
      ).unwrap()
      let observed = StringBuilder()
      let mut count = 0
      while @execution.next_completed_output_export_canonical_row(
              stream, 100, 20, 100,
            ).unwrap()
            is Some((row_index, wire, row)) {
        observed.write_string(wire)
        if index == effect_local_index {
          let (selector, changes) = @strategy.project_captured_effect_proposal_row(
            plan, row, row_index, 16, 10000, 4096, 100, 20,
          ).unwrap()
          assert_eq(selector, "3")
          assert_eq(changes, "{\"state\":\"present\",\"value\":{\"Name\":3}}")
        }
        count += 1
      }
      let (private_receipt, end) = @execution.finish_completed_relation_export(
        stream,
      ).unwrap()
      observed.write_string(end)
      assert_true(
        @strategy.captured_effect_local_result_export_matches_receipt(
          inputs, exported, private_receipt,
        ),
      )
      assert_false(
        @strategy.captured_effect_local_result_export_matches_receipt(
          inputs, exported, receipt,
        ),
      )
      if index == effect_local_index {
        assert_eq(count, 1)
        assert_eq(observed.to_string(), "[{\"id\":3}]")
        @strategy.finish_captured_effect_proposal_plan(plan, count).unwrap()
      } else {
        assert_eq(count, 3)
        assert_eq(observed.to_string(), "[{\"id\":1},{\"id\":2},{\"id\":3}]")
      }
      @execution.cancel_completed_relation_export_receipt(private_receipt)
      @execution.cancel_completed_output_export(stream)
      @execution.cancel_completed_result_relation_export(preparation) |> ignore
    }
    retained_effect_transferred_artifact(
      consumer,
      effect_materials.unwrap().0,
      inputs,
      root_local_index,
      effect_local_index,
      earlier,
      acquired.unwrap().1,
      @host.client_effect_acquired_invocation(again),
      producer_dependency.unwrap().0,
      producer_dependency.unwrap().1,
      producer_dependency.unwrap().2,
      producer_dependency.unwrap().4,
      common_input,
      site,
      output,
      stop_custodies,
    )
    assert_eq(acquisitions.val, 1)
    assert_eq(entries.val, 1)
    Some(
      consumer
      .prepare_effect_result_export(inputs, effect_local_index, limits)
      .unwrap(),
    )
  } else {
    None
  }
  assert_false(consumer.close())
  for (custody, store) in stop_custodies {
    assert_true(
      custody.begin_payload() is Err(Unavailable),
      msg="stopped parent must reject new payload allocation while cleanup is pending",
    )
    assert_true(custody.confirm_payload() is Err(Unavailable))
    assert_true(custody.open_reader() is Err(Unavailable))
    assert_true(custody.retry_cleanup().unwrap())
    assert_false(custody.retry_cleanup().unwrap())
    assert_eq(store.capacity_usage().unwrap().reserved_bytes, 0L)
    assert_true(store.close().unwrap())
  }
  assert_true(consumer.usage().held_bytes > 0L)
  assert_eq(journal.destination_capacity_usage().unwrap().reserved_bytes, bytes)
  output.cancel()
  if effect_inputs is Some(inputs) {
    assert_false(consumer.close())
    assert_true(consumer.usage().held_bytes > 0L)
    assert_eq(
      journal.destination_capacity_usage().unwrap().reserved_bytes,
      bytes,
    )
    assert_true(@strategy.release_captured_effect_inputs(inputs))
    assert_false(@strategy.release_captured_effect_inputs(inputs))
    if pending_effect_export is Some(exported) {
      let preparation = @strategy.captured_effect_local_result_export_preparation(
        exported,
      )
      assert_true(
        @execution.advance_completed_result_relation_export(preparation, 16)
        is Err(_),
      )
      @execution.cancel_completed_result_relation_export(preparation) |> ignore
    }
  }
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
  if producer_dependency is Some((pins, _, _, dependency_receipt, _)) {
    if provider && !provider_artifact_bound.val {
      // This observation case retains the producer pin itself instead of
      // passing it through the complete Effect capture helper above.
      assert_true(@strategy.release_captured_effect_local_unit_inputs(pins))
    }
    assert_false(@strategy.release_captured_effect_local_unit_inputs(pins))
    @execution.cancel_completed_relation_export_receipt(dependency_receipt)
  }
  assert_true(source_owner.close())
  assert_true(source_owner.close())
  assert_eq(source_owner.usage().held_bytes, 0L)
  assert_eq(source_owner.usage().reserved_execution_bytes, 0L)
  assert_true(
    retained_compute_acquired_evidence(source_owner) is Err(Unavailable),
  )
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

///|
test "retained Native consumer completes through Runtime claim evidence readers and formal cleanup" {
  retained_compute_case(false, through_runtime=true)
}

///|
test "Effect retained consumer resumes from committed Transfer without Source IO" {
  retained_compute_case(false, effect=true)
}

///|
test "Effect Native proposal receiver failure and revoked pins preserve original input custody" {
  retained_compute_case(false, effect=true, probe_proposals=true)
}

///|
test "Effect retained consumer cancellation returns its borrow before holding cleanup" {
  retained_compute_case(true, effect=true)
}

///|
test "Effect retained consumer completes through Runtime claim evidence readers and formal cleanup" {
  retained_compute_case(false, through_runtime=true, effect=true)
}

///|
test "Effect saved consumer envelope rebuilds original Run through journal and Runtime" {
  retained_compute_case(
    false,
    through_runtime=true,
    effect=true,
    through_saved_effect=true,
  )
}

///|
test "Effect saved consumer envelope rechecks original deadline at exclusive start" {
  retained_compute_case(
    false,
    through_runtime=true,
    effect=true,
    through_saved_effect=true,
    expire_at_start=true,
  )
}

///|
test "Native retained consumer proposals reach actual Provider target reads without applying writes" {
  retained_compute_case(false, effect=true, provider=true)
}

///|
test "Native retained consumer Provider observation refuses lost current permission without releasing custody" {
  retained_compute_case(false, effect=true, provider=true, deny_provider=true)
}

///|
test "Native Checkpoint custody retains the original confirmed Effect review before waiting" {
  retained_compute_case(
    false,
    effect=true,
    provider=true,
    checkpoint_custody=true,
  )
}
