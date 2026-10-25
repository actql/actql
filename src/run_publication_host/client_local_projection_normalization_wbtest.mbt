// Legacy catalogue compatibility cases retain the original recipe issuer.

///|
fn local_projection_normalized_output(
  owner : PreparedClientProgram,
  field : String,
) -> Unit raise {
  match _issue_prepared_client_legacy_local_normalization(owner) {
    Ok(_) => ()
    Err(Inventory(ProfileNotInstalled)) =>
      fail("original Local inventory: ProfileNotInstalled")
    Err(Inventory(CompletionObserved)) =>
      fail("original Local inventory: CompletionObserved")
    Err(_) => fail("original Local normalization failed outside the inventory")
  }
  let output = local_distinct_execute(owner)
  assert_eq(@execution.completed_row_count(output), 1)
  assert_eq(@execution.completed_column_name(output, 0), Some(field))
  assert_true(
    @execution.completed_cell(output, 0, 0) is Some(Number(value)) &&
    value == 3.0,
  )
}

///|
test "public Pipe DROP retains its original projection normalization" {
  local_projection_normalized_output(
    local_explicit_cast_original(
      text="SELECT ABS(-3) AS id, 2 AS other |> DROP other",
      format=@source_frontend.Text,
    ),
    "id",
  )
}

///|
test "public Pipe RENAME retains its original projection normalization" {
  local_projection_normalized_output(
    local_explicit_cast_original(
      text="SELECT ABS(-3) AS id |> RENAME id AS renamed",
      format=@source_frontend.Text,
    ),
    "renamed",
  )
}

///|
fn local_projection_drop_original() -> PreparedClientProgram raise {
  local_group_original_document(
    (
      #|{"version":"actql/0.1","id":"local.projection-drop","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"other":{"type":"number","nullable":false}},"rows":[{"id":-3,"other":2}]},"as":"input"},{"derive":{"value":"abs(id)"}},{"drop":["id","other"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
  )
}

///|
test "authored AQL DROP retains its original checked projection normalization" {
  local_projection_normalized_output(local_projection_drop_original(), "value")
}

///|
test "authored AQL RENAME retains its original checked projection normalization" {
  let owner = local_group_original_document(
    (
      #|{"version":"actql/0.1","id":"local.projection-rename","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":3}]},"as":"input"},{"rename":{"id":"renamed"},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["renamed"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
  )
  local_projection_normalized_output(owner, "renamed")
}

///|
let local_projection_catalog_cid : String = "sha256:eaaf8fc464b5079e782f5dbcbdd7ef0c8b2934ef0a01c7e465907f8c6f850923"

///|
let local_projection_expected_journal : String =
  #|{"entries":[{"authored":"[\"id\",\"other\"]","canonical":"{\"columns\":[\"value\"]}","path":"$.stages[0].steps[2].drop","rule":"relation.drop_projection"}],"journal_cid":"sha256:2da1ae14420b3f98d3b676f8d403a9bb0ecb5576608720ab3832ad7b32b7b434","rule_catalog_cid":"sha256:eaaf8fc464b5079e782f5dbcbdd7ef0c8b2934ef0a01c7e465907f8c6f850923","version":"actql-normalization-journal/0.1"}

///|
test "projection journal retains exact original path rule and independent canonical bytes" {
  let owner = local_projection_drop_original()
  let proof = _issue_prepared_client_legacy_local_normalization(owner).unwrap()
  guard proof.audit is SortCompletion(inventory) else {
    fail("owned semantic completion inventory expected")
  }
  assert_true(
    @checked.local_sort_normalization_inventory_uses_projection(inventory),
  )
  assert_eq(@checked.local_sort_normalization_entry_count(inventory), 1)
  assert_eq(
    @checked.local_sort_normalization_entry_rule_at(inventory, 0),
    Some("relation.drop_projection"),
  )
  assert_true(@checked.local_sort_normalization_entry_at(inventory, -1) is None)
  assert_true(
    @checked.local_sort_normalization_entry_rule_at(inventory, 1) is None,
  )
  let wire = @publication.run_evidence_value_json(
    prepared_client_local_normalization_evidence(owner, proof).unwrap(),
  )
  assert_eq(wire, local_projection_expected_journal)
  assert_true(
    restore_prepared_client_local_normalization(
      owner, proof, wire, local_projection_catalog_cid,
    )
    is Ok(_),
  )
  assert_true(
    physical_equal(
      proof,
      _issue_prepared_client_legacy_local_normalization(owner).unwrap(),
    ),
  )
}

///|
test "projection journal rejects equal foreign owners copied proofs and substituted evidence" {
  let owner = local_projection_drop_original()
  let proof = _issue_prepared_client_legacy_local_normalization(owner).unwrap()
  let foreign = local_projection_drop_original()
  assert_true(
    prepared_client_local_normalization_evidence(foreign, proof)
    is Err(ForeignPreparation),
  )
  let copied_owner = { ..owner, }
  let copied_proof = { ..proof, }
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
      owner, proof, local_projection_expected_journal, "sha256:a9d402c6c62d80cc8aed4a55d0753acec16dab22e7cd31399f4bc5459a248d45",
    )
    is Err(ForeignCatalog),
  )
  let empty = @publication.seal_run_evidence_value(
    "normalization_journal",
    "{\"entries\":[],\"rule_catalog_cid\":\"" +
    local_projection_catalog_cid +
    "\",\"version\":\"actql-normalization-journal/0.1\"}",
    1024,
    32,
    8,
  ).unwrap()
  assert_true(
    restore_prepared_client_local_normalization(
      owner,
      proof,
      @publication.run_evidence_value_json(empty),
      local_projection_catalog_cid,
    )
    is Err(SubstitutedJournal),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      owner,
      proof,
      local_projection_expected_journal.replace(
        old="relation.drop_projection",
        new="sort.candidate_key_completion",
      ),
      local_projection_catalog_cid,
    )
    is Err(SubstitutedJournal),
  )
}

///|
fn local_projection_identity_original(
  steps : String,
) -> PreparedClientProgram raise {
  local_group_original_document(
    "{\"version\":\"actql/0.1\",\"id\":\"local.projection-identity\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":3}]},\"as\":\"input\"}," +
    steps +
    ",{\"select\":[\"id\"],\"as\":\"selected\"}],\"results\":{\"rows\":{\"from\":\"selected\",\"fields\":[\"id\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
  )
}

///|
test "projection journal keeps authored empty rename and drop as distinct original occurrences" {
  let owner = local_projection_identity_original(
    "{\"rename\":{}},{\"drop\":[]}",
  )
  let proof = _issue_prepared_client_legacy_local_normalization(owner).unwrap()
  guard proof.audit is SortCompletion(inventory) else {
    fail("projection inventory expected")
  }
  assert_eq(@checked.local_sort_normalization_entry_count(inventory), 2)
  assert_eq(
    @checked.local_sort_normalization_entry_at(inventory, 0),
    Some(("$.stages[0].steps[1].rename", "{}", "{\"columns\":[\"id\"]}")),
  )
  assert_eq(
    @checked.local_sort_normalization_entry_at(inventory, 1),
    Some(("$.stages[0].steps[2].drop", "[]", "{\"columns\":[\"id\"]}")),
  )
  assert_eq(
    @checked.local_sort_normalization_entry_rule_at(inventory, 0),
    Some("relation.rename_projection"),
  )
  assert_eq(
    @checked.local_sort_normalization_entry_rule_at(inventory, 1),
    Some("relation.drop_projection"),
  )
  local_projection_normalized_output(owner, "id")
}

///|
test "projection journal preserves actual nonzero Sort completion alongside original projection" {
  let document =
    #|{"version":"actql/0.1","id":"local.projection-sort","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"key":{"type":"string","nullable":false}},"rows":[{"key":"b"},{"key":"a"}]},"as":"input"},{"group":{"by":["key"],"aggregates":{"n":{"fn":"count"}}}},{"drop":[]},{"sort":[{"field":"n","dir":"asc","nulls":"last"}],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["key","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let owner = local_group_original_document(document)
  let proof = _issue_prepared_client_legacy_local_normalization(owner).unwrap()
  guard proof.audit is SortCompletion(inventory) else {
    fail("mixed inventory expected")
  }
  assert_eq(@checked.local_sort_normalization_entry_count(inventory), 2)
  assert_eq(
    @checked.local_sort_normalization_entry_rule_at(inventory, 0),
    Some("relation.drop_projection"),
  )
  assert_eq(
    @checked.local_sort_normalization_entry_rule_at(inventory, 1),
    Some("sort.candidate_key_completion"),
  )
  assert_eq(
    @checked.local_sort_normalization_entry_at(inventory, 1),
    Some(
      (
        "$.stages[0].steps[3].sort", "[{\"dir\":\"asc\",\"field\":\"n\",\"nulls\":\"last\"}]",
        "[{\"dir\":\"asc\",\"field\":\"n\",\"nulls\":\"last\"},{\"dir\":\"asc\",\"field\":\"key\",\"nulls\":\"last\"}]",
      ),
    ),
  )
  let output = local_distinct_execute(owner)
  assert_eq(@execution.completed_row_count(output), 2)
  assert_true(@execution.completed_cell(output, 0, 0) is Some(Text("a")))
  assert_true(@execution.completed_cell(output, 1, 0) is Some(Text("b")))
}

///|
test "projection journal retains repeated authored removals without duplicating logical columns" {
  let base =
    #|{"version":"actql/0.1","id":"local.repeated-drop","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"other":{"type":"number","nullable":false}},"rows":[{"id":3,"other":2}]},"as":"input"},{"drop":["other"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let single = local_group_original_document(base)
  let repeated = local_group_original_document(
    base.replace(old="[\"other\"]", new="[\"other\",\"other\"]"),
  )
  let one = _issue_prepared_client_legacy_local_normalization(single).unwrap()
  let two = _issue_prepared_client_legacy_local_normalization(repeated).unwrap()
  guard two.audit is SortCompletion(inventory) else {
    fail("original repeated removal expected")
  }
  assert_eq(
    @checked.local_sort_normalization_entry_at(inventory, 0),
    Some(
      (
        "$.stages[0].steps[1].drop", "[\"other\",\"other\"]", "{\"columns\":[\"id\"]}",
      ),
    ),
  )
  assert_true(
    @publication.run_evidence_value_json(
      prepared_client_local_normalization_evidence(single, one).unwrap(),
    ) !=
    @publication.run_evidence_value_json(
      prepared_client_local_normalization_evidence(repeated, two).unwrap(),
    ),
  )
  local_projection_normalized_output(single, "id")
  local_projection_normalized_output(repeated, "id")
}

///|
test "projection journal uses original UTF16 schema order for supplementary and BMP names" {
  let document =
    #|{"version":"actql/0.1","id":"local.unicode-rename","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"":{"type":"number","nullable":false},"𐀀":{"type":"number","nullable":false}},"rows":[{"":2,"𐀀":3}]},"as":"input"},{"rename":{"":"bmp","𐀀":"supp"},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["bmp","supp"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let owner = local_group_original_document(document)
  let proof = _issue_prepared_client_legacy_local_normalization(owner).unwrap()
  guard proof.audit is SortCompletion(inventory) else {
    fail("owned Unicode projection expected")
  }
  assert_eq(
    @checked.local_sort_normalization_entry_at(inventory, 0),
    Some(
      (
        "$.stages[0].steps[1].rename", "{\"𐀀\":\"supp\",\"\":\"bmp\"}", "{\"columns\":[{\"from\":\"𐀀\",\"to\":\"supp\"},{\"from\":\"\",\"to\":\"bmp\"}]}",
      ),
    ),
  )
}

///|
test "projection journal refuses original journal limit overflow without an empty fallback" {
  let owner = local_projection_identity_original(
    "{\"drop\":[]},{\"drop\":[]},{\"drop\":[]},{\"drop\":[]},{\"drop\":[]},{\"drop\":[]}",
  )
  let inventory = @checked.local_program_sort_normalization_inventory(
      @strategy.graph_program(owner.graph),
    )
    .unwrap()
    .unwrap()
  assert_eq(@checked.local_sort_normalization_entry_count(inventory), 6)
  assert_true(
    _issue_prepared_client_legacy_local_normalization(owner) is Err(Evidence(_)),
  )
  assert_true(owner.local_normalization is None)
}

///|
test "projection journal keeps original Default and supplied origins despite equal effective values" {
  let declarations = "{\"id\":{\"type\":\"int64\",\"nullable\":false,\"default\":\"9007199254740993\"}}"
  let text = "SELECT @id AS id, 2 AS other |> DROP other"
  let defaulted = local_supplied_parameter_preparation(
    @source_frontend.Text,
    declarations,
    None,
    text~,
  )
  let supplied = local_supplied_parameter_preparation(
    @source_frontend.Text,
    declarations,
    Some("{\"id\":\"9007199254740993\"}"),
    text~,
  )
  let proof = _issue_prepared_client_legacy_local_normalization(defaulted).unwrap()
  let supplied_proof = _issue_prepared_client_legacy_local_normalization(
    supplied,
  ).unwrap()
  guard proof.audit is SortCompletion(inventory) else {
    fail("original Default projection expected")
  }
  assert_true(
    @checked.local_sort_normalization_inventory_parameters_defaulted(inventory),
  )
  assert_eq(@checked.local_sort_normalization_entry_count(inventory), 1)
  assert_eq(
    @checked.local_sort_normalization_entry_rule_at(inventory, 0),
    Some("relation.drop_projection"),
  )
  assert_eq(
    local_parameter_values_identity(defaulted),
    local_parameter_values_identity(supplied),
  )
  assert_eq(
    @publication.run_evidence_value_json(
      prepared_client_local_normalization_evidence(defaulted, proof).unwrap(),
    ),
    @publication.run_evidence_value_json(
      prepared_client_local_normalization_evidence(supplied, supplied_proof).unwrap(),
    ),
  )
  assert_true(
    prepared_client_local_normalization_evidence(supplied, proof)
    is Err(ForeignPreparation),
  )
  let output = local_distinct_execute(defaulted)
  assert_true(
    @execution.completed_cell(output, 0, 0) is Some(Captured(Signed64(value))) &&
    value == 9007199254740993L,
  )
}
