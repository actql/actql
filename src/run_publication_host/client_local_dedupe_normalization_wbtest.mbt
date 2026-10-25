// Legacy catalogue compatibility cases retain the original recipe issuer.

///|
fn local_dedupe_original_document() -> PreparedClientProgram raise {
  local_group_original_document(
    (
      #|{"version":"actql/0.1","id":"local.original-dedupe","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"rank":{"type":"number","nullable":false}},"rows":[{"id":2,"rank":4},{"id":1,"rank":2},{"id":1,"rank":1}]},"as":"input"},{"dedupe_rows":{"by":["id"],"order_by":[{"field":"rank","dir":"asc","nulls":"last"}]},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","rank"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
  )
}

///|
test "public AQL original dedupe uses its stated order and canonical typed group order" {
  let owner = local_dedupe_original_document()
  match _issue_prepared_client_legacy_local_normalization(owner) {
    Ok(_) => ()
    Err(Inventory(ProfileNotInstalled)) =>
      fail("original Local dedupe inventory: ProfileNotInstalled")
    Err(Inventory(CompletionObserved)) =>
      fail("fixed dedupe semantics must not become a Source completion")
    Err(_) =>
      fail("original Local dedupe normalization failed outside inventory")
  }
  let output = local_distinct_execute(owner)
  assert_eq(@execution.completed_row_count(output), 2)
  assert_eq(@execution.completed_column_name(output, 0), Some("id"))
  assert_eq(@execution.completed_column_name(output, 1), Some("rank"))
  for index, expected in [(1.0, 1.0), (2.0, 4.0)] {
    assert_true(
      @execution.completed_cell(output, index, 0) is Some(Number(value)) &&
      value == expected.0,
    )
    assert_true(
      @execution.completed_cell(output, index, 1) is Some(Number(value)) &&
      value == expected.1,
    )
  }
}

///|
let local_dedupe_expected_empty_journal : String =
  #|{"entries":[],"journal_cid":"sha256:5fdf2e0b2801b1c6b2d54bac28adb1d2fff714602b90372aaa15769886c65ec5","rule_catalog_cid":"sha256:0837ef2d59853872ac03acf1ab6cb7351a253377f0cd27b219d3bd94c790191e","version":"actql-normalization-journal/0.1"}

///|
fn local_dedupe_checked_document(
  rows : String,
  by : String,
  after? : String = "",
) -> PreparedClientProgram raise {
  local_group_original_document(
    "{\"version\":\"actql/0.1\",\"id\":\"local.dedupe-domain\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"int64\",\"nullable\":true},\"rank\":{\"type\":\"number\",\"nullable\":false},\"payload\":{\"type\":\"string\",\"nullable\":false}},\"rows\":" +
    rows +
    "},\"as\":\"input\"},{\"dedupe_rows\":{\"by\":" +
    by +
    ",\"order_by\":[{\"field\":\"rank\",\"dir\":\"asc\",\"nulls\":\"last\"},{\"field\":\"rank\",\"dir\":\"asc\",\"nulls\":\"last\"}]}" +
    after +
    ",\"as\":\"selected\"}],\"results\":{\"rows\":{\"from\":\"selected\",\"fields\":[\"id\",\"rank\",\"payload\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
  )
}

///|
test "dedupe nullable full int64 repeated keys and order preserve typed canonical group order" {
  let rows =
    #|[{"id":"9223372036854775807","rank":2,"payload":"later"},{"id":"9223372036854775807","rank":1,"payload":"chosen"},{"id":null,"rank":3,"payload":"null-chosen"}]
  let owner = local_dedupe_checked_document(rows, "[\"id\",\"id\"]")
  let proof = _issue_prepared_client_legacy_local_normalization(owner).unwrap()
  guard proof.audit is CompletionFree(inventory) else {
    fail("fixed dedupe law is not a Source journal completion")
  }
  assert_true(@checked.local_completion_free_inventory_uses_dedupe(inventory))
  assert_eq(
    @publication.run_evidence_value_json(
      prepared_client_local_normalization_evidence(owner, proof).unwrap(),
    ),
    local_dedupe_expected_empty_journal,
  )
  let output = local_distinct_execute(owner)
  assert_eq(@execution.completed_row_count(output), 2)
  assert_true(@execution.completed_cell(output, 0, 0) is Some(Null))
  assert_true(
    @execution.completed_cell(output, 1, 0)
    is Some(Captured(Signed64(9223372036854775807L))),
  )
  assert_eq(@execution.completed_column_name(output, 0), Some("id"))
  assert_eq(@execution.completed_column_name(output, 1), Some("payload"))
  assert_eq(@execution.completed_column_name(output, 2), Some("rank"))
  assert_true(@execution.completed_cell(output, 0, 2) is Some(Number(3.0)))
  assert_true(@execution.completed_cell(output, 1, 2) is Some(Number(1.0)))
  assert_true(
    @execution.completed_cell(output, 0, 1) is Some(Text("null-chosen")),
  )
  assert_true(@execution.completed_cell(output, 1, 1) is Some(Text("chosen")))
  let global = local_dedupe_checked_document(rows, "[]")
  ignore(_issue_prepared_client_legacy_local_normalization(global).unwrap())
  let result = local_distinct_execute(global)
  assert_eq(@execution.completed_row_count(result), 1)
  assert_true(@execution.completed_cell(result, 0, 1) is Some(Text("chosen")))
}

///|
test "empty dedupe global partition has zero survivors not an invented row" {
  for by in ["[]", "[\"id\",\"id\"]"] {
    let owner = local_dedupe_checked_document("[]", by)
    ignore(_issue_prepared_client_legacy_local_normalization(owner).unwrap())
    assert_eq(@execution.completed_row_count(local_distinct_execute(owner)), 0)
  }
}

///|
test "dedupe original normalization does not admit an unresolved identical top tie" {
  let rows =
    #|[{"id":null,"rank":1,"payload":"same"},{"id":null,"rank":1,"payload":"same"}]
  let owner = local_dedupe_checked_document(rows, "[\"id\"]")
  ignore(_issue_prepared_client_legacy_local_normalization(owner).unwrap())
  let task = @strategy.graph_task_owner(owner.graph, 0).unwrap()
  let sequence = @lower.prepare_sequence(task, run_materials_limits().sequence).unwrap()
  assert_true(
    @execution.execute_generated_sequence(
      local_group_generated(sequence),
      [],
      string_try_number_execution_limits(),
    )
    is Err(Rows(_, DedupeTopTie(_, _))),
  )
}

///|
test "dedupe journal retains original preparation and refuses equal copies and old evidence" {
  let owner = local_dedupe_original_document()
  let equal = local_dedupe_original_document()
  let proof = _issue_prepared_client_legacy_local_normalization(owner).unwrap()
  let copied_owner = { ..owner, }
  let copied_proof = { ..proof, }
  assert_true(
    prepared_client_local_normalization_evidence(equal, proof)
    is Err(ForeignPreparation),
  )
  assert_true(
    prepared_client_local_normalization_evidence(copied_owner, proof)
    is Err(ForeignPreparation),
  )
  assert_true(
    prepared_client_local_normalization_evidence(owner, copied_proof)
    is Err(ForeignPreparation),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      owner,
      proof,
      local_dedupe_expected_empty_journal,
      local_dedupe_catalog_cid(),
    )
    is Ok(_),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      owner, proof, local_projection_expected_journal, local_projection_catalog_cid,
    )
    is Err(ForeignCatalog),
  )
  assert_true(
    physical_equal(
      proof,
      _issue_prepared_client_legacy_local_normalization(owner).unwrap(),
    ),
  )
}

///|
test "dedupe preserves the real original projection completion instead of an empty journal" {
  let document =
    #|{"version":"actql/0.1","id":"local.dedupe-drop","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"rank":{"type":"number","nullable":false}},"rows":[{"id":2,"rank":4},{"id":1,"rank":2},{"id":1,"rank":1}]},"as":"input"},{"dedupe_rows":{"by":["id"],"order_by":[{"field":"rank","dir":"asc","nulls":"last"}]}},{"drop":["rank"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let owner = local_group_original_document(document)
  let proof = _issue_prepared_client_legacy_local_normalization(owner).unwrap()
  guard proof.audit is SortCompletion(inventory) else {
    fail("original projection completion expected")
  }
  assert_true(
    @checked.local_sort_normalization_inventory_uses_dedupe(inventory),
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
    local_dedupe_catalog_cid(),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      owner,
      proof,
      local_dedupe_expected_empty_journal,
      local_dedupe_catalog_cid(),
    )
    is Err(SubstitutedJournal),
  )
  assert_eq(@execution.completed_row_count(local_distinct_execute(owner)), 2)
}

///|
test "dedupe preserves actual candidate key Sort completion and its original path" {
  let document =
    #|{"version":"actql/0.1","id":"local.dedupe-sort","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"key":{"type":"string","nullable":false}},"rows":[{"key":"b"},{"key":"a"}]},"as":"input"},{"group":{"by":["key"],"aggregates":{"n":{"fn":"count"}}}},{"dedupe_rows":{"by":["key"],"order_by":[{"field":"n","dir":"asc","nulls":"last"}]}},{"sort":[{"field":"n","dir":"asc","nulls":"last"}],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["key","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let owner = local_group_original_document(document)
  let proof = _issue_prepared_client_legacy_local_normalization(owner).unwrap()
  guard proof.audit is SortCompletion(inventory) else {
    fail("original appended Sort completion expected")
  }
  assert_true(
    @checked.local_sort_normalization_inventory_uses_dedupe(inventory),
  )
  assert_eq(@checked.local_sort_normalization_entry_count(inventory), 1)
  assert_eq(
    @checked.local_sort_normalization_entry_rule_at(inventory, 0),
    Some("sort.candidate_key_completion"),
  )
  let (path, _, _) = @checked.local_sort_normalization_entry_at(inventory, 0).unwrap()
  assert_eq(path, "$.stages[0].steps[3].sort")
  assert_true(
    restore_prepared_client_local_normalization(
      owner,
      proof,
      local_dedupe_expected_empty_journal,
      local_dedupe_catalog_cid(),
    )
    is Err(SubstitutedJournal),
  )
  assert_eq(@execution.completed_row_count(local_distinct_execute(owner)), 2)
}

///|
test "dedupe original Default and Supplied bindings compose with actual Set without a Source entry" {
  let document =
    #|{"version":"actql/0.1","id":"local.default-set-dedupe","params":{"id":{"type":"int64","default":"9007199254740993"}},"stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"key":{"type":"string","nullable":false}},"rows":[{"key":"b"}]},"as":"left_values"},{"derive":{"id":{"$param":"id"}},"as":"left"},{"values":{"schema":{"key":{"type":"string","nullable":false}},"rows":[{"key":"a"}]},"as":"right_values"},{"derive":{"id":{"$param":"id"}},"as":"right"},{"from":"left","append":{"with":"right"}},{"dedupe_rows":{"by":["id"],"order_by":[{"field":"key","dir":"asc","nulls":"last"}]},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","key"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
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
      fail("Default/Set/Dedupe has no Source completion")
    }
    assert_true(@checked.local_completion_free_inventory_uses_dedupe(inventory))
    assert_true(@checked.local_completion_free_inventory_uses_set(inventory))
    assert_eq(
      @checked.local_completion_free_inventory_parameters_defaulted(inventory),
      supplied is None,
    )
    let origin = @parameter.bound_value_at(local_default_bound_values(owner), 0).unwrap().origin
    if supplied is None {
      assert_true(origin is @parameter.Default)
    } else {
      assert_true(origin is @parameter.Supplied)
    }
    assert_eq(
      @publication.run_evidence_value_json(
        prepared_client_local_normalization_evidence(owner, proof).unwrap(),
      ),
      local_dedupe_expected_empty_journal,
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
