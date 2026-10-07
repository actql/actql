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

///|
test "captured Effect source matches only the same completed Result facts" {
  let chain = captured_run_test_chain()
  let source = final_test_source(chain, final_test_preview(chain))
  assert_true(
    captured_effect_source_matches_result_facts(source, chain.artifact, "rows"),
  )
  assert_false(
    captured_effect_source_matches_result_facts(
      source,
      chain.artifact,
      "answer",
    ),
  )
  assert_false(
    captured_effect_source_matches_result_facts(
      source,
      final_test_source_artifact(chain),
      "rows",
    ),
  )
  let body = @json.object_without_field(
    captured_test_value(publication_contract_json(chain.artifact)),
    "result_artifact_cid",
  ).unwrap()
  let changed = seal_publication_contract(
    "result_artifact",
    captured_test_wire(body).replace(
      old="\"actual_row_count\":1",
      new="\"actual_row_count\":2",
    ),
    65536,
    4096,
    32,
  ).unwrap()
  assert_false(
    captured_effect_source_matches_result_facts(source, changed, "rows"),
  )
}

///|
test "Effect Table source Artifact is exclusive and preserves Result bytes" {
  let chain = captured_run_test_chain()
  let ordinary = final_test_source_artifact(chain)
  let retention = manifest_test_retention(ordering_test_cid("e"))
  let artifact_value = captured_test_value(
    publication_contract_json(chain.artifact),
  )
  let logical = final_test_receipt_field(artifact_value, "logical_result_cid")
  let schema = final_test_receipt_field(artifact_value, "result_schema_cid")
  let issue = (name : String, count : Int) => {
    issue_effect_table_input_artifact(
      chain.invocation,
      retention,
      name,
      ordering_test_cid("a"),
      ordering_test_cid("d"),
      logical,
      schema,
      count,
      65536,
      4096,
      32,
    )
  }
  let table = issue("rows", 1).unwrap()
  let table_cid = publication_contract_identity(table)
  let ordinary_cid = publication_contract_identity(ordinary)
  let invocation_cid = publication_contract_identity(chain.invocation)
  assert_true(table_cid != ordinary_cid)
  assert_eq(
    publication_contract_json(table),
    publication_contract_json(ordinary)
    .replace(old="\"source_result\":", new="\"source_table_input\":")
    .replace(old=ordinary_cid, new=table_cid),
  )
  assert_eq(
    effect_table_input_artifact_preview_binding(
      table,
      invocation_cid,
      "rows",
      ordering_test_cid("d"),
    ).unwrap(),
    (table_cid, ordering_test_cid("a")),
  )
  for source in [table, ordinary] {
    let table_binding = effect_table_input_artifact_preview_binding(
      source,
      invocation_cid,
      "rows",
      ordering_test_cid("d"),
    )
    let result_binding = effect_source_artifact_preview_binding(
      source,
      invocation_cid,
      "rows",
      ordering_test_cid("d"),
    )
    assert_eq(
      table_binding is Ok(_),
      publication_contract_identity(source) == table_cid,
    )
    assert_eq(
      result_binding is Ok(_),
      publication_contract_identity(source) == ordinary_cid,
    )
  }
  assert_true(
    effect_table_input_artifact_preview_binding(
      table,
      invocation_cid,
      "other",
      ordering_test_cid("d"),
    )
    is Err(EffectSourceWrongContract),
  )
  assert_true(issue("", 1) is Err(EffectSourceInvalidBinding))
  assert_true(issue("e\u{301}", 1) is Err(EffectSourceInvalidBinding))
  assert_true(issue("rows", -1) is Err(EffectSourceInvalidMeasurement))
  assert_true(
    publication_contract_json(issue("rows", 0).unwrap()).contains(
      "\"actual_row_count\":0",
    ),
  )
  let body = @json.object_without_field(
    captured_test_value(publication_contract_json(table)),
    "result_artifact_cid",
  ).unwrap()
  let wire = captured_test_wire(body)
  for
    invalid in [
      wire.replace(old="\"source_table_input\":\"rows\",", new=""),
      wire.replace(
        old="\"source_table_input\":",
        new="\"source_result\":\"rows\",\"source_table_input\":",
      ),
    ] {
    assert_true(
      seal_publication_contract(
        "effect_source_artifact", invalid, 65536, 4096, 32,
      )
      is Err(_),
    )
  }
}

///|
test "Effect Table source admission matches typed Preview and exact export facts" {
  let chain = captured_run_test_chain()
  let retention = manifest_test_retention(ordering_test_cid("e"))
  let placeholder = ordering_test_cid("a")
  let raw = final_test_preview_wire(
      chain,
      placeholder,
      placeholder,
      plan=false,
      artifact_cid=Some(publication_contract_identity(chain.artifact)),
    )
    .replace(old="\"source_result\":", new="\"source_table_input\":")
    .replace(old="\"effect_kind\":\"update\"", new="\"effect_kind\":\"store\"")
  let (_, preview) = author_effect_preview_semantic_wire(
    raw,
    publication_contract_identity(chain.run),
    run_evidence_value_identity(chain.authoring),
    65536,
    4096,
    32,
  ).unwrap()
  let artifact_value = captured_test_value(
    publication_contract_json(chain.artifact),
  )
  let logical = final_test_receipt_field(artifact_value, "logical_result_cid")
  let schema = final_test_receipt_field(artifact_value, "result_schema_cid")
  let physical = issue_effect_table_input_artifact(
    chain.invocation,
    retention,
    "rows",
    ordering_test_cid("a"),
    ordering_test_cid("d"),
    logical,
    schema,
    1,
    65536,
    4096,
    32,
  ).unwrap()
  let admit = (artifact : PublicationContract) => {
    admit_captured_effect_source_from_table_input(
      preview,
      0,
      chain.invocation,
      artifact,
      chain.artifact,
      ordering_test_cid("d"),
    )
  }
  let source = admit(physical).unwrap()
  assert_true(
    captured_effect_source_matches_table_input_facts(
      source,
      chain.artifact,
      "rows",
    ),
  )
  assert_false(
    captured_effect_source_matches_result_facts(source, chain.artifact, "rows"),
  )
  assert_true(admit(final_test_source_artifact(chain)) is Err(_))
  assert_true(
    admit_captured_effect_source_from_result(
      preview,
      0,
      chain.invocation,
      physical,
      chain.artifact,
      ordering_test_cid("d"),
    )
    is Err(_),
  )
  assert_true(
    captured_effect_source_inventory_from_artifacts_valid(
      preview,
      [0],
      [physical],
      [chain.artifact],
    ),
  )
  assert_false(
    captured_effect_source_inventory_from_results_valid(
      preview,
      [0],
      [physical],
      [chain.artifact],
    ),
  )
  assert_false(captured_effect_source_recovery_inventory_valid(preview, [], []))
  assert_false(
    captured_effect_source_inventory_from_artifacts_valid(
      preview,
      [0, 0],
      [physical, physical],
      [chain.artifact, chain.artifact],
    ),
  )
  let body = captured_test_wire(
    @json.object_without_field(
      captured_test_value(publication_contract_json(physical)),
      "result_artifact_cid",
    ).unwrap(),
  )
  for
    field in [
      "logical_result_cid", "result_schema_cid", "effective_data_policy_cid", "effective_retention_policy_cid",
      "source_binding_cid", "store_authority_cid", "invocation_cid",
    ] {
    let old = final_test_receipt_field(
      captured_test_value(publication_contract_json(physical)),
      field,
    )
    let foreign = seal_publication_contract(
      "effect_source_artifact",
      body.replace(
        old="\"" + field + "\":\"" + old + "\"",
        new="\"" + field + "\":\"" + ordering_test_cid("f") + "\"",
      ),
      65536,
      4096,
      32,
    ).unwrap()
    assert_true(admit(foreign) is Err(_))
  }
  let foreign_count = issue_effect_table_input_artifact(
    chain.invocation,
    retention,
    "rows",
    ordering_test_cid("a"),
    ordering_test_cid("d"),
    logical,
    schema,
    2,
    65536,
    4096,
    32,
  ).unwrap()
  assert_true(admit(foreign_count) is Err(_))
}
