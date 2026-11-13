///|
test "closed checked Values derive envelopes while retaining explicit Host row policy" {
  let assets = @publication_host.client_local_product_assets()
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    "sha256:42e2125d9fbac72912fd67d8f619769810d5d4c606a362a4e569a89f32be54e0",
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  for (width, rows) in [(101, 0), (101, 1), (1, 101), (1, 1001)] {
    let schema = []
    let cells = []
    let fields = []
    for field in 0..<width {
      let name = "\"v" + field.to_string() + "\""
      fields.push(name)
      schema.push(name + ":{\"type\":\"number\",\"nullable\":false}")
      cells.push(name + ":0")
    }
    let row = "{" + cells.join(",") + "}"
    let data = Array::make(rows, row).join(",")
    let document = "{\"version\":\"actql/0.1\",\"id\":\"closed-shape\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"as\":\"v\",\"values\":{\"schema\":{" +
      schema.join(",") +
      "},\"rows\":[" +
      data +
      "]}}],\"results\":{\"rows\":{\"from\":\"v\",\"fields\":[" +
      fields.join(",") +
      "]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}"
    let result = @publication_host.prepare_effect_free_client_program(
      document,
      Json,
      environment,
      None,
      @publication_host.client_standard_program_preparation_limits(),
    )
    if rows == 1001 {
      guard result is Err(Check(issue)) else {
        fail("Explicit installed Host row policy was bypassed")
      }
      assert_eq(@checked.diagnostic_category(issue), @checked.InvalidInput)
      continue
    }
    let prepared = result.unwrap()
    assert_eq(
      @publication_host.prepared_client_values_max_rows(prepared),
      Int::max(
        @publication_host.client_standard_values_sequence_limits().max_rows,
        rows,
      ),
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
    let plan = client_local_capacity_plan(
      sequences,
      @publication_host.prepared_client_values_max_rows(prepared),
      scalar_values=true,
      graph=Some(@publication_host.prepared_client_graph(prepared)),
    )
    assert_eq(plan.imports.wire.max_columns, width)
    assert_eq(plan.metadata.schema.max_fields, width)
    assert_eq(plan.execution.rows.max_rows, Int::max(1, rows))
    if rows == 0 {
      let demand = plan.scalar_demand.unwrap()
      assert_eq(demand.rows, 1)
      assert_eq(demand.value_nodes, width + 1)
      assert_true(
        physical_equal(demand.original, plan.schema_inventory.unwrap()),
      )
      assert_true(
        client_local_capacity_plan_matches(
          plan,
          sequences,
          @publication_host.prepared_client_values_max_rows(prepared),
        ),
      )
    }
    assert_true(
      source_free_installed_managed_preparation_owned(
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
      is Some(_),
    )
    println(
      "CLOSED_SHAPE width=\{width} rows=\{rows} nodes=\{plan.values.max_nodes}",
    )
  }
}
