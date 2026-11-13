///|
fn sequence_demand_fixture(
  rows : Int,
  second : Bool,
  fields? : Int = 1,
) -> @publication_host.PreparedClientProgram raise {
  let assets = @publication_host.client_local_product_assets()
  // Same installed Local selector as installed-host-policy.mjs, not a new
  // fixture-only row grant: derive both ceilings from the original policy.
  let selected_rows = client_local_materialized_row_ceiling(
      client_local_resource_policy(),
    )
    .unwrap()
    .to_string()
  assert_eq(selected_rows, "2097152")
  let environment_wire = assets.environment
    .replace(
      old="\"max_relation_output_rows\":1000",
      new="\"max_relation_output_rows\":" + selected_rows,
    )
    .replace(
      old="\"max_artifact_rows\":1000",
      new="\"max_artifact_rows\":" + selected_rows,
    )
    .replace(
      old="sha256:42e2125d9fbac72912fd67d8f619769810d5d4c606a362a4e569a89f32be54e0",
      new="sha256:5bb1836f262e68497d8aa17c963ae51b0f69e669114f127bf93c634211eb8258",
    )
  assert_true(environment_wire != assets.environment)
  let environment = @publication_host.admit_client_check_environment(
    environment_wire,
    "sha256:5bb1836f262e68497d8aa17c963ae51b0f69e669114f127bf93c634211eb8258",
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let mut schema = "\"x\":{\"type\":\"number\",\"nullable\":false}"
  let mut row = "\"x\":1"
  for field in 1..<fields {
    schema += ",\"x\{field}\":{\"type\":\"number\",\"nullable\":false}"
    row += ",\"x\{field}\":1"
  }
  let cells = ("{" + row + "},").repeat(rows)
  let body = if rows == 0 { "" } else { cells[:cells.length() - 1].to_owned() }
  let first = "{\"values\":{\"schema\":{" +
    schema +
    "},\"rows\":[" +
    body +
    "]},\"as\":\"a\"}"
  let next = if second {
    "," +
    first.replace(old="\"as\":\"a\"", new="\"as\":\"b\"") +
    ",{\"from\":\"a\",\"join\":{\"with\":\"b\",\"kind\":\"inner\",\"on\":[{\"left\":\"x\",\"right\":\"x\"}],\"max_output_rows\":1,\"select\":{\"x\":\"left.x\"}},\"as\":\"j\"}"
  } else {
    ""
  }
  let result = if second { "j" } else { "a" }
  let document = "{\"version\":\"actql/0.1\",\"id\":\"demand\",\"stages\":[{\"id\":\"s\",\"inputs\":{},\"steps\":[" +
    first +
    next +
    "],\"results\":{\"r\":{\"from\":\"" +
    result +
    "\",\"fields\":[\"x\"]}}}],\"results\":{\"r\":{\"from\":{\"stage\":\"s\",\"result\":\"r\"}}}}"
  let standard = @publication_host.client_standard_program_preparation_limits()
  let extent = document.length()
  let limits = {
    ..standard,
    checking: {
      ..standard.checking,
      input: {
        source: { max_input_bytes: extent, max_nodes: extent, max_depth: 32, },
        tree: {
          max_nodes: extent,
          max_depth: 32,
          max_string_bytes: 64,
          max_total_string_bytes: extent,
        },
        max_stages: 1,
      },
    },
  }
  match
    @publication_host.prepare_effect_free_client_program(
      document,
      Json,
      environment,
      None,
      limits,
    ) {
    Ok(value) => value
    Err(@publication_host.Check(issue)) =>
      match @checked.diagnostic_cause(issue) {
        @checked.Closure(cause) => raise cause
        cause => raise cause
      }
    Err(_) => abort("sequence demand fixture preparation")
  }
}

///|
test "authored Values intake survives JOIN cardinality and exact one-short budgets" {
  for rows in [51, 1000] {
    let program = sequence_demand_fixture(rows, true)
    let graph = @publication_host.prepared_client_graph(program)
    let owner = @strategy.graph_task_owner(graph, 0).unwrap()
    let prepared = @lower.bound_preparation(owner)
    let nodes = @lower.node_count(prepared)
    let demand = @lower.prepared_sequence_preparation_demand(prepared, nodes).unwrap()
    assert_eq(demand.authored_literal_rows, rows * 2)
    assert_eq(demand.authored_literal_cells, rows * 2)
    assert_eq(demand.work_used, nodes)
    assert_true(
      @lower.prepared_sequence_preparation_demand(prepared, nodes - 1)
      is Err(@lower.WorkLimit),
    )
    let limits = @publication_host.prepared_client_values_sequence_limits(
      program,
    )
    assert_true(limits.max_rows >= rows * 2)
    assert_true(limits.max_cells >= rows * 2)
    let exact = { ..limits, max_rows: rows * 2, max_cells: rows * 2, }
    assert_true(@lower.prepare_sequence(owner, exact) is Ok(_))
    assert_true(
      @lower.prepare_sequence(owner, { ..exact, max_rows: rows * 2 - 1, })
      is Err(@lower.ValuesFailure(_, _)),
    )
    assert_true(
      @lower.prepare_sequence(owner, { ..exact, max_cells: rows * 2 - 1, })
      is Err(@lower.ValuesFailure(_, _)),
    )
  }
}

///|
test "single Values authored cells cross former10000 boundary without copying original rows" {
  for
    (rows, fields) in [(0, 1), (1000, 10), (1000, 11), (1000, 100), (100000, 1)] {
    let cells = rows * fields
    let program = sequence_demand_fixture(rows, false, fields~)
    let owner = @strategy.graph_task_owner(
      @publication_host.prepared_client_graph(program),
      0,
    ).unwrap()
    let limits = @publication_host.prepared_client_values_sequence_limits(
      program,
    )
    assert_true(limits.max_cells >= cells)
    let sequence = @lower.prepare_sequence(owner, {
      ..limits,
      max_rows: rows,
      max_cells: cells,
    }).unwrap()
    assert_true(physical_equal(@lower.sequence_owner(sequence), owner))
    if rows > 0 {
      assert_true(
        @lower.prepare_sequence(owner, {
          ..limits,
          max_rows: rows,
          max_cells: cells - 1,
        })
        is Err(@lower.ValuesFailure(_, _)),
      )
    }
    assert_true(
      @lower.prepared_sequence_preparation_demand(
        @lower.bound_preparation(owner),
        -1,
      )
      is Err(@lower.InvalidLimits),
    )
  }
}
