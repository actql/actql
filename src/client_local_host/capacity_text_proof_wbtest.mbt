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
    "sha256:2217670f3f4f54047e764878501863d4eaf37cf069ab741d7306a9d8985cc94f",
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
            "sha256:2217670f3f4f54047e764878501863d4eaf37cf069ab741d7306a9d8985cc94f",
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
  let evidence = "sha256:2217670f3f4f54047e764878501863d4eaf37cf069ab741d7306a9d8985cc94f"
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
