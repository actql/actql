// Legacy catalogue compatibility cases retain the original recipe issuer.

///|
let local_distinct_catalog_cid : String = "sha256:4cbc2466af84dc925b7e79c91c0a7a19a2a16873bb6e7975e8f6855a954831d8"

///|
let local_distinct_expected_journal : String =
  #|{"entries":[],"journal_cid":"sha256:ddf6bca88c86504be01ba9c34baa5391d8cea27028475268c24ef2b3fdce0031","rule_catalog_cid":"sha256:4cbc2466af84dc925b7e79c91c0a7a19a2a16873bb6e7975e8f6855a954831d8","version":"actql-normalization-journal/0.1"}

///|
fn local_distinct_normalization(
  owner : PreparedClientProgram,
) -> ClientLocalNormalization raise {
  let proof = _issue_prepared_client_legacy_local_normalization(owner).unwrap()
  assert_eq(
    local_normalization_catalog_cid(proof.audit),
    local_distinct_catalog_cid,
  )
  guard proof.audit is CompletionFree(inventory) else {
    fail("completion-free original DISTINCT expected")
  }
  assert_true(@checked.local_completion_free_inventory_uses_distinct(inventory))
  assert_eq(
    @publication.run_evidence_value_json(
      prepared_client_local_normalization_evidence(owner, proof).unwrap(),
    ),
    local_distinct_expected_journal,
  )
  proof
}

///|
fn local_distinct_execute(
  owner : PreparedClientProgram,
) -> @execution.CompletedOutput raise {
  let task = @strategy.graph_task_owner(owner.graph, 0).unwrap()
  let sequence = @lower.prepare_sequence(task, run_materials_limits().sequence).unwrap()
  let completed = @execution.execute_generated_sequence(
    local_group_generated(sequence),
    [],
    string_try_number_execution_limits(),
  ).unwrap()
  @execution.completed_output(
    completed,
    @pipeline.Step(@lower.sequence_count(sequence) - 1),
  ).unwrap()
}

///|
test "original public DISTINCT and its Group combination normalize through existing execution" {
  for text in ["SELECT DISTINCT 1 AS n", "SELECT DISTINCT COUNT(*) AS n"] {
    let owner = local_explicit_cast_original(text~)
    ignore(local_distinct_normalization(owner))
    let output = local_distinct_execute(owner)
    assert_eq(@execution.completed_row_count(output), 1)
    assert_eq(@execution.completed_column_name(output, 0), Some("n"))
    assert_true(
      @execution.completed_cell(output, 0, 0) is Some(Number(value)) &&
      value == 1.0,
    )
  }
}

///|
fn local_distinct_rows(body : String) -> PreparedClientProgram raise {
  let fields = if body == "true" { "[\"id\",\"other\"]" } else { "[\"id\"]" }
  let document = "{\"version\":\"actql/0.1\",\"id\":\"local.distinct\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"int64\",\"nullable\":true},\"other\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":\"9223372036854775807\",\"other\":2},{\"id\":\"9223372036854775807\",\"other\":2},{\"id\":null,\"other\":1},{\"id\":null,\"other\":1}]},\"as\":\"input\"},{\"distinct\":" +
    body +
    ",\"as\":\"selected\"}],\"results\":{\"rows\":{\"from\":\"selected\",\"fields\":" +
    fields +
    "}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}"
  local_group_original_document(document)
}

///|
test "whole and keyed DISTINCT preserve exact int64 NULL and first occurrence without inventing order" {
  for body in ["true", "[\"id\"]"] {
    let owner = local_distinct_rows(body)
    ignore(local_distinct_normalization(owner))
    let output = local_distinct_execute(owner)
    assert_eq(@execution.completed_row_count(output), 2)
    assert_true(
      @execution.completed_cell(output, 0, 0)
      is Some(Captured(Signed64(9223372036854775807L))),
    )
    assert_true(@execution.completed_cell(output, 1, 0) is Some(Null))
    assert_eq(
      @execution.completed_column_count(output),
      if body == "true" {
        2
      } else {
        1
      },
    )
  }
}

///|
test "DISTINCT journal restores only its original preparation and catalogue" {
  let owner = local_explicit_cast_original(text="SELECT DISTINCT 1 AS n")
  let proof = local_distinct_normalization(owner)
  let foreign = local_explicit_cast_original(text="SELECT DISTINCT 1 AS n")
  assert_true(
    prepared_client_local_normalization_evidence(foreign, proof)
    is Err(ForeignPreparation),
  )
  let copy : ClientLocalNormalization = {
    preparation: proof.preparation,
    audit: proof.audit,
    evidence: proof.evidence,
  }
  assert_true(
    prepared_client_local_normalization_evidence(owner, copy)
    is Err(ForeignPreparation),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      owner, proof, local_distinct_expected_journal, local_distinct_catalog_cid,
    )
    is Ok(_),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      owner, proof, local_distinct_expected_journal, local_group_catalog_cid,
    )
    is Err(ForeignCatalog),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      owner, proof, local_group_journal, local_distinct_catalog_cid,
    )
    is Err(SubstitutedJournal),
  )
}

///|
test "DISTINCT plus actual Sort completion retains the original nonempty journal" {
  let base = local_completed_sort_original()
  let source =
    #|{"version":"actql/0.1","id":"local.distinct-sort","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"key":{"type":"string","nullable":false}},"rows":[{"key":"b"},{"key":"a"}]},"as":"input"},{"group":{"by":["key"],"aggregates":{"n":{"fn":"count"}}}},{"distinct":true},{"sort":[{"field":"n","dir":"asc","nulls":"last"}],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["key","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let owner = local_group_original_document(source)
  let proof = _issue_prepared_client_legacy_local_normalization(owner).unwrap()
  guard proof.audit is SortCompletion(inventory) else {
    fail("actual Sort completion expected")
  }
  assert_eq(@checked.local_sort_normalization_entry_count(inventory), 1)
  assert_true(
    @checked.local_sort_normalization_inventory_uses_distinct(inventory),
  )
  assert_eq(
    local_normalization_catalog_cid(proof.audit),
    local_distinct_catalog_cid,
  )
  assert_true(
    restore_prepared_client_local_normalization(
      owner, proof, local_distinct_expected_journal, local_distinct_catalog_cid,
    )
    is Err(SubstitutedJournal),
  )
  let wire = @publication.run_evidence_value_json(
    prepared_client_local_normalization_evidence(owner, proof).unwrap(),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      owner, proof, wire, local_distinct_catalog_cid,
    )
    is Ok(_),
  )
  assert_eq(@execution.completed_row_count(local_distinct_execute(owner)), 2)
  assert_eq(
    local_normalization_catalog_cid(
      _issue_prepared_client_legacy_local_normalization(base).unwrap().audit,
    ),
    "sha256:43da977432e59fa094193c21ef4a11ba10de94f54400ef2576d6293b12500a57",
  )
}
