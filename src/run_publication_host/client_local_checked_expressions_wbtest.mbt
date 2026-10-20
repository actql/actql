///|
let local_checked_expression_catalog_cid : String = "sha256:e51161c71f8cb1565fd562ce325a78d2cec3b5c55a5aca54e70953fd6d92db74"

///|
let local_checked_expression_journal : String =
  #|{"entries":[],"journal_cid":"sha256:56a751c1140b78d0f2330ad7ec5c9f4517bdf00bfa2a921758e7af0318f3b48a","rule_catalog_cid":"sha256:e51161c71f8cb1565fd562ce325a78d2cec3b5c55a5aca54e70953fd6d92db74","version":"actql-normalization-journal/0.1"}

///|
fn local_checked_expression_normalization(
  owner : PreparedClientProgram,
) -> ClientLocalNormalization raise {
  let issued = issue_prepared_client_local_normalization(owner).unwrap()
  assert_eq(
    @publication.run_evidence_value_json(
      prepared_client_local_normalization_evidence(owner, issued).unwrap(),
    ),
    local_checked_expression_journal,
  )
  issued
}

///|
test "the unchanged public ABS query issues original normalization and evaluates its Number cell" {
  let original = local_explicit_cast_original(
    text="SELECT ABS(-3) AS magnitude",
  )
  let issued = local_checked_expression_normalization(original)
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
  assert_eq(@execution.completed_row_count(output), 1)
  assert_eq(@execution.completed_column_name(output, 0), Some("magnitude"))
  assert_true(
    @execution.completed_cell(output, 0, 0) is Some(Number(value)) &&
    value == 3.0,
  )
}

///|
test "one closed catalog covers checked scalar families and membership auxiliaries" {
  for
    text in [
      "SELECT ABS(-3) AS a, SIGN(-2) AS s, SQRT(4) AS q, FLOOR(1.5) AS f, ROUND(1.5) AS r",
      "SELECT LOWER('ABC') AS a, UPPER('abc') AS b, LENGTH('abc') AS n, CONCAT('a','b') AS c",
      "SELECT CASE WHEN TRUE THEN ABS(-3) ELSE SQRT(-1) END AS value", "SELECT 3 IN (1,3,5) AS included, 2 NOT IN (1,3,5) AS excluded",
      "SELECT COALESCE(CAST(NULL AS NUMBER), ABS(-3)) AS value", "SELECT CAST(ABS(-3) AS NUMBER) AS value",
    ] {
    let original = local_explicit_cast_original(text~)
    let issued = local_checked_expression_normalization(original)
    assert_true(
      restore_prepared_client_local_normalization(
        original, issued, local_checked_expression_journal, local_checked_expression_catalog_cid,
      )
      is Ok(_),
    )
  }
}

///|
test "checked scalars retain actual Parameter origin and use the same catalog with explicit CAST" {
  let declarations = "{\"value\":{\"type\":\"number\",\"nullable\":false,\"default\":-3}}"
  let text = "SELECT ABS(CAST(@value AS NUMBER)) AS magnitude"
  for format in [@source_frontend.Sql, @source_frontend.Text] {
    let supplied = local_supplied_parameter_preparation(
      format,
      declarations,
      Some("{\"value\":-3}"),
      text~,
    )
    let issued = local_checked_expression_normalization(supplied)
    let defaulted = local_supplied_parameter_preparation(
      format,
      declarations,
      None,
      text~,
    )
    assert_eq(
      local_parameter_values_identity(supplied),
      local_parameter_values_identity(defaulted),
    )
    assert_true(
      issue_prepared_client_local_normalization(defaulted)
      is Err(Inventory(ProfileNotInstalled)),
    )
    assert_true(defaulted.local_normalization is None)
    assert_true(
      prepared_client_local_normalization_evidence(defaulted, issued)
      is Err(ForeignPreparation),
    )
  }
}

///|
test "a supported scalar never hides implicit completion or uninstalled relation operations" {
  let implicit_else = local_explicit_cast_original(
    text="SELECT CASE WHEN TRUE THEN ABS(-3) END AS value",
  )
  assert_true(
    issue_prepared_client_local_normalization(implicit_else)
    is Err(Inventory(CompletionObserved)),
  )
  assert_true(implicit_else.local_normalization is None)
  let uncovered_relation = local_explicit_cast_original(
    text="SELECT DISTINCT ABS(-3) AS value",
  )
  assert_true(
    issue_prepared_client_local_normalization(uncovered_relation)
    is Err(Inventory(ProfileNotInstalled)),
  )
  assert_true(uncovered_relation.local_normalization is None)
}

///|
test "checked-expression evidence retains original custody and rejects prior catalog substitution" {
  let original = local_explicit_cast_original(
    text="SELECT ABS(-3) AS magnitude",
  )
  let issued = local_checked_expression_normalization(original)
  let equal_input = local_explicit_cast_original(
    text="SELECT ABS(-3) AS magnitude",
  )
  assert_true(
    prepared_client_local_normalization_evidence(equal_input, issued)
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
  for
    old in [
      client_local_completion_free_catalog_cid(),
      "sha256:105e716b0494553cf970393a550ece0553787fb1967ee01f245ea607b03d0fe1",
      "sha256:538424f689566bf75ba8e9e20241aad4bea6acdeccf301216bcd3dc64036ad49",
      "sha256:0eebf603b459361c55386c3863c0fc6e3928cdae2def8aeca899272b3ecade47",
    ] {
    assert_true(
      restore_prepared_client_local_normalization(
        original, issued, local_checked_expression_journal, old,
      )
      is Err(ForeignCatalog),
    )
  }
  assert_true(
    restore_prepared_client_local_normalization(
      original,
      issued,
      local_checked_expression_journal.replace(
        old="\"entries\":[]",
        new="\"entries\":[{}]",
      ),
      local_checked_expression_catalog_cid,
    )
    is Err(SubstitutedJournal),
  )
}

///|
test "normalization evidence neither eagerly evaluates lazy children nor suppresses demanded arithmetic failure" {
  let selected = local_explicit_cast_original(
    text="SELECT CASE WHEN TRUE THEN ABS(-3) ELSE SQRT(-1) END AS value",
  )
  ignore(local_checked_expression_normalization(selected))
  let task = @strategy.graph_task_owner(selected.graph, 0).unwrap()
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
    @execution.completed_cell(output, 0, 0) is Some(Number(value)) &&
    value == 3.0,
  )
  let demanded = local_explicit_cast_original(text="SELECT ABS(1 / 0) AS value")
  ignore(local_checked_expression_normalization(demanded))
  let task = @strategy.graph_task_owner(demanded.graph, 0).unwrap()
  let sequence = @lower.prepare_sequence(task, run_materials_limits().sequence).unwrap()
  assert_true(
    @execution.execute_generated_sequence(
      local_explicit_cast_generated(sequence),
      [],
      string_try_number_execution_limits(),
    )
    is Err(_),
  )
}
