// Legacy catalogue compatibility cases retain the original recipe issuer.

///|
let local_sort_catalog_cid : String = "sha256:aa08e331a77f389359583e74ce6d7c801ad76a21d13520e55571f71a237ff24e"

///|
let local_sort_journal : String =
  #|{"entries":[],"journal_cid":"sha256:288f55dc38776acf2f073c2ddbaaaa563dd95ad717157dc845274ad0c3ad86de","rule_catalog_cid":"sha256:aa08e331a77f389359583e74ce6d7c801ad76a21d13520e55571f71a237ff24e","version":"actql-normalization-journal/0.1"}

///|
fn local_sort_normalization(
  owner : PreparedClientProgram,
) -> ClientLocalNormalization raise {
  let issued = _issue_prepared_client_legacy_local_normalization(owner).unwrap()
  assert_true(
    @checked.local_completion_free_inventory_uses_sort(
      match issued.audit {
        CompletionFree(value) => value
        SortCompletion(_) | Common(_) =>
          fail("completion-free legacy original expected")
      },
    ),
  )
  assert_eq(
    @publication.run_evidence_value_json(
      prepared_client_local_normalization_evidence(owner, issued).unwrap(),
    ),
    local_sort_journal,
  )
  issued
}

///|
test "original public COUNT ORDER BY LIMIT resolves the covered singleton key" {
  for
    (text, expected) in [
      ("SELECT COUNT(*) AS n ORDER BY n ASC NULLS FIRST LIMIT 1", 1.0),
      (
        "SELECT MIN(ABS(CAST(-3 AS NUMBER))) AS lo ORDER BY lo DESC NULLS LAST",
        3.0,
      ),
    ] {
    let original = local_explicit_cast_original(text~)
    ignore(local_sort_normalization(original))
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
    assert_eq(@execution.completed_row_count(output), 1)
    assert_true(
      @execution.completed_cell(output, 0, 0) is Some(Number(v)) &&
      v == expected,
    )
  }
  let declarations = "{\"count\":{\"type\":\"int64\",\"nullable\":false}}"
  ignore(
    local_sort_normalization(
      local_supplied_parameter_preparation(
        @source_frontend.Sql,
        declarations,
        Some("{\"count\":\"1\"}"),
        text="SELECT COUNT(*) AS n ORDER BY n DESC NULLS LAST LIMIT @count",
      ),
    ),
  )
}

///|
test "original Group key ordering composes with Take on multiple actual rows" {
  let document =
    #|{"version":"actql/0.1","id":"local.ordered","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"key":{"type":"string","nullable":false}},"rows":[{"key":"c"},{"key":"a"},{"key":"b"},{"key":"a"}]},"as":"input"},{"group":{"by":["key"],"aggregates":{"n":{"fn":"count"}}}},{"sort":[{"field":"key","dir":"asc","nulls":"first"}]},{"take":2,"as":"selected"}],"results":{"rows":{"from":"selected","fields":["key","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let original = local_group_original_document(document)
  ignore(local_sort_normalization(original))
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
  assert_true(
    @execution.completed_cell(output, 0, 1) is Some(Number(v)) && v == 2.0,
  )
  assert_true(
    @execution.completed_cell(output, 1, 1) is Some(Number(v)) && v == 1.0,
  )
}

///|
test "actual appended Group identity still refuses the completion-free inventory" {
  let document =
    #|{"version":"actql/0.1","id":"local.completed-sort","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"key":{"type":"string","nullable":false}},"rows":[{"key":"a"},{"key":"b"}]},"as":"input"},{"group":{"by":["key"],"aggregates":{"n":{"fn":"count"}}}},{"sort":[{"field":"n","dir":"asc","nulls":"last"}],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["key","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let original = local_group_original_document(document)
  let pipeline = @checked.unit_pipeline(
    @strategy.graph_program(original.graph),
    0,
  ).unwrap()
  let order = @pipeline.sort_order(pipeline, 2).unwrap()
  guard @pipeline.sort_order_strategy(order) is CandidateKey(completion) else {
    fail("actual candidate-key completion expected")
  }
  assert_eq(@pipeline.sort_completion_count(completion), 1)
  assert_true(
    @checked.local_program_completion_free_inventory(
      @strategy.graph_program(original.graph),
    )
    is Err(CompletionObserved),
  )
  assert_true(original.local_normalization is None)
}

///|
test "stable original Values order retains null placement and ties without inventing a key" {
  let document =
    #|{"version":"actql/0.1","id":"local.stable","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"n":{"type":"number","nullable":true}},"rows":[{"id":3,"n":null},{"id":2,"n":1},{"id":1,"n":1}]},"as":"input"},{"sort":[{"field":"n","dir":"asc","nulls":"first"}],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let original = local_group_original_document(document)
  ignore(local_sort_normalization(original))
  let task = @strategy.graph_task_owner(original.graph, 0).unwrap()
  let pipeline = @checked.unit_pipeline(
    @strategy.graph_program(original.graph),
    0,
  ).unwrap()
  let sort = @pipeline.sort_order(pipeline, 1).unwrap()
  guard @pipeline.sort_order_strategy(sort) is ExistingTotal(prior) else {
    fail("original total order expected")
  }
  let order = @pipeline.sort_order_evidence(sort)
  assert_eq(@pipeline.order_origin(order), @pipeline.Step(1))
  assert_eq(@pipeline.order_dependency_count(order), 1)
  assert_eq(
    @pipeline.order_dependency_at(order, 0),
    Some(@pipeline.sort_order_input(sort)),
  )
  assert_true(physical_equal(@pipeline.order_tie_break(order).unwrap(), prior))
  assert_false(physical_equal(order, prior))
  guard @pipeline.order_producer(order).unwrap().operation
    is @pipeline.Unary(producer) &&
    @pipeline.sort_order_consumer(sort).operation
    is @pipeline.Unary(original_sort) else {
    fail("original Sort producer expected")
  }
  assert_true(physical_equal(producer, original_sort))
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
  assert_eq(@execution.completed_row_count(output), 3)
  for (index, expected) in [(0, 3.0), (1, 2.0), (2, 1.0)] {
    assert_true(
      @execution.completed_cell(output, index, 0) is Some(Number(value)) &&
      value == expected,
    )
  }
}

///|
test "empty Sort retains its authored operation and original row order" {
  let document =
    #|{"version":"actql/0.1","id":"local.empty-sort","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"n":{"type":"number","nullable":false}},"rows":[{"n":2},{"n":1}]},"as":"input"},{"sort":[],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let original = local_group_original_document(document)
  ignore(local_sort_normalization(original))
  let task = @strategy.graph_task_owner(original.graph, 0).unwrap()
  let sequence = @lower.prepare_sequence(task, run_materials_limits().sequence).unwrap()
  assert_eq(@lower.sequence_count(sequence), 2)
  let completed = @execution.execute_generated_sequence(
    local_group_generated(sequence),
    [],
    string_try_number_execution_limits(),
  ).unwrap()
  let output = @execution.completed_output(completed, @pipeline.Step(1)).unwrap()
  assert_true(
    @execution.completed_cell(output, 0, 0) is Some(Number(v)) && v == 2.0,
  )
  assert_true(
    @execution.completed_cell(output, 1, 0) is Some(Number(v)) && v == 1.0,
  )
}

///|
test "normalization rejects foreign copied and predecessor order evidence" {
  let original = local_explicit_cast_original(
    text="SELECT COUNT(*) AS n ORDER BY n",
  )
  let issued = local_sort_normalization(original)
  let equal_original = local_explicit_cast_original(
    text="SELECT COUNT(*) AS n ORDER BY n",
  )
  assert_true(
    prepared_client_local_normalization_evidence(equal_original, issued)
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
      original, issued, local_take_journal, local_take_catalog_cid,
    )
    is Err(ForeignCatalog),
  )
  let changed = local_sort_journal.replace(
    old=local_sort_catalog_cid,
    new=local_take_catalog_cid,
  )
  assert_true(
    restore_prepared_client_local_normalization(
      original, issued, changed, local_sort_catalog_cid,
    )
    is Err(SubstitutedJournal),
  )
}
