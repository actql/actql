///|
let local_unary_timestamp_journal : String =
  #|{"entries":[],"journal_cid":"sha256:026d16c5cb970a2dc46b051552c6224c4fe21f5a2f7d2d5813da799d5511fb69","rule_catalog_cid":"sha256:3c378529adb7b274f8f8293184087641f95e9f421c4315034e77c02a383b2dc1","version":"actql-normalization-journal/0.1"}

///|
test "public unary Timestamp preparation retains its original audit and executes the exact instant" {
  let original = local_explicit_cast_original(
    text="SELECT TRY_TIMESTAMP('2000-02-29T00:00:00.123456789Z') AS value",
  )
  let issued = issue_prepared_client_local_normalization(original).unwrap()
  assert_eq(
    @publication.run_evidence_value_json(
      prepared_client_local_normalization_evidence(original, issued).unwrap(),
    ),
    common_local_empty_journal,
  )
  assert_true(
    physical_equal(
      issued,
      issue_prepared_client_local_normalization(original).unwrap(),
    ),
  )
  let task = @strategy.graph_task_owner(original.graph, 0).unwrap()
  let sequence = @lower.prepare_sequence(task, run_materials_limits().sequence).unwrap()
  let completed = @execution.execute_generated_sequence(
    local_explicit_cast_generated(sequence),
    [],
    string_try_number_execution_limits(),
  ).unwrap()
  let output = @execution.completed_output(
    completed,
    @pipeline.Step(@lower.sequence_count(sequence) - 1),
  ).unwrap()
  assert_true(
    @execution.completed_cell(output, 0, 0)
    is Some(Captured(@values.Timestamp(value))) &&
    value == "2000-02-29T00:00:00.123456789Z",
  )
  let foreign = local_explicit_cast_original(
    text="SELECT TRY_TIMESTAMP('2000-02-29T00:00:00.123456789Z') AS value",
  )
  assert_true(
    prepared_client_local_normalization_evidence(foreign, issued)
    is Err(ForeignPreparation),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      original,
      issued,
      common_local_empty_journal,
      local_decimal_sum_catalog_cid(),
    )
    is Err(ForeignCatalog),
  )
  ignore(
    local_checked_expression_normalization(
      local_explicit_cast_original(text="SELECT ABS(-3) AS value"),
    ),
  )
}

///|
test "unary Timestamp keeps equal Default and Supplied values as distinct original preparations" {
  let declarations = "{\"stamp\":{\"type\":\"string\",\"nullable\":false,\"default\":\"2000-02-29T00:00:00.123Z\"}}"
  for format in [@source_frontend.Sql, @source_frontend.Text] {
    let defaulted = local_supplied_parameter_preparation(
      format,
      declarations,
      None,
      text="SELECT TRY_TIMESTAMP(@stamp) AS value",
    )
    let supplied = local_supplied_parameter_preparation(
      format,
      declarations,
      Some("{\"stamp\":\"2000-02-29T00:00:00.123Z\"}"),
      text="SELECT TRY_TIMESTAMP(@stamp) AS value",
    )
    assert_eq(
      local_parameter_values_identity(defaulted),
      local_parameter_values_identity(supplied),
    )
    let original = issue_prepared_client_local_normalization(defaulted).unwrap()
    assert_eq(
      @publication.run_evidence_value_json(
        prepared_client_local_normalization_evidence(defaulted, original).unwrap(),
      ),
      common_local_empty_journal,
    )
    assert_true(
      prepared_client_local_normalization_evidence(supplied, original)
      is Err(ForeignPreparation),
    )
    let supplied_original = issue_prepared_client_local_normalization(supplied).unwrap()
    assert_eq(
      @publication.run_evidence_value_json(
        prepared_client_local_normalization_evidence(
          supplied, supplied_original,
        ).unwrap(),
      ),
      common_local_empty_journal,
    )
  }
}

///|
test "legacy unary Timestamp journal keeps its exact original catalog and wire" {
  let original = local_explicit_cast_original(
    text="SELECT TRY_TIMESTAMP('2000-02-29T00:00:00.123456789Z') AS value",
  )
  let legacy = _issue_prepared_client_legacy_local_normalization(original).unwrap()
  let evidence = prepared_client_local_normalization_evidence(original, legacy).unwrap()
  assert_eq(
    @publication.run_evidence_value_json(evidence),
    local_unary_timestamp_journal,
  )
  assert_true(
    physical_equal(
      legacy,
      issue_prepared_client_local_normalization(original).unwrap(),
    ),
  )
  let restored = restore_prepared_client_local_normalization(
    original,
    legacy,
    local_unary_timestamp_journal,
    local_unary_timestamp_catalog_cid(),
  ).unwrap()
  assert_true(physical_equal(restored, evidence))
}

///|
test "literal unary SQL and Pipe handoffs prepare through the current public frontend" {
  for
    (format, text) in [
      (
        @source_frontend.Sql,
        "SELECT TRY_TIMESTAMP('2000-02-29T00:00:00.123456789Z') AS value",
      ),
      (
        @source_frontend.Text,
        "WITH seed AS (SELECT '2000-02-29T00:00:00.123456789Z' AS stamp) FROM seed |> SELECT TRY_TIMESTAMP(stamp) AS value",
      ),
    ] {
    let prepared = local_explicit_cast_original(text~, format~)
    let original = issue_prepared_client_local_normalization(prepared).unwrap()
    assert_eq(
      @publication.run_evidence_value_json(
        prepared_client_local_normalization_evidence(prepared, original).unwrap(),
      ),
      common_local_empty_journal,
    )
  }
}
