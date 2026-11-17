///|
// Real checked Source-only Effect with the same declared keyed file protocol.
// It has no Infer node or Model scope. No provider or durable ACK is invented.
fn source_effect_keyed_fixture() -> (
  PreparedClientEffectComputation,
  ClientKeyedAcquisition,
  @publication.PublicationContract,
) raise {
  let (base, profile) = client_keyed_plan_test_environment(declared=true)
  let writer = @encode.writer(1000000, 100000, 100)
  @environment.emit(@checked.checking_environment_wire(base), writer)
  guard @json.parse(@encode.finish(writer)) is Object(fields) &&
    @json.parse(client_composed_acquired_effect_environment) is Object(effect) &&
    fields["connector_catalogs"] is Array(catalogs) &&
    effect["connector_catalogs"] is Array(original_catalogs) &&
    fields["connector_manifest"] is Object(manifest) &&
    manifest["connectors"] is Array(connectors) else {
    fail("original Source-only fixture environment")
  }
  fields.remove("evidence_bundle_cid") |> ignore
  fields["model_task_contracts"] = Json::array([])
  fields["mapping_contracts"] = effect["mapping_contracts"]
  for original in original_catalogs {
    guard original is Object(catalog) else { fail("original Effect catalog") }
    if catalog["connector_id"] == Json::string("crm") {
      catalogs.push(original)
    }
  }
  connectors.push(
    @json.parse(
      "{\"connector\":\"crm\",\"connector_id\":\"crm\",\"connector_version\":\"fixture\"}",
    ),
  )
  let unsigned = @canonical.from_json(
    Json::object(fields),
    100000,
    100,
    1000000,
  )
  let cid = @canonical.cid_value(unsigned, 1000000, 100000, 100)
  let wire = @canonical.stringify_value(
    @canonical.object_with_string_field(unsigned, "evidence_bundle_cid", cid).unwrap(),
    1000000,
    100000,
    100,
  )
  let environment = admit_client_check_environment(
    wire,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"source-keyed-effect","stages":[{"id":"capture","inputs":{"files":{"connector":"lookup-fixture","resource":"files"},"remote":{"connector":"lookup-fixture","resource":"contents","request":{"tenant":"original"}}},"steps":[{"from":"files","filter":"id <> ''","as":"filtered"},{"select":["id","text","mime","version"],"as":"left"},{"from":"left","join":{"with":"remote","kind":"inner","on":[{"left":"id","right":"id"}],"select":{"id":"left.id","text":"right.text"}},"as":"joined"},{"derive":{"value":{"literal":1}},"as":"selected"}],"results":{"out":{"from":"selected","fields":["value"]}},"effects":{"save":{"create":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"out"}}}}}],"results":{"published":{"from":{"stage":"capture","result":"out"}}}}
  let prepared = match
    prepare_client_effect_computation(
      document,
      Json,
      environment,
      None,
      [],
      client_standard_effect_computation_limits(),
    ) {
    Ok(value) => value
    Err(Candidate(@checked.Computation(issue))) => raise issue
    Err(Syntax(_)) => fail("Source-only syntax")
    Err(Candidate(_)) => fail("Source-only Candidate")
    Err(Static(_)) => fail("Source-only Static")
    Err(Stage(_)) => fail("Source-only Stage")
    Err(Graph(issue)) => fail("Source-only Graph " + @debug.to_string(issue))
    Err(_) => fail("Source-only preparation")
  }
  assert_true(prepared_client_effect_infer_occurrences(prepared) is Some([]))
  let keyed = select_client_effect_single_keyed_acquisition(prepared)
    .unwrap()
    .unwrap()
  (prepared, keyed, profile)
}

///|
test "Source-only keyed construction retains the actual Effect join without a Model stand-in" {
  let (prepared, keyed, profile) = source_effect_keyed_fixture()
  let construction = measure_client_effect_keyed_plan_construction(
    prepared,
    keyed,
    profile,
    client_standard_values_sequence_limits(),
    1000000,
    100000,
    100,
  ).unwrap()
  let graph = issue_client_effect_keyed_plan_graph(
    construction, 1000000, 100000, 100,
  ).unwrap()
  assert_true(client_effect_keyed_plan_graph_matches(graph, prepared, keyed))
  assert_eq(graph.graph_nodes.length(), 3)
  guard graph.component is NativeKeyedPlan(component) else {
    fail("real Native Source-only plan")
  }
  assert_true(physical_equal(component.original.fragments.acquisition, keyed))
  assert_true(physical_equal(component.original.profile, profile))
  assert_eq(
    component.original.fragments.final_step,
    @acquisition.keyed_join_step(keyed.binding.join),
  )
  for
    (fragment, measured) in [
      (component.left, construction.fragments[0].fragment),
      (component.barrier, construction.node),
      (component.joined, construction.fragments[1].fragment),
    ] {
    let actual = content_construction_geometry(fragment.wire)
    assert_true(
      actual.0 <= measured.0 && actual.1 <= measured.1 && actual.2 <= measured.2,
    )
  }
  let storage = prepared_client_effect_keyed_plan_measurement_storage(
    prepared, keyed,
  ).unwrap()
  assert_true(@execution.preparation_representation_cost(storage).unwrap() > 0L)
  assert_eq(
    @execution.preparation_representation_cost(
      client_composed_keyed_model_origin_construction_inventory(),
    ),
    Some(32L),
  )
}

///|
test "Source-only keyed construction refuses foreign Plan profile and insufficient real codec geometry" {
  let (prepared, keyed, profile) = source_effect_keyed_fixture()
  let (foreign, other_keyed, _) = source_effect_keyed_fixture()
  assert_true(
    measure_client_effect_keyed_plan_construction(
      foreign,
      keyed,
      profile,
      client_standard_values_sequence_limits(),
      1000000,
      100000,
      100,
    )
    is Err(UnsupportedProgram),
  )
  assert_true(
    prepared_client_effect_keyed_plan_measurement_storage(prepared, other_keyed)
    is None,
  )
  let construction = measure_client_effect_keyed_plan_construction(
    prepared,
    keyed,
    profile,
    client_standard_values_sequence_limits(),
    1000000,
    100000,
    100,
  ).unwrap()
  assert_true(
    issue_client_effect_keyed_plan_graph(construction, 1, 100000, 100) is Err(_),
  )
  let graph = issue_client_effect_keyed_plan_graph(
    construction, 1000000, 100000, 100,
  ).unwrap()
  assert_false(client_effect_keyed_plan_graph_matches(graph, foreign, keyed))
  assert_false(
    client_effect_keyed_plan_graph_matches(graph, prepared, other_keyed),
  )
}

///|
test "Source-only original binds the same compiled Effect Request and census once and retains failed-start custody" {
  let (prepared, keyed, profile) = source_effect_keyed_fixture()
  let graph = prepare_client_effect_keyed_plan_graph(
    prepared,
    keyed,
    profile,
    client_standard_values_sequence_limits(),
    1000000,
    100000,
    100,
  ).unwrap()
  let limits = run_materials_limits()
  let compilation = issue_prepared_client_effect_compilation(
    prepared,
    run_materials_manifests(),
    limits.sequence,
    limits.max_sequence_steps,
    limits.max_sequence_work,
    limits.max_evidence_bytes,
    limits.max_evidence_nodes,
    limits.max_evidence_depth,
  ).unwrap()
  let allowed = issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_effect_run_definition(
    allowed, "source-only-scope", "source-only-original", "2026-11-15T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  assert_eq(
    @execution.preparation_representation_cost(
      client_effect_allowed_keyed_run_construction_inventory(),
    ),
    Some(296L),
  )
  let compiled = client_effect_allowed_keyed_run(allowed, graph, definition).unwrap()
  let request = prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "c".repeat(64),
    "source-only-request",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  let foreign_request = prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "c".repeat(64),
    "another-source-only-request",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  let ledger = @resources.create_ledger({
    planning_work: 10000,
    attempts: 100,
    holdings: 100,
    transfer_bytes: 1000000L,
    retained_bytes: 1000000L,
    execution_bytes: 1000000L,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 100000L, 100000L).unwrap()
  let identity = @resources.begin_original_ledger_inventory(
    ledger, bootstrap, 10, 10, 0,
  ).unwrap()
  let foreign_ledger = @resources.create_ledger(
    @resources.ledger_limits(ledger),
  ).unwrap()
  assert_true(
    bind_client_effect_keyed_original(
      prepared, compilation, compiled, definition, request, graph, keyed, foreign_ledger,
      identity,
    )
    is Err(ForeignLeft),
  )
  let original = bind_client_effect_keyed_original(
    prepared, compilation, compiled, definition, request, graph, keyed, ledger, identity,
  ).unwrap()
  assert_true(
    client_effect_keyed_original_matches(
      original, prepared, compiled, definition, request, graph, keyed, ledger,
    ),
  )
  assert_false(
    client_effect_keyed_original_matches(
      original, prepared, compiled, definition, foreign_request, graph, keyed, ledger,
    ),
  )
  assert_true(
    bind_client_effect_keyed_original(
      prepared, compilation, compiled, definition, request, graph, keyed, ledger,
      identity,
    )
    is Err(ForeignLeft),
  )
  assert_true(
    client_effect_keyed_capture_start_construction_inventory(original)
    is Some(_),
  )
  let before = @resources.ledger_usage(ledger)
  assert_true(
    start_client_effect_keyed_capture_lookup_input(
      original,
      [],
      10000,
      10000,
      10000,
      10000,
    )
    is Err(ForeignLeft),
  )
  assert_true(original.started)
  assert_true(
    client_effect_keyed_capture_start_construction_inventory(original) is None,
  )
  assert_true(
    start_client_effect_keyed_capture_lookup_input(
      original,
      [],
      10000,
      10000,
      10000,
      10000,
    )
    is Err(ForeignLeft),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    @resources.finish_original_ledger_inventory(ledger, true).unwrap(),
  )
  assert_false(client_effect_keyed_original_current(original))
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
// Real Source Query execution and original supplied rows exercise the Strategy
// seam. These are explicit mock inputs, not a lookup protocol or durable ACK.
test "Source-only keyed DAG retains the actual supplied binding and refuses foreign slot owner and cancellation" {
  let (prepared, keyed, profile) = source_effect_keyed_fixture()
  let fragment = Some(product_test_fragment_wire())
  let ordered = Some(compiler_registered_ordered_wire())
  let contracts = @local_query_time.prepare_installed_sequence_contracts(
    compiler_registered_body_wire(),
    compiler_registered_values_wire(),
    fragment,
    ordered,
  ).unwrap()
  let requirement = match
    @local_query_time.prepare_effect_local_query_requirement(
      prepared,
      0,
      0,
      contracts,
      compiler_registered_values_wire(),
      fragment,
      ordered,
    ) {
    Ok(value) => value
    Err(@local_query_time.Sequences) =>
      fail("Source fixture generated sequences")
    Err(@local_query_time.MissingStage) => fail("Source fixture missing stage")
    Err(@local_query_time.Requirement(_)) =>
      fail("Source fixture query requirement")
  }
  let sequence = @planning.query_material_owner(
    @planning.query_requirement_material(requirement),
  )
  let execution = string_try_number_execution_limits()
  let input = scalar_profile_cursor(
    "{\"id\":\"original-a\",\"mime\":\"text/plain\",\"text\":\"left original\",\"version\":\"v1\"}",
  )
  let receipt = match
    @query.admit_query_receipt(
      sequence,
      [input],
      1,
      execution.rows.input_values,
    ) {
    Ok(value) => value
    Err(@query.ReceiptAdmission(_)) => fail("Source fixture row admission")
    Err(_) => fail("Source fixture query receipt")
  }
  let query_rows = @query.query_receipt_rows(receipt)
  let query_read = @execution.prepare_supplied_relation_read(
    keyed.owner,
    @query.query_receipt_input_index(sequence),
    query_rows,
    () => true,
  ).unwrap()
  let generated = @query.query_generated_sequence(sequence)
  let provider = @local.local_bounded_relation_provider(
    execution,
    { max_work: 100000, max_bytes: 20000, max_nodes: 10000, max_depth: 20, },
    generated,
  ).unwrap()
  let child = @local.start_managed_provider_with_inputs_and_execution(
    provider,
    generated,
    [@local.managed_provider_supplied_relation_input(query_read)],
    10000,
    20000,
    execution,
  ).unwrap()
  let mut completed = None
  for _ in 0..<10000 {
    match @local.advance_managed_provider(child, 31).unwrap() {
      @local.Complete(output, ..) => {
        completed = Some(output)
        break
      }
      @local.Continue(..) | @local.Settling(_, ..) => ()
      _ => fail("actual Source Query prefix must complete")
    }
  }
  let output = completed.unwrap()
  let live = Ref(true)
  let port = @query.prepare_trusted_capture_port(
    sequence,
    @planning.query_requirement_program(requirement),
    fn(_ : Unit) { if live.val { Some((output, 1)) } else { None } },
  ).unwrap()
  let capture = @query.capture_verified_source(port, ()).unwrap()
  let right_input = @acquisition.keyed_join_input(keyed.binding.join)
  let right_rows = @execution.capture_input(
    keyed.owner,
    right_input,
    [
      scalar_profile_cursor(
        "{\"id\":\"original-a\",\"mime\":\"text/plain\",\"text\":\"actual right original\",\"version\":\"v1\"}",
      ),
    ],
    max_rows=1,
    execution.rows.input_values,
  ).unwrap()
  let read = @execution.prepare_supplied_relation_read(
    keyed.owner,
    right_input,
    right_rows,
    () => live.val,
  ).unwrap()
  // Same rows and owner, separately issued read identity: this must not match.
  let foreign_read = @execution.prepare_supplied_relation_read(
    keyed.owner,
    right_input,
    right_rows,
    () => live.val,
  ).unwrap()
  let limits = run_materials_limits()
  let compilation = issue_prepared_client_effect_compilation(
    prepared,
    run_materials_manifests(),
    limits.sequence,
    limits.max_sequence_steps,
    limits.max_sequence_work,
    limits.max_evidence_bytes,
    limits.max_evidence_nodes,
    limits.max_evidence_depth,
  ).unwrap()
  let allowed = issue_client_effect_allowed_run(
    compilation,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = issue_client_effect_run_definition(
    allowed, "source-slot-scope", "source-slot-original", "2026-11-15T00:00:00.000Z",
    "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let bound = bind_prepared_client_effect_run(
    prepared,
    client_effect_allowed_run_admission(allowed),
    definition,
  ).unwrap()
  let ledger = @resources.create_ledger({
    planning_work: 100000,
    attempts: 100,
    holdings: 100,
    transfer_bytes: 1000000L,
    retained_bytes: 1000000L,
    execution_bytes: 1000000L,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 100000L, 100000L).unwrap()
  let census = @resources.begin_original_ledger_inventory(
    ledger, bootstrap, 20, 20, 0,
  ).unwrap()
  let graph = prepare_client_effect_keyed_plan_graph(
    prepared,
    keyed,
    profile,
    client_standard_values_sequence_limits(),
    1000000,
    100000,
    100,
  ).unwrap()
  let compiled = client_effect_allowed_keyed_run(allowed, graph, definition).unwrap()
  let request = prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "cache-not-ready",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  let source_original = bind_client_effect_keyed_original(
    prepared, compilation, compiled, definition, request, graph, keyed, ledger, census,
  ).unwrap()
  let retention = @publication.issue_result_retention_for_data_policy(
    product_expiry_original_retention(product_test_originals()),
    prepared_client_effect_publication_data_policy_cid(prepared).unwrap(),
    1000000,
    100000,
    100,
  ).unwrap()
  let left = prepare_client_keyed_capture_left_read(
    keyed, capture, 10000, 10000,
  ).unwrap()
  let lookup = start_client_keyed_lookup_input(left, ledger, 10000, 10000).unwrap()
  let before_cache = @resources.ledger_usage(ledger)
  assert_true(
    client_effect_keyed_cached_dependency_bodies(
      source_original, lookup, retention,
    )
    is None,
  )
  assert_eq(@resources.ledger_usage(ledger), before_cache)
  let (_, task, _) = client_keyed_acquisition_coordinates(keyed).unwrap()
  let host = @strategy.open_captured_effect_keyed_source_run_dag(
    prepared_client_effect_run_graph(bound),
    [(0, capture)],
    ledger,
    task,
    read,
  ).unwrap()
  let run = @strategy.captured_effect_run_dag(host)
  assert_true(
    @strategy.captured_effect_keyed_supplied_input_matches(run, task, 1, read),
  )
  assert_false(
    @strategy.captured_effect_keyed_supplied_input_matches(
      run, task, 1, foreign_read,
    ),
  )
  assert_false(
    @strategy.captured_effect_keyed_supplied_input_matches(run, task, 0, read),
  )
  assert_false(
    @strategy.captured_effect_keyed_supplied_input_matches(
      run,
      task + 1,
      1,
      read,
    ),
  )
  assert_false(
    @strategy.captured_effect_keyed_completed_input_matches(host, task, 1, read),
  )
  assert_false(
    @strategy.captured_effect_keyed_completed_input_matches(
      host, task, 1, foreign_read,
    ),
  )
  assert_false(
    @strategy.captured_effect_keyed_completed_input_matches(host, task, 0, read),
  )
  @strategy.stop_captured_dag(run)
  assert_false(
    @strategy.captured_effect_keyed_completed_input_matches(host, task, 1, read),
  )
  assert_false(
    @strategy.captured_effect_keyed_supplied_input_matches(run, task, 1, read),
  )
  assert_true(@strategy.retire_captured_task_outputs(run))
  stop_client_keyed_lookup_input(lookup)
  assert_true(
    client_effect_keyed_cached_dependency_bodies(
      source_original, lookup, retention,
    )
    is None,
  )
  assert_true(cleanup_client_keyed_lookup_input(lookup, 10000).unwrap())
  assert_true(
    @resources.finish_original_ledger_inventory(ledger, true).unwrap(),
  )
  assert_false(client_effect_keyed_original_current(source_original))
  assert_true(
    client_effect_keyed_cached_dependency_bodies(
      source_original, lookup, retention,
    )
    is None,
  )
  let mut retired = @local.cancel_managed_provider(child)
  assert_true(@local.managed_provider_stopped(child))
  // Provider-internal bounded reclamation preserves a pending first cancel;
  // every continuation consumes its actual original finite cleanup cursor.
  for _ in 0..<1000 {
    if retired {
      break
    }
    let before = @local.managed_provider_cleanup_continuation(child)
    retired = @local.cleanup_managed_provider(child).unwrap()
    if !retired {
      assert_true(before > 0L)
      assert_true(@local.managed_provider_cleanup_continuation(child) < before)
    }
  }
  assert_true(retired)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}
