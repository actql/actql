///|
let local_take_catalog_cid : String = "sha256:2e87dfc12f59f5755bc3a41b61fc0a9b5b5cc0c0f7861128924c852c13ce7d03"

///|
let local_take_journal : String =
  #|{"entries":[],"journal_cid":"sha256:84b650b308e19adb41fc508e306e85c65a6db547711f9ac9303f536814cdca95","rule_catalog_cid":"sha256:2e87dfc12f59f5755bc3a41b61fc0a9b5b5cc0c0f7861128924c852c13ce7d03","version":"actql-normalization-journal/0.1"}

///|
fn local_take_normalization(
  owner : PreparedClientProgram,
) -> ClientLocalNormalization raise {
  let issued = issue_prepared_client_local_normalization(owner).unwrap()
  assert_true(
    @checked.local_completion_free_inventory_uses_take(
      match issued.audit {
        CompletionFree(value) => value
        SortCompletion(_) => fail("completion-free original expected")
      },
    ),
  )
  assert_eq(
    @publication.run_evidence_value_json(
      prepared_client_local_normalization_evidence(owner, issued).unwrap(),
    ),
    local_take_journal,
  )
  issued
}

///|
test "public COUNT LIMIT and OFFSET retain original Group and existing Take execution" {
  for
    (text, expected_rows) in [
      ("SELECT COUNT(*) AS n LIMIT 1", 1),
      ("SELECT COUNT(*) AS n LIMIT 1 OFFSET 1", 0),
      ("SELECT COUNT(*) AS n LIMIT 9007199254740991 OFFSET 0", 1),
    ] {
    let original = local_explicit_cast_original(text~)
    ignore(local_take_normalization(original))
    let task = @strategy.graph_task_owner(original.graph, 0).unwrap()
    let sequence = @lower.prepare_sequence(
      task,
      run_materials_limits().sequence,
    ).unwrap()
    let completed = @execution.execute_generated_sequence(
      local_group_generated(sequence),
      [],
      string_try_number_execution_limits(),
    ).unwrap()
    let output = @execution.completed_output(
      completed,
      @pipeline.Step(@lower.sequence_count(sequence) - 1),
    ).unwrap()
    assert_eq(@execution.completed_row_count(output), expected_rows)
    if expected_rows == 1 {
      assert_true(
        @execution.completed_cell(output, 0, 0) is Some(Number(v)) && v == 1.0,
      )
    }
  }
}

///|
test "Take closes actual supplied Number and int64 scalar demands without converting either domain" {
  for format in [@source_frontend.Sql, @source_frontend.Text] {
    for
      (kind, values) in [
        ("number", "{\"count\":1,\"offset\":0}"),
        ("int64", "{\"count\":\"1\",\"offset\":\"0\"}"),
        (
          "int64", "{\"count\":\"9007199254740991\",\"offset\":\"9007199254740991\"}",
        ),
      ] {
      let declarations = "{\"count\":{\"type\":\"" +
        kind +
        "\",\"nullable\":false},\"offset\":{\"type\":\"" +
        kind +
        "\",\"nullable\":false}}"
      let original = local_supplied_parameter_preparation(
        format,
        declarations,
        Some(values),
        text="SELECT COUNT(*) AS n LIMIT @count OFFSET @offset",
      )
      ignore(local_take_normalization(original))
    }
  }
}

///|
test "Take keeps actual default origin separate from equal supplied values" {
  let declarations = "{\"count\":{\"type\":\"number\",\"nullable\":false,\"default\":1}}"
  let text = "SELECT COUNT(*) AS n LIMIT @count"
  let supplied = local_supplied_parameter_preparation(
    @source_frontend.Sql,
    declarations,
    Some("{\"count\":1}"),
    text~,
  )
  let defaulted = local_supplied_parameter_preparation(
    @source_frontend.Sql,
    declarations,
    None,
    text~,
  )
  assert_eq(
    local_parameter_values_identity(supplied),
    local_parameter_values_identity(defaulted),
  )
  let issued = local_take_normalization(supplied)
  ignore(local_default_parameter_normalization(defaulted))
  assert_true(
    prepared_client_local_normalization_evidence(defaulted, issued)
    is Err(ForeignPreparation),
  )
}

///|
test "Take preserves existing SafeInteger role rejection before issuing normalization" {
  for
    (kind, value) in [
      ("number", "0"),
      ("number", "-1"),
      ("number", "1.5"),
      ("number", "9007199254740992"),
      ("int64", "\"9007199254740992\""),
    ] {
    let declarations = "{\"count\":{\"type\":\"" +
      kind +
      "\",\"nullable\":false}}"
    // Original source/binding admission may reject before operation-scalar
    // closure. Both paths must remain actual typed input failures, not a
    // preparation or permission inferred from a declaration.
    guard local_supplied_parameter_preparation_attempt(
        @source_frontend.Sql,
        declarations,
        Some("{\"count\":" + value + "}"),
        text="SELECT COUNT(*) AS n LIMIT @count",
      )
      is Err(Check(diagnostic)) else {
      fail(
        "invalid supplied Take count did not produce its original diagnostic",
      )
    }
    assert_eq(@checked.diagnostic_category(diagnostic), @checked.InvalidInput)
  }
  let offset = "{\"offset\":{\"type\":\"number\",\"nullable\":false}}"
  guard local_supplied_parameter_preparation_attempt(
      @source_frontend.Sql,
      offset,
      Some("{\"offset\":-1}"),
      text="SELECT COUNT(*) AS n LIMIT 1 OFFSET @offset",
    )
    is Err(Check(diagnostic)) else {
    fail(
      "negative supplied Take offset did not produce its original diagnostic",
    )
  }
  assert_eq(@checked.diagnostic_category(diagnostic), @checked.InvalidInput)
}

///|
test "Take rejects foreign original preparations copied tokens and preceding Group journal" {
  let original = local_explicit_cast_original(
    text="SELECT COUNT(*) AS n LIMIT 1",
  )
  let issued = local_take_normalization(original)
  let foreign = local_explicit_cast_original(
    text="SELECT COUNT(*) AS n LIMIT 1",
  )
  assert_true(
    prepared_client_local_normalization_evidence(foreign, issued)
    is Err(ForeignPreparation),
  )
  let copy : ClientLocalNormalization = {
    preparation: issued.preparation,
    audit: issued.audit,
    evidence: issued.evidence,
  }
  assert_true(
    prepared_client_local_normalization_evidence(original, copy)
    is Err(ForeignPreparation),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      original, issued, local_group_journal, local_take_catalog_cid,
    )
    is Err(SubstitutedJournal),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      original, issued, local_take_journal, local_group_catalog_cid,
    )
    is Err(ForeignCatalog),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      original, issued, local_take_journal, local_take_catalog_cid,
    )
    is Ok(_),
  )
}
