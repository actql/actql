///|
// Genuine common Whole RowRun, original source/input custody, actual empty
// typed key set and lookup holding. This component fixture has no physical
// provider/Store IO and claims no Native transport or durable ACK.
test "generic Whole lookup freezes its genuine empty response closure before holding and retires once" {
  let (prepared, keyed, declaration) = generic_file_effect_fixture(whole=true)
  let measured = measure_client_effect_generic_keyed_plan_construction(
    prepared,
    keyed,
    client_standard_values_sequence_limits(),
    1000000,
    100000,
    100,
  ).unwrap()
  let graph = issue_client_effect_keyed_plan_graph(
    measured, 1000000, 100000, 100,
  ).unwrap()
  guard graph.component is GenericKeyedPlan(component) else {
    fail("generic checked component")
  }
  let generated = @execution.prepare_generated_sequence(
    whole_source_capture_contracts(),
    component.original.fragments.joined.sequence,
    [],
    [],
    10000,
    1000000,
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
    allowed, "generic-scope", "generic-original", "2026-11-15T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
  ).unwrap()
  let compiled = client_effect_allowed_keyed_run(allowed, graph, definition).unwrap()
  let request = prepare_client_effect_request_identity(
    prepared,
    "sha256:" + "c".repeat(64),
    "generic-whole",
    source_free_caller_input_intent_cid(),
  ).unwrap()
  let ledger = @resources.create_ledger({
    planning_work: 1000000,
    attempts: 100,
    holdings: 100,
    transfer_bytes: 1000000L,
    retained_bytes: 67108864L,
    execution_bytes: 67108864L,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 100000L, 100000L).unwrap()
  let inventory = @resources.begin_original_ledger_inventory(
    ledger, bootstrap, 50, 50, 0,
  ).unwrap()
  let parent = bind_client_effect_keyed_original(
    prepared, compilation, compiled, definition, request, graph, keyed, ledger, inventory,
  ).unwrap()
  let original = prepare_client_effect_source_acquisition(prepared, 0, 0).unwrap()
  let owner = @strategy.graph_task_owner(
    @strategy.checked_effect_computation_graph(prepared.graph),
    0,
  ).unwrap()
  let sequence = @lower.prepare_sequence_prefix(owner, 0, limits.sequence).unwrap()
  let selected = @row_host.prepare_row_input_acquisition(
    original,
    @checked.source_identity(
      @strategy.graph_program(
        @strategy.checked_effect_computation_graph(prepared.graph),
      ),
    ),
    sequence,
    whole_source_capture_contracts(),
    declaration,
    {
      max_rows: 1,
      page: { max_bytes: 4096, max_nodes: 1000, max_depth: 20, max_rows: 1, },
      retention: {
        max_nodes: 10000,
        max_text_bytes: 10000,
        max_depth: 20,
        max_work: 1000000,
      },
      wire: {
        max_columns: 10,
        max_order_work: 10000,
        max_bytes: 20000,
        max_nodes: 10000,
        max_depth: 20,
      },
    },
  ).unwrap()
  let settled = Ref(false)
  let stopped = Ref(false)
  let run = @row_host.start_accounted_row_input_acquisition(
    selected,
    None,
    "generic-source",
    _ => settled.val,
    ledger,
    4096L,
    4096L,
  ).unwrap()
  @row_host.begin_row_run_with_page_limits(
    run,
    { max_bytes: 4096, max_nodes: 1000, max_depth: 20, max_rows: 1, },
    1,
  ).unwrap()
  let responses = @row_host.borrow_row_input_run_responses(run, selected).unwrap()
  @row_host.bind_row_run_response_borrow_cleanup(responses, () => stopped.val).unwrap()
  let bytes = @utf8.encode("[]")
  let charge = @row_host.charge_row_run_page(run, bytes).unwrap()
  assert_eq(
    @row_host.accept_charged_row_run_page(run, charge, bytes).unwrap(),
    0,
  )
  @row_host.finish_row_run(run).unwrap()
  settled.val = true
  assert_true(whole_row_validate(run))
  let capture = @row_host.capture_row_run(run).unwrap()
  let source = @row_host.row_capture_source(capture).unwrap()
  let rows = @row_host.row_capture_input(capture).unwrap()
  let wire : @execution.RowWireLimits = {
    max_columns: 10,
    max_order_work: 10000,
    max_bytes: 20000,
    max_nodes: 10000,
    max_depth: 20,
  }
  let identity = @query.identify_captured_source_relation(
    source,
    1,
    {
      max_nodes: 10000,
      max_text_bytes: 20000,
      max_depth: 20,
      max_work: 1000000,
    },
    wire,
    wire,
    { max_fields: 10, max_bytes: 20000, max_nodes: 10000, max_depth: 20, },
    20000,
    retain_body_bytes=20000,
  ).unwrap()
  let logical = issue_captured_whole_source_input_logical(
    @strategy.checked_effect_computation_graph(prepared.graph),
    source,
    identity,
    original,
    task=0,
  ).unwrap()
  let observation = @row_host.issue_row_input_source_evidence(
    selected,
    capture,
    identity,
    logical,
    client_request_authority_scope_cid(request),
    @planning.source_acquisition_evidence_facts(original).unwrap().source_data_policy_cid,
    "2026-11-15T00:00:01.000Z",
  ).unwrap()
  let lookup = start_client_effect_keyed_capture_lookup_input(
    parent,
    [rows],
    10000,
    10000,
    1000000,
    1000000,
    source_sequence=Some(generated),
  ).unwrap()
  let retention = match
    prepare_client_effect_keyed_generic_source_metadata(
      parent,
      lookup,
      identity,
      logical,
      observation,
      "sha256:" + "d".repeat(64),
      "2099-01-01T00:00:00.000Z",
      "2099-01-02T00:00:00.000Z",
      "2099-01-03T00:00:00.000Z",
      "sha256:" + "e".repeat(64),
      "sha256:" + "f".repeat(64),
      1000000,
      100000,
      100,
    ) {
    Ok(value) => value
    Err(Assembly(reason)) => fail("generic metadata: " + reason)
    Err(_) => fail("generic metadata: typed refusal")
  }
  assert_true(
    client_effect_keyed_cached_dependency_bodies(parent, lookup, retention)
    is None,
  )
  let before_invalid = @resources.ledger_usage(ledger)
  assert_true(
    finish_client_effect_keyed_generic_publication_input(
      parent, lookup, "not-a-time", 1000000, 100000, 100,
    )
    is Err(Assembly("foreign_generic_completion")),
  )
  assert_eq(@resources.ledger_usage(ledger), before_invalid)
  let read = match
    finish_client_effect_keyed_generic_publication_input(
      parent, lookup, "2026-11-15T00:00:02.000Z", 1000000, 100000, 100,
    ) {
    Ok(value) => value
    Err(Assembly(reason)) => fail("generic completion: " + reason)
    Err(LookupLimit(reason)) => fail("generic completion limit: " + reason)
    Err(Dependency(Dependency(issue))) =>
      fail("generic dependency admission: " + @debug.to_string(issue))
    Err(Dependency(Static(issue))) =>
      fail("generic dependency catalog: " + @debug.to_string(issue))
    Err(Dependency(ForeignInput)) => fail("generic dependency foreign input")
    Err(Dependency(ConstructionRefused)) =>
      fail("generic dependency construction refused")
    Err(Dependency(_)) => fail("generic completion dependency")
    Err(_) => fail("generic completion: typed refusal")
  }
  assert_true(@execution.supplied_relation_read_available(read))
  assert_true(lookup.native_sources is None && lookup.native_completion is None)
  let observed = issue_client_keyed_lookup_observation(
    lookup,
    client_request_authority_scope_cid(request),
    "2026-11-15T00:00:02.000Z",
  ).unwrap()
  assert_true(
    parent.generic is Some(state) &&
    state.completed is Some(completed) &&
    physical_equal(observed, completed.observation),
  )
  let bodies = client_effect_keyed_cached_dependency_bodies(
    parent, lookup, retention,
  ).unwrap()
  assert_true(bodies.length() > 0)
  let before_cached = @resources.ledger_usage(ledger)
  assert_true(
    physical_equal(
      bodies,
      client_effect_keyed_cached_dependency_bodies(parent, lookup, retention).unwrap(),
    ),
  )
  assert_true(
    physical_equal(
      read,
      finish_client_effect_keyed_generic_publication_input(
        parent, lookup, "2026-11-15T00:00:02.000Z", 1000000, 100000, 100,
      ).unwrap(),
    ),
  )
  assert_eq(@resources.ledger_usage(ledger), before_cached)
  assert_true(
    issue_client_keyed_lookup_observation(
      lookup,
      "sha256:" + "9".repeat(64),
      "2026-11-15T00:00:02.000Z",
    )
    is Err(Assembly("foreign_generic_observation_authority")),
  )
  assert_true(
    client_effect_keyed_cached_dependency_bodies(
      parent,
      lookup,
      product_expiry_original_retention(product_test_originals()),
    )
    is None,
  )
  for body in bodies {
    let kind = @publication.captured_effect_dependency_body_kind(body)
    assert_false(kind.has_prefix("native_file_"))
    assert_false(kind == "acquisition_attempt_receipt")
  }
  stop_client_keyed_lookup_input(lookup)
  assert_true(
    client_effect_keyed_cached_dependency_bodies(parent, lookup, retention)
    is None,
  )
  while !cleanup_client_keyed_lookup_input(lookup, 64).unwrap() {

  }
  assert_true(parent.generic is None)
  assert_false(@execution.supplied_relation_read_available(read))
  stopped.val = true
  @row_host.close_accounted_row_run(run).unwrap()
  assert_true(
    @resources.finish_original_ledger_inventory(ledger, true).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}
