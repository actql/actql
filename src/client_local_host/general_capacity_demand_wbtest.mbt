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
  ).to_option()
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
      ("SELECT [1,2] AS x", true),
      ("SELECT STRUCT(1 AS a) AS x", true),
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

///|
test "closed nested value demand keeps the original bounded rectangle instead of a general forest" {
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
  let document = "{\"version\":\"actql/0.1\",\"id\":\"closed-rectangle-demand\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"rows\":{\"type\":\"array\",\"nullable\":false,\"max_items\":2,\"items\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"text\":{\"type\":\"string\",\"nullable\":false},\"number\":{\"type\":\"number\",\"nullable\":false},\"flag\":{\"type\":\"boolean\",\"nullable\":false}}}}},\"rows\":[{\"rows\":[{\"text\":\"é\\r\\n=literal\",\"number\":0,\"flag\":false},{\"text\":\"日本語🙂\",\"number\":1,\"flag\":true}]}]},\"as\":\"out\"}],\"results\":{\"rows\":{\"from\":\"out\",\"fields\":[\"rows\"]}}}],\"results\":{\"rows\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}"
  let prepared = @publication_host.prepare_effect_free_client_program(
    document,
    Json,
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
  let rows = @publication_host.prepared_client_values_max_rows(prepared)
  let plan = client_local_capacity_plan(
    sequences,
    rows,
    scalar_values=true,
    graph=Some(@publication_host.prepared_client_graph(prepared)),
  )
  guard plan.value_node_demand is Some(demand) else {
    fail(
      "the checked two-item, three-scalar rectangle must carry its closed value-node demand",
    )
  }
  // Root row + array + two object rows with three leaves each = ten nodes.
  // The inventory also counts the original generated input/intermediate ports.
  assert_true(demand.nodes >= 10)
  assert_true(demand.nodes < 100)
  assert_eq(plan.values.max_text_bytes, 500000)
  assert_eq(plan.imports.wire.max_bytes, 1000000)
  assert_true(client_local_capacity_plan_matches(plan, sequences, rows))
  // Actual original Local compiler/provider consumer, with its own explicit
  // component Ledger. This is not an ordinary Host admission or normal ABI.
  let original = source_free_installed_managed_preparation_owned(
      Pure(prepared),
      installed,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
      false,
    )
    .to_option()
    .unwrap()
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
  let output = match
    execute_source_free_local_tasks_guarded(setup, 64, 100000, () => true) {
    Ok(value) => value
    Err(failure) => {
      retry_local_values_execution_failure_cleanup(failure) |> ignore
      fail(
        "the original Local consumer could not use the bounded rectangle Plan",
      )
    }
  }
  assert_eq(output.rows().unwrap(), [
    "{\"rows\":[{\"flag\":false,\"number\":0,\"text\":\"é\\r\\n=literal\"},{\"flag\":true,\"number\":1,\"text\":\"日本語🙂\"}]}",
  ])
  assert_true(output.close())
  let closed = @resources.ledger_usage(ledger)
  assert_eq(closed.holdings, 0)
  assert_eq(closed.live_reservations, 0)
  assert_eq(closed.reserved_retention_bytes, 0L)
  assert_eq(closed.reserved_execution_bytes, 0L)
}

///|
test "bounded contract node proof preserves nullable empty work depth and opaque fallbacks" {
  let text = @contract.primitive(StringType, nullable=true)
  let number = @contract.primitive(NumberType, nullable=false)
  let object = @contract.object_contract(
    [("text", text), ("number", number)],
    nullable=true,
    max_fields=2,
    max_name_bytes=10,
  ).unwrap()
  let array = @contract.array_contract(
    object,
    nullable=true,
    max_items=Some(2L),
  ).unwrap()
  let work = Ref(4)
  assert_eq(client_local_json_contract_nodes(array, work, 3), Some(7L))
  assert_eq(work.val, 0)
  assert_true(client_local_json_contract_nodes(array, Ref(3), 3) is None)
  assert_true(client_local_json_contract_nodes(array, Ref(4), 1) is None)
  let unbounded = @contract.array_contract(text, nullable=false).unwrap()
  assert_true(
    client_local_json_contract_nodes(unbounded, Ref(100), 100) is None,
  )
  let empty = @contract.array_contract(
    unbounded,
    nullable=false,
    max_items=Some(0L),
  ).unwrap()
  assert_eq(client_local_json_contract_nodes(empty, Ref(1), 0), Some(1L))
  let overflow = @contract.array_contract(
    text,
    nullable=false,
    max_items=Some(2147483647L),
  ).unwrap()
  assert_true(client_local_json_contract_nodes(overflow, Ref(100), 100) is None)
  let json_contract = @contract.primitive(JsonType, nullable=false)
  assert_true(
    client_local_json_contract_nodes(json_contract, Ref(100), 100) is None,
  )
  let content = @contract.content_reference_contract(
    None,
    nullable=false,
    max_name_bytes=100,
  ).unwrap()
  assert_true(client_local_json_contract_nodes(content, Ref(100), 100) is None)
}

///|
test "checked node proof does not spend the original root field visits twice" {
  let number = @contract.primitive(NumberType, nullable=false)
  let text = @contract.primitive(StringType, nullable=true)
  let root = @contract.object_contract(
    [("number", number), ("text", text)],
    nullable=false,
    max_fields=2,
    max_name_bytes=10,
  ).unwrap()
  let schema = @schema.from_object(root).unwrap()
  // The inventory has already spent one visit for each original root field.
  // No nested contract remains, even when that leaves zero proof work.
  assert_eq(client_local_json_schema_nodes(schema, 0, 100), Some((3L, 0)))
}
