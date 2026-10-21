// Legacy catalogue compatibility cases retain the original recipe issuer.

///|
let local_completed_sort_expected_journal : String =
  #|{"entries":[{"authored":"[{\"dir\":\"asc\",\"field\":\"n\",\"nulls\":\"last\"}]","canonical":"[{\"dir\":\"asc\",\"field\":\"n\",\"nulls\":\"last\"},{\"dir\":\"asc\",\"field\":\"key\",\"nulls\":\"last\"}]","path":"$.stages[0].steps[2].sort","rule":"sort.candidate_key_completion"}],"journal_cid":"sha256:e4285d4c0c7eab9889e52a5d3774575846c7dd2ddf221f2e41ff8a95786f0847","rule_catalog_cid":"sha256:43da977432e59fa094193c21ef4a11ba10de94f54400ef2576d6293b12500a57","version":"actql-normalization-journal/0.1"}

///|
fn local_completed_sort_original() -> PreparedClientProgram raise {
  let document =
    #|{"version":"actql/0.1","id":"local.completed-sort","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"key":{"type":"string","nullable":false}},"rows":[{"key":"b"},{"key":"a"}]},"as":"input"},{"group":{"by":["key"],"aggregates":{"n":{"fn":"count"}}}},{"sort":[{"field":"n","dir":"asc","nulls":"last"}],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["key","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  local_group_original_document(document)
}

///|
test "actual Group Sort completion issues the independent journal and refuses empty evidence" {
  let original = local_completed_sort_original()
  let proof = issue_prepared_client_legacy_local_normalization(original).unwrap()
  guard proof.audit is SortCompletion(inventory) else {
    fail("actual completion inventory expected")
  }
  assert_eq(@checked.local_sort_normalization_entry_count(inventory), 1)
  let wire = @publication.run_evidence_value_json(
    prepared_client_local_normalization_evidence(original, proof).unwrap(),
  )
  assert_eq(wire, local_completed_sort_expected_journal)
  assert_true(
    physical_equal(
      proof,
      issue_prepared_client_legacy_local_normalization(original).unwrap(),
    ),
  )
  let catalog = local_normalization_catalog_cid(proof.audit)
  let empty = @publication.seal_run_evidence_value(
    "normalization_journal",
    "{\"entries\":[],\"rule_catalog_cid\":\"" +
    catalog +
    "\",\"version\":\"actql-normalization-journal/0.1\"}",
    1024,
    32,
    8,
  ).unwrap()
  assert_true(
    restore_prepared_client_local_normalization(
      original,
      proof,
      @publication.run_evidence_value_json(empty),
      catalog,
    )
    is Err(SubstitutedJournal),
  )
  assert_true(
    restore_prepared_client_local_normalization(original, proof, wire, catalog)
    is Ok(_),
  )
  let foreign = local_completed_sort_original()
  assert_true(
    prepared_client_local_normalization_evidence(foreign, proof)
    is Err(ForeignPreparation),
  )
  let copied = { ..original, }
  assert_true(
    prepared_client_local_normalization_evidence(copied, proof)
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
  assert_eq(@execution.completed_row_count(output), 2)
  assert_true(@execution.completed_cell(output, 0, 0) is Some(Text("a")))
  assert_true(@execution.completed_cell(output, 1, 0) is Some(Text("b")))
}

///|
test "the original public grouped ORDER BY query retains the actual completion through execution" {
  let original = local_explicit_cast_original(
    text="SELECT 1 AS k, COUNT(*) AS n GROUP BY k ORDER BY n ASC NULLS FIRST LIMIT 1",
  )
  let proof = issue_prepared_client_legacy_local_normalization(original).unwrap()
  guard proof.audit is SortCompletion(inventory) else {
    fail("actual public completion expected")
  }
  assert_eq(@checked.local_sort_normalization_entry_count(inventory), 1)
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
  for field in 0..<2 {
    assert_true(
      @execution.completed_cell(output, 0, field) is Some(Number(value)) &&
      value == 1.0,
    )
  }
}

///|
test "two original Sort occurrences journal in UTF16 path order rather than execution order" {
  let document =
    #|{"version":"actql/0.1","id":"local.two-sort-occurrences","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"key":{"type":"string","nullable":false}},"rows":[{"key":"b"},{"key":"a"}]},"as":"input"},{"group":{"by":["key"],"aggregates":{"n":{"fn":"count"}}}},{"sort":[{"field":"n","dir":"asc","nulls":"last"}],"as":"first"},{"sort":[]},{"sort":[]},{"sort":[]},{"sort":[]},{"sort":[]},{"sort":[]},{"sort":[]},{"sort":[{"field":"n","dir":"desc","nulls":"first"}],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["key","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let original = local_group_original_document(document)
  let proof = issue_prepared_client_legacy_local_normalization(original).unwrap()
  guard proof.audit is SortCompletion(inventory) else {
    fail("actual two-entry inventory expected")
  }
  assert_eq(@checked.local_sort_normalization_entry_count(inventory), 2)
  let expected =
    #|{"entries":[{"authored":"[{\"dir\":\"desc\",\"field\":\"n\",\"nulls\":\"first\"}]","canonical":"[{\"dir\":\"desc\",\"field\":\"n\",\"nulls\":\"first\"},{\"dir\":\"asc\",\"field\":\"key\",\"nulls\":\"last\"}]","path":"$.stages[0].steps[10].sort","rule":"sort.candidate_key_completion"},{"authored":"[{\"dir\":\"asc\",\"field\":\"n\",\"nulls\":\"last\"}]","canonical":"[{\"dir\":\"asc\",\"field\":\"n\",\"nulls\":\"last\"},{\"dir\":\"asc\",\"field\":\"key\",\"nulls\":\"last\"}]","path":"$.stages[0].steps[2].sort","rule":"sort.candidate_key_completion"}],"journal_cid":"sha256:ebaa2edd214854c79bb1e5ebaccc4e0733b76eb0f292e7d9a6414f8bfcfb08d9","rule_catalog_cid":"sha256:43da977432e59fa094193c21ef4a11ba10de94f54400ef2576d6293b12500a57","version":"actql-normalization-journal/0.1"}
  assert_eq(
    @publication.run_evidence_value_json(
      prepared_client_local_normalization_evidence(original, proof).unwrap(),
    ),
    expected,
  )
}

///|
test "a journal exceeding original limits refuses atomically without an empty fallback" {
  let document =
    #|{"version":"actql/0.1","id":"local.three-sort-limit","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"key":{"type":"string","nullable":false}},"rows":[{"key":"b"},{"key":"a"}]},"as":"input"},{"group":{"by":["key"],"aggregates":{"n":{"fn":"count"}}}},{"sort":[{"field":"n","dir":"asc","nulls":"last"}],"as":"first"},{"sort":[{"field":"n","dir":"asc","nulls":"last"}],"as":"second"},{"sort":[{"field":"n","dir":"asc","nulls":"last"}],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["key","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let original = local_group_original_document(document)
  let inventory = @checked.local_program_sort_normalization_inventory(
      @strategy.graph_program(original.graph),
    )
    .unwrap()
    .unwrap()
  assert_eq(@checked.local_sort_normalization_entry_count(inventory), 3)
  assert_true(
    issue_prepared_client_legacy_local_normalization(original)
    is Err(Evidence(_)),
  )
  assert_true(original.local_normalization is None)
}
