///|
fn test_limits() -> ResponseLimits {
  {
    max_bytes: 8192,
    max_nodes: 1000,
    max_depth: 16,
    max_columns: 8,
    max_name_units: 128,
    max_handle_units: 128,
    max_partitions: 4,
    max_rows: 4,
    max_total_rows: 8L,
  }
}

///|
fn test_body(
  columns : String,
  data : String,
  partitions? : String = "[{\"rowCount\":1}]",
  total? : String = "1",
) -> Bytes {
  @utf8.encode(
    "{\"statementHandle\":\"536fad38-b564-4dc5-9892-a4543504df6c\",\"sqlState\":\"00000\",\"resultSetMetaData\":{\"format\":\"jsonv2\",\"numRows\":" +
    total +
    ",\"rowType\":" +
    columns +
    ",\"partitionInfo\":" +
    partitions +
    "},\"data\":" +
    data +
    "}",
  )
}

///|
fn text_column() -> String {
  (
    #|[{"name":"ACCOUNT_ID","type":"text","nullable":false}]
  )
}

///|
fn fixed_column(precision : Int, scale : Int) -> String {
  "[{\"name\":\"ACTIVE_USERS\",\"type\":\"FIXED\",\"nullable\":false,\"precision\":" +
  precision.to_string() +
  ",\"scale\":" +
  scale.to_string() +
  "}]"
}

///|
test "hero usage rows preserve column order and exact decimal contract" {
  let columns =
    #|[{"name":"ACCOUNT_ID","type":"TEXT","nullable":false},{"name":"ACTIVE_USERS","type":"fixed","precision":12,"scale":0,"nullable":false},{"name":"TREND","type":"text","nullable":false}]
  let bytes = test_body(columns, "[[\"001A\",\"250\",\"down\"]]")
  let result = project_result_set(bytes, test_limits()).unwrap()
  assert_eq(result_set_column_count(result), 3)
  assert_eq(result_set_column_name(result, 0), Some("ACCOUNT_ID"))
  assert_eq(result_set_column_name(result, 2), Some("TREND"))
  assert_true(
    result_set_cell(result, 0, 0).unwrap().value is @admitted.Text("001A"),
  )
  assert_true(
    result_set_cell(result, 0, 1).unwrap().value is @admitted.Decimal(value) &&
    value.coefficient == "250" &&
    value.precision == 12 &&
    value.scale == 0,
  )
  assert_eq(result_set_response_sha256(result), @sha.hex(bytes))
}

///|
test "NUMBER38 is not rounded through binary64 or relabelled int64" {
  let result = project_result_set(
    test_body(
      fixed_column(38, 0),
      "[[\"99999999999999999999999999999999999999\"]]",
    ),
    test_limits(),
  ).unwrap()
  assert_true(
    result_set_cell(result, 0, 0).unwrap().value is @admitted.Decimal(value) &&
    value.coefficient == "99999999999999999999999999999999999999" &&
    value.precision == 38 &&
    value.scale == 0,
  )
}

///|
test "decimal normalization uses Common exact scale admission" {
  for spelling in ["1", "1.00", "1e0"] {
    let result = project_result_set(
      test_body(fixed_column(6, 2), "[[\"" + spelling + "\"]]"),
      test_limits(),
    ).unwrap()
    assert_true(
      result_set_cell(result, 0, 0).unwrap().value is @admitted.Decimal(value) &&
      value.coefficient == "100" &&
      value.scale == 2,
    )
  }
}

///|
test "decimal range and nonzero extra scale refuse without rounding" {
  assert_true(
    project_result_set(
      test_body(fixed_column(3, 2), "[[\"10.00\"]]"),
      test_limits(),
    )
    is Err(ValueOutOfRange("ACTIVE_USERS")),
  )
  assert_true(
    project_result_set(
      test_body(fixed_column(6, 2), "[[\"1.001\"]]"),
      test_limits(),
    )
    is Err(ValueBeyondScale("ACTIVE_USERS")),
  )
}

///|
test "SQL NULL is distinct from text null and VARIANT JSON null" {
  let columns =
    #|[{"name":"SQL_NULL","type":"text","nullable":true},{"name":"TEXT_NULL","type":"text","nullable":false},{"name":"JSON_NULL","type":"variant","nullable":false}]
  let result = project_result_set(
    test_body(columns, "[[null,\"null\",\"null\"]]"),
    test_limits(),
  ).unwrap()
  assert_true(result_set_cell(result, 0, 0).unwrap().value is @admitted.Null)
  assert_true(
    result_set_cell(result, 0, 1).unwrap().value is @admitted.Text("null"),
  )
  assert_true(
    result_set_cell(result, 0, 2).unwrap().value
    is @admitted.JsonData(@admitted.Null),
  )
}

///|
test "nonnullable NULL and omitted cells are refused separately" {
  assert_true(
    project_result_set(test_body(text_column(), "[[null]]"), test_limits())
    is Err(ValueAdmission("ACCOUNT_ID", _)),
  )
  assert_true(
    project_result_set(test_body(text_column(), "[[]]"), test_limits())
    is Err(WrongRowWidth),
  )
  assert_true(
    project_result_set(
      test_body(text_column(), "[[\"a\",\"b\"]]"),
      test_limits(),
    )
    is Err(WrongRowWidth),
  )
}

///|
test "SQL API numbers and booleans must retain their documented string transport" {
  assert_true(
    project_result_set(test_body(fixed_column(12, 0), "[[250]]"), test_limits())
    is Err(InvalidCell("ACTIVE_USERS")),
  )
  let column = "[{\"name\":\"FLAG\",\"type\":\"boolean\",\"nullable\":false}]"
  let result = project_result_set(
    test_body(column, "[[\"false\"]]"),
    test_limits(),
  ).unwrap()
  assert_true(
    result_set_cell(result, 0, 0).unwrap().value is @admitted.Boolean(false),
  )
  assert_true(
    project_result_set(test_body(column, "[[false]]"), test_limits())
    is Err(InvalidCell("FLAG")),
  )
  assert_true(
    project_result_set(test_body(column, "[[\"FALSE\"]]"), test_limits())
    is Err(InvalidCell("FLAG")),
  )
}

///|
test "finite float admission refuses Snowflake nonfinite spellings" {
  let column = "[{\"name\":\"N\",\"type\":\"real\",\"nullable\":false}]"
  let result = project_result_set(
    test_body(column, "[[\"1.25\"]]"),
    test_limits(),
  ).unwrap()
  assert_true(
    result_set_cell(result, 0, 0).unwrap().value is @admitted.Number(1.25),
  )
  for
    spelling in ["NaN", "inf", "Infinity", "-Infinity", "1e999", "true", "null"] {
    assert_true(
      project_result_set(
        test_body(column, "[[\"" + spelling + "\"]]"),
        test_limits(),
      )
      is Err(InvalidCell("N")),
    )
  }
}

///|
test "Unicode and line endings remain original data" {
  let result = project_result_set(
    test_body(text_column(), "[[\"😀é\\r\\n\"]]"),
    test_limits(),
  ).unwrap()
  assert_true(
    result_set_cell(result, 0, 0).unwrap().value
    is @admitted.Text("😀é\r\n"),
  )
}

///|
test "closed metadata invariants refuse unknown types nullability and duplicates" {
  assert_true(
    project_result_set(
      test_body("[{\"name\":\"A\",\"type\":\"text\"}]", "[[\"a\"]]"),
      test_limits(),
    )
    is Err(InvalidResponse),
  )
  assert_true(
    project_result_set(
      test_body(
        "[{\"name\":\"A\",\"type\":\"time\",\"nullable\":false}]", "[[\"0.0\"]]",
      ),
      test_limits(),
    )
    is Err(UnsupportedColumn("A", "time")),
  )
  let duplicate = "[{\"name\":\"A\",\"type\":\"text\",\"nullable\":false},{\"name\":\"A\",\"type\":\"text\",\"nullable\":false}]"
  assert_true(
    project_result_set(test_body(duplicate, "[[\"a\",\"b\"]]"), test_limits())
    is Err(DuplicateColumn("A")),
  )
  assert_true(
    project_result_set(
      test_body(fixed_column(39, 0), "[[\"1\"]]"),
      test_limits(),
    )
    is Err(InvalidColumn("ACTIVE_USERS")),
  )
}

///|
test "partition row counts must exactly cover total and actual first data" {
  assert_true(
    project_result_set(
      test_body(text_column(), "[[\"a\"]]", total="2"),
      test_limits(),
    )
    is Err(InvalidPartition),
  )
  assert_true(
    project_result_set(test_body(text_column(), "[]"), test_limits())
    is Err(InvalidPartition),
  )
  assert_true(
    project_result_set(
      test_body(
        text_column(),
        "[[\"a\"]]",
        partitions="[{\"rowCount\":2},{\"rowCount\":1}]",
        total="2",
      ),
      test_limits(),
    )
    is Err(InvalidPartition),
  )
}

///|
test "additional partition keeps nominal original and rejects schema replacement" {
  let original = project_result_set(
    test_body(
      text_column(),
      "[[\"a\"]]",
      partitions="[{\"rowCount\":1},{\"rowCount\":1}]",
      total="2",
    ),
    test_limits(),
  ).unwrap()
  let page = project_partition(
    @utf8.encode("{\"data\":[[\"b\"]]}"),
    original,
    1,
    test_limits(),
  ).unwrap()
  assert_true(partition_matches_original(page, original))
  assert_true(partition_cell(page, 0, 0).unwrap().value is @admitted.Text("b"))
  let foreign = project_result_set(
    test_body(text_column(), "[[\"a\"]]"),
    test_limits(),
  ).unwrap()
  assert_false(partition_matches_original(page, foreign))
  assert_true(
    project_partition(
      @utf8.encode("{\"data\":[],\"resultSetMetaData\":{}}"),
      original,
      1,
      test_limits(),
    )
    is Err(InvalidResponse),
  )
  assert_true(
    project_partition(
      @utf8.encode("{\"data\":[[\"b\"]]}"),
      original,
      0,
      test_limits(),
    )
    is Err(InvalidPartition),
  )
}

///|
test "empty Result preserves its declared schema" {
  let result = project_result_set(
    test_body(text_column(), "[]", total="0", partitions="[{\"rowCount\":0}]"),
    test_limits(),
  ).unwrap()
  assert_eq(result_set_column_count(result), 1)
  assert_eq(result_set_row_count(result), 0)
  assert_eq(result_set_total_rows(result), 0L)
}

///|
test "caller bounds are never expanded by provider metadata" {
  let bytes = test_body(text_column(), "[[\"a\"]]")
  let limits = test_limits()
  assert_true(
    project_result_set(bytes, { ..limits, max_bytes: 1, })
    is Err(BudgetExceeded),
  )
  assert_true(
    project_result_set(bytes, { ..limits, max_rows: 0, }) is Err(BudgetExceeded),
  )
  assert_true(
    project_result_set(bytes, { ..limits, max_total_rows: 0L, })
    is Err(BudgetExceeded),
  )
  assert_true(
    project_result_set(bytes, { ..limits, max_nodes: 1, })
    is Err(BudgetExceeded),
  )
  assert_true(
    project_result_set(bytes, { ..limits, max_columns: 0, })
    is Err(InvalidLimits),
  )
}

///|
test "statement handle remains an opaque bounded identity" {
  let body = @utf8.decode(test_body(text_column(), "[[\"a\"]]")) catch {
    _ => abort("fixture UTF8")
  }
  let handle_body = body.replace_all(
    old="536fad38-b564-4dc5-9892-a4543504df6c",
    new="opaque-handle:1",
  )
  let result = project_result_set(@utf8.encode(handle_body), test_limits()).unwrap()
  assert_eq(result_set_handle(result), "opaque-handle:1")
  let limits = test_limits()
  assert_true(
    project_result_set(@utf8.encode(handle_body), {
      ..limits,
      max_handle_units: 2,
    })
    is Err(InvalidHandle),
  )
}

///|
test "JSON literal admission keeps nullable contract without collapsing its domain" {
  let columns = "[{\"name\":\"V\",\"type\":\"variant\",\"nullable\":true}]"
  let result = project_result_set(
    test_body(columns, "[[\"null\"]]"),
    test_limits(),
  ).unwrap()
  let value = result_set_cell(result, 0, 0).unwrap()
  assert_true(value.value is @admitted.JsonData(@admitted.Null))
  assert_true(@contract.contract_nullable(value.contract))
  let object_column = "[{\"name\":\"V\",\"type\":\"object\",\"nullable\":false}]"
  assert_true(
    project_result_set(test_body(object_column, "[[\"[]\"]]"), test_limits())
    is Err(InvalidCell("V")),
  )
}

///|
test "nested JSON limits remain capacity failures" {
  let columns = "[{\"name\":\"V\",\"type\":\"variant\",\"nullable\":false}]"
  let limits = test_limits()
  assert_true(
    project_result_set(test_body(columns, "[[\"[[[[[[[0]]]]]]]\"]]"), {
      ..limits,
      max_depth: 5,
    })
    is Err(BudgetExceeded),
  )
}

///|
test "expanded decimal holding shares one page value budget" {
  let fields = StringBuilder()
  let row = StringBuilder()
  fields.write_string("[")
  row.write_string("[")
  for index in 0..<8 {
    if index != 0 {
      fields.write_string(",")
      row.write_string(",")
    }
    fields.write_string(
      "{\"name\":\"N" +
      index.to_string() +
      "\",\"type\":\"fixed\",\"precision\":38,\"scale\":0,\"nullable\":false}",
    )
    row.write_string("\"1e37\"")
  }
  fields.write_string("]")
  row.write_string("]")
  let data = "[" +
    row.to_string() +
    "," +
    row.to_string() +
    "," +
    row.to_string() +
    "," +
    row.to_string() +
    "]"
  let bytes = test_body(
    fields.to_string(),
    data,
    partitions="[{\"rowCount\":4}]",
    total="4",
  )
  let limits = test_limits()
  assert_true(bytes.length() <= 1100)
  assert_true(
    project_result_set(bytes, { ..limits, max_bytes: 1100, })
    is Err(BudgetExceeded),
  )
}

///|
test "later partition observes tighter caller metadata limits" {
  let original = project_result_set(
    test_body(
      text_column(),
      "[[\"a\"]]",
      partitions="[{\"rowCount\":1},{\"rowCount\":1}]",
      total="2",
    ),
    test_limits(),
  ).unwrap()
  let bytes = @utf8.encode("{\"data\":[[\"b\"]]}")
  let limits = test_limits()
  for
    selected in [
      { ..limits, max_total_rows: 1L, },
      { ..limits, max_partitions: 1, },
      { ..limits, max_name_units: 1, },
      { ..limits, max_handle_units: 1, },
    ] {
    assert_true(
      project_partition(bytes, original, 1, selected) is Err(BudgetExceeded),
    )
  }
}
