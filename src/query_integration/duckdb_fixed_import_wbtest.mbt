///|
fn duckdb_captured_input(
  filter? : String = "id > 0",
) -> @execution.ProducerRead raise {
  duckdb_captured_input_lifetime(filter~).0
}

///|
fn duckdb_captured_input_lifetime(
  filter? : String = "id > 0",
) -> (@execution.ProducerRead, () -> Unit) raise {
  let (issuer, sequence) = query_issuer_fixture()
  let owner = @query.query_sequence_owner(sequence)
  let receiver = typed_receiver(
    owner,
    "[{\"filter\":\"" + filter + "\"},{\"select\":[\"id\"]}]",
  )
  let attempt = query_issuer_attempt(
    issuer,
    sequence,
    @planning.BroadWithResidual,
  )
  query_issuer_run(attempt)
  let records = @planning.issue_mock_query_records(
    attempt,
    query_material_limits(),
  ).unwrap()
  let observation = @planning.capture_mock_query(
    issuer,
    attempt,
    records,
    query_capture_limits(),
  ).unwrap()
  let bound = @planning.bind_captured_query_input(
    issuer, attempt, observation, receiver, 0, owner,
  ).unwrap()
  (
    @execution.prepare_producer_read(receiver, bound, 100, 1000).unwrap(),
    fn() { @planning.close_mock_query_issuer(issuer) },
  )
}

///|
test "completed capture prepares exact isolated Compute import without source access" {
  let input = duckdb_captured_input()
  let plan = @duckdb.prepare_fixed_import(input, "owned\"input", 1, 1000).unwrap()
  assert_true(physical_equal(@duckdb.fixed_import_input(plan), input))
  assert_eq(@duckdb.fixed_import_column_count(plan), 1)
  assert_eq(@execution.producer_read_row_count(input), 2)
  let create = "CREATE TEMP TABLE \"owned\"\"input\" (\"id\" DOUBLE NOT NULL)"
  let insert = "INSERT INTO \"owned\"\"input\" VALUES (?)"
  assert_eq(@duckdb.fixed_import_create_sql(plan), create)
  assert_eq(@duckdb.fixed_import_insert_sql(plan), insert)
  for (row, expected) in [(0, "4008000000000000"), (1, "4000000000000000")] {
    let parameter = @duckdb.fixed_import_parameter(plan, row, 0).unwrap()
    let writer = @encode.writer(1000, 20, 4)
    @duckdb.emit_physical_parameter(parameter, writer)
    assert_eq(
      @encode.finish(writer),
      "{\"type\":{\"id\":\"DOUBLE\"},\"value\":\"" + expected + "\"}",
    )
  }
  for (row, column) in [(-1, 0), (2, 0), (0, -1), (0, 1)] {
    assert_true(
      @duckdb.fixed_import_parameter(plan, row, column) is Err(OutOfRange),
    )
  }
  let bytes = create.length() + insert.length()
  assert_true(
    @duckdb.prepare_fixed_import(input, "owned\"input", 1, bytes) is Ok(_),
  )
  assert_true(
    @duckdb.prepare_fixed_import(input, "owned\"input", 1, bytes - 1)
    is Err(Limit),
  )
  assert_true(
    @duckdb.prepare_fixed_import(input, "input", 0, 1000) is Err(Limit),
  )
  assert_true(
    @duckdb.prepare_fixed_import(input, "bad\u0000name", 1, 1000)
    is Err(InvalidIdentifier),
  )
  // A failed physical preparation neither consumes nor invalidates the capture.
  assert_true(@duckdb.prepare_fixed_import(input, "retry", 1, 1000) is Ok(_))
  let query = @duckdb.compile_native_filter_select(
    @execution.producer_read_receiver(input),
    "main",
    "owned\"input",
    native_compile_limits(),
  ).unwrap()
  assert_eq(
    @duckdb.native_query_sql(query),
    "SELECT \"id\" AS \"id\" FROM \"main\".\"owned\"\"input\" WHERE CAST(\"id\" AS DOUBLE) > ?",
  )
}

///|
fn duckdb_fixed_values(
  source : String,
  steps? : String = "[{\"select\":[\"x\"]}]",
) -> @execution.ProducerRead raise {
  duckdb_fixed_values_storage(source, steps~).0
}

///|
fn duckdb_fixed_values_storage(
  source : String,
  steps? : String = "[{\"select\":[\"x\"]}]",
) -> (@execution.ProducerRead, @execution.ProducerStorage) raise {
  let pipeline = @pipeline.check(input_cursor(source), [], None, None, {
    max_steps: 10,
    max_work: 100000,
    max_text_bytes: 10000,
    max_nodes: 1000,
    max_tokens: 1000,
    max_depth: 100,
  }).unwrap()
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
  let complete = @execution.execute_generated_sequence(
    compute_test_sequence(owner),
    [],
    compute_test_limits(),
  ).unwrap()
  let receiver = typed_receiver(owner, steps, target=Step(0))
  let output = @execution.completed_output(complete, Step(0)).unwrap()
  let bound = @execution.bind_completed_input(receiver, 0, owner, output).unwrap()
  (
    @execution.prepare_producer_read(receiver, bound, 100, 1000).unwrap(),
    @execution.prepare_producer_storage(output, 100, 1000).unwrap(),
  )
}

///|
test "resident SQL uses exact producer storage and checked receiver projection" {
  let source = "[{\"values\":{\"schema\":{\"x\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"x\":3},{\"x\":3}]},\"as\":\"seed\"}]"
  let steps = "[{\"filter\":\"x > 1\"},{\"select\":[\"x\"]}]"
  let (input, storage) = duckdb_fixed_values_storage(source, steps~)
  let imported = @duckdb.prepare_resident_import(
    storage, "resident_x", 10, 1000,
  ).unwrap()
  assert_eq(
    @duckdb.resident_import_create_sql(imported),
    "CREATE TABLE \"resident_x\" (\"x\" DOUBLE NOT NULL)",
  )
  assert_eq(
    @duckdb.resident_import_receiver_sql(
      imported, input, "owned_input", 10, 1000,
    ).unwrap(),
    "CREATE TEMP VIEW \"owned_input\" AS SELECT \"x\" AS \"x\" FROM main.\"resident_x\"",
  )
  let foreign = duckdb_fixed_values(source, steps~)
  assert_true(
    @duckdb.resident_import_receiver_sql(
      imported, foreign, "owned_input", 10, 1000,
    )
    is Err(UnsupportedShape),
  )
  let query = @duckdb.compile_native_filter_select(
    @execution.producer_read_receiver(input),
    "main",
    "owned_input",
    native_compile_limits(),
  ).unwrap()
  let retained = @duckdb.prepare_resident_query(query, "resident_a", 1000).unwrap()
  assert_eq(
    @duckdb.resident_query_create_sql(retained),
    "CREATE TABLE \"resident_a\" AS SELECT \"x\" AS \"x\" FROM \"main\".\"owned_input\" WHERE CAST(\"x\" AS DOUBLE) > ?",
  )
  assert_eq(
    @duckdb.resident_query_read_sql(retained),
    "SELECT * FROM main.\"resident_a\"",
  )
  assert_eq(
    @duckdb.resident_query_drop_sql(retained),
    "DROP TABLE main.\"resident_a\"",
  )
  assert_true(
    @duckdb.prepare_resident_query(query, "owned_input", 1000)
    is Err(InvalidIdentifier),
  )
  assert_true(
    @duckdb.prepare_resident_query(query, "resident_a", 1) is Err(Limit),
  )
}

///|
test "fixed import preserves admitted scalar domains NULL and empty type eligibility" {
  for
    (contract, source_value, sql_type, physical_type, physical_value) in [
      (
        "{\"type\":\"string\",\"nullable\":true}", "\"日本語\"", "VARCHAR", "{\"id\":\"VARCHAR\"}",
        "\"日本語\"",
      ),
      (
        "{\"type\":\"boolean\",\"nullable\":true}", "false", "BOOLEAN", "{\"id\":\"BOOLEAN\"}",
        "false",
      ),
      (
        "{\"type\":\"number\",\"nullable\":true}", "9007199254740992", "DOUBLE",
        "{\"id\":\"DOUBLE\"}", "\"4340000000000000\"",
      ),
      (
        "{\"type\":\"decimal\",\"precision\":38,\"scale\":2,\"nullable\":true}",
        "\"999999999999999999999999999999999999.99\"", "DECIMAL(38,2)", "{\"id\":\"DECIMAL\",\"precision\":38,\"scale\":2}",
        "\"99999999999999999999999999999999999999\"",
      ),
      (
        "{\"type\":\"date\",\"nullable\":true}", "\"2000-02-29\"", "DATE", "{\"id\":\"DATE\"}",
        "\"11016\"",
      ),
      (
        "{\"type\":\"timestamp\",\"nullable\":true}", "\"1969-12-31T23:59:59.999Z\"",
        "TIMESTAMPTZ", "{\"id\":\"TIMESTAMP_TZ\"}", "\"-1000\"",
      ),
    ] {
    let prefix = "[{\"values\":{\"schema\":{\"x\":" + contract + "},\"rows\":"
    let input = duckdb_fixed_values(
      prefix + "[{\"x\":" + source_value + "},{\"x\":null}]},\"as\":\"seed\"}]",
    )
    let plan = @duckdb.prepare_fixed_import(input, "fixed", 1, 1000).unwrap()
    assert_eq(
      @duckdb.fixed_import_create_sql(plan),
      "CREATE TEMP TABLE \"fixed\" (\"x\" " + sql_type + ")",
    )
    for (row, expected) in [(0, physical_value), (1, "null")] {
      let writer = @encode.writer(1000, 20, 4)
      @duckdb.emit_physical_parameter(
        @duckdb.fixed_import_parameter(plan, row, 0).unwrap(),
        writer,
      )
      assert_eq(
        @encode.finish(writer),
        "{\"type\":" + physical_type + ",\"value\":" + expected + "}",
      )
    }
    let empty = duckdb_fixed_values(prefix + "[]},\"as\":\"seed\"}]")
    assert_eq(@execution.producer_read_row_count(empty), 0)
    assert_true(@duckdb.prepare_fixed_import(empty, "empty", 1, 1000) is Ok(_))
  }
}
