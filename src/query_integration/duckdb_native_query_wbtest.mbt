///|
fn native_compile_limits() -> @duckdb.NativeQueryLimits {
  {
    max_entries: 100,
    max_sql_bytes: 10000,
    expressions: {
      max_nodes: 1000,
      max_work: 10000,
      max_depth: 100,
      max_literal_nodes: 1000,
      max_literal_text_bytes: 10000,
    },
  }
}

///|
test "fixed boolean input compiles equality without numeric coercion" {
  let schema = @schema.from_fields(
    [
      (
        @schema.Unqualified("enabled"),
        @value_contract.primitive(@value_contract.BooleanType, nullable=true),
      ),
    ],
    max_fields=1,
    max_name_bytes=100,
  ).unwrap()
  let pipeline = @pipeline.check(
    input_cursor(
      "[{\"filter\":\"enabled = false\"},{\"select\":[\"enabled\"]}]",
    ),
    [("fixed", schema)],
    None,
    None,
    {
      max_steps: 2,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let owner = @lower.bind_parameters(
    @lower.prepare(pipeline, {
      max_nodes: 100,
      max_references: 100,
      max_work: 10000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let query = @duckdb.compile_native_filter_select(
    owner,
    "main",
    "owned_input",
    native_compile_limits(),
  ).unwrap()
  assert_eq(
    @duckdb.native_query_sql(query),
    "SELECT \"enabled\" AS \"enabled\" FROM \"main\".\"owned_input\" WHERE \"enabled\" = ?",
  )
  assert_eq(
    native_parameter_wire(query),
    "{\"type\":{\"id\":\"BOOLEAN\"},\"value\":false}",
  )
  assert_true(
    @duckdb.prepare_native_root_guard(query, 4) is Err(UnsupportedCeiling),
  )
  assert_eq(
    @duckdb.native_root_guard_bound(
      @duckdb.prepare_native_root_guard(query, 5).unwrap(),
    ),
    5,
  )
}

///|
fn native_parameter_wire(query : @duckdb.NativeQuery) -> String raise {
  let output = @encode.writer(1000, 20, 4)
  @duckdb.emit_physical_parameter(@duckdb.native_query_parameter(query), output)
  @encode.finish(output)
}

///|
test "DuckDB SQL consumes owned filter select and bound values without source SQL" {
  let (_, owner) = query_sequence_fixture()
  let compiled = @duckdb.compile_native_filter_select(
    owner,
    "main",
    "input",
    native_compile_limits(),
  ).unwrap()
  assert_true(physical_equal(@duckdb.native_query_owner(compiled), owner))
  assert_eq(
    @duckdb.native_query_sql(compiled),
    "SELECT \"id\" AS \"id\" FROM \"main\".\"input\" WHERE CAST(\"id\" AS DOUBLE) > ?",
  )
  assert_eq(
    native_parameter_wire(compiled),
    "{\"type\":{\"id\":\"DOUBLE\"},\"value\":\"3ff0000000000000\"}",
  )
  let (_, other) = query_sequence_fixture(supplied="{\"minimum\":2}")
  let changed = @duckdb.compile_native_filter_select(
    other,
    "main",
    "input",
    native_compile_limits(),
  ).unwrap()
  assert_false(physical_equal(@duckdb.native_query_owner(changed), owner))
  assert_eq(
    @duckdb.native_query_sql(changed),
    @duckdb.native_query_sql(compiled),
  )
  assert_eq(
    native_parameter_wire(changed),
    "{\"type\":{\"id\":\"DOUBLE\"},\"value\":\"4000000000000000\"}",
  )
}

///|
test "DuckDB identifiers are quoted and SQL construction is bounded exactly" {
  let (_, owner) = query_sequence_fixture()
  let compiled = @duckdb.compile_native_filter_select(
    owner,
    "odd\"schema",
    "t; DROP TABLE x--",
    native_compile_limits(),
  ).unwrap()
  let expected = "SELECT \"id\" AS \"id\" FROM \"odd\"\"schema\".\"t; DROP TABLE x--\" WHERE CAST(\"id\" AS DOUBLE) > ?"
  assert_eq(@duckdb.native_query_sql(compiled), expected)
  assert_true(
    @duckdb.compile_native_filter_select(
      owner,
      "odd\"schema",
      "t; DROP TABLE x--",
      { ..native_compile_limits(), max_sql_bytes: expected.length(), },
    )
    is Ok(_),
  )
  assert_true(
    @duckdb.compile_native_filter_select(
      owner,
      "odd\"schema",
      "t; DROP TABLE x--",
      { ..native_compile_limits(), max_sql_bytes: expected.length() - 1, },
    )
    is Err(Limit),
  )
  assert_true(
    @duckdb.compile_native_filter_select(
      owner,
      "main",
      "bad\u0000name",
      native_compile_limits(),
    )
    is Err(InvalidIdentifier),
  )
  assert_true(
    @duckdb.compile_native_filter_select(
      owner,
      "",
      "input",
      native_compile_limits(),
    )
    is Err(InvalidIdentifier),
  )
}

///|
test "unsupported expressions remain eligible only for separately offered local residual" {
  for
    filter in [
      "id + 1 > 2", "id > id", "id > 1 AND id < 3", "if(id > 0, true, false)",
    ] {
    let (_, owner) = query_sequence_fixture(filter~)
    assert_true(
      @duckdb.check_fixed_compute_static(
        owner,
        ["owned_input"],
        native_compile_limits(),
      )
      is Err(UnsupportedPredicate),
    )
    assert_true(
      @duckdb.compile_native_filter_select(
        owner,
        "main",
        "input",
        native_compile_limits(),
      )
      is Err(UnsupportedPredicate),
    )
  }
  let (_, longer) = query_sequence_fixture(extra=",{\"select\":[\"id\"]}")
  assert_true(
    @duckdb.compile_native_filter_select(
      longer,
      "main",
      "input",
      native_compile_limits(),
    )
    is Err(UnsupportedShape),
  )
  let (_, owner) = query_sequence_fixture(
    parameters="{\"minimum\":{\"type\":\"number\",\"nullable\":true}}",
    supplied="{\"minimum\":null}",
  )
  let compiled = @duckdb.compile_native_filter_select(
    owner,
    "main",
    "input",
    native_compile_limits(),
  ).unwrap()
  assert_eq(
    native_parameter_wire(compiled),
    "{\"type\":{\"id\":\"DOUBLE\"},\"value\":null}",
  )
}
