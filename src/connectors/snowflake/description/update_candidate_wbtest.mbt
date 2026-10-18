///|
fn update_limits() -> UpdateCandidateLimits {
  {
    max_fields: 32,
    max_comparison_work: 100000,
    max_value_nodes: 128,
    max_value_text_bytes: 4096,
    max_value_depth: 8,
    max_statement_bytes: 8192,
    max_body_bytes: 8192,
    max_body_nodes: 256,
  }
}

///|
fn write_value(
  description : TableDescription,
  index : Int,
  value : @admitted.Value,
) -> @admitted.CheckedValue {
  @admitted.recheck_runtime_value(
    value,
    description_column_contract(description, index).unwrap(),
    { max_nodes: 64, max_depth: 8, max_text_bytes: 4096, },
  ).unwrap()
}

///|
fn update_before(
  description : TableDescription,
) -> Array[(String, @admitted.CheckedValue)] {
  [
    (
      "ACCOUNT_ID",
      write_value(description, 0, @admitted.text_value("a1", 4096).unwrap()),
    ),
    (
      "ACTIVE_USERS",
      write_value(
        description,
        1,
        @admitted.decimal_from_coefficient(
          "99999999999999999999999999999999999999", 38, 0,
        ).unwrap(),
      ),
    ),
    ("TREND", write_value(description, 2, @admitted.null_value())),
  ]
}

///|
test "UPDATE candidate keeps full key cardinality separate from the complete before image" {
  let original = description()
  let value = prepare_update_candidate(
    original,
    "ACCOUNT_ID",
    write_value(original, 0, @admitted.text_value("a1", 4096).unwrap()),
    update_before(original),
    [
      (
        "TREND",
        write_value(original, 2, @admitted.text_value("up", 4096).unwrap()),
      ),
    ],
    update_limits(),
  ).unwrap()
  assert_eq(
    update_candidate_statement(value),
    "UPDATE \"PRODUCT\".\"USAGE\".\"USAGE_30D\" AS \"ACTQL_TARGET\" SET \"TREND\" = ? WHERE TO_BINARY(\"ACTQL_TARGET\".\"ACCOUNT_ID\", 'UTF-8') IS NOT DISTINCT FROM TO_BINARY(?, 'UTF-8') AND (SELECT COUNT(*) FROM \"PRODUCT\".\"USAGE\".\"USAGE_30D\" AS \"ACTQL_KEYS\" WHERE TO_BINARY(\"ACTQL_KEYS\".\"ACCOUNT_ID\", 'UTF-8') IS NOT DISTINCT FROM TO_BINARY(?, 'UTF-8')) = 1 AND TO_BINARY(\"ACTQL_TARGET\".\"ACCOUNT_ID\", 'UTF-8') IS NOT DISTINCT FROM TO_BINARY(?, 'UTF-8') AND \"ACTQL_TARGET\".\"ACTIVE_USERS\" IS NOT DISTINCT FROM TO_DECIMAL(?, 38, 0) AND TO_BINARY(\"ACTQL_TARGET\".\"TREND\", 'UTF-8') IS NOT DISTINCT FROM TO_BINARY(NULL, 'UTF-8')",
  )
  assert_eq(
    update_candidate_bindings(value),
    "{\"1\":{\"type\":\"TEXT\",\"value\":\"up\"},\"2\":{\"type\":\"TEXT\",\"value\":\"a1\"},\"3\":{\"type\":\"TEXT\",\"value\":\"a1\"},\"4\":{\"type\":\"TEXT\",\"value\":\"a1\"},\"5\":{\"type\":\"TEXT\",\"value\":\"99999999999999999999999999999999999999\"}}",
  )
  assert_true(update_candidate_matches_description(value, original))
  assert_false(update_candidate_matches_description(value, description()))
}

///|
test "UPDATE values never interpolate SQL syntax or collapse SQL NULL into text" {
  let original = description()
  let injected = "x' ; DELETE FROM accounts; -- é😀"
  let value = prepare_update_candidate(
    original,
    "ACCOUNT_ID",
    update_before(original)[0].1,
    update_before(original),
    [
      (
        "TREND",
        write_value(original, 2, @admitted.text_value(injected, 4096).unwrap()),
      ),
    ],
    update_limits(),
  ).unwrap()
  assert_false(update_candidate_statement(value).contains(injected))
  assert_true(update_candidate_bindings(value).contains(injected))
  assert_false(update_candidate_bindings(value).contains("\"value\":null"))
}

///|
test "UPDATE rechecks original decimal precision and scale without float or rounding" {
  let rows = [
    metadata_row("K", 1, "TEXT"),
    metadata_row("VALUE", 2, "NUMBER", precision=Some(38), scale=Some(2)),
    metadata_row("FLAG", 3, "BOOLEAN"),
  ]
  let original = project_table_description(
    target(),
    metadata_response(rows),
    [],
    limits(),
  ).unwrap()
  let key = write_value(original, 0, @admitted.text_value("key", 4096).unwrap())
  let precise = write_value(
    original,
    1,
    @admitted.decimal_from_coefficient("12345", 38, 2).unwrap(),
  )
  let flag = write_value(original, 2, @admitted.boolean_value(true))
  let before = [("K", key), ("VALUE", precise), ("FLAG", flag)]
  let value = prepare_update_candidate(
    original,
    "K",
    key,
    before,
    [("VALUE", precise), ("FLAG", flag)],
    update_limits(),
  ).unwrap()
  assert_true(
    update_candidate_statement(value).contains(
      "\"VALUE\" = TO_DECIMAL(?, 38, 2)",
    ),
  )
  assert_true(update_candidate_bindings(value).contains("\"value\":\"123.45\""))
  assert_true(
    update_candidate_bindings(value).contains(
      "\"type\":\"BOOLEAN\",\"value\":\"true\"",
    ),
  )
  // A value admitted by a different Contract is not assumed to fit this field.
  let wrong = @admitted.checked_text_value(
    "123.456",
    @contract.primitive(@contract.StringType, nullable=false),
  ).unwrap()
  assert_true(
    prepare_update_candidate(
      original,
      "K",
      key,
      before,
      [("VALUE", wrong)],
      update_limits(),
    )
    is Err(InvalidValue("VALUE")),
  )
}

///|
test "UPDATE refuses incomplete duplicate unknown and mismatched original key inputs" {
  let original = description()
  let before = update_before(original)
  let changes = [
    (
      "TREND",
      write_value(original, 2, @admitted.text_value("up", 4096).unwrap()),
    ),
  ]
  assert_true(
    prepare_update_candidate(
      original,
      "ACCOUNT_ID",
      before[0].1,
      before[:2].to_owned(),
      changes,
      update_limits(),
    )
    is Err(IncompleteBeforeImage),
  )
  assert_true(
    prepare_update_candidate(
      original,
      "ACCOUNT_ID",
      before[0].1,
      [before[0], before[0], before[2]],
      changes,
      update_limits(),
    )
    is Err(DuplicateField("ACCOUNT_ID")),
  )
  assert_true(
    prepare_update_candidate(
      original,
      "ACCOUNT_ID",
      before[0].1,
      before,
      [changes[0], changes[0]],
      update_limits(),
    )
    is Err(DuplicateField("TREND")),
  )
  assert_true(
    prepare_update_candidate(
      original,
      "ACCOUNT_ID",
      before[0].1,
      before,
      [("absent", changes[0].1)],
      update_limits(),
    )
    is Err(UnknownField("absent")),
  )
  assert_true(
    prepare_update_candidate(
      original,
      "ACCOUNT_ID",
      write_value(original, 0, @admitted.text_value("other", 4096).unwrap()),
      before,
      changes,
      update_limits(),
    )
    is Err(DifferentBeforeImageKey),
  )
  assert_true(
    prepare_update_candidate(
      original,
      "ACCOUNT_ID",
      before[0].1,
      before,
      [],
      update_limits(),
    )
    is Err(EmptyUpdate),
  )
}

///|
test "UPDATE bounds comparison admission statement and binding output independently" {
  let original = description()
  let before = update_before(original)
  let changes = [
    (
      "TREND",
      write_value(original, 2, @admitted.text_value("up", 4096).unwrap()),
    ),
  ]
  let normal = update_limits()
  for
    small in [
      { ..normal, max_comparison_work: 1, },
      { ..normal, max_value_nodes: 1, },
      { ..normal, max_value_text_bytes: 1, },
      { ..normal, max_statement_bytes: 1, },
      { ..normal, max_body_bytes: 1, },
      { ..normal, max_body_nodes: 1, },
    ] {
    assert_true(
      prepare_update_candidate(
        original,
        "ACCOUNT_ID",
        before[0].1,
        before,
        changes,
        small,
      )
      is Err(_),
    )
  }
  assert_true(
    prepare_update_candidate(
      original,
      "ACCOUNT_ID",
      before[0].1,
      before,
      changes,
      { ..normal, max_fields: 0, },
    )
    is Err(InvalidLimits),
  )
}

///|
test "UPDATE JSON values use Common payload encoding and explicit provider JSON parsing" {
  let rows = [metadata_row("K", 1, "TEXT"), metadata_row("J", 2, "VARIANT")]
  let original = project_table_description(
    target(),
    metadata_response(rows, total=2, partition_counts=[2]),
    [],
    limits(),
  ).unwrap()
  let key = write_value(original, 0, @admitted.text_value("key", 4096).unwrap())
  let json = write_value(
    original,
    1,
    @admitted.recheck_json_payload_usage(
      @admitted.text_value("payload", 4096).unwrap(),
      { max_nodes: 8, max_depth: 4, max_text_bytes: 4096, },
    ).unwrap().0.value,
  )
  let candidate = prepare_update_candidate(
    original,
    "K",
    key,
    [("K", key), ("J", json)],
    [("J", json)],
    update_limits(),
  ).unwrap()
  assert_true(
    update_candidate_statement(candidate).contains("SET \"J\" = PARSE_JSON(?)"),
  )
  assert_true(
    update_candidate_bindings(candidate).contains(
      "\"value\":\"\\\"payload\\\"\"",
    ),
  )
  assert_true(
    update_candidate_assignments(candidate)[0].1.value is @admitted.JsonData(_),
  )
}

///|
test "UPDATE quoted identifiers preserve exact Unicode and doubled quotes" {
  let database = "D\""
  let schema = "S😀"
  let table = "T\"; DELETE FROM secret; --"
  let rows = [
    metadata_row("K\"", 1, "TEXT", database~, schema~, table~),
    metadata_row("V😀", 2, "TEXT", database~, schema~, table~),
  ]
  let original = project_table_description(
    table_target(database, schema, table, 4096).unwrap(),
    metadata_response(rows, total=2, partition_counts=[2]),
    [],
    limits(),
  ).unwrap()
  let key = write_value(original, 0, @admitted.text_value("key", 4096).unwrap())
  let value = write_value(
    original,
    1,
    @admitted.text_value("e\u{0301}", 4096).unwrap(),
  )
  let candidate = prepare_update_candidate(
    original,
    "K\"",
    key,
    [("K\"", key), ("V😀", value)],
    [("V😀", value)],
    update_limits(),
  ).unwrap()
  assert_true(
    update_candidate_statement(candidate).has_prefix(
      "UPDATE \"D\"\"\".\"S😀\".\"T\"\"; DELETE FROM secret; --\" AS ",
    ),
  )
  assert_true(
    update_candidate_statement(candidate).contains(
      "TO_BINARY(\"ACTQL_KEYS\".\"K\"\"\", 'UTF-8')",
    ),
  )
  assert_true(update_candidate_bindings(candidate).contains("e\u{0301}"))
  assert_false(update_candidate_bindings(candidate).contains("é"))
}

///|
test "UPDATE scalar character limits do not count UTF16 units or normalize text" {
  let rows = [
    metadata_row("K", 1, "TEXT"),
    metadata_row("V", 2, "TEXT", length=Some(1)),
  ]
  let original = project_table_description(
    target(),
    metadata_response(rows, total=2, partition_counts=[2]),
    [],
    limits(),
  ).unwrap()
  let key = write_value(original, 0, @admitted.text_value("key", 4096).unwrap())
  let emoji = write_value(
    original,
    1,
    @admitted.text_value("😀", 4096).unwrap(),
  )
  let before = [("K", key), ("V", emoji)]
  assert_true(
    prepare_update_candidate(
      original,
      "K",
      key,
      before,
      [("V", emoji)],
      update_limits(),
    )
    is Ok(_),
  )
  let separate = write_value(
    original,
    1,
    @admitted.text_value("e\u{0301}", 4096).unwrap(),
  )
  assert_true(
    prepare_update_candidate(
      original,
      "K",
      key,
      before,
      [("V", separate)],
      update_limits(),
    )
    is Err(InvalidValue("V")),
  )
}

///|
test "UPDATE parameter text does not consume the independent statement byte bound" {
  let rows = [
    metadata_row("K", 1, "TEXT"),
    metadata_row("V", 2, "TEXT", length=Some(6000)),
  ]
  let original = project_table_description(
    target(),
    metadata_response(rows, total=2, partition_counts=[2]),
    [],
    limits(),
  ).unwrap()
  let key = write_value(original, 0, @admitted.text_value("key", 4096).unwrap())
  let old = write_value(original, 1, @admitted.text_value("old", 4096).unwrap())
  let large = "x".repeat(5000)
  let changed = @admitted.checked_text_value(
    large,
    description_column_contract(original, 1).unwrap(),
  ).unwrap()
  let bounded = {
    ..update_limits(),
    max_value_text_bytes: 16384,
    max_statement_bytes: 1024,
    max_body_bytes: 16384,
  }
  let result = prepare_update_candidate(
    original,
    "K",
    key,
    [("K", key), ("V", old)],
    [("V", changed)],
    bounded,
  ).unwrap()
  assert_true(update_candidate_statement(result).length() < 1024)
  assert_true(update_candidate_bindings(result).contains(large))
}

///|
test "UPDATE bindings above nine retain exact ordinal placeholder correspondence" {
  let names = ["K", "A", "B", "C"]
  let rows = names.mapi((index, name) => metadata_row(name, index + 1, "TEXT"))
  let original = project_table_description(
    target(),
    metadata_response(rows, total=4, partition_counts=[4]),
    [],
    limits(),
  ).unwrap()
  let entries = [
    ("K", write_value(original, 0, @admitted.text_value("k", 4096).unwrap())),
    ("A", write_value(original, 1, @admitted.text_value("a", 4096).unwrap())),
    ("B", write_value(original, 2, @admitted.text_value("b", 4096).unwrap())),
    ("C", write_value(original, 3, @admitted.text_value("c", 4096).unwrap())),
  ]
  let value = prepare_update_candidate(
    original,
    "K",
    entries[0].1,
    entries,
    entries,
    update_limits(),
  ).unwrap()
  assert_eq(
    update_candidate_bindings(value),
    "{\"1\":{\"type\":\"TEXT\",\"value\":\"k\"},\"2\":{\"type\":\"TEXT\",\"value\":\"a\"},\"3\":{\"type\":\"TEXT\",\"value\":\"b\"},\"4\":{\"type\":\"TEXT\",\"value\":\"c\"},\"5\":{\"type\":\"TEXT\",\"value\":\"k\"},\"6\":{\"type\":\"TEXT\",\"value\":\"k\"},\"7\":{\"type\":\"TEXT\",\"value\":\"k\"},\"8\":{\"type\":\"TEXT\",\"value\":\"a\"},\"9\":{\"type\":\"TEXT\",\"value\":\"b\"},\"10\":{\"type\":\"TEXT\",\"value\":\"c\"}}",
  )
}

///|
test "UPDATE retains original checked values and detaches caller collections" {
  let original = description()
  let before = update_before(original)
  let changes = [
    (
      "TREND",
      write_value(original, 2, @admitted.text_value("up", 4096).unwrap()),
    ),
  ]
  let candidate = prepare_update_candidate(
    original,
    "ACCOUNT_ID",
    before[0].1,
    before,
    changes,
    update_limits(),
  ).unwrap()
  let saved = update_candidate_statement(candidate)
  changes.clear()
  before.clear()
  assert_eq(update_candidate_before_image(candidate).length(), 3)
  let projected = update_candidate_assignments(candidate)
  assert_eq(projected[0].0, "TREND")
  assert_true(
    physical_equal(
      projected[0].1.contract,
      description_column_contract(original, 2).unwrap(),
    ),
  )
  projected.clear()
  assert_eq(update_candidate_assignments(candidate).length(), 1)
  assert_eq(update_candidate_key(candidate).0, "ACCOUNT_ID")
  assert_eq(update_candidate_statement(candidate), saved)
}

///|
test "UPDATE SQL NULL and typed JSON null remain different original values" {
  let rows = [
    metadata_row("K", 1, "TEXT"),
    metadata_row("J", 2, "VARIANT", nullable=true),
  ]
  let original = project_table_description(
    target(),
    metadata_response(rows, total=2, partition_counts=[2]),
    [],
    limits(),
  ).unwrap()
  let key = write_value(original, 0, @admitted.text_value("key", 4096).unwrap())
  let sql_null = write_value(original, 1, @admitted.null_value())
  let json_null = write_value(
    original,
    1,
    @admitted.recheck_json_payload_usage(@admitted.null_value(), {
      max_nodes: 8,
      max_depth: 4,
      max_text_bytes: 4096,
    }).unwrap().0.value,
  )
  let before = [("K", key), ("J", sql_null)]
  let candidate = prepare_update_candidate(
    original,
    "K",
    key,
    before,
    [("J", sql_null)],
    update_limits(),
  ).unwrap()
  assert_true(
    update_candidate_statement(candidate).contains("SET \"J\" = NULL"),
  )
  let variant_null = prepare_update_candidate(
    original,
    "K",
    key,
    before,
    [("J", json_null)],
    update_limits(),
  ).unwrap()
  assert_true(
    update_candidate_statement(variant_null).contains(
      "SET \"J\" = PARSE_JSON(?)",
    ),
  )
  assert_true(
    update_candidate_bindings(variant_null).contains("\"value\":\"null\""),
  )
  assert_false(
    update_candidate_statement(variant_null).contains("SET \"J\" = NULL"),
  )
}

///|
test "UPDATE native Object and Array cannot coerce a JSON scalar or JSON null" {
  let rows = [
    metadata_row("K", 1, "TEXT"),
    metadata_row("O", 2, "OBJECT"),
    metadata_row("A", 3, "ARRAY"),
  ]
  let original = project_table_description(
    target(),
    metadata_response(rows),
    [],
    limits(),
  ).unwrap()
  let key = write_value(original, 0, @admitted.text_value("key", 4096).unwrap())
  let bounds : @admitted.Limits = {
    max_nodes: 64,
    max_depth: 8,
    max_text_bytes: 4096,
  }
  let object = write_value(
    original,
    1,
    @admitted.admit_json_literal(
      "{\"$json\":null,\"x\":[true,\"é😀\"]}", bounds,
    ).unwrap().0.value,
  )
  let array = write_value(
    original,
    2,
    @admitted.admit_json_literal("[null,1,\"x\"]", bounds).unwrap().0.value,
  )
  let before = [("K", key), ("O", object), ("A", array)]
  let candidate = prepare_update_candidate(
    original,
    "K",
    key,
    before,
    [("O", object), ("A", array)],
    update_limits(),
  ).unwrap()
  assert_true(
    update_candidate_statement(candidate).contains(
      "\"O\" = TO_OBJECT(PARSE_JSON(?))",
    ),
  )
  assert_true(
    update_candidate_statement(candidate).contains(
      "\"A\" = TO_ARRAY(PARSE_JSON(?))",
    ),
  )
  assert_true(
    update_candidate_bindings(candidate).contains("\\\"$json\\\":null"),
  )
  for wire in ["null", "\"scalar\"", "1", "true", "[]"] {
    let wrong = write_value(
      original,
      1,
      @admitted.admit_json_literal(wire, bounds).unwrap().0.value,
    )
    assert_true(
      prepare_update_candidate(
        original,
        "K",
        key,
        before,
        [("O", wrong)],
        update_limits(),
      )
      is Err(InvalidValue("O")),
    )
  }
  for wire in ["null", "\"scalar\"", "1", "true", "{}"] {
    let wrong = write_value(
      original,
      2,
      @admitted.admit_json_literal(wire, bounds).unwrap().0.value,
    )
    assert_true(
      prepare_update_candidate(
        original,
        "K",
        key,
        before,
        [("A", wrong)],
        update_limits(),
      )
      is Err(InvalidValue("A")),
    )
  }
}

///|
test "UPDATE finite FLOAT values use REAL bindings without Boolean or decimal coercion" {
  let rows = [metadata_row("K", 1, "TEXT"), metadata_row("F", 2, "FLOAT")]
  let original = project_table_description(
    target(),
    metadata_response(rows, total=2, partition_counts=[2]),
    [],
    limits(),
  ).unwrap()
  let key = write_value(original, 0, @admitted.text_value("key", 4096).unwrap())
  let finite = write_value(original, 1, @admitted.number_value(1.25).unwrap())
  let candidate = prepare_update_candidate(
    original,
    "K",
    key,
    [("K", key), ("F", finite)],
    [("F", finite)],
    update_limits(),
  ).unwrap()
  assert_true(
    update_candidate_bindings(candidate).contains(
      "\"type\":\"REAL\",\"value\":\"1.25\"",
    ),
  )
  assert_false(update_candidate_statement(candidate).contains("TO_DECIMAL"))
  assert_true(
    @admitted.checked_number_value(
      -0.0,
      description_column_contract(original, 1).unwrap(),
    )
    is None,
  )
  let boolean = @admitted.checked_boolean_value(
    true,
    @contract.primitive(@contract.BooleanType, nullable=false),
  ).unwrap()
  assert_true(
    prepare_update_candidate(
      original,
      "K",
      key,
      [("K", key), ("F", finite)],
      [("F", boolean)],
      update_limits(),
    )
    is Err(InvalidValue("F")),
  )
}
