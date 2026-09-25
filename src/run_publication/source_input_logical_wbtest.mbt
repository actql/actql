///|
test "completed source input binds rows, source, schema and order" {
  let rows = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  let source = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  let schema = "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
  let order = "{\"stable\":true,\"keys\":[{\"field\":\"id\",\"dir\":\"asc\",\"nulls\":\"last\"}]}"
  let body = "{\"version\":\"actql-source-input-logical/0.1\"," +
    "\"logical_relation_cid\":\"" +
    rows +
    "\"," +
    "\"source_contract_cid\":\"" +
    source +
    "\"," +
    "\"relation_schema_cid\":\"" +
    schema +
    "\"," +
    "\"completeness\":\"complete\",\"ordering_evidence\":" +
    order +
    "}"
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
    )
    is Ok(_),
  )
  assert_true(
    admit_completed_source_input_logical(
      input_value, "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
      schema, source, order, 4096, 128, 16,
    )
    is Err(SourceInputOwnerMismatch("logical_relation_cid")),
  )
  assert_true(
    admit_completed_source_input_logical(
      input_value, rows, schema, source, "{\"stable\":false,\"keys\":[]}", 4096,
      128, 16,
    )
    is Err(SourceInputInvalidOrdering),
  )
  let incomplete = seal_run_evidence_value(
    "source_input_logical",
    "{\"version\":\"actql-source-input-logical/0.1\"," +
    "\"logical_relation_cid\":\"" +
    rows +
    "\"," +
    "\"source_contract_cid\":\"" +
    source +
    "\"," +
    "\"relation_schema_cid\":\"" +
    schema +
    "\"," +
    "\"completeness\":\"partial\",\"ordering_evidence\":" +
    order +
    "}",
    4096,
    128,
    16,
  ).unwrap()
  assert_true(
    admit_completed_source_input_logical(
      incomplete, rows, schema, source, order, 4096, 128, 16,
    )
    is Err(SourceInputIncomplete),
  )
}

///|
test "source observation binds the completed input and checked source" {
  let source_cid = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  let scope = "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
  let other = "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
  let order = "{\"stable\":false,\"keys\":[]}"
  let input = seal_run_evidence_value(
    "source_input_logical",
    "{\"version\":\"actql-source-input-logical/0.1\"," +
    "\"logical_relation_cid\":\"" +
    other +
    "\"," +
    "\"relation_schema_cid\":\"" +
    other +
    "\"," +
    "\"source_contract_cid\":\"" +
    source_cid +
    "\"," +
    "\"completeness\":\"complete\",\"ordering_evidence\":" +
    order +
    "}",
    8192,
    256,
    16,
  ).unwrap()
  let source_ref = "connector://crm/main/r#v"
  let prefix = "{\"version\":\"actql-source-evidence/0.1\"," +
    "\"source_ref\":\"" +
    source_ref +
    "\"," +
    "\"input_logical_cid\":\"" +
    run_evidence_value_identity(input) +
    "\"," +
    "\"source_contract_cid\":\"" +
    source_cid +
    "\"," +
    "\"schema_evidence_cid\":\"" +
    other +
    "\"," +
    "\"capability_evidence_cid\":\"" +
    other +
    "\"," +
    "\"authority_scope_cid\":\"" +
    scope +
    "\"," +
    "\"source_data_policy_cid\":\"" +
    other +
    "\"," +
    "\"effective_data_policy_cid\":\"" +
    other +
    "\"," +
    "\"data_classification\":\"internal\"," +
    "\"source_view_contract_cid\":\"" +
    other +
    "\"," +
    "\"output_carrier\":\"relation\",\"read_mode\":\"snapshot\"," +
    "\"observed_at\":\"2026-09-26T00:00:00.000Z\"," +
    "\"snapshot_ref\":\"snapshot-1\"," +
    "\"completeness\":\"complete\",\"ordering_evidence\":" +
    order +
    ",\"consistency_level\":\"snapshot\"}"
  let evidence = seal_run_evidence_value(
    "source_evidence", prefix, 8192, 256, 16,
  ).unwrap()
  assert_eq(
    admit_completed_source_observation_binding(
      evidence, input, source_ref, source_cid, scope, other, 8192, 256, 16,
    ),
    Ok(run_evidence_value_identity(evidence)),
  )
  assert_true(
    admit_completed_source_observation_binding(
      evidence, input, "connector://other", source_cid, scope, other, 8192, 256,
      16,
    )
    is Err(Mismatch("source_ref")),
  )
  assert_true(
    admit_completed_source_observation_binding(
      evidence, input, source_ref, source_cid, other, other, 8192, 256, 16,
    )
    is Err(Mismatch("authority_scope_cid")),
  )
  let partial = seal_run_evidence_value(
    "source_evidence",
    prefix.replace(
      old="\"completeness\":\"complete\"",
      new="\"completeness\":\"partial\"",
    ),
    8192,
    256,
    16,
  ).unwrap()
  assert_true(
    admit_completed_source_observation_binding(
      partial, input, source_ref, source_cid, scope, other, 8192, 256, 16,
    )
    is Err(Incomplete),
  )
  let wrong_order = seal_run_evidence_value(
    "source_evidence",
    prefix.replace(old=order, new="{\"stable\":true,\"keys\":[]}"),
    8192,
    256,
    16,
  ).unwrap()
  assert_true(
    admit_completed_source_observation_binding(
      wrong_order, input, source_ref, source_cid, scope, other, 8192, 256, 16,
    )
    is Err(InvalidOrdering),
  )
}
