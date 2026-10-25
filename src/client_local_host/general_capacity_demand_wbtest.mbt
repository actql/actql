///|
test "closed text UNION keeps its checked finite demand through installed preparation" {
  let assets = @publication_host.client_local_product_assets()
  guard @json.parse(assets.environment) is Object(fields) &&
    fields.get("evidence_bundle_cid") is Some(String(evidence)) else {
    fail("authored product Environment evidence missing")
  }
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    evidence,
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let query = "SELECT x FROM (SELECT 'd' AS x UNION ALL SELECT 'b' AS x UNION ALL SELECT 'c' AS x UNION ALL SELECT 'a' AS x) ORDER BY x"
  let lowered = @frontend.lower(
    query,
    @frontend.Sql,
    Some(@frontend.bind_query_context([], evidence).unwrap()),
  ).unwrap()
  let prepared = @publication_host.prepare_effect_free_client_program(
    lowered.document,
    lowered.format,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  let installed = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let graph = @publication_host.prepared_client_graph(prepared)
  let sequences = prepare_client_local_sequences(
    prepared,
    installed,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  let rows = @publication_host.prepared_client_values_max_rows(prepared)
  let inventory = client_local_schema_proof_inventory(
    sequences,
    graph=Some(graph),
    scalar_only=false,
  ).unwrap()
  assert_eq(inventory.closed_rows, Some(4))
  assert_true(
    client_local_schema_proof_inventory(sequences, graph=Some(graph)) is None,
  )
  let plan = client_local_capacity_plan(
    sequences,
    rows,
    scalar_values=true,
    graph=Some(graph),
  )
  let mut provider = 0L
  for sequence in sequences {
    let capacity = @execution.generated_sequence_capacity(
      sequence,
      plan.execution,
      plan.measurement,
    ).unwrap()
    provider = Int64::max(
      provider,
      @execution.execution_capacity_retained_bytes(capacity),
    )
  }
  let imports = @local.local_import_retention_capacity(plan.imports).unwrap()
  let exports = @local.local_export_retention_capacity(plan.exports).unwrap()
  let tasks = @strategy.graph_task_count(graph)
  let ports = @strategy.graph_data_count(graph)
  let retained = tasks.to_int64() *
    (provider + exports + plan.metadata_retained_bytes) +
    ports.to_int64() * imports
  let original = source_free_installed_managed_preparation_owned(
    Pure(prepared),
    installed,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    false,
  )
  println(
    "GENERAL_CAPACITY text rows=\{plan.execution.rows.max_rows} proven=4 nodes=\{plan.values.max_nodes} tasks=\{tasks} ports=\{ports} provider=\{provider} imports=\{imports} exports=\{exports} metadata=\{plan.metadata_retained_bytes} retained=\{retained} accepted=\{original is Some(_)}",
  )
  assert_true(
    original is Some(_),
    msg="four checked literal text rows must retain a finite installed demand",
  )
  let original = original.unwrap()
  let retained_plan = original.capacity_plan
  assert_eq(retained_plan.execution.rows.max_rows, 4)
  assert_eq(retained_plan.values.max_text_bytes, 500000)
  assert_eq(retained_plan.imports.wire.max_bytes, 1000000)
  assert_eq(retained_plan.exports.wire.max_bytes, 1000000)
  assert_true(
    client_local_capacity_plan_matches(retained_plan, original.sequences, rows),
  )
  let demand = retained_plan.value_node_demand.unwrap()
  assert_false(
    client_local_capacity_plan_matches(
      { ..retained_plan, value_node_demand: None, },
      original.sequences,
      rows,
    ),
  )
  assert_false(
    client_local_capacity_plan_matches(
      {
        ..retained_plan,
        value_node_demand: Some({ ..demand, original: { ..demand.original, }, }),
      },
      original.sequences,
      rows,
    ),
  )
  assert_false(
    client_local_capacity_plan_matches(
      {
        ..retained_plan,
        value_node_demand: Some({ ..demand, nodes: demand.nodes - 1, }),
      },
      original.sequences,
      rows,
    ),
  )
  // Explicit component Ledger only. This is the same immutable installed
  // preparation and selected consumers, not an ordinary Host admission.
  let ledger = @resources.create_ledger(original.limits).unwrap()
  let setup = open_checked_local_host(
    prepared,
    None,
    installed,
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
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  let output = match
    execute_source_free_local_tasks_guarded(setup, 64, 100000, () => true) {
    Ok(value) => value
    Err(failure) => {
      retry_local_values_execution_failure_cleanup(failure) |> ignore
      fail("same prepared text demand failed its actual Local consumer")
    }
  }
  assert_eq(output.rows().unwrap(), [
    "{\"x\":\"a\"}", "{\"x\":\"b\"}", "{\"x\":\"c\"}", "{\"x\":\"d\"}",
  ])
  assert_eq(@resources.ledger_usage(ledger).attempts, tasks)
  assert_true(output.close())
  let closed = @resources.ledger_usage(ledger)
  assert_eq(closed.attempts, tasks)
  assert_eq(closed.holdings, 0)
  assert_eq(closed.live_reservations, 0)
  assert_eq(closed.reserved_retention_bytes, 0L)
  assert_eq(closed.reserved_execution_bytes, 0L)
}

///|
test "leaf demand preserves Unicode nullable text and nested fallback budgets" {
  let assets = @publication_host.client_local_product_assets()
  guard @json.parse(assets.environment) is Object(fields) &&
    fields.get("evidence_bundle_cid") is Some(String(evidence)) else {
    fail("authored product Environment evidence missing")
  }
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    evidence,
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let installed = prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
  ).unwrap()
  for
    (query, leaf) in [
      ("SELECT '日本語🙂' AS x", true),
      (
        "SELECT CASE WHEN TRUE THEN '日本語🙂' ELSE CAST(NULL AS STRING) END AS x",
        true,
      ),
      ("SELECT [1,2] AS x", false),
      ("SELECT STRUCT(1 AS a) AS x", false),
    ] {
    let lowered = @frontend.lower(
      query,
      @frontend.Sql,
      Some(@frontend.bind_query_context([], evidence).unwrap()),
    ).unwrap()
    let prepared = @publication_host.prepare_effect_free_client_program(
      lowered.document,
      lowered.format,
      environment,
      None,
      @publication_host.client_standard_program_preparation_limits(),
    ).unwrap()
    let sequences = prepare_client_local_sequences(
      prepared,
      installed,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
    ).unwrap()
    let graph = @publication_host.prepared_client_graph(prepared)
    let rows = @publication_host.prepared_client_values_max_rows(prepared)
    let plan = client_local_capacity_plan(
      sequences,
      rows,
      scalar_values=true,
      graph=Some(graph),
    )
    assert_eq(plan.value_node_demand is Some(_), leaf)
    assert_true(client_local_capacity_plan_matches(plan, sequences, rows))
    assert_eq(plan.execution.rows.max_rows, 1)
    assert_eq(plan.values.max_text_bytes, 500000)
    assert_eq(plan.values.max_depth, 100)
    assert_eq(plan.values.max_work, 20000000)
    assert_eq(plan.imports.wire.max_bytes, 1000000)
    assert_true(
      client_local_schema_proof_inventory(
        sequences,
        max_work=0,
        graph=Some(graph),
        scalar_only=false,
        leaf_only=true,
      )
      is None,
    )
    if leaf {
      assert_eq(plan.imports.wire.max_nodes, plan.values.max_nodes + 3)
    } else {
      assert_eq(plan.values.max_nodes, 20000)
      assert_eq(plan.imports.wire.max_nodes, 100000)
    }
  }
}
