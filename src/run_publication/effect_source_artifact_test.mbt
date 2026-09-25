///|
test "Effect source issuer binds checked export facts without public name" {
  let chain = captured_run_test_chain()
  let public_value = captured_test_value(
    publication_contract_json(chain.artifact),
  )
  let logical = final_test_receipt_field(public_value, "logical_result_cid")
  let schema = final_test_receipt_field(public_value, "result_schema_cid")
  let retention = manifest_test_retention(ordering_test_cid("e"))
  let issue = fn(name : String, binding : String, rows : Int) {
    issue_effect_source_artifact(
      chain.invocation,
      retention,
      name,
      binding,
      ordering_test_cid("d"),
      logical,
      schema,
      rows,
      65536,
      4096,
      32,
    )
  }
  let artifact = issue("rows", ordering_test_cid("a"), 1).unwrap()
  assert_eq(
    effect_source_artifact_preview_binding(
      artifact,
      publication_contract_identity(chain.invocation),
      "rows",
      ordering_test_cid("d"),
    ).unwrap(),
    (publication_contract_identity(artifact), ordering_test_cid("a")),
  )
  assert_true(
    effect_source_artifact_preview_binding(
      artifact,
      publication_contract_identity(chain.invocation),
      "answer",
      ordering_test_cid("d"),
    )
    is Err(EffectSourceWrongContract),
  )
  assert_true(
    effect_source_artifact_preview_binding(
      artifact,
      ordering_test_cid("f"),
      "rows",
      ordering_test_cid("d"),
    )
    is Err(EffectSourceWrongContract),
  )
  assert_true(
    effect_source_artifact_preview_binding(
      chain.artifact,
      publication_contract_identity(chain.invocation),
      "rows",
      ordering_test_cid("d"),
    )
    is Err(EffectSourceWrongContract),
  )
  assert_true(
    effect_source_artifact_preview_binding(
      artifact,
      publication_contract_identity(chain.invocation),
      "rows",
      ordering_test_cid("f"),
    )
    is Err(EffectSourceWrongContract),
  )
  assert_true(publication_contract_name(artifact) == "effect_source_artifact")
  assert_true(
    publication_contract_identity(artifact) ==
    publication_contract_identity(final_test_source_artifact(chain)),
  )
  assert_true(
    publication_contract_identity(
      issue("answer", ordering_test_cid("a"), 1).unwrap(),
    ) !=
    publication_contract_identity(artifact),
  )
  assert_true(
    publication_contract_identity(
      issue("rows", ordering_test_cid("b"), 1).unwrap(),
    ) !=
    publication_contract_identity(artifact),
  )
  assert_true(
    publication_contract_identity(
      issue("rows", ordering_test_cid("a"), 2).unwrap(),
    ) !=
    publication_contract_identity(artifact),
  )
  assert_true(issue("rows", "invalid", 1) is Err(EffectSourceInvalidBinding))
  assert_true(
    issue("rows", ordering_test_cid("a"), -1)
    is Err(EffectSourceInvalidMeasurement),
  )
}
