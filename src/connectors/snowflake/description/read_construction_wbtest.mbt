///|
fn read_quote_limits() -> @rows.RowDeclarationLimits {
  {
    max_bytes: 200000,
    max_nodes: 20000,
    max_depth: 24,
    max_views: 1,
    max_fields: 16,
  }
}

///|
test "Snowflake quote includes all supplied response prefixes with no output maximum tariff" {
  let quote = fn(lengths, declaration) {
    read_declaration_construction_capacity(
      lengths,
      4000,
      24,
      5,
      9,
      13,
      response_limits(),
      limits(),
      declaration,
    )
  }
  let one = quote([1200], read_quote_limits()).unwrap()
  let two = quote([1200, 400], read_quote_limits()).unwrap()
  let peak = @execution.execution_capacity_execution_bytes(two)
  println("Snowflake constructor body_bytes=1600 peak_bytes=\{peak}")
  assert_true(peak < 536870912L)
  assert_true(peak > @execution.execution_capacity_execution_bytes(one))
  assert_eq(@execution.execution_capacity_retained_bytes(two), peak)
  assert_eq(
    @execution.execution_capacity_execution_bytes(one),
    @execution.execution_capacity_execution_bytes(
      quote([1200], { ..read_quote_limits(), max_bytes: 200001, }).unwrap(),
    ),
  )
  assert_true(quote([], read_quote_limits()) is None)
  assert_true(quote([-1], read_quote_limits()) is None)
  assert_true(
    quote([response_limits().max_bytes + 1], read_quote_limits()) is None,
  )
}

///|
test "Snowflake real metadata description and common declaration retain provider originals" {
  let original = metadata_response(hero_rows())
  let description = project_table_description(target(), original, [], limits()).unwrap()
  let projection = prepare_read_projection(
    description,
    ["ACCOUNT_ID", "ACTIVE_USERS", "TREND"],
    limits(),
  ).unwrap()
  assert_true(read_projection_matches_description(projection, description))
  let declaration = generate_read_declaration(
    projection,
    "usage",
    "snowflake",
    "snowflake/0.1",
    read_quote_limits(),
  ).unwrap()
  assert_eq(declaration.views[0].fields, ["ACCOUNT_ID", "ACTIVE_USERS", "TREND"])
}
