///|
fn count_group_owner(
  typ : @value_contract.Contract,
  by : String,
  counts : String,
  name? : String = "k",
) -> @lower.BoundPrepared {
  let schema = @schema.from_fields(
    [(@schema.Unqualified(name), typ)],
    max_fields=1,
    max_name_bytes=1,
  ).unwrap()
  let pipeline = @pipeline.check(
    input_cursor(
      "[{\"group\":{\"by\":" + by + ",\"aggregates\":" + counts + "}}]",
    ),
    [("fixed", schema)],
    None,
    None,
    {
      max_steps: 1,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
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
}

///|
test "fixed count SQL uses owned checked keys and exact count without a fabricated predicate" {
  let owner = count_group_owner(
    @value_contract.primitive(@value_contract.NumberType, nullable=true),
    "[\"k\",\"k\"]",
    "{\"n\":{\"fn\":\"count\"},\"p\":{\"fn\":\"count\",\"field\":\"k\"}}",
  )
  let compiled = @duckdb.compile_fixed_count_group(
    owner,
    "main",
    "fixed",
    native_compile_limits(),
  ).unwrap()
  assert_true(physical_equal(@duckdb.fixed_count_group_owner(compiled), owner))
  let expected = "SELECT * FROM (SELECT __actql_source.\"k\" AS \"__actql_output_0\", CAST(COUNT(*) AS DOUBLE) AS \"__actql_output_1\", CAST(COUNT(__actql_source.\"k\") AS DOUBLE) AS \"__actql_output_2\" FROM \"main\".\"fixed\" AS __actql_source GROUP BY __actql_source.\"k\", __actql_source.\"k\") AS __actql_grouped ORDER BY \"__actql_grouped\".\"__actql_output_0\" ASC NULLS FIRST, \"__actql_grouped\".\"__actql_output_0\" ASC NULLS FIRST"
  assert_eq(@duckdb.fixed_count_group_sql(compiled), expected)
  assert_true(
    @duckdb.compile_fixed_count_group(owner, "main", "fixed", {
      ..native_compile_limits(),
      max_sql_bytes: expected.length(),
    })
    is Ok(_),
  )
  assert_true(
    @duckdb.compile_fixed_count_group(owner, "main", "fixed", {
      ..native_compile_limits(),
      max_sql_bytes: expected.length() - 1,
    })
    is Err(Limit),
  )
  assert_true(
    @duckdb.compile_fixed_count_group(
      owner,
      "main",
      "bad\u0000name",
      native_compile_limits(),
    )
    is Err(InvalidIdentifier),
  )
}

///|
test "global count SQL has no accidental keyed grouping or empty order clause" {
  let owner = count_group_owner(
    @value_contract.primitive(@value_contract.BooleanType, nullable=true),
    "[]",
    "{\"n\":{\"fn\":\"count\",\"field\":\"k\"}}",
  )
  let compiled = @duckdb.compile_fixed_count_group(
    owner,
    "main",
    "fixed",
    native_compile_limits(),
  ).unwrap()
  assert_eq(
    @duckdb.fixed_count_group_sql(compiled),
    "SELECT CAST(COUNT(__actql_source.\"k\") AS DOUBLE) AS \"__actql_output_0\" FROM \"main\".\"fixed\" AS __actql_source",
  )
  let unsupported = count_group_owner(
    @value_contract.primitive(@value_contract.NumberType, nullable=true),
    "[]",
    "{\"n\":{\"fn\":\"sum\",\"field\":\"k\"}}",
  )
  // General group lowering accepts sum. This count-only DuckDB adapter still
  // rejects that prepared kernel before execution.
  assert_true(
    @duckdb.compile_fixed_count_group(
      unsupported,
      "main",
      "fixed",
      native_compile_limits(),
    )
    is Err(UnsupportedShape),
  )
  let query = @duckdb.compile_fixed_query(
    owner,
    "main",
    "fixed",
    native_compile_limits(),
  ).unwrap()
  let resident = @duckdb.prepare_resident_query(query, "result", 10000).unwrap()
  assert_eq(
    @duckdb.resident_query_create_sql(resident),
    "CREATE TABLE \"result\" AS SELECT \"__actql_result\".\"__actql_output_0\" AS \"n\" FROM (SELECT CAST(COUNT(__actql_source.\"k\") AS DOUBLE) AS \"__actql_output_0\" FROM \"main\".\"fixed\" AS __actql_source) AS \"__actql_result\"",
  )
  assert_eq(
    @duckdb.resident_query_read_sql(resident),
    "SELECT \"n\" AS \"__actql_output_0\" FROM main.\"result\"",
  )
}

///|
test "fixed count_if SQL counts only true Boolean rows" {
  let owner = count_group_owner(
    @value_contract.primitive(@value_contract.BooleanType, nullable=true),
    "[]",
    "{\"hits\":{\"fn\":\"count_if\",\"field\":\"k\"}}",
  )
  let compiled = @duckdb.compile_fixed_count_group(
    owner,
    "main",
    "fixed",
    native_compile_limits(),
  ).unwrap()
  assert_eq(
    @duckdb.fixed_count_group_sql(compiled),
    "SELECT CAST(COUNT(CASE WHEN __actql_source.\"k\" THEN 1 END) AS DOUBLE) AS \"__actql_output_0\" FROM \"main\".\"fixed\" AS __actql_source",
  )
  let writer = @encode.writer(10000, 100, 10)
  @encode.begin_object(writer)
  @encode.key(writer, "sql")
  @encode.string_value(writer, @duckdb.fixed_count_group_sql(compiled))
  @encode.end_object(writer)
  println("ACTQL_COUNT_IF " + @encode.finish(writer))
}

///|
test "emit owned group SQL for real DuckDB conformance without deriving expected results" {
  for
    (name, typ) in [
      (
        "number",
        @value_contract.primitive(@value_contract.NumberType, nullable=true),
      ),
      (
        "text",
        @value_contract.primitive(@value_contract.StringType, nullable=true),
      ),
    ] {
    let owner = count_group_owner(
      typ, "[\"k\"]", "{\"n\":{\"fn\":\"count\"},\"p\":{\"fn\":\"count\",\"field\":\"k\"}}",
    )
    let query = @duckdb.compile_fixed_query(
      owner,
      "main",
      "fixed",
      native_compile_limits(),
    ).unwrap()
    assert_true(physical_equal(@duckdb.fixed_query_owner(query), owner))
    assert_eq(@duckdb.fixed_query_target(query), @pipeline.Step(0))
    assert_eq(@duckdb.fixed_query_parameter_count(query), 0)
    assert_true(@duckdb.fixed_query_parameter(query, 0) is None)
    let writer = @encode.writer(10000, 100, 10)
    @encode.begin_object(writer)
    @encode.key(writer, "name")
    @encode.string_value(writer, name)
    @encode.key(writer, "sql")
    @encode.string_value(writer, @duckdb.fixed_query_sql(query))
    @encode.end_object(writer)
    println("ACTQL_COUNT_GROUP " + @encode.finish(writer))
  }
}

///|
test "case-distinct aggregate aliases are fresh eligible but not resident names" {
  for (key, aggregate) in [("K", "k"), ("k", "K")] {
    let owner = count_group_owner(
      @value_contract.primitive(@value_contract.NumberType, nullable=true),
      "[\"" + key + "\"]",
      "{\"" + aggregate + "\":{\"fn\":\"count\"}}",
      name=key,
    )
    let query = @duckdb.compile_fixed_query(
      owner,
      "main",
      "fixed",
      native_compile_limits(),
    ).unwrap()
    assert_true(
      @duckdb.check_fixed_compute_static(
        owner,
        ["fixed"],
        native_compile_limits(),
      )
      is Ok(_),
    )
    assert_true(
      @duckdb.check_resident_output_static(owner, Step(0))
      is Err(UnsupportedField),
    )
    assert_true(
      @duckdb.prepare_resident_query(query, "result", 10000)
      is Err(UnsupportedField),
    )
  }
}
