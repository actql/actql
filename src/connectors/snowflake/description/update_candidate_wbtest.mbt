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
fn update_before(description : TableDescription) -> Array[(String, @admitted.CheckedValue)] {
  [
    ("ACCOUNT_ID", write_value(description, 0, @admitted.text_value("a1", 4096).unwrap())),
    (
      "ACTIVE_USERS",
      write_value(description, 1, @admitted.decimal_from_coefficient(
        "99999999999999999999999999999999999999", 38, 0,
      ).unwrap()),
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
    [("TREND", write_value(original, 2, @admitted.text_value("up", 4096).unwrap()))],
    update_limits(),
  ).unwrap()
  assert_eq(
    update_candidate_statement(value),
    "UPDATE \"PRODUCT\".\"USAGE\".\"USAGE_30D\" AS \"ACTQL_TARGET\" SET \"TREND\" = ? WHERE \"ACTQL_TARGET\".\"ACCOUNT_ID\" IS NOT DISTINCT FROM ? AND (SELECT COUNT(*) FROM \"PRODUCT\".\"USAGE\".\"USAGE_30D\" AS \"ACTQL_KEYS\" WHERE \"ACTQL_KEYS\".\"ACCOUNT_ID\" IS NOT DISTINCT FROM ?) = 1 AND \"ACTQL_TARGET\".\"ACCOUNT_ID\" IS NOT DISTINCT FROM ? AND \"ACTQL_TARGET\".\"ACTIVE_USERS\" IS NOT DISTINCT FROM TO_DECIMAL(?, 38, 0) AND \"ACTQL_TARGET\".\"TREND\" IS NOT DISTINCT FROM NULL",
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
    original, "ACCOUNT_ID", update_before(original)[0].1, update_before(original),
    [("TREND", write_value(original, 2, @admitted.text_value(injected, 4096).unwrap()))], update_limits(),
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
  let original = project_table_description(target(), metadata_response(rows), [], limits()).unwrap()
  let key = write_value(original, 0, @admitted.text_value("key", 4096).unwrap())
  let precise = write_value(original, 1, @admitted.decimal_from_coefficient("12345", 38, 2).unwrap())
  let flag = write_value(original, 2, @admitted.boolean_value(true))
  let before = [("K", key), ("VALUE", precise), ("FLAG", flag)]
  let value = prepare_update_candidate(original, "K", key, before,
    [("VALUE", precise), ("FLAG", flag)], update_limits()).unwrap()
  assert_true(update_candidate_statement(value).contains("\"VALUE\" = TO_DECIMAL(?, 38, 2)"))
  assert_true(update_candidate_bindings(value).contains("\"value\":\"123.45\""))
  assert_true(update_candidate_bindings(value).contains("\"type\":\"BOOLEAN\",\"value\":\"true\""))
  // A value admitted by a different Contract is not assumed to fit this field.
  let wrong = @admitted.checked_text_value("123.456", @contract.primitive(@contract.StringType, nullable=false)).unwrap()
  assert_true(prepare_update_candidate(original, "K", key, before,
    [("VALUE", wrong)], update_limits()) is Err(InvalidValue("VALUE")))
}

///|
test "UPDATE refuses incomplete duplicate unknown and mismatched original key inputs" {
  let original = description()
  let before = update_before(original)
  let changes = [("TREND", write_value(original, 2, @admitted.text_value("up", 4096).unwrap()))]
  assert_true(prepare_update_candidate(original, "ACCOUNT_ID", before[0].1,
    before[:2].to_owned(), changes, update_limits()) is Err(IncompleteBeforeImage))
  assert_true(prepare_update_candidate(original, "ACCOUNT_ID", before[0].1,
    [before[0], before[0], before[2]], changes, update_limits()) is Err(DuplicateField("ACCOUNT_ID")))
  assert_true(prepare_update_candidate(original, "ACCOUNT_ID", before[0].1,
    before, [changes[0], changes[0]], update_limits()) is Err(DuplicateField("TREND")))
  assert_true(prepare_update_candidate(original, "ACCOUNT_ID", before[0].1,
    before, [("absent", changes[0].1)], update_limits()) is Err(UnknownField("absent")))
  assert_true(prepare_update_candidate(original, "ACCOUNT_ID",
    write_value(original, 0, @admitted.text_value("other", 4096).unwrap()), before, changes,
    update_limits()) is Err(DifferentBeforeImageKey))
  assert_true(prepare_update_candidate(original, "ACCOUNT_ID", before[0].1,
    before, [], update_limits()) is Err(EmptyUpdate))
}

///|
test "UPDATE bounds comparison admission statement and binding output independently" {
  let original = description()
  let before = update_before(original)
  let changes = [("TREND", write_value(original, 2, @admitted.text_value("up", 4096).unwrap()))]
  let normal = update_limits()
  for small in [
    { ..normal, max_comparison_work: 1 },
    { ..normal, max_value_nodes: 1 },
    { ..normal, max_value_text_bytes: 1 },
    { ..normal, max_statement_bytes: 1 },
    { ..normal, max_body_bytes: 1 },
    { ..normal, max_body_nodes: 1 },
  ] {
    assert_true(prepare_update_candidate(original, "ACCOUNT_ID", before[0].1,
      before, changes, small) is Err(_))
  }
  assert_true(prepare_update_candidate(original, "ACCOUNT_ID", before[0].1,
    before, changes, { ..normal, max_fields: 0 }) is Err(InvalidLimits))
}

///|
test "UPDATE preserves a read-only unsupported non-null JSON carrier as named refusal" {
  let rows = [metadata_row("K", 1, "TEXT"), metadata_row("J", 2, "VARIANT")]
  let original = project_table_description(target(),
    metadata_response(rows, total=2, partition_counts=[2]), [], limits()).unwrap()
  let key = write_value(original, 0, @admitted.text_value("key", 4096).unwrap())
  let json = write_value(original, 1, @admitted.recheck_json_payload_usage(@admitted.text_value("payload", 4096).unwrap(), { max_nodes: 8, max_depth: 4, max_text_bytes: 4096 }).unwrap().0.value)
  assert_true(prepare_update_candidate(original, "K", key,
    [("K", key), ("J", json)], [("J", json)], update_limits())
    is Err(UnsupportedWriteType("J", "VARIANT")))
}
