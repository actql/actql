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
  let observed = admit_model_source_observation(
    evidence, input, source_ref, source_cid, scope, other, "2026-09-26T00:00:00.000Z",
    "2026-09-26T00:00:01.000Z",
  ).unwrap()
  assert_true(model_source_observation_matches_input(observed, input))
  let observation_body = "{\"version\":\"actql-observation-set/0.1\"," +
    "\"invocation_template_cid\":\"" +
    other +
    "\"," +
    "\"data_policy_cid\":\"" +
    other +
    "\"," +
    "\"consistency\":\"independent_snapshots\"," +
    "\"capture_started_at\":\"2026-09-26T00:00:00.000Z\"," +
    "\"capture_completed_at\":\"2026-09-26T00:00:01.000Z\"," +
    "\"source_evidence_cids\":[\"" +
    evidence.identity +
    "\"]," +
    "\"captured_input_artifact_cids\":[],\"model_slot_capture_cids\":[]," +
    "\"replayability\":{\"materialized\":false,\"availability_evidence_cids\":[]}}"
  let saved = seal_run_evidence_value(
    "observation_set", observation_body, 8192, 256, 16,
  ).unwrap()
  let fresh_evidence = seal_run_evidence_value(
    "source_evidence",
    prefix.replace(
      old="2026-09-26T00:00:00.000Z",
      new="2026-09-27T00:00:00.000Z",
    ),
    8192,
    256,
    16,
  ).unwrap()
  let fresh = admit_model_source_observation(
    fresh_evidence, input, source_ref, source_cid, scope, other, "2026-09-27T00:00:00.000Z",
    "2026-09-27T00:00:01.000Z",
  ).unwrap()
  let restored = restore_model_source_observation(fresh, evidence, saved).unwrap()
  assert_eq(
    model_source_observation_fields(restored),
    model_source_observation_fields(observed),
  )
  assert_true(
    restore_model_source_observation(fresh, fresh_evidence, saved)
    is Err(RunEvidenceReferenceMismatch("observation.source_evidence_cids")),
  )
  for
    inventory in [
      "[]",
      "[\"" + other + "\"]",
      "[\"" + evidence.identity + "\",\"" + other + "\"]",
    ] {
    let invalid = seal_run_evidence_value(
      "observation_set",
      observation_body.replace(
        old="[\"" + evidence.identity + "\"]",
        new=inventory,
      ),
      8192,
      256,
      16,
    ).unwrap()
    assert_true(
      restore_model_source_observation(fresh, evidence, invalid)
      is Err(RunEvidenceReferenceMismatch("observation.source_evidence_cids")),
    )
  }
  assert_eq(
    model_source_observation_fields(observed),
    (
      run_evidence_value_identity(evidence),
      "2026-09-26T00:00:00.000Z",
      "2026-09-26T00:00:01.000Z",
    ),
  )
  assert_true(
    admit_model_source_observation(
      evidence, input, source_ref, source_cid, other, other, "2026-09-26T00:00:00.000Z",
      "2026-09-26T00:00:01.000Z",
    )
    is Err(RunEvidenceReferenceMismatch("source_evidence")),
  )
  for
    (start, finish) in [
      ("invalid", "2026-09-26T00:00:01.000Z"),
      ("2026-09-26T00:00:02.000Z", "2026-09-26T00:00:01.000Z"),
    ] {
    assert_true(
      admit_model_source_observation(
        evidence, input, source_ref, source_cid, scope, other, start, finish,
      )
      is Err(RunEvidenceReferenceMismatch("source.capture_interval")),
    )
  }
  let saved_input = admit_source_effect_dependency_body(
    "source_input_logical",
    input.wire,
    8192,
    256,
    16,
  ).unwrap()
  let saved_observation = admit_source_effect_dependency_body(
    "source_evidence",
    evidence.wire,
    8192,
    256,
    16,
  ).unwrap()
  assert_eq(
    saved_input.node.references.map(value => (value.kind, value.identity)),
    [
      ("relation_value", other),
      ("relation_schema", other),
      ("source_contract", source_cid),
    ],
  )
  assert_eq(saved_observation.node.references[0].kind, "source_input_logical")
  assert_eq(saved_observation.node.references[0].identity, input.identity)
  assert_eq(
    captured_effect_dependency_body_json(saved_observation),
    evidence.wire,
  )
  assert_true(
    admit_source_effect_dependency_body(
      "source_input_logical",
      evidence.wire,
      8192,
      256,
      16,
    )
    is Err(InvalidBody),
  )
  assert_true(
    admit_source_effect_dependency_body(
      "source_evidence",
      " " + evidence.wire,
      8192,
      256,
      16,
    )
    is Err(InvalidBody),
  )
  assert_true(
    admit_source_effect_dependency_body(
      "source_evidence",
      evidence.wire.replace(old="snapshot-1", new="snapshot-2"),
      8192,
      256,
      16,
    )
    is Err(InvalidBody),
  )
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
