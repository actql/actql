///|
fn metadata_capacity_prepared(
  query : String,
  max_rows : Int,
) -> @publication_host.PreparedClientProgram raise {
  let assets = @publication_host.client_local_product_assets()
  guard @json.parse(assets.environment) is Object(fields) &&
    fields.get("evidence_bundle_cid") is Some(String(cid)) else {
    fail("ordinary product Environment evidence missing")
  }
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let lowered = @frontend.lower(
    query,
    @frontend.Sql,
    Some(@frontend.bind_query_context([], cid).unwrap()),
    public_primary=true,
  ).unwrap()
  let prepared = @publication_host.prepare_effect_free_client_program(
    lowered.document,
    lowered.format,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  @publication_host.with_prepared_client_values_row_limit(prepared, max_rows).unwrap()
}

///|
fn metadata_capacity_array_prepared(
  max_rows : Int,
  items? : Int64? = None,
  outer? : Bool = false,
) -> @publication_host.PreparedClientProgram raise {
  let assets = @publication_host.client_local_product_assets()
  guard @json.parse(assets.environment) is Object(fields) &&
    fields.get("evidence_bundle_cid") is Some(String(cid)) else {
    fail("ordinary product Environment evidence missing")
  }
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  // A declared unknown array bound stays unknown despite this fixture's two
  // literal cells. The product proof consumes checked types, never these rows.
  let bound = items
    .map(value => ",\"max_items\":" + value.to_string())
    .unwrap_or("")
  let cells = if items == Some(0L) { "[]" } else { "[1,2]" }
  let document = "{\"version\":\"actql/0.1\",\"id\":\"unproved-array\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"as\":\"seed\",\"values\":{\"schema\":{\"xs\":{\"type\":\"array\",\"nullable\":false,\"items\":{\"type\":\"number\",\"nullable\":false}" +
    bound +
    "}},\"rows\":[{\"xs\":" +
    cells +
    "}]}},{\"as\":\"expanded\",\"from\":\"seed\",\"unnest\":{\"column\":\"xs\",\"as\":\"x\",\"outer\":" +
    outer.to_string() +
    "}}],\"results\":{\"rows\":{\"from\":\"expanded\",\"fields\":[\"x\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}"
  let prepared = @publication_host.prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  @publication_host.with_prepared_client_values_row_limit(prepared, max_rows).unwrap()
}

///|
// This component uses the real prepared graph and execution on one explicitly
// unaccounted diagnostic Ledger; it is not an installed physical Run service.
fn metadata_capacity_host(
  prepared : @publication_host.PreparedClientProgram,
) -> (
  @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  @resources.Ledger,
  @resources.LedgerLimits,
) raise {
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let original = prepare_installed_managed_source_free_with_contracts(
    prepared,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    retained_output=true,
    provider_factory=_ => [],
  ).unwrap()
  assert_true(original.capacity_plan.metadata_retained_bytes > 0L)
  assert_eq(original.capacity_plan.metadata.result_rows_reserved, Some(1))
  let ledger = @resources.create_ledger(original.limits).unwrap()
  let setup = open_checked_local_host(
    prepared,
    None,
    contracts,
    assets.values,
    1L,
    0L,
    0L,
    0L,
    fragment_body=Some(assets.fragment),
    ordered_body=assets.ordered,
    retained_output=true,
    acquisition_ledger=Some(ledger),
    source_free_preparation=Some(original),
  ).unwrap()
  // Use the same trusted publication policy as the ordinary Node caller.
  // This makes the actual Named Result projection/order owner construct its
  // row indices; an output-only task would not need that workspace.
  assert_true(
    @strategy.configure_captured_managed_identity_policy(
      @host_driver.dispatch_driver_run(@builtin.configured_host_driver(setup)),
      true,
      false,
      false,
      false,
    ),
  )
  (setup, ledger, original.limits)
}

///|
test "unknown array metadata funds actual two rows independently of the ten million row policy" {
  let prepared = metadata_capacity_array_prepared(10000000)
  let (setup, ledger, _) = metadata_capacity_host(prepared)
  let execution = match
    execute_source_free_local_tasks_guarded(setup, 64, 100000, () => true) {
    Ok(value) => value
    Err(failure) => {
      retry_local_values_execution_failure_cleanup(failure) |> ignore
      fail("actual two-row metadata execution failed")
    }
  }
  assert_eq(execution.rows().unwrap(), [
    "{\"x\":1,\"xs\":[1,2]}", "{\"x\":2,\"xs\":[1,2]}",
  ])
  let attempts = @resources.ledger_usage(ledger).attempts
  assert_eq(
    attempts,
    @strategy.graph_task_count(
      @publication_host.prepared_client_graph(prepared),
    ),
  )
  assert_true(execution.close())
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.attempts, attempts)
  assert_eq(
    (
      usage.held_bytes,
      usage.reserved_retention_bytes,
      usage.reserved_execution_bytes,
    ),
    (0L, 0L, 0L),
  )
}

///|
test "actual metadata growth exhaustion preserves the same Run attempt and cleanup" {
  let prepared = metadata_capacity_array_prepared(10000000)
  let (setup, ledger, limits) = metadata_capacity_host(prepared)
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(setup),
  )
  let graph = @strategy.captured_dag_graph(run)
  let last = @strategy.graph_result_task(graph, 0).unwrap()
  let blocker : Ref[@resources.CapacityReservation?] = Ref(None)
  let result = execute_source_free_local_tasks_guarded(setup, 64, 100000, fn() {
    let usage = @resources.ledger_usage(ledger)
    if blocker.val is None && usage.attempts == last + 1 {
      // Leave the selected provider's already-reserved workspace untouched,
      // but exhaust the SAME Ledger before Result metadata growth starts.
      blocker.val = Some(
        @resources.reserve_capacity(
          ledger,
          0L,
          limits.execution_bytes - usage.reserved_execution_bytes,
        ).unwrap(),
      )
    }
    true
  })
  assert_true(blocker.val is Some(_))
  guard result is Err(failure) else { fail("exhausted metadata completed") }
  assert_true(failure.issue is Driver(Execution(Physical(ExecutionLimit))))
  assert_true(retry_local_values_execution_failure_cleanup(failure))
  @resources.settle_capacity(ledger, blocker.val.unwrap()).unwrap()
  let usage = @resources.ledger_usage(ledger)
  assert_eq(usage.attempts, last + 1)
  assert_eq(
    (
      usage.held_bytes,
      usage.reserved_retention_bytes,
      usage.reserved_execution_bytes,
    ),
    (0L, 0L, 0L),
  )
}

///|
test "metadata capacity controls preserve successful scalar and general layouts" {
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  for
    (query, rows) in [
      ("SELECT x FROM UNNEST([1, 2]) AS x", 100),
      ("SELECT 7 AS x", 10000000),
      ("SELECT x FROM UNNEST([1, 2]) AS x WHERE FALSE", 100),
    ] {
    let prepared = metadata_capacity_prepared(query, rows)
    let sequences = prepare_client_local_sequences(
      prepared,
      contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ).unwrap()
    let graph = @publication_host.prepared_client_graph(prepared)
    let plan = client_local_capacity_plan(
      sequences,
      rows,
      scalar_values=true,
      graph=Some(graph),
    )
    assert_true(plan.metadata_retained_bytes > 0L)
    assert_true(client_local_capacity_plan_matches(plan, sequences, rows))
    let envelope = plan._retained_result_envelope.unwrap()
    if query == "SELECT 7 AS x" {
      let proof = plan.schema_inventory.unwrap()
      let specialized = client_local_scalar_metadata_envelope(
        proof, graph, 1, envelope,
      ).unwrap()
      assert_eq(plan.metadata_retained_bytes, specialized.0)
    } else {
      assert_true(plan.schema_inventory is None)
      assert_eq(
        client_local_result_metadata_retained(
          envelope,
          1,
          client_node_publication_schema_bytes(),
        ),
        Some(plan.metadata_retained_bytes),
      )
    }
    let generic = client_local_capacity_plan(
      sequences,
      rows,
      scalar_values=false,
      graph=Some(graph),
    )
    assert_eq(
      generic.metadata_retained_bytes,
      client_local_cleanup_retained_bytes(),
    )
    assert_true(client_local_capacity_plan_matches(generic, sequences, rows))
    let no_graph = client_local_capacity_plan(sequences, rows)
    assert_eq(no_graph.metadata_retained_bytes, 0L)
    assert_true(client_local_capacity_plan_matches(no_graph, sequences, rows))
  }
}

///|
test "policy row product does not allocate an overflowing metadata envelope" {
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let prepared = metadata_capacity_array_prepared(2147483647)
  let sequences = prepare_client_local_sequences(
    prepared,
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let plan = client_local_capacity_plan(
    sequences,
    2147483647,
    scalar_values=true,
    graph=Some(@publication_host.prepared_client_graph(prepared)),
  )
  assert_eq(
    plan._retained_result_envelope.unwrap().workspace_entries,
    2147483647,
  )
  assert_true(plan.metadata_quote is MetadataQuoted(_))
  assert_true(plan.metadata_retained_bytes > 0L)
  assert_true(client_local_capacity_plan_matches(plan, sequences, 2147483647))
}

///|
test "metadata quote retains empty typed Results with aliases and repeated order" {
  let prepared = result_envelope_fixture()
  let original = publication_plan_fixture(prepared)
  assert_true(original.capacity_plan._retained_result_envelope is Some(_))
  assert_true(original.capacity_plan.metadata_retained_bytes > 0L)
  assert_true(
    client_local_capacity_plan_matches(
      original.capacity_plan,
      original.sequences,
      @publication_host.prepared_client_values_max_rows(prepared),
    ),
  )
}

///|
test "closed UNNEST metadata uses original proven demand independently of the Host row ceiling" {
  let assets = @publication_host.client_local_product_assets()
  let contracts = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let original = metadata_capacity_prepared(
    "SELECT x FROM UNNEST([1, 2]) AS x", 100,
  )
  let graph = @publication_host.prepared_client_graph(original)
  let mut retained : Int64? = None
  for ceiling in [100, 100000, 10000000] {
    let prepared = @publication_host.with_prepared_client_values_row_limit(
      original, ceiling,
    ).unwrap()
    assert_true(
      physical_equal(graph, @publication_host.prepared_client_graph(prepared)),
    )
    let sequences = prepare_client_local_sequences(
      prepared,
      contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ).unwrap()
    let plan = client_local_capacity_plan(
      sequences,
      ceiling,
      scalar_values=true,
      graph=Some(graph),
    )
    assert_eq(plan.admitted_rows, ceiling)
    assert_eq(plan.execution.rows.max_rows, 2)
    assert_true(plan.metadata_retained_bytes > 0L)
    assert_true(client_local_capacity_plan_matches(plan, sequences, ceiling))
    match retained {
      None => retained = Some(plan.metadata_retained_bytes)
      Some(previous) => assert_eq(plan.metadata_retained_bytes, previous)
    }
    assert_true(
      source_free_installed_managed_preparation_owned(
        Pure(prepared),
        contracts,
        assets.values,
        Some(assets.fragment),
        assets.ordered,
        false,
      )
      is Ok(_),
    )
  }
}

///|
test "checked UNNEST bounds preserve unknown positional outer and overflow distinctions" {
  for
    (items, outer, rows, expected) in [
      (None, false, 1, None),
      (Some(2L), false, 3, Some(6)),
      (Some(0L), false, 3, Some(0)),
      (Some(0L), true, 3, Some(3)),
      (Some(2L), true, 0, Some(0)),
      (Some(2147483647L), false, 2, None),
      (Some(2147483648L), false, 1, None),
    ] {
    let prepared = metadata_capacity_array_prepared(100, items~, outer~)
    let graph = @publication_host.prepared_client_graph(prepared)
    let owner = @strategy.graph_task_owner(graph, 0).unwrap()
    let original = @lower.bound_preparation(owner)
    let mut observed = 0
    for index in 0..<@lower.node_count(original) {
      let node = @lower.node_at(original, index).unwrap()
      if @lower.payload(node) is @lower.Unnest(_) {
        observed += 1
        assert_eq(@lower.node_row_count_bound(node, [rows]), expected)
        assert_eq(@lower.node_row_count_bound(node, [-1]), None)
        assert_eq(@lower.node_row_count_bound(node, []), None)
      }
    }
    assert_eq(observed, 1)
  }
}

///|
test "metadata quote distinguishes required failure absent role and genuine zero" {
  let original = metadata_capacity_prepared("SELECT 7 AS x", 100)
  let graph = @publication_host.prepared_client_graph(original)
  let envelope = client_local_result_envelope(graph, 1).unwrap()
  assert_true(
    client_local_result_metadata_quote(None, true, None, 1)
    is MetadataNotApplicable,
  )
  assert_true(
    client_local_result_metadata_quote(Some(graph), true, None, 1)
    is MetadataUnavailable,
  )
  assert_true(
    client_local_result_metadata_quote(
      Some(graph),
      true,
      Some(envelope),
      2147483647,
    )
    is MetadataUnavailable,
  )
  assert_true(
    client_local_result_metadata_quote(Some(graph), true, Some(envelope), 1)
    is MetadataQuoted(_),
  )
  let graphless = client_local_capacity_plan([], 100)
  assert_true(graphless.metadata_quote is MetadataNotApplicable)
  assert_true(client_local_capacity_plan_matches(graphless, [], 100))
  assert_true(
    client_local_capacity_plan_matches(
      { ..graphless, metadata_quote: MetadataQuoted(0L), },
      [],
      100,
    ),
  )
  assert_false(
    client_local_capacity_plan_matches(
      { ..graphless, metadata_quote: MetadataUnavailable, },
      [],
      100,
    ),
  )
  assert_false(
    client_local_capacity_plan_matches(
      { ..graphless, metadata_quote: MetadataQuoted(1L), },
      [],
      100,
    ),
  )
}
