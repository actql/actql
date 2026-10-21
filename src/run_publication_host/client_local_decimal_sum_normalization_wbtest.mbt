///|
let local_decimal_sum_public_sql : String = "WITH amounts AS (\n  SELECT CAST('1.25' AS DECIMAL(6,2)) AS amount\n  UNION ALL SELECT CAST('2.75' AS DECIMAL(6,2)) AS amount\n)\nSELECT SUM(amount) AS total FROM amounts\n"

///|
fn local_decimal_sum_normalization(
  owner : PreparedClientProgram,
) -> ClientLocalNormalization raise {
  let proof = issue_prepared_client_local_normalization(owner).unwrap()
  assert_eq(
    local_normalization_catalog_cid(proof.audit),
    "sha256:58cc11cad4aac1d83ccb051ebe2c6cec97ffdff6de9133bdd881d6446b90d409",
  )
  guard proof.audit is CompletionFree(inventory) else {
    fail("original completion-free Decimal sum expected")
  }
  assert_true(
    @checked.local_completion_free_inventory_uses_decimal_sum(inventory),
  )
  assert_true(@checked.local_completion_free_inventory_uses_groups(inventory))
  assert_true(
    @checked.local_completion_free_inventory_matches(
      inventory,
      @strategy.graph_program(owner.graph),
    ),
  )
  proof
}

///|
test "public Decimal SUM keeps the original SQL set and Group owners" {
  let original = local_explicit_cast_original(text=local_decimal_sum_public_sql)
  ignore(local_decimal_sum_normalization(original))
  let count = local_explicit_cast_original(text="SELECT COUNT(*) AS n")
  let old = issue_prepared_client_local_normalization(count).unwrap()
  assert_eq(local_normalization_catalog_cid(old.audit), local_group_catalog_cid)
}

///|
test "original Decimal sum retains nullable distinct filter and exact coefficient execution" {
  let document =
    #|{"version":"actql/0.1","id":"local.decimal-sum","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"amount":{"type":"decimal","nullable":true,"precision":6,"scale":2}},"rows":[{"amount":"1.25"},{"amount":"2.75"},{"amount":"1.25"},{"amount":null}]},"as":"input"},{"from":"input","group":{"by":[],"aggregates":{"total":{"fn":"sum","field":"amount","distinct":true,"filter":"amount IS NOT NULL"}}},"as":"grouped"}],"results":{"rows":{"from":"grouped","fields":["total"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let original = local_group_original_document(document)
  ignore(local_decimal_sum_normalization(original))
  let task = @strategy.graph_task_owner(original.graph, 0).unwrap()
  let sequence = @lower.prepare_sequence(task, run_materials_limits().sequence).unwrap()
  let completed = @execution.execute_generated_sequence(
    local_group_generated(sequence),
    [],
    string_try_number_execution_limits(),
  ).unwrap()
  let output = @execution.completed_output(
    completed,
    @pipeline.Step(@lower.sequence_count(sequence) - 1),
  ).unwrap()
  assert_eq(@execution.completed_row_count(output), 1)
  guard @execution.completed_cell(output, 0, 0)
    is Some(Captured(@values.Decimal(value))) else {
    fail("same exact Decimal result expected")
  }
  assert_eq(value.coefficient, "400")
  assert_eq(value.precision, 38)
  assert_eq(value.scale, 2)
}

///|
test "Decimal sum original NULL value and foreign preparation remain distinct" {
  let original = local_explicit_cast_original(
    text="SELECT SUM(CAST(NULL AS DECIMAL(6,2))) AS total",
  )
  let proof = local_decimal_sum_normalization(original)
  let equal = local_explicit_cast_original(
    text="SELECT SUM(CAST(NULL AS DECIMAL(6,2))) AS total",
  )
  assert_true(
    prepared_client_local_normalization_evidence(equal, proof)
    is Err(ForeignPreparation),
  )
  let task = @strategy.graph_task_owner(original.graph, 0).unwrap()
  let sequence = @lower.prepare_sequence(task, run_materials_limits().sequence).unwrap()
  let completed = @execution.execute_generated_sequence(
    local_group_generated(sequence),
    [],
    string_try_number_execution_limits(),
  ).unwrap()
  let output = @execution.completed_output(
    completed,
    @pipeline.Step(@lower.sequence_count(sequence) - 1),
  ).unwrap()
  assert_eq(@execution.completed_row_count(output), 1)
  assert_true(@execution.completed_cell(output, 0, 0) is Some(Null))
}

///|
test "Decimal sum retains real candidate-key Sort completion and refuses empty evidence" {
  let document =
    #|{"version":"actql/0.1","id":"local.decimal-sum-sort","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"key":{"type":"string","nullable":false},"amount":{"type":"decimal","nullable":false,"precision":4,"scale":2}},"rows":[{"key":"b","amount":"1.00"},{"key":"a","amount":"1.00"}]},"as":"input"},{"group":{"by":["key"],"aggregates":{"n":{"fn":"sum","field":"amount"}}}},{"sort":[{"field":"n","dir":"asc","nulls":"last"}],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["key","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let owner = local_group_original_document(document)
  let proof = issue_prepared_client_local_normalization(owner).unwrap()
  guard proof.audit is SortCompletion(inventory) else {
    fail("actual Sort completion must survive exact-sum audit")
  }
  assert_true(
    @checked.local_sort_normalization_inventory_uses_decimal_sum(inventory),
  )
  assert_eq(@checked.local_sort_normalization_entry_count(inventory), 1)
  let wire = @publication.run_evidence_value_json(
    prepared_client_local_normalization_evidence(owner, proof).unwrap(),
  )
  let expected =
    #|{"entries":[{"authored":"[{\"dir\":\"asc\",\"field\":\"n\",\"nulls\":\"last\"}]","canonical":"[{\"dir\":\"asc\",\"field\":\"n\",\"nulls\":\"last\"},{\"dir\":\"asc\",\"field\":\"key\",\"nulls\":\"last\"}]","path":"$.stages[0].steps[2].sort","rule":"sort.candidate_key_completion"}],"journal_cid":"sha256:f4df8ce4ea7964cc751bff2781f72a4f915f0c7ad25af6ba3d81712353b58a85","rule_catalog_cid":"sha256:58cc11cad4aac1d83ccb051ebe2c6cec97ffdff6de9133bdd881d6446b90d409","version":"actql-normalization-journal/0.1"}
  assert_eq(wire, expected)
  let empty =
    #|{"entries":[],"journal_cid":"sha256:67072dc588b826b993bf1aba14a957127e8e86ad3cad351c905252df63e77d5c","rule_catalog_cid":"sha256:58cc11cad4aac1d83ccb051ebe2c6cec97ffdff6de9133bdd881d6446b90d409","version":"actql-normalization-journal/0.1"}
  assert_true(
    restore_prepared_client_local_normalization(
      owner,
      proof,
      empty,
      local_decimal_sum_catalog_cid(),
    )
    is Err(SubstitutedJournal),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      owner,
      proof,
      wire,
      local_decimal_sum_catalog_cid(),
    )
    is Ok(_),
  )
}

///|
test "Decimal sum keeps original Default versus supplied typed binding and proof identity" {
  let declarations = "{\"amount\":{\"type\":\"decimal\",\"nullable\":false,\"precision\":6,\"scale\":2,\"default\":\"1.25\"}}"
  let query = "SELECT SUM(@amount) AS total"
  let defaulted = local_supplied_parameter_preparation(
    @source_frontend.Sql,
    declarations,
    None,
    text=query,
  )
  let supplied = local_supplied_parameter_preparation(
    @source_frontend.Sql,
    declarations,
    Some("{\"amount\":\"1.25\"}"),
    text=query,
  )
  let proof = local_decimal_sum_normalization(defaulted)
  ignore(local_decimal_sum_normalization(supplied))
  assert_eq(
    local_parameter_values_identity(defaulted),
    local_parameter_values_identity(supplied),
  )
  assert_true(
    @parameter.bound_value_at(local_default_bound_values(defaulted), 0).unwrap().origin
    is @parameter.Default,
  )
  assert_true(
    prepared_client_local_normalization_evidence(supplied, proof)
    is Err(ForeignPreparation),
  )
  let copied : ClientLocalNormalization = {
    preparation: proof.preparation,
    audit: proof.audit,
    evidence: proof.evidence,
  }
  assert_true(
    prepared_client_local_normalization_evidence(defaulted, copied)
    is Err(ForeignPreparation),
  )
}
