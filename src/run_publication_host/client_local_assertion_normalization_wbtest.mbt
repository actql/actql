// Legacy catalogue compatibility cases retain the original recipe issuer.

///|
let local_assertion_expected_journal : String =
  #|{"entries":[],"journal_cid":"sha256:e3e2382ee9dce9ee95db74345b92e38779780c8cc7bff164c463d2f42d659a41","rule_catalog_cid":"sha256:108f657d51073d968109ff5d4e993503d0f0a3604aa13db8cfefca3239c6c5dc","version":"actql-normalization-journal/0.1"}

///|
fn local_assertion_document(
  rows : String,
  body : String,
  suffix? : String = "",
) -> PreparedClientProgram raise {
  local_group_original_document(
    "{\"version\":\"actql/0.1\",\"id\":\"local.original-assertion\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"int64\",\"nullable\":true},\"ok\":{\"type\":\"boolean\",\"nullable\":true}},\"rows\":" +
    rows +
    "},\"as\":\"input\"},{\"assert_rows\":" +
    body +
    ",\"as\":\"asserted\"}" +
    suffix +
    "],\"results\":{\"rows\":{\"from\":\"asserted\",\"fields\":[\"id\",\"ok\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
  )
}

///|
fn local_assertion_execute(
  owner : PreparedClientProgram,
) -> Result[@execution.CompletedSequence, @execution.SequenceRunIssue] {
  let task = @strategy.graph_task_owner(owner.graph, 0).unwrap()
  let sequence = @lower.prepare_sequence(task, run_materials_limits().sequence).unwrap()
  @execution.execute_generated_sequence(
    local_group_generated(sequence),
    [],
    string_try_number_execution_limits(),
  ) catch {
    _ => abort("assertion context construction")
  }
}

///|
test "documented public ASSERT UNIQUE BY normalizes through the original checked operation" {
  let owner = local_explicit_cast_original(
    text="SELECT ABS(-1) AS id |> ASSERT UNIQUE BY (id)",
  )
  let proof = _issue_prepared_client_legacy_local_normalization(owner).unwrap()
  assert_eq(
    local_normalization_catalog_cid(proof.audit),
    local_assertion_catalog_cid(),
  )
  assert_eq(
    @publication.run_evidence_value_json(
      prepared_client_local_normalization_evidence(owner, proof).unwrap(),
    ),
    local_assertion_expected_journal,
  )
  let output = local_distinct_execute(owner)
  assert_eq(@execution.completed_row_count(output), 1)
  assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(1.0)))
}

///|
test "original assertions preserve full int64 row order nullable schema and empty extent" {
  let rows = "[{\"id\":\"9223372036854775807\",\"ok\":true},{\"id\":\"-9223372036854775808\",\"ok\":true}]"
  for body in ["{\"where\":\"ok\"}", "{\"unique_by\":[\"id\"]}"] {
    let owner = local_assertion_document(rows, body)
    let proof = _issue_prepared_client_legacy_local_normalization(owner).unwrap()
    guard proof.audit is CompletionFree(inventory) else {
      fail("fixed assertion is not Source completion")
    }
    assert_true(
      @checked.local_completion_free_inventory_uses_assertions(inventory),
    )
    let output = local_distinct_execute(owner)
    assert_eq(@execution.completed_row_count(output), 2)
    assert_true(
      @execution.completed_cell(output, 0, 0)
      is Some(Captured(Signed64(9223372036854775807L))),
    )
    assert_true(
      @execution.completed_cell(output, 1, 0)
      is Some(Captured(Signed64(-9223372036854775808L))),
    )
    let empty = local_assertion_document("[]", body)
    ignore(_issue_prepared_client_legacy_local_normalization(empty).unwrap())
    assert_eq(@execution.completed_row_count(local_distinct_execute(empty)), 0)
  }
}

///|
test "normalization never establishes unique success for duplicate or NULL keys" {
  let duplicate = local_assertion_document(
    "[{\"id\":\"9007199254740993\",\"ok\":true},{\"id\":\"9007199254740993\",\"ok\":true}]",
    "{\"unique_by\":[\"id\"]}",
  )
  ignore(_issue_prepared_client_legacy_local_normalization(duplicate).unwrap())
  assert_true(
    local_assertion_execute(duplicate) is Err(Rows(_, AssertionDuplicate(0, 1))),
  )
  let nullable = local_assertion_document(
    "[{\"id\":\"9007199254740993\",\"ok\":true},{\"id\":null,\"ok\":true}]", "{\"unique_by\":[\"id\"]}",
  )
  ignore(_issue_prepared_client_legacy_local_normalization(nullable).unwrap())
  assert_true(
    local_assertion_execute(nullable) is Err(Rows(_, AssertionNullKey(1, 0))),
  )
}

///|
test "normalization never turns false or unknown assertion rows into filtering" {
  for value in ["false", "null"] {
    let owner = local_assertion_document(
      "[{\"id\":\"1\",\"ok\":true},{\"id\":\"2\",\"ok\":" + value + "}]",
      "{\"where\":\"ok\"}",
    )
    ignore(_issue_prepared_client_legacy_local_normalization(owner).unwrap())
    assert_true(
      local_assertion_execute(owner) is Err(Rows(_, AssertionPredicate(1))),
    )
  }
}

///|
test "assertion evidence keeps original preparation and rejects equal copies and old catalogue" {
  let owner = local_assertion_document(
    "[{\"id\":\"1\",\"ok\":true}]", "{\"unique_by\":[\"id\"]}",
  )
  let equal = local_assertion_document(
    "[{\"id\":\"1\",\"ok\":true}]", "{\"unique_by\":[\"id\"]}",
  )
  let proof = _issue_prepared_client_legacy_local_normalization(owner).unwrap()
  assert_true(
    prepared_client_local_normalization_evidence(equal, proof)
    is Err(ForeignPreparation),
  )
  assert_true(
    prepared_client_local_normalization_evidence({ ..owner, }, proof)
    is Err(ForeignPreparation),
  )
  assert_true(
    prepared_client_local_normalization_evidence(owner, { ..proof, })
    is Err(ForeignPreparation),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      owner,
      proof,
      local_assertion_expected_journal,
      local_assertion_catalog_cid(),
    )
    is Ok(_),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      owner,
      proof,
      local_dedupe_expected_empty_journal,
      local_dedupe_catalog_cid(),
    )
    is Err(ForeignCatalog),
  )
}

///|
test "assertion catalogue retains actual projection completion and its owned path" {
  let owner = local_group_original_document(
    (
      #|{"version":"actql/0.1","id":"local.assertion-projection","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"int64","nullable":true},"ok":{"type":"boolean","nullable":true}},"rows":[{"id":"1","ok":true}]},"as":"input"},{"assert_rows":{"unique_by":["id"]}},{"drop":["ok"],"as":"projected"}],"results":{"rows":{"from":"projected","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
  )
  let proof = _issue_prepared_client_legacy_local_normalization(owner).unwrap()
  guard proof.audit is SortCompletion(inventory) else {
    fail("actual Drop expansion is not empty evidence")
  }
  assert_true(
    @checked.local_sort_normalization_inventory_uses_assertions(inventory),
  )
  assert_eq(@checked.local_sort_normalization_entry_count(inventory), 1)
  assert_eq(
    @checked.local_sort_normalization_entry_rule_at(inventory, 0),
    Some("relation.drop_projection"),
  )
  let (path, _, _) = @checked.local_sort_normalization_entry_at(inventory, 0).unwrap()
  assert_eq(path, "$.stages[0].steps[2].drop")
  assert_eq(
    local_normalization_catalog_cid(proof.audit),
    local_assertion_catalog_cid(),
  )
  assert_true(
    @publication.run_evidence_value_json(
      prepared_client_local_normalization_evidence(owner, proof).unwrap(),
    ) !=
    local_assertion_expected_journal,
  )
  let output = local_distinct_execute(owner)
  assert_eq(@execution.completed_column_count(output), 1)
  assert_eq(@execution.completed_row_count(output), 1)
  assert_true(
    @execution.completed_cell(output, 0, 0) is Some(Captured(Signed64(1L))),
  )
}

///|
test "original Default and Supplied values compose with Set Dedupe and unique assertion" {
  let document =
    #|{"version":"actql/0.1","id":"local.default-set-dedupe-assertion","params":{"id":{"type":"int64","default":"9007199254740993"}},"stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"key":{"type":"string","nullable":false}},"rows":[{"key":"b"}]},"as":"left_values"},{"derive":{"id":{"$param":"id"}},"as":"left"},{"values":{"schema":{"key":{"type":"string","nullable":false}},"rows":[{"key":"a"}]},"as":"right_values"},{"derive":{"id":{"$param":"id"}},"as":"right"},{"from":"left","append":{"with":"right"}},{"dedupe_rows":{"by":["id"],"order_by":[{"field":"key","dir":"asc","nulls":"last"}]}},{"assert_rows":{"unique_by":["id"]},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","key"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let environment = admit_client_check_environment(
    local_normalization_environment_wire,
    "sha256:e3da0e91ef758728bdf6e58957c09fe044d97d1fa2a21c9c19e3bdf5109bf45b",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  for supplied in [None, Some("{\"id\":\"9007199254740993\"}")] {
    let owner = prepare_effect_free_client_program(
      document,
      Json,
      environment,
      supplied.map(scalar_profile_cursor),
      client_standard_program_preparation_limits(),
    ).unwrap()
    let proof = _issue_prepared_client_legacy_local_normalization(owner).unwrap()
    guard proof.audit is CompletionFree(inventory) else {
      fail("fixed operations do not create Source entries")
    }
    assert_true(
      @checked.local_completion_free_inventory_uses_assertions(inventory),
    )
    assert_true(@checked.local_completion_free_inventory_uses_dedupe(inventory))
    assert_true(@checked.local_completion_free_inventory_uses_set(inventory))
    assert_eq(
      @checked.local_completion_free_inventory_parameters_defaulted(inventory),
      supplied is None,
    )
    assert_eq(
      @publication.run_evidence_value_json(
        prepared_client_local_normalization_evidence(owner, proof).unwrap(),
      ),
      local_assertion_expected_journal,
    )
    let output = local_distinct_execute(owner)
    assert_eq(@execution.completed_row_count(output), 1)
    assert_true(
      @execution.completed_cell(output, 0, 0)
      is Some(Captured(Signed64(9007199254740993L))),
    )
    assert_true(@execution.completed_cell(output, 0, 1) is Some(Text("a")))
  }
}
