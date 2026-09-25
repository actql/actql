///|
test "completed source input binds rows, source, schema and order" {
  let rows = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let source = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  let schema = "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
  let order = "{\"stable\":true,\"keys\":[{\"field\":\"id\",\"dir\":\"asc\",\"nulls\":\"last\"}]}"
  let body =
    "{\"version\":\"actql-source-input-logical/0.1\"," +
    "\"logical_relation_cid\":\"" + rows + "\"," +
    "\"source_contract_cid\":\"" + source + "\"," +
    "\"relation_schema_cid\":\"" + schema + "\"," +
    "\"completeness\":\"complete\",\"ordering_evidence\":" + order + "}"
  let input_value = seal_run_evidence_value(
    "source_input_logical", body, 4096, 128, 16,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(input_value),
    "sha256:4c0b352e47b4494f4f36267f7c3f2927986a79935e37bd542bc7480f94c7d220",
  )
  assert_true(
    admit_completed_source_input_logical(
      input_value, rows, schema, source, order, 4096, 128, 16,
    ) is Ok(_),
  )
  assert_true(
    admit_completed_source_input_logical(
      input_value, "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
      schema, source, order, 4096, 128, 16,
    ) is Err(SourceInputOwnerMismatch("logical_relation_cid")),
  )
  assert_true(
    admit_completed_source_input_logical(
      input_value, rows, schema, source,
      "{\"stable\":false,\"keys\":[]}", 4096, 128, 16,
    ) is Err(SourceInputInvalidOrdering),
  )
  let incomplete = seal_run_evidence_value(
    "source_input_logical",
    "{\"version\":\"actql-source-input-logical/0.1\"," +
    "\"logical_relation_cid\":\"" + rows + "\"," +
    "\"source_contract_cid\":\"" + source + "\"," +
    "\"relation_schema_cid\":\"" + schema + "\"," +
    "\"completeness\":\"partial\",\"ordering_evidence\":" + order + "}",
    4096, 128, 16,
  ).unwrap()
  assert_true(
    admit_completed_source_input_logical(
      incomplete, rows, schema, source, order, 4096, 128, 16,
    ) is Err(SourceInputIncomplete),
  )
}
