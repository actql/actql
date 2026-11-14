///|
/// Scalar cells still charge original UTF-8 field names per row occurrence.
fn client_local_scalar_name_bytes(
  sequences : Array[@execution.GeneratedSequence],
  max_rows : Int,
) -> Int? {
  match client_local_schema_proof_inventory(sequences) {
    Some(inventory) => client_local_inventory_names(inventory, max_rows)
    None => None
  }
}

///|
test "text-free capacity proof checks every typed child and original step" {
  let assets = @publication_host.client_local_product_assets()
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    "sha256:42e2125d9fbac72912fd67d8f619769810d5d4c606a362a4e569a89f32be54e0",
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  for
    (query, expected, format) in [
      ("SELECT 1 AS n", true, @frontend.Sql),
      (
        "SELECT x FROM (SELECT 1 AS x UNION ALL SELECT 2 AS x UNION ALL SELECT 3 AS x UNION ALL SELECT 4 AS x UNION ALL SELECT 5 AS x) ORDER BY x",
        true,
        @frontend.Sql,
      ),
      (
        "FROM (SELECT 1 AS x UNION ALL SELECT 2 AS x) AS t |> WHERE x > 0 |> EXTEND x * 2 AS y |> SELECT y",
        true,
        @frontend.Text,
      ),
      ("SELECT LENGTH(REPEAT('x', 4)) AS n", false, @frontend.Sql),
      (
        "SELECT CASE WHEN FALSE THEN LENGTH(REPEAT('x', 4)) ELSE 1 END AS n",
        false,
        @frontend.Sql,
      ),
      ("SELECT TRY_NUMBER('12') AS n", false, @frontend.Sql),
      ("SELECT [1,2][OFFSET(0)] AS n", false, @frontend.Sql),
      ("SELECT STRUCT(1 AS x).x AS n", false, @frontend.Sql),
      (
        "SELECT COUNT(*) AS n FROM (SELECT 1 AS x UNION ALL SELECT 2 AS x)",
        true,
        @frontend.Sql,
      ),
      (
        "SELECT x, COUNT(*) AS n FROM (SELECT 1 AS x UNION ALL SELECT 1 AS x UNION ALL SELECT 2 AS x) GROUP BY x HAVING COUNT(*) > 1",
        true,
        @frontend.Sql,
      ),
      (
        "SELECT x, COUNT(x) AS n FROM (SELECT 1 AS x UNION ALL SELECT 2 AS x) GROUP BY x",
        true,
        @frontend.Sql,
      ),
      (
        "SELECT x, COUNT(*) AS n, COUNTIF(x) AS hits FROM (SELECT TRUE AS x UNION ALL SELECT FALSE AS x UNION ALL SELECT CAST(NULL AS BOOL) AS x) GROUP BY x",
        true,
        @frontend.Sql,
      ),
      (
        "SELECT COUNTIF(x > 0) AS n FROM (SELECT 1 AS x UNION ALL SELECT 2 AS x)",
        false,
        @frontend.Sql,
      ),
      (
        "SELECT COUNTIF(LENGTH(REPEAT('x', 4)) > 0) AS n FROM (SELECT 1 AS x)",
        false,
        @frontend.Sql,
      ),
      ("SELECT COUNT(*) AS n FROM (SELECT [1,2] AS x)", false, @frontend.Sql),
      ("SELECT COUNT(*) AS n FROM (SELECT 'text' AS x)", false, @frontend.Sql),
      (
        "SELECT x, COUNT(*) AS n FROM (SELECT 'text' AS x) GROUP BY x",
        false,
        @frontend.Sql,
      ),
      (
        "SELECT COUNT(*) AS n FROM (SELECT CASE WHEN FALSE THEN LENGTH(REPEAT('x', 4)) ELSE 1 END AS x)",
        false,
        @frontend.Sql,
      ),
    ] {
    let lowered = match
      @frontend.lower(
        query,
        format,
        Some(
          @frontend.bind_query_context(
            [],
            "sha256:42e2125d9fbac72912fd67d8f619769810d5d4c606a362a4e569a89f32be54e0",
          ).unwrap(),
        ),
        public_primary=true,
      ) {
      Ok(value) => value
      Err(_) => fail("query lowering failed: " + query)
    }
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
    if client_local_text_free_scalar_sequences(sequences) != expected {
      fail("unexpected text-free proof: " + query)
    }
    let rows = @publication_host.prepared_client_values_max_rows(prepared)
    let plan = client_local_capacity_plan(
      sequences,
      rows,
      scalar_values=true,
      graph=Some(@publication_host.prepared_client_graph(prepared)),
    )
    if expected {
      assert_eq(
        plan.execution.rows.output_values.max_text_bytes,
        client_local_scalar_name_bytes(sequences, plan.execution.rows.max_rows).unwrap(),
      )
    } else {
      assert_eq(plan.execution.rows.output_values.max_text_bytes, 500000)
      assert_eq(plan.execution.rows.input_values.max_text_bytes, 500000)
    }
    assert_eq(plan.measurement.max_bytes, 500000)
    assert_false(client_local_text_free_scalar_sequences(sequences, max_work=0))
    assert_false(client_local_text_free_scalar_sequences(sequences, max_work=1))
  }
  assert_false(client_local_text_free_scalar_sequences([]))
}

///|
test "capacity plan funds checked leaf nodes separately from text and Result metadata" {
  let assets = @publication_host.client_local_product_assets()
  let evidence = "sha256:42e2125d9fbac72912fd67d8f619769810d5d4c606a362a4e569a89f32be54e0"
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    evidence,
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let lowered = @frontend.lower(
    "SELECT 'text' AS value",
    @frontend.Sql,
    Some(@frontend.bind_query_context([], evidence).unwrap()),
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
  let rows = @publication_host.prepared_client_values_max_rows(prepared)
  let plan = client_local_capacity_plan(
    sequences,
    rows,
    scalar_values=true,
    graph=Some(@publication_host.prepared_client_graph(prepared)),
  )
  assert_eq(plan.imports.wire.max_nodes, plan.values.max_nodes + 3)
  assert_eq(plan.imports.wire.max_bytes, 1000000)
  assert_eq(plan.values.max_text_bytes, 500000)
  assert_eq(plan.execution.rows.output_values.max_text_bytes, 500000)
  let selected_rows = plan.execution.rows.max_rows
  assert_eq(selected_rows, 1)
  assert_eq(
    plan.metadata_retained_bytes,
    (24L + 2L * selected_rows.to_int64() + 64L) * 256L +
    client_node_publication_schema_bytes().to_int64() * 8L +
    client_local_cleanup_retained_bytes(),
  )
  assert_eq(plan.metadata.retained_bytes, plan.metadata_retained_bytes)
  assert_eq(plan.metadata.result_workspace_entries, 2 * selected_rows)
  assert_true(
    client_local_sequence_capacity_original(
      sequences,
      sequences.length(),
      capacity_plan=Some(plan),
      max_rows=rows,
    )
    is None,
  )
}

///|
fn client_local_inventory_names(
  inventory : ClientLocalSchemaProofInventory,
  max_rows : Int,
) -> Int? {
  client_local_scalar_product(inventory.max_name_width, max_rows, 0)
}

///|
test "Decimal text proof retains unbounded and dormant child fallback" {
  let assets = @publication_host.client_local_product_assets()
  let evidence = "sha256:42e2125d9fbac72912fd67d8f619769810d5d4c606a362a4e569a89f32be54e0"
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    evidence,
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  for
    (query, bounded) in [
      ("SELECT CAST('1.25' AS DECIMAL(8,2)) AS amount", true),
      ("SELECT CAST(CAST(NULL AS STRING) AS DECIMAL(8,2)) AS amount", false),
      (
        "SELECT CASE WHEN TRUE THEN CAST('1.25' AS DECIMAL(8,2)) ELSE CAST(CAST(NULL AS STRING) AS DECIMAL(8,2)) END AS amount",
        false,
      ),
      (
        "WITH seed AS (SELECT CAST(NULL AS STRING) AS value) SELECT CAST(value AS DECIMAL(8,2)) AS amount FROM seed",
        false,
      ),
    ] {
    let lowered = @frontend.lower(
      query,
      @frontend.Sql,
      Some(@frontend.bind_query_context([], evidence).unwrap()),
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
    let plan = client_local_capacity_plan(
      sequences,
      @publication_host.prepared_client_values_max_rows(prepared),
      scalar_values=true,
      graph=Some(@publication_host.prepared_client_graph(prepared)),
    )
    guard plan.value_node_demand is Some(demand) else {
      fail("Decimal output node proof missing")
    }
    assert_eq(demand.text_bound is Some(_), bounded)
    assert_false(client_local_text_free_scalar_sequences(sequences))
    assert_true(
      client_local_decimal_text_bound(sequences, demand, 500000, max_work=0)
      is None,
    )
    assert_true(
      client_local_decimal_text_bound(sequences, demand, 500000, max_slots=0)
      is None,
    )
    assert_true(client_local_decimal_text_bound(sequences, demand, -1) is None)
    if !bounded {
      assert_eq(plan.values.max_text_bytes, 500000)
      assert_eq(plan.execution.rows.input_values.max_text_bytes, 500000)
      assert_eq(plan.execution.rows.output_values.max_text_bytes, 500000)
    } else {
      let bytes = demand.text_bound.unwrap()
      assert_true(bytes >= 4 + 11 + 6)
      assert_true(
        client_local_capacity_plan_matches(plan, sequences, plan.admitted_rows),
      )
      assert_false(
        client_local_capacity_plan_matches(
          {
            ..plan,
            value_node_demand: Some({ ..demand, text_bound: Some(bytes - 1), }),
          },
          sequences,
          plan.admitted_rows,
        ),
      )
    }
    assert_eq(plan.imports.wire.max_bytes, 1000000)
    assert_eq(plan.measurement.max_bytes, 500000)
  }
}
