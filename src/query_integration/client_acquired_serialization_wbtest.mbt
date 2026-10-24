///|
fn acquired_serialization_prepared(
  infer? : Bool = false,
) -> @publication_host.PreparedClientProgram raise {
  let document =
    #|{"version":"actql/0.1","id":"acquired-serialize","stages":[{"id":"main","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id >= 0","as":"filtered"},{"select":["id"],"as":"captured"},{"assert_rows":{"unique_by":["id"]},"as":"unique"},{"serialize":{"format":"jsonl","fields":["id"],"order_by":[{"id":"asc"}],"name":"out.jsonl"},"as":"attachment"}],"results":{"file":{"from":"attachment","fields":["name","content"]}}}],"results":{"file":{"from":{"stage":"main","result":"file"}}}}
  let document = if infer {
    document
    .replace(
      old="}],\"results\":{\"file\":{\"from\":\"attachment\"",
      new="},{\"assert_rows\":{\"unique_by\":[\"name\"]},\"as\":\"unique_content\"},{\"infer\":{\"contract\":\"model-task:risk-score.v1\",\"key\":\"name\",\"input\":{\"document\":{\"field\":\"content\"}}},\"as\":\"inferred\"}],\"results\":{\"file\":{\"from\":\"inferred\"",
    )
    .replace(
      old="\"fields\":[\"name\",\"content\"]",
      new="\"fields\":[\"name\",\"outcome\",\"value\"]",
    )
  } else {
    document
  }
  @publication_host.prepare_effect_free_client_program(
    document,
    Json,
    if infer {
      acquired_serialization_model_environment()
    } else {
      analytic_shared_seed_environment()
    },
    None,
    analytic_shared_seed_limits(),
  ).unwrap()
}

///|
fn acquired_serialization_model_environment() -> @program_check.CheckEnvironment raise {
  // The task is the same independently sealed Content-input vector used by
  // the source-free Model tests. Neither Source rows nor product Plan output
  // are used to fabricate an expected contract or observation.
  let task =
    #|{"authored_model_selector":"fixture-risk-model","connector_id":"models/fixture","contract_cid":"sha256:836444f3888092768af981447509670f2efc05bc047bf2665a951603c93b160d","data_handling":{"accepted_classifications":["public","internal"],"allowed_regions":["fixture-region"],"contract_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","retention":"none","training_use":"forbidden"},"generation_config":{"max_output_tokens":32,"seed_requested":-7,"temperature":0,"top_p":1},"input_contract":{"additional_properties":false,"fields":{"document":{"media_type":"application/x-ndjson","nullable":false,"type":"content_ref"}},"nullable":false,"type":"object"},"input_schema_cid":"sha256:60859537e680a59e68650f78be73ce2c818e3f3f2e37460568c8a54877c03d7a","max_items":2,"output_contract":{"additional_properties":false,"fields":{"reason":{"nullable":true,"type":"string"},"risk":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"output_schema_cid":"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3","prompt_template_cid":"sha256:d0ff84aab70965d97df8303954e5ab59e9b554de3251ca53f55da56577eedde2","retrieval_policy":"none","schema":"actql.model_task/0.1","streaming":false,"task_id":"model-task:risk-score.v1","task_kind":"structured_generate","tool_policy":"none","version":"1"}
  let writer = @encode.writer(1000000, 100000, 100)
  let original = @environment.member_environment(
    @environment.source_request_member(
      @environment.source_request_at(
        query_program_catalog_fixture(analytic=true),
        0,
      ).unwrap(),
    ),
  )
  @environment.emit(original, writer)
  let parsed = @json.parse(@encode.finish(writer))
  guard parsed is Object(fields) else {
    fail("missing original Source environment")
  }
  fields["model_task_contracts"] = @json.parse("[" + task + "]")
  fields.remove("evidence_bundle_cid") |> ignore
  let body = @identity.stringify_value(
    @identity.from_json(parsed, 100000, 100, 1000000),
    1000000,
    100000,
    100,
  )
  let cid = "sha256:" + @sha.hex(@utf8.encode(body))
  fields["evidence_bundle_cid"] = Json::string(cid)
  let wire = @identity.stringify_value(
    @identity.from_json(parsed, 100000, 100, 1000000),
    1000000,
    100000,
    100,
  )
  @publication_host.admit_client_check_environment(
    wire,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
}

///|
fn acquired_serialization_contracts() -> (
  @client_local_host.ClientInstalledSequenceContracts,
  String,
  String?,
  String?,
) raise {
  (
    registered_installed_sequence_contracts(),
    @identity.stringify_value(registered_values(), 100000, 10000, 100),
    Some(@identity.stringify_value(registered_fragment(), 100000, 10000, 100)),
    Some(@identity.stringify_value(registered_ordered(), 100000, 10000, 100)),
  )
}

///|
fn acquired_serialization_capture(
  prepared : @publication_host.PreparedClientProgram,
) -> (@query.CapturedInputSource, @local_connector.ManagedProviderExecution) raise {
  let (registry, values, fragment, ordered) = acquired_serialization_contracts()
  let requirement = @client_local_host.prepare_local_query_requirement(
    prepared, 0, 0, registry, values, fragment, ordered,
  ).unwrap()
  let sequence = @planning.query_material_owner(
    @planning.query_requirement_material(requirement),
  )
  // Physical rows deliberately disagree with the required Content ordering.
  let receipt = @query.admit_query_receipt(
    sequence,
    ["{\"id\":3}", "{\"id\":1}", "{\"id\":2}"].map(input_cursor),
    3,
    run_limits().input_values,
  ).unwrap()
  let residual = @client_local_host.prepare_client_query_residual(
    sequence,
    receipt,
    fn() { true },
    compute_test_limits(),
    { max_work: 100000, max_bytes: 100000, max_nodes: 10000, max_depth: 100, },
    100,
    10000,
    max_name_bytes=10000,
  ).unwrap()
  let active = @client_local_host.client_query_residual_execution(residual)
  let mut complete = false
  for _ in 0..<10000 {
    match @local_connector.advance_managed_provider(active, 1).unwrap() {
      Complete(_, ..) => {
        complete = true
        break
      }
      Continue(..) => ()
      _ => fail("original bounded acquisition did not complete")
    }
  }
  assert_true(complete)
  // Fixture-only trusted wiring verifies the actual guarded completion every
  // time. A parsed row array, successful Bool or copied CID cannot issue it.
  let port = @query.prepare_trusted_capture_port(
    sequence,
    @planning.query_requirement_program(requirement),
    fn(_ : Unit) {
      @client_local_host.client_query_residual_output(
        residual, sequence, receipt, 100, 10000,
      ).map(output => (output, 28))
    },
  ).unwrap()
  (@query.capture_verified_source(port, ()).unwrap(), active)
}

///|
fn acquired_serialization_ledger(
  capacity : @execution.ExecutionCapacity,
  short? : Bool = false,
) -> @resources.Ledger {
  @resources.create_ledger({
    planning_work: 0,
    attempts: 1,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: @execution.execution_capacity_retained_bytes(capacity),
    execution_bytes: @execution.execution_capacity_execution_bytes(capacity) -
    (if short { 1L } else { 0L }),
  }).unwrap()
}

///|
fn acquired_serialization_generation_fixture(
  infer? : Bool = false,
) -> Unit raise {
  let prepared = acquired_serialization_prepared(infer~)
  assert_eq(
    @publication_host.prepared_client_serialization_occurrences(prepared),
    [(0, 3)],
  )
  let graph = @publication_host.prepared_client_graph(prepared)
  assert_eq(@strategy.graph_task_selected_step(graph, 0).unwrap_or(0), 0)
  let query = @publication_host.prepare_client_query_acquisition(prepared, 0, 0).unwrap()
  assert_eq(@acquisition.query_acquisition_capture(query), @pipeline.Step(1))
  let (registry, values, fragment, ordered) = acquired_serialization_contracts()
  let limits = compute_test_limits()
  let measurement : @execution.FixedInputGuardMeasureLimits = {
    max_work: 100000,
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }
  // The old empty-input route remains unavailable for an acquired Program.
  assert_true(
    @client_local_host.prepare_client_serialization_prefix(
      prepared, 0, 3, registry, values, fragment, ordered,
    )
    is None,
  )
  let sequence = @client_local_host.prepare_client_acquired_serialization_prefix(
    prepared, 0, 3, registry, values, fragment, ordered,
  ).unwrap()
  assert_eq(@execution.generated_sequence_step_index_at(sequence, 0), Some(2))
  assert_eq(@execution.generated_sequence_step_index_at(sequence, 1), Some(3))
  let capacity = @client_local_host.client_acquired_serialization_prefix_capacity(
    prepared, 0, 3, registry, values, fragment, ordered, limits, measurement,
  ).unwrap()
  let ledger = acquired_serialization_ledger(capacity)
  let (source, acquisition) = acquired_serialization_capture(prepared)
  let prefix = @client_local_host.start_client_acquired_serialization_prefix(
    prepared, 0, 3, source, registry, values, fragment, ordered, limits, measurement,
    ledger,
  ).unwrap()
  let mut completion : @execution.CompletedOutput? = None
  for _ in 0..<10000 {
    match
      @client_local_host.advance_client_serialization_prefix(prefix, 1).unwrap() {
      Complete(result, ..) => {
        completion = Some(result)
        break
      }
      Continue(..) => ()
      _ => fail("acquired serialization prefix did not complete")
    }
  }
  let output = completion.unwrap()
  assert_eq(@execution.completed_row_count(output), 3)
  for row, expected in [1.0, 2.0, 3.0] {
    guard @execution.completed_cell(output, row, 0) is Some(Number(actual)) else {
      fail("missing numeric id")
    }
    assert_eq(actual, expected)
  }
  let barrier = @publication_host.prepare_client_serialization(
    prepared,
    0,
    3,
    max_work=10000,
  ).unwrap()
  let encoder = @publication_host.start_client_serialization_encoder(
    barrier,
    max_rows=3,
    max_bytes=27,
    max_value_nodes=100,
    max_value_depth=10,
    max_frames=100,
  ).unwrap()
  let input = @publication_host.bind_client_serialization_completed_input(
    barrier, output, encoder,
  ).unwrap()
  let component = (if infer {
    @publication_host.issue_prepared_client_acquired_serialization_plan_component
  } else {
    @publication_host.issue_prepared_client_acquired_serialization_plan_graph
  })(
    prepared,
    0,
    3,
    3,
    27,
    10000,
    @publication_host.client_standard_values_sequence_limits(),
    1000000,
    100000,
    100,
  ).unwrap()
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).unwrap()
  let model_plan = if infer {
    let occurrence = @publication_host.prepared_client_composed_infer_occurrence(
      prepared,
    ).unwrap()
    let wire =
      #|{"backoff_contract_cid":"sha256:739f886f72a9d0393470b92ccc3eb6a3a00f0616ed2d6f61df714f429de99d56","default_publication":"outcomes","max_attempts_per_slot":1,"max_total_attempts":1,"max_total_cost_units":0,"max_total_duration_ms":500,"max_total_token_reservation":33,"max_total_wire_bytes":133072,"media_input_contracts":{"document":"sha256:03213e7e836021f73b99d57eb5ea5855cd8430cd85b4a4079a8d92eede531507"},"model_task_contract_cid":"sha256:836444f3888092768af981447509670f2efc05bc047bf2665a951603c93b160d","retry_classification_contract_cid":"sha256:0c53e62a9c01afcf23a2036a06dd0b5e47653e943cae76d48bee1c84c11efb90","self_cid":"sha256:4393328509ccd287c21d7cc029062dd0f5833907fcdd81d4adf33ef493950097","version":"actql-model-execution-contract/0.1"}
    let execution = @publication_host.read_client_infer_occurrence_model_execution(
      occurrence,
      @utf8.encode(wire),
      "sha256:4393328509ccd287c21d7cc029062dd0f5833907fcdd81d4adf33ef493950097",
      { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 10, },
      100000,
    ).unwrap()
    Some(
      @publication_host.issue_prepared_client_serialized_infer_plan_graph(
        occurrence,
        component,
        execution,
        @publication_host.client_standard_values_sequence_limits(),
        1000000,
        100000,
        100,
      ).unwrap(),
    )
  } else {
    None
  }
  let compilation = match model_plan {
    Some(plan) =>
      @publication_host.issue_prepared_client_infer_compilation(
        prepared, plan, manifests, 1000, 1000, 1000000, 100000, 100,
      ).unwrap()
    None =>
      @publication_host.issue_prepared_client_serialization_compilation(
        prepared, component, manifests, 1000, 1000, 1000000, 100000, 100,
      ).unwrap()
  }
  let run = @publication_host.issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_compiled_run_definition(
    run, "local", "acquired-content", "2026-10-10T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let wire : @execution.RowWireLimits = {
    max_columns: 100,
    max_order_work: 1000,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 100,
  }
  let schema_limits : @execution.RelationSchemaIdentityLimits = {
    max_fields: 100,
    max_bytes: 10000,
    max_nodes: 1000,
    max_depth: 100,
  }
  let value_limits : @execution.ValueLimits = {
    max_nodes: 1000,
    max_text_bytes: 10000,
    max_depth: 100,
    max_work: 10000,
  }
  let identity = @query.identify_captured_source_relation(
    source, 3, value_limits, wire, wire, schema_limits, 1000,
  ).unwrap()
  let requirement = @client_local_host.prepare_local_query_requirement(
    prepared, 0, 0, registry, values, fragment, ordered,
  ).unwrap()
  let logical = @publication_host.issue_captured_source_input_logical(
    graph, source, identity, requirement,
  ).unwrap()
  let facts = @planning.query_source_evidence_fact_values(
    @planning.query_requirement_source_evidence_facts(requirement).unwrap(),
  )
  let authority = "sha256:" + "2".repeat(64)
  let fields : @publication.CompletedSourceObservationBody = {
    input: logical,
    source_ref: facts[0],
    source_contract_cid: facts[1],
    schema_evidence_cid: facts[2],
    capability_evidence_cid: "sha256:" + "7".repeat(64),
    authority_scope_cid: authority,
    source_data_policy_cid: facts[3],
    data_classification: facts[4],
    source_view_contract_cid: facts[5],
    observed_at: "2026-10-10T00:00:01.000Z",
    snapshot_ref: "fixture-observation",
  }
  let source_evidence = @publication.seal_completed_source_observation(fields).unwrap()
  let captured = @publication_host.admit_client_serialization_captured_input(
    prepared, component, source, identity, requirement, logical, source_evidence,
    authority, "2026-10-10T00:00:00.000Z", "2026-10-10T00:00:01.000Z",
  ).unwrap()
  let wrong_policy = @publication.seal_completed_source_observation({
    ..fields,
    source_data_policy_cid: "sha256:" + "8".repeat(64),
  }).unwrap()
  assert_true(
    @publication_host.admit_client_serialization_captured_input(
      prepared, component, source, identity, requirement, logical, wrong_policy,
      authority, "2026-10-10T00:00:00.000Z", "2026-10-10T00:00:01.000Z",
    )
    is Err(_),
  )
  assert_true(
    @publication_host.admit_client_serialization_captured_input(
      prepared, component, source, identity, requirement, logical, source_evidence,
      authority, "2026-10-10T00:00:02.000Z", "2026-10-10T00:00:01.000Z",
    )
    is Err(_),
  )
  let scan = @publication_host.start_client_serialization_input_identity(
    input, value_limits, wire, wire, schema_limits, 10000, 10000,
  ).unwrap()
  let mut identified = false
  for _ in 0..<10000 {
    if @execution.advance_completed_relation_identity_scan(scan, 1).unwrap().0 {
      identified = true
      break
    }
  }
  assert_true(identified)
  let receipt = @execution.finish_completed_relation_identity_scan(scan).unwrap()
  assert_true(
    @publication_host.bind_client_serialization_input_identity(
      run, input, receipt, 16384, 256, 16,
    )
    is Err(@publication.RunEvidenceReferenceMismatch("content_input_artifact")),
  )
  let input_evidence = @publication_host.bind_client_acquired_serialization_input_identity(
    run, input, receipt, captured, 16384, 256, 16,
  ).unwrap()
  @execution.cancel_completed_relation_export_receipt(receipt)
  let bytes = StringBuilder()
  let mut header_ready = false
  for _ in 0..<10000 {
    match @publication.advance_content_bytes(encoder, 1) {
      ContentBytesContinue(piece, ..) => bytes.write_string(piece)
      ContentBytesReady(piece, ..) => {
        bytes.write_string(piece)
        header_ready = true
        break
      }
      ContentBytesFailed(_, ..) => fail("content header failed")
    }
  }
  assert_true(header_ready)
  assert_eq(bytes.to_string(), "")
  for row in 0..<3 {
    @publication_host.start_client_serialization_input_row(input, row).unwrap()
    let mut ready = false
    for _ in 0..<10000 {
      match @publication.advance_content_bytes(encoder, 1) {
        ContentBytesContinue(piece, ..) => bytes.write_string(piece)
        ContentBytesReady(piece, ..) => {
          bytes.write_string(piece)
          ready = true
          break
        }
        ContentBytesFailed(_, ..) =>
          fail("captured rows failed byte generation")
      }
    }
    assert_true(ready)
  }
  assert_eq(bytes.to_string(), "{\"id\":1}\n{\"id\":2}\n{\"id\":3}\n")
  let content = @publication.finish_content_bytes(encoder).unwrap()
  assert_eq((content.row_count, content.size_bytes), (3, 27))
  assert_eq(
    content.content_cid,
    "sha256:c83135caa2c4f32882c30d1a3c7d26a0a582da313e810a8978bcc5f5b78d1c49",
  )
  let policy = @publication_host.client_compiled_run_serialization_policy_body(
    run,
  ).unwrap()
  let reference_limits : @admitted.ReferenceLimits = {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 8,
    max_text_units: 4096,
  }
  let binding : @publication.GeneratedContentBinding = {
    content_store_id: "fixture",
    content_store_cid: "sha256:" + "1".repeat(64),
    workspace_scope_cid: authority,
    storage_scope: "workspace",
    retention_class: "fixture",
    expires_at: None,
    availability_evidence_cid: "sha256:" + "3".repeat(64),
    effective_data_policy_cid: @publication.captured_effect_dependency_body_cid(
      policy,
    ),
    data_classification: "unknown",
    issuer_contract_cid: "sha256:" + "5".repeat(64),
    capture_authority_cid: authority,
  }
  let candidate = @publication.prepare_generated_content_reference(
    encoder, binding, reference_limits,
  ).unwrap()
  // Only this trusted byte fixture issues the reference after exact bytes above.
  let live = Ref(true)
  let issuer = @admitted.bind_reference_issuer(
    (_, envelope) => {
      live.val &&
      envelope == @publication.generated_content_reference_wire(candidate)
    },
    _ => live.val,
  )
  let reference = @publication.issue_generated_content_reference(
    candidate, issuer, reference_limits,
  ).unwrap()
  let generation = @publication_host.complete_client_serialization_generation(
    run,
    definition,
    input,
    input_evidence,
    candidate,
    reference,
    () => live.val,
    value_limits,
    1000,
  ).unwrap()
  let originals = @publication_host.client_serialization_generation_source_observations_for(
    generation, run,
  ).unwrap()
  assert_eq(originals.length(), 1)
  assert_eq(originals[0].0, "remote")
  let (original_source, original_input, original_started, original_completed) = @publication.model_source_observation_originals(
    originals[0].1,
  )
  assert_eq(
    @publication.run_evidence_value_identity(original_source),
    @publication.run_evidence_value_identity(source_evidence),
  )
  assert_eq(
    @publication.run_evidence_value_identity(original_input),
    @publication.run_evidence_value_identity(logical),
  )
  assert_eq(
    (original_started, original_completed),
    ("2026-10-10T00:00:00.000Z", "2026-10-10T00:00:01.000Z"),
  )
  // Equal compilation bytes cannot substitute another admitted Run.
  let other_run = @publication_host.issue_client_task_compiled_run(
    prepared,
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  assert_true(
    @publication_host.client_serialization_generation_source_observations_for(
      generation, other_run,
    )
    is None,
  )
  if model_plan is None {
    let (observation, _) = @publication_host.issue_client_serialization_invocation(
      run, definition, generation, 100000, 10000, 100,
    ).unwrap()
    let observed = @identity.from_json(
      @json.parse(@publication.run_evidence_value_json(observation)),
      10000,
      100,
      100000,
    )
    assert_eq(
      @identity.stringify_value(
        @identity.object_field(observed, "source_evidence_cids").unwrap(),
        1000,
        100,
        10,
      ),
      "[\"" + @publication.run_evidence_value_identity(source_evidence) + "\"]",
    )
    assert_eq(
      @identity.stringify_value(
        @identity.object_field(observed, "capture_started_at").unwrap(),
        1000,
        100,
        10,
      ),
      "\"2026-10-10T00:00:00.000Z\"",
    )
    assert_eq(
      @identity.stringify_value(
        @identity.object_field(observed, "consistency").unwrap(),
        1000,
        100,
        10,
      ),
      "\"independent_snapshots\"",
    )
  }
  assert_true(
    @client_local_host.client_serialization_prefix_work(prefix).unwrap() > 0L,
  )
  assert_true(@resources.ledger_usage(ledger).reserved_execution_bytes > 0L)
  assert_true(
    @client_local_host.cleanup_client_serialization_prefix(prefix) is Ok(true),
  )
  assert_true(
    @client_local_host.cleanup_client_serialization_prefix(prefix) is Ok(true),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_true(@query.captured_source_available(source))
  assert_eq(@query.captured_source_row_count(source), Some(3))
  assert_true(@local_connector.cleanup_managed_provider(acquisition).unwrap())
  assert_false(@query.captured_source_available(source))
  assert_true(
    @publication_host.client_serialization_generation_source_observations_for(
      generation, run,
    )
    is Some(remaining) &&
    remaining.length() == 1,
  )
  // The Source and prefix have now been reclaimed. Consume the original
  // generated bytes and Source closure, never reacquire the vanished rows.
  if model_plan is Some(plan) {
    let stored = @publication.prepare_stored_generated_content_reference(
      @publication.generated_content_reference_wire(candidate),
      binding,
      reference_limits,
    ).unwrap()
    let saved = @publication_host.client_serialization_generation_recovery_bindings(
      generation,
      run,
      "sha256:" + "1".repeat(64),
    ).unwrap()
    // The replacement process's issuer independently confirms the same saved
    // bytes. Revoking the first issued Ref must not revoke this new borrow.
    let recovered_live = Ref(true)
    let recovered_issuer = @admitted.bind_reference_issuer(
      (_, envelope) => {
        recovered_live.val &&
        envelope == @publication.generated_content_reference_wire(candidate)
      },
      _ => recovered_live.val,
    )
    let recovered_generation = @publication_host.readmit_client_serialization_generation_evidence(
      run,
      definition,
      saved[2].1,
      @publication.admit_run_evidence_value(
        saved[0].0,
        saved[0].2,
        16384,
        256,
        16,
      ).unwrap(),
      @publication.admit_run_evidence_value(
        saved[1].0,
        saved[1].2,
        16384,
        256,
        16,
      ).unwrap(),
      @publication.admit_run_evidence_value(
        saved[2].0,
        saved[2].2,
        16384,
        256,
        16,
      ).unwrap(),
      stored,
      @publication.issue_stored_generated_content_reference(
        stored, recovered_issuer, reference_limits,
      ).unwrap(),
    ).unwrap()
    let occurrence = @publication_host.client_serialization_generation_infer_occurrence(
      generation, run, plan,
    ).unwrap()
    // Recovery admits reconstruction of the same semantic Run, not an object
    // allocation identity. Changing its authorization makes a foreign Run.
    assert_true(
      @publication_host.client_serialization_recovery_matches_infer(
        other_run, definition, plan, occurrence, recovered_generation,
      ),
    )
    let foreign_run = @publication_host.issue_client_task_compiled_run(
      prepared,
      compilation,
      "sha256:" + "c".repeat(64),
      "sha256:" + "b".repeat(64),
      "2099-01-01T00:00:00.000Z",
    ).unwrap()
    assert_false(
      @publication_host.client_serialization_recovery_matches_infer(
        foreign_run, definition, plan, occurrence, recovered_generation,
      ),
    )
    acquired_serialization_model_scope_fixture(
      prepared, run, definition, generation, plan, source_evidence, logical, value_limits,
      wire, schema_limits, recovered_generation, live, recovered_live,
    )
  }
  live.val = false
  assert_true(
    @publication_host.client_serialization_generation_source_observations_for(
      generation, run,
    )
    is None,
  )
}

///|
test "acquired serialization sorts the original captured rows and preserves borrowed custody after cleanup" {
  acquired_serialization_generation_fixture()
}

///|
test "generated acquired Content carries exact Source originals into Model scope and saved scope without reacquisition" {
  acquired_serialization_generation_fixture(infer=true)
}

///|
fn acquired_serialization_model_scope_fixture(
  prepared : @publication_host.PreparedClientProgram,
  run : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  generation : @publication_host.ClientSerializationGeneration,
  plan : @publication_host.ClientInferPlanGraph,
  source_evidence : @publication.RunEvidenceValue,
  logical : @publication.RunEvidenceValue,
  values : @execution.ValueLimits,
  wire : @execution.RowWireLimits,
  schema : @execution.RelationSchemaIdentityLimits,
  recovered_generation : @publication.BoundContentGeneration,
  original_reference_live : Ref[Bool],
  recovered_reference_live : Ref[Bool],
) -> Unit raise {
  let occurrence = @publication_host.client_serialization_generation_infer_occurrence(
    generation, run, plan,
  ).unwrap()
  let output = @publication_host.client_serialization_generation_output_for(
    generation, run,
  ).unwrap()
  let segment = @execution.prepare_serialization_infer_input_segment(
    output,
    5,
    @publication_host.prepared_client_values_sequence_limits(prepared),
    10000,
    10000,
  ).unwrap()
  let limits = @infer_host.standard_limits()
  let active = @client_local_host.start_client_serialized_infer_input(
    occurrence,
    segment,
    3,
    output,
    limits.input,
    limits.measurement,
    limits.mapping,
  ).unwrap()
  let mut ready = false
  let mut original_rows = None
  for _ in 0..<10000 {
    match @client_local_host.advance_client_infer_input(active, 1).unwrap() {
      Complete(rows, ..) => {
        original_rows = Some(rows)
        ready = true
        break
      }
      Continue(..) => ()
      _ => fail("generated captured Model input failed")
    }
  }
  assert_true(ready)
  guard original_rows is Some(original_rows) &&
    @execution.prepared_infer_rows_value(original_rows, 0, 0)
    is Some(original_value) &&
    original_value.value is @admitted.Reference(original_reference) else {
    fail("original Model reference")
  }
  let input = @client_local_host.client_infer_completed_input(active).unwrap()
  let scan = @execution.start_completed_relation_identity_scan(
    input, 1, values, wire, wire, schema, 10000, 10000,
  ).unwrap()
  let mut complete = false
  for _ in 0..<10000 {
    if @execution.advance_completed_relation_identity_scan(scan, 1).unwrap().0 {
      complete = true
      break
    }
  }
  assert_true(complete)
  let receipt = @execution.finish_completed_relation_identity_scan(scan).unwrap()
  // A complete generated row cannot substitute the original Source closure.
  assert_true(
    @publication_host.issue_client_infer_occurrence_call_scope(
      occurrence, plan, input, receipt, 100000, 10000, 100,
    )
    is Err(ForeignInput),
  )
  let scope = @publication_host.issue_client_infer_occurrence_call_scope(
    occurrence,
    plan,
    input,
    receipt,
    100000,
    10000,
    100,
    generation=Some(generation),
  ).unwrap()
  let originals = @publication_host.client_infer_call_scope_source_observations(
    scope,
  )
  assert_eq(originals.length(), 1)
  let (source, captured, _, _) = @publication.model_source_observation_originals(
    originals[0],
  )
  assert_eq(
    @publication.run_evidence_value_json(source),
    @publication.run_evidence_value_json(source_evidence),
  )
  assert_eq(
    @publication.run_evidence_value_json(captured),
    @publication.run_evidence_value_json(logical),
  )
  let snapshot = @publication_host.client_infer_call_scope_snapshot(scope).unwrap()
  assert_true(snapshot.contains("\"name\":\"remote\""))
  let custody = Ref(true)
  // Exercise the installed recovery bridge, not only the lower-level reader.
  // Saved scope admission precedes rehydration of the actual Model input.
  let bridge_saved = @infer_host.read_saved_input_scope(
    run,
    definition,
    prepared,
    5,
    plan,
    snapshot,
    "sha256:" + "2".repeat(64),
    () => custody.val,
  ).unwrap()
  assert_true(
    @publication_host.client_infer_saved_call_scope_matches_run(
      bridge_saved, run, definition,
    ),
  )
  let saved = @publication_host.read_client_infer_saved_call_scope(
    run,
    definition,
    occurrence,
    plan,
    snapshot,
    "sha256:" + "2".repeat(64),
    () => custody.val,
  ).unwrap()
  // Export while the original owner is live, then close that mapper and revoke
  // its Ref. Cell storage and Ref permission are separate: the old cell buffer
  // may remain represented, but cannot supply live Content to another Model.
  let retained = @client_local_host.export_client_infer_retained_input(
    input, snapshot,
  ).unwrap()
  let descriptor = @client_local_host.client_infer_retained_input_export_descriptor(
    retained,
  )
  let rows = @client_local_host.client_infer_retained_input_export_rows(
    retained,
  )
  @execution.cancel_completed_relation_export_receipt(receipt)
  assert_true(@client_local_host.cleanup_client_infer_input(active).unwrap())
  original_reference_live.val = false
  assert_true(@client_local_host.client_infer_completed_input(active) is None)
  assert_true(
    @publication_host.client_serialization_generation_reference_for(
      generation, run,
    )
    is None,
  )
  let (registry, values_body, fragment, ordered) = acquired_serialization_contracts()
  assert_true(
    @client_local_host.start_client_restored_infer_input(
      prepared,
      0,
      5,
      registry,
      values_body,
      snapshot,
      snapshot,
      descriptor,
      rows,
      () => custody.val,
      limits.input,
      limits.mapping,
      fragment_body=fragment,
      ordered_body=ordered,
    )
    is Err(_),
  )
  assert_true(
    @client_local_host.start_client_restored_serialized_infer_input(
      prepared,
      run,
      definition,
      plan,
      occurrence,
      recovered_generation,
      registry,
      values_body,
      snapshot,
      "wrong-binding",
      descriptor,
      rows,
      () => custody.val,
      limits.input,
      limits.mapping,
      fragment_body=fragment,
      ordered_body=ordered,
    )
    is Err(RetainedInput(BindingMismatch)),
  )
  assert_true(
    @client_local_host.start_client_restored_serialized_infer_input(
      prepared,
      run,
      definition,
      plan,
      occurrence,
      recovered_generation,
      registry,
      values_body,
      snapshot,
      snapshot,
      descriptor,
      rows,
      () => false,
      limits.input,
      limits.mapping,
      fragment_body=fragment,
      ordered_body=ordered,
    )
    is Err(RetainedInput(CustodyUnavailable)),
  )
  let changed_rows = rows.map(row => {
    row.replace(
      old="c83135caa2c4f32882c30d1a3c7d26a0a582da313e810a8978bcc5f5b78d1c49",
      new="d83135caa2c4f32882c30d1a3c7d26a0a582da313e810a8978bcc5f5b78d1c49",
    )
  })
  assert_false(changed_rows == rows)
  assert_true(
    @client_local_host.start_client_restored_serialized_infer_input(
      prepared,
      run,
      definition,
      plan,
      occurrence,
      recovered_generation,
      registry,
      values_body,
      snapshot,
      snapshot,
      descriptor,
      changed_rows,
      () => custody.val,
      limits.input,
      limits.mapping,
      fragment_body=fragment,
      ordered_body=ordered,
    )
    is Err(_),
  )
  let recovered = @client_local_host.start_client_restored_serialized_infer_input(
    prepared,
    run,
    definition,
    plan,
    occurrence,
    recovered_generation,
    registry,
    values_body,
    snapshot,
    snapshot,
    descriptor,
    rows,
    () => custody.val,
    limits.input,
    limits.mapping,
    fragment_body=fragment,
    ordered_body=ordered,
  ).unwrap()
  let mut mapped = false
  let mut recovered_rows = None
  for _ in 0..<10000 {
    match @client_local_host.advance_client_infer_input(recovered, 1).unwrap() {
      Complete(rows, ..) => {
        recovered_rows = Some(rows)
        mapped = true
        break
      }
      Continue(..) => ()
      _ => fail("saved generated Model input did not map")
    }
  }
  assert_true(mapped)
  guard recovered_rows is Some(recovered_rows) &&
    @execution.prepared_infer_rows_value(recovered_rows, 0, 0)
    is Some(recovered_value) &&
    recovered_value.value is @admitted.Reference(recovered_reference) else {
    fail("restored typed Model reference")
  }
  assert_false(@admitted.reference_available(original_reference))
  assert_true(@admitted.reference_available(recovered_reference))
  assert_eq(
    @admitted.reference_wire(original_reference),
    @admitted.reference_wire(recovered_reference),
  )
  assert_false(
    @admitted.reference_same_issuer(original_reference, recovered_reference),
  )
  let input = @client_local_host.client_infer_completed_input(recovered).unwrap()
  let scan = @execution.start_completed_relation_identity_scan(
    input, 1, values, wire, wire, schema, 10000, 10000,
  ).unwrap()
  let mut identified = false
  for _ in 0..<10000 {
    if @execution.advance_completed_relation_identity_scan(scan, 1).unwrap().0 {
      identified = true
      break
    }
  }
  assert_true(identified)
  let receipt = @execution.finish_completed_relation_identity_scan(scan).unwrap()
  let restored = @publication_host.restore_client_infer_call_scope(
    saved, input, receipt,
  ).unwrap()
  assert_eq(
    @publication.run_evidence_value_identity(
      @publication_host.client_infer_call_scope_artifact(restored),
    ),
    @publication.run_evidence_value_identity(
      @publication_host.client_infer_call_scope_artifact(scope),
    ),
  )
  let restored_sources = @publication_host.client_infer_call_scope_source_observations(
    restored,
  )
  assert_eq(
    @publication.model_source_observation_fields(restored_sources[0]),
    @publication.model_source_observation_fields(originals[0]),
  )
  // Consume the authenticated generation and scope in the actual Model owner.
  // Recovery borrows the original bytes: it cannot manufacture an encoder
  // completion or authorize a physical call. This fixture stops during bounded
  // preflight; public approval/resume acceptance uses the installed byte reader.
  let recovered_token = @publication_host.readmit_client_serialization_generation(
    run, definition, plan, saved, recovered_generation,
  ).unwrap()
  assert_true(
    @publication_host.client_serialization_generation_output_for(
      recovered_token, run,
    )
    is None,
  )
  let calls = Ref(0)
  let provider = @model.install_model_provider("models/fixture", _ => {
    calls.val += 1
    Err(@model.Timeout)
  }).unwrap()
  let model_owner = @infer_host.start_restored_generated_input(
    prepared,
    run,
    definition,
    recovered_token,
    plan,
    registry,
    values_body,
    provider,
    snapshot,
    snapshot,
    descriptor,
    rows,
    () => custody.val,
    limits,
    fragment_body=fragment,
    ordered_body=ordered,
  ).unwrap()
  @infer_host.bind_run(model_owner, run, definition).unwrap()
  @infer_host.bind_quantity_capacity(model_owner, {
    limits: { tokens: 33L, cost_units: 0L, duration_ms: 500L, },
    per_attempt: { tokens: 33L, cost_units: 0L, duration_ms: 500L, },
  }).unwrap()
  let preflights = Ref(0)
  let physical_work = Ref(0)
  @infer_host.bind_physical_preflight(model_owner, _ => {
    preflights.val += 1
    Ok({
      advance: () => {
        physical_work.val += 1
        if physical_work.val > 2 {
          Err(@model.InvalidProvider)
        } else {
          Ok(None)
        }
      },
      cleanup: () => true,
    })
  }).unwrap()
  let mut preparing = false
  for _ in 0..<10000 {
    match @infer_host.advance(model_owner, 1).unwrap() {
      Continue(..) =>
        if physical_work.val == 1 {
          preparing = true
          break
        }
      Failed(Model(issue), ..) =>
        fail("restored generated Model: " + @debug.to_string(issue))
      Failed(CallScope(ForeignInput), ..) =>
        fail("restored generated Model: foreign saved input")
      Failed(CallScope(_), ..) => fail("restored generated Model: saved scope")
      Failed(Input(_), ..) => fail("restored generated Model: input")
      Failed(IdentityExport(_), ..) =>
        fail("restored generated Model: identity")
      Failed(Capacity(_), ..) => fail("restored generated Model: capacity")
      Failed(InvalidAdvance, ..) =>
        fail("restored generated Model: invalid advance")
      _ => fail("restored generated Model did not reach bounded preflight")
    }
  }
  assert_true(preparing)
  assert_eq(calls.val, 0)
  assert_eq(preflights.val, 1)
  assert_eq(physical_work.val, 1)
  let model_scope = @infer_host.call_scope(model_owner).unwrap()
  assert_eq(
    @publication.run_evidence_value_identity(
      @publication_host.client_infer_call_scope_artifact(model_scope),
    ),
    @publication.run_evidence_value_identity(
      @publication_host.client_infer_call_scope_artifact(scope),
    ),
  )
  assert_eq(
    @publication.model_source_observation_fields(
      @publication_host.client_infer_call_scope_source_observations(model_scope)[0],
    ),
    @publication.model_source_observation_fields(originals[0]),
  )
  assert_true(@infer_host.cancel(model_owner))
  let mut stopped = false
  for _ in 0..<10000 {
    match @infer_host.advance(model_owner, 1).unwrap() {
      Continue(..) | Waiting(..) => ()
      Stopped(..) => {
        stopped = true
        break
      }
      _ => fail("restored generated Model did not stop")
    }
  }
  assert_true(stopped)
  assert_true(@infer_host.cleanup(model_owner).unwrap())
  assert_true(@infer_host.cleanup(model_owner).unwrap())
  assert_eq(calls.val, 0)
  assert_eq(preflights.val, 1)
  assert_true(recovered_reference_live.val)
  assert_true(
    @publication_host.client_serialization_generation_capture_for(
      recovered_token, run, definition,
    )
    is Some(_),
  )
  // Historical Source evidence is not authority once its holding is revoked.
  custody.val = false
  assert_true(
    @publication_host.client_serialization_generation_capture_for(
      recovered_token, run, definition,
    )
    is None,
  )
  assert_true(
    @publication_host.readmit_client_serialization_generation(
      run, definition, plan, saved, recovered_generation,
    )
    is Err(ForeignInput),
  )
  assert_true(
    @publication_host.restore_client_infer_call_scope(saved, input, receipt)
    is Err(ForeignInput),
  )
  assert_true(
    @publication_host.issue_client_serialization_invocation(
      run, definition, generation, 100000, 10000, 100,
    )
    is Err(_),
  )
  @execution.cancel_completed_relation_export_receipt(receipt)
  assert_true(@client_local_host.cleanup_client_infer_input(recovered).unwrap())
  assert_true(@client_local_host.cleanup_client_infer_input(recovered).unwrap())
  assert_false(@execution.completed_output_available(input))
  assert_true(
    @publication_host.client_serialization_generation_output_for(
      generation, run,
    )
    is None,
  )
  recovered_reference_live.val = false
  assert_true(
    @client_local_host.start_client_restored_serialized_infer_input(
      prepared,
      run,
      definition,
      plan,
      occurrence,
      recovered_generation,
      registry,
      values_body,
      snapshot,
      snapshot,
      descriptor,
      rows,
      () => true,
      limits.input,
      limits.mapping,
      fragment_body=fragment,
      ordered_body=ordered,
    )
    is Err(UnsupportedProgram),
  )
}

///|
test "acquired serialization cancellation retains its reservation until stop and leaves capture owned by its producer" {
  let prepared = acquired_serialization_prepared()
  let (registry, values, fragment, ordered) = acquired_serialization_contracts()
  let limits = compute_test_limits()
  let measurement : @execution.FixedInputGuardMeasureLimits = {
    max_work: 100000,
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }
  let capacity = @client_local_host.client_acquired_serialization_prefix_capacity(
    prepared, 0, 3, registry, values, fragment, ordered, limits, measurement,
  ).unwrap()
  let ledger = acquired_serialization_ledger(capacity)
  let (source, acquisition) = acquired_serialization_capture(prepared)
  let prefix = @client_local_host.start_client_acquired_serialization_prefix(
    prepared, 0, 3, source, registry, values, fragment, ordered, limits, measurement,
    ledger,
  ).unwrap()
  assert_true(
    @client_local_host.advance_client_serialization_prefix(prefix, 1)
    is Ok(Continue(..)),
  )
  assert_true(
    @client_local_host.client_serialization_prefix_work(prefix).unwrap() > 0L,
  )
  assert_true(@client_local_host.cancel_client_serialization_prefix(prefix))
  assert_true(@resources.ledger_usage(ledger).reserved_execution_bytes > 0L)
  let mut stopped = false
  for _ in 0..<10000 {
    match
      @client_local_host.advance_client_serialization_prefix(prefix, 1).unwrap() {
      Stopped(..) => {
        stopped = true
        break
      }
      Continue(..) => ()
      _ => fail("cancelled prefix must not publish completed rows")
    }
  }
  assert_true(stopped)
  assert_true(
    @client_local_host.cleanup_client_serialization_prefix(prefix) is Ok(true),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_true(@query.captured_source_available(source))
  assert_eq(@query.captured_source_row_count(source), Some(3))
  assert_true(@local_connector.cleanup_managed_provider(acquisition).unwrap())
  assert_false(@query.captured_source_available(source))
}

///|
test "acquired serialization rejects a foreign capture and one-short reservation without borrowing or replay" {
  let prepared = acquired_serialization_prepared()
  let (registry, values, fragment, ordered) = acquired_serialization_contracts()
  let limits = compute_test_limits()
  let measurement : @execution.FixedInputGuardMeasureLimits = {
    max_work: 100000,
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }
  let capacity = @client_local_host.client_acquired_serialization_prefix_capacity(
    prepared, 0, 3, registry, values, fragment, ordered, limits, measurement,
  ).unwrap()
  let (foreign, foreign_acquisition) = acquired_serialization_capture(
    acquired_serialization_prepared(),
  )
  let ledger = acquired_serialization_ledger(capacity)
  assert_true(
    @client_local_host.start_client_acquired_serialization_prefix(
      prepared, 0, 3, foreign, registry, values, fragment, ordered, limits, measurement,
      ledger,
    )
    is Err(Capture(_)),
  )
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  assert_true(@query.captured_source_available(foreign))
  let (source, acquisition) = acquired_serialization_capture(prepared)
  let short = acquired_serialization_ledger(capacity, short=true)
  assert_true(
    @client_local_host.start_client_acquired_serialization_prefix(
      prepared, 0, 3, source, registry, values, fragment, ordered, limits, measurement,
      short,
    )
    is Err(Physical(ExecutionLimit)),
  )
  assert_eq(@resources.ledger_usage(short).attempts, 0)
  assert_eq(@resources.ledger_usage(short).reserved_retention_bytes, 0L)
  assert_true(@query.captured_source_available(source))
  assert_true(@local_connector.cleanup_managed_provider(acquisition).unwrap())
  assert_true(
    @local_connector.cleanup_managed_provider(foreign_acquisition).unwrap(),
  )
}
