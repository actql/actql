///|
/// Canonical finite Number/Boolean rows only. The pinned binary64 formatter
/// emits at most 25 ASCII bytes (the negative fixed-notation -6 exponent case).
/// Decimal, strings, references and nested values never enter this proof.
fn client_local_scalar_wire_bytes(
  sequences : Array[@execution.GeneratedSequence],
  max_rows : Int,
) -> Int? {
  match client_local_schema_proof_inventory(sequences) {
    Some(inventory) =>
      client_local_scalar_wire_byte_bound(
        inventory.fields,
        inventory.names,
        max_rows,
      )
    None => None
  }
}

///|
test "capacity plan quote funds metadata and narrows only scalar wire" {
  let assets = @publication_host.client_local_product_assets()
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    "sha256:2217670f3f4f54047e764878501863d4eaf37cf069ab741d7306a9d8985cc94f",
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  for
    (name, query, format) in [
      (
        "ordered-offset",
        "SELECT x FROM (SELECT 3 AS x UNION ALL SELECT 1 AS x UNION ALL SELECT 2 AS x) ORDER BY x LIMIT 1 OFFSET 1",
        @frontend.Sql,
      ),
      (
        "having",
        "SELECT x, COUNT(*) AS n FROM (SELECT 1 AS x UNION ALL SELECT 1 AS x UNION ALL SELECT 2 AS x) GROUP BY x HAVING COUNT(*) > 1",
        @frontend.Sql,
      ),
      (
        "pipe",
        "FROM (SELECT 3 AS x UNION ALL SELECT 1 AS x UNION ALL SELECT 2 AS x) AS t |> WHERE x > 1 |> EXTEND x * 2 AS y |> ORDER BY y DESC |> LIMIT 1 |> SELECT y",
        @frontend.Text,
      ),
      (
        "four-term",
        "SELECT x FROM (SELECT 1 AS x UNION ALL SELECT 2 AS x UNION ALL SELECT 3 AS x UNION ALL SELECT 4 AS x) ORDER BY x",
        @frontend.Sql,
      ),
    ] {
    let lowered = @frontend.lower(
      query,
      format,
      Some(
        @frontend.bind_query_context(
          [],
          "sha256:2217670f3f4f54047e764878501863d4eaf37cf069ab741d7306a9d8985cc94f",
        ).unwrap(),
      ),
      public_primary=true,
    ).unwrap()
    let prepared = @publication_host.prepare_effect_free_client_program(
      lowered.document,
      lowered.format,
      environment,
      None,
      @publication_host.client_standard_program_preparation_limits(),
    ).unwrap()
    let sequences = prepare_client_local_sequences_owned(
        Pure(prepared),
        prepare_installed_sequence_contracts(
          assets.registry,
          assets.values,
          Some(assets.fragment),
          assets.ordered,
        ).unwrap(),
        assets.values,
        Some(assets.fragment),
        assets.ordered,
      )
      .to_option()
      .unwrap()
    let max_rows = @publication_host.prepared_client_values_max_rows(prepared)
    client_local_scalar_nodes(sequences, max_rows).unwrap() |> ignore
    let (_, execution, measurement) = client_local_execution_limits(
      max_rows~,
      scalar_sequences=Some(sequences),
    )
    let mut provider = 0L
    for sequence in sequences {
      let current = @execution.execution_capacity_retained_bytes(
        @execution.generated_sequence_capacity(sequence, execution, measurement).unwrap(),
      )
      if current > provider {
        provider = current
      }
    }
    let graph = @publication_host.prepared_client_graph(prepared)
    let plan = client_local_capacity_plan(
      sequences,
      max_rows,
      scalar_values=true,
      graph=Some(graph),
    )
    assert_true(client_local_capacity_plan_matches(plan, sequences, max_rows))
    let general = client_local_capacity_plan(
      sequences,
      max_rows,
      scalar_values=false,
      graph=Some(graph),
    )
    assert_eq(
      general.metadata_retained_bytes,
      client_local_cleanup_retained_bytes(),
    )
    assert_eq(general.metadata.retained_bytes, general.metadata_retained_bytes)
    assert_true(
      client_local_capacity_plan_matches(general, sequences, max_rows),
    )
    assert_false(
      client_local_capacity_plan_matches(
        {
          ..plan,
          metadata: { ..plan.metadata, retained_bytes: 0L, },
          metadata_retained_bytes: 0L,
        },
        sequences,
        max_rows,
      ),
    )
    // A missing or foreign typed demand cannot silently select generic/zero
    // metadata after the original scalar proof has been established.
    assert_false(
      client_local_capacity_plan_matches(
        { ..plan, scalar_demand: None, },
        sequences,
        max_rows,
      ),
    )
    let original_demand = plan.scalar_demand.unwrap()
    let foreign_inventory = { ..original_demand.original, }
    let foreign_demand = { ..original_demand, original: foreign_inventory, }
    assert_false(
      client_local_capacity_plan_matches(
        { ..plan, scalar_demand: Some(foreign_demand), },
        sequences,
        max_rows,
      ),
    )
    assert_false(
      client_local_capacity_plan_matches(plan, sequences, max_rows + 1),
    )
    assert_false(client_local_capacity_plan_matches(plan, [], max_rows))
    assert_eq(plan.imports.wire.max_nodes, plan.values.max_nodes + 3)
    assert_eq(plan.exports.wire.max_nodes, plan.values.max_nodes + 3)
    assert_eq(plan.metadata.schema.max_nodes, 100000)
    assert_eq(plan.metadata.schema.max_bytes, 1000000)
    assert_eq(
      plan.metadata.schema.max_fields,
      plan.schema_inventory.unwrap().fields,
    )
    assert_eq(plan.metadata.bridge_entries, 100000)
    assert_eq(plan.metadata.completion_entries, 100000)
    assert_eq(
      plan.values.max_text_bytes,
      client_local_scalar_name_bytes(sequences, plan.execution.rows.max_rows).unwrap(),
    )
    assert_eq(plan.measurement.max_bytes, 500000)
    assert_eq(
      plan.imports.wire.max_bytes,
      client_local_scalar_wire_bytes(sequences, plan.execution.rows.max_rows).unwrap(),
    )
    assert_eq(plan.metadata.name_bytes, 1000000)
    assert_true(plan.metadata_retained_bytes > 0L)
    assert_eq(plan.metadata.retained_bytes, plan.metadata_retained_bytes)
    let mut terms = 0
    for index in 0..<@strategy.graph_result_count(graph) {
      let occurrence = @strategy.graph_result_occurrence(graph, index).unwrap()
      terms += @results.port_order_term_count(
        @execution.managed_result_occurrence_port(occurrence),
      )
    }
    assert_eq(
      plan.metadata.result_workspace_entries,
      2 * plan.execution.rows.max_rows + terms,
    )
    let mut f = 0
    let mut n = 0
    let mut p = 0
    let mut b = 0
    for sequence in sequences {
      let original = @lower.bound_preparation(
        @execution.generated_sequence_owner(sequence),
      )
      let inputs = @lower.preparation_input_count(original)
      p = Int::max(p, inputs)
      b = Int::max(b, inputs)
      for index in 0..<inputs {
        let schema = @lower.preparation_input_schema(original, index).unwrap()
        f = Int::max(f, @schema.field_count(schema))
        n = Int::max(n, @schema.field_reference_name_bytes(schema))
      }
      for index in 0..<@lower.node_count(original) {
        let node = @lower.node_at(original, index).unwrap()
        let schema = @lower.node_relation_schema(node).unwrap()
        f = Int::max(f, @schema.field_count(schema))
        n = Int::max(n, @schema.field_reference_name_bytes(schema))
        p = Int::max(p, @lower.node_input_count(node))
        b = Int::max(b, @lower.node_input_count(node))
      }
    }
    let i = @strategy.graph_result_count(graph) + 1
    let bridge = p * (3 * f + 2 * b + 8)
    let completion = 4 * p + 2 * b + 64 * i + 16
    // The initial Result constructor retains one pair of row-index slots.
    // Later actual rows grow that same metadata owner before construction;
    // the independent row-policy ceiling above remains unchanged.
    let exported = 24 * f + 2 + terms + 64
    let dispatch = 8 * p + 8 * i + 64
    let schema_bytes = 6 * n + 96 * f + 2
    let expected_metadata = (bridge + completion + exported + dispatch).to_int64() *
      256L +
      schema_bytes.to_int64() * 8L +
      client_local_cleanup_retained_bytes()
    assert_eq(plan.metadata_retained_bytes, expected_metadata)
    println(
      "METADATA_PROOF name=\{name} F=\{f} N=\{n} P=\{p} B=\{b} I=\{i} R=\{plan.execution.rows.max_rows} O=\{terms} bridge=\{bridge} completion=\{completion} export=\{exported} dispatch=\{dispatch} schema_bytes=\{schema_bytes}",
    )

    let mut provider = 0L
    for sequence in sequences {
      let actual = @execution.generated_sequence_capacity(
        sequence,
        plan.execution,
        plan.measurement,
      ).unwrap()
      provider = Int64::max(
        provider,
        @execution.execution_capacity_retained_bytes(actual),
      )
    }
    let import_bytes = @local.local_import_retention_capacity(plan.imports).unwrap()
    let export_bytes = @local.local_export_retention_capacity(plan.exports).unwrap()
    let tasks = @strategy.graph_task_count(graph)
    let ports = @strategy.graph_data_count(graph)
    let retained = tasks.to_int64() *
      (provider + export_bytes + plan.metadata_retained_bytes) +
      ports.to_int64() * import_bytes
    let accepted = source_free_installed_managed_preparation_owned(
        Pure(prepared),
        prepare_installed_sequence_contracts(
          assets.registry,
          assets.values,
          Some(assets.fragment),
          assets.ordered,
        ).unwrap(),
        assets.values,
        Some(assets.fragment),
        assets.ordered,
        false,
      ).to_option()
      is Some(_)
    // The estimate can exceed the finite policy without rejecting a small
    // actual execution. Per-task construction and live holdings still need
    // their original reservations from that policy at runtime.
    assert_true(accepted)
    println(
      "CAPACITY_PLAN_QUOTE name=\{name} rows=\{plan.execution.rows.max_rows} nodes=\{plan.values.max_nodes} tasks=\{tasks} ports=\{ports} provider=\{provider} import=\{import_bytes} export=\{export_bytes} metadata=\{plan.metadata_retained_bytes} retained=\{retained} accepted=\{accepted}",
    )
  }
}

///|
test "scalar wire capacity byte proof bounds empty rows and checked arithmetic" {
  assert_eq(client_local_scalar_wire_byte_bound(1, 2, 0), Some(30))
  assert_eq(client_local_scalar_wire_byte_bound(1, 2, 1), Some(74))
  assert_eq(client_local_scalar_wire_byte_bound(100, 1000000, 20000), None)
  assert_eq(client_local_scalar_wire_byte_bound(-1, 0, 1), None)
  assert_eq(client_local_scalar_wire_byte_bound(1, -1, 1), None)
  assert_eq(client_local_scalar_wire_byte_bound(1, 1, -1), None)
  assert_eq(client_local_scalar_wire_byte_bound(101, 1, 1), Some(2968))
  assert_eq(client_local_scalar_wire_bytes([], 100), None)
}

///|
test "capacity plan derives task inventory from charged graph work beyond thirty two" {
  let assets = @publication_host.client_local_product_assets()
  let evidence = "sha256:2217670f3f4f54047e764878501863d4eaf37cf069ab741d7306a9d8985cc94f"
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    evidence,
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  for terms in [6, 7, 8, 9, 10] {
    let parts = []
    for index in 1..<(terms + 1) {
      parts.push("SELECT " + index.to_string() + " AS x")
    }
    let query = "SELECT x FROM (" + parts.join(" UNION ALL ") + ") ORDER BY x"
    let lowered = @frontend.lower(
      query,
      @frontend.Sql,
      Some(@frontend.bind_query_context([], evidence).unwrap()),
      public_primary=true,
    ).unwrap()
    let limits = @publication_host.client_standard_program_preparation_limits()
    let ordinary = @publication_host.prepare_effect_free_client_program(
      lowered.document,
      lowered.format,
      environment,
      None,
      limits,
    )
    assert_true(ordinary is Ok(_))
    let prepared = ordinary.unwrap()
    assert_eq(@publication_host.prepared_client_values_max_rows(prepared), 100)
    let tasks = @strategy.graph_task_count(
      @publication_host.prepared_client_graph(prepared),
    )
    let sequences = prepare_client_local_sequences_owned(
        Pure(prepared),
        prepare_installed_sequence_contracts(
          assets.registry,
          assets.values,
          Some(assets.fragment),
          assets.ordered,
        ).unwrap(),
        assets.values,
        Some(assets.fragment),
        assets.ordered,
      )
      .to_option()
      .unwrap()
    let inventory = client_local_schema_proof_inventory(
      sequences,
      graph=Some(@publication_host.prepared_client_graph(prepared)),
    ).unwrap()
    assert_eq(inventory.original_count, tasks)
    assert_eq(inventory.closed_rows, Some(terms))
    let plan = client_local_capacity_plan(
      sequences,
      100,
      scalar_values=true,
      graph=Some(@publication_host.prepared_client_graph(prepared)),
    )
    assert_eq(plan.admitted_rows, 100)
    assert_eq(plan.execution.rows.max_rows, terms)
    assert_true(plan.dispatch_entries >= 2)
    assert_true(plan.dispatch_name_bytes >= inventory.names)
    let wider = { ..inventory, fields: 101, names: 303, }
    assert_eq(
      client_local_dispatch_bounds(
        Some(wider),
        Some(@publication_host.prepared_client_graph(prepared)),
      ),
      (20604, 30906),
    )
    assert_true(client_local_capacity_plan_matches(plan, sequences, 100))
    assert_false(client_local_capacity_plan_matches(plan, sequences, 99))
    assert_true(inventory._observed_owner_count < tasks)
    assert_true(inventory._observed_work_used > 0)
    assert_true(
      client_local_schema_proof_inventory(
        sequences,
        max_work=inventory._observed_work_used,
      )
      is Some(_),
    )
    assert_true(
      client_local_schema_proof_inventory(
        sequences,
        max_work=inventory._observed_work_used - 1,
      )
      is None,
    )
    println(
      "PROOF_INVENTORY tasks=\{tasks} original_owners=\{inventory._observed_owner_count} work=\{inventory._observed_work_used}",
    )

    let admitted = source_free_installed_managed_preparation_owned(
        Pure(prepared),
        prepare_installed_sequence_contracts(
          assets.registry,
          assets.values,
          Some(assets.fragment),
          assets.ordered,
        ).unwrap(),
        assets.values,
        Some(assets.fragment),
        assets.ordered,
        false,
      ).to_option()
      is Some(_)
    assert_eq(tasks, 4 * terms + 1)
    assert_true(admitted)
    println("TASK_BOUNDARY terms=\{terms} tasks=\{tasks} admitted=\{admitted}")
  }
}
