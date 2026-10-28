// Legacy catalogue compatibility cases retain the original recipe issuer.

///|
let local_default_parameter_expected_journal : String =
  #|{"entries":[],"journal_cid":"sha256:44e145d70edf8d9e3c00055d5b5dce68a59daa2ab4ca148b48c28ae330533b69","rule_catalog_cid":"sha256:096c228635c4a08bbe7080f3447a9ca35b439fdb5113a17b0cca2b7735a55d2d","version":"actql-normalization-journal/0.1"}

///|
fn local_default_parameter_normalization(
  owner : PreparedClientProgram,
) -> ClientLocalNormalization raise {
  let proof = _issue_prepared_client_legacy_local_normalization(owner).unwrap()
  assert_eq(
    local_normalization_catalog_cid(proof.audit),
    local_default_parameter_catalog_cid(),
  )
  guard proof.audit is CompletionFree(inventory) else {
    fail("original completion-free default binding expected")
  }
  assert_true(
    @checked.local_completion_free_inventory_parameters_defaulted(inventory),
  )
  assert_false(
    @checked.local_completion_free_inventory_parameters_supplied(inventory),
  )
  assert_eq(
    @publication.run_evidence_value_json(
      prepared_client_local_normalization_evidence(owner, proof).unwrap(),
    ),
    local_default_parameter_expected_journal,
  )
  proof
}

///|
fn local_default_bound_values(
  owner : PreparedClientProgram,
) -> @parameter.BoundValues {
  let identity = @checked.source_identity(@strategy.graph_program(owner.graph))
  @parameters.bound_values(
    @context.stage_identity_parameter_values(
      @context.program_identity_stage_at(identity, 0).unwrap(),
    ),
  )
}

///|
test "public SQL and Pipe default Parameters execute exact signed64 original values and overrides" {
  for format in [@source_frontend.Sql, @source_frontend.Text] {
    for
      value in [-9223372036854775808L, 9007199254740993L, 9223372036854775807L] {
      let declarations = "{\"id\":{\"type\":\"int64\",\"nullable\":false,\"default\":\"" +
        value.to_string() +
        "\"}}"
      let defaulted = local_supplied_parameter_preparation(
        format,
        declarations,
        None,
      )
      ignore(local_default_parameter_normalization(defaulted))
      let bindings = local_default_bound_values(defaulted)
      assert_true(
        @parameter.bound_value_at(bindings, 0).unwrap().origin
        is @parameter.Default,
      )
      let output = local_distinct_execute(defaulted)
      assert_eq(@execution.completed_row_count(output), 1)
      assert_true(
        @execution.completed_cell(output, 0, 0)
        is Some(Captured(Signed64(actual))) &&
        actual == value,
      )
      let supplied = local_supplied_parameter_preparation(
        format,
        declarations,
        Some("{\"id\":\"" + value.to_string() + "\"}"),
      )
      assert_eq(
        local_parameter_values_identity(defaulted),
        local_parameter_values_identity(supplied),
      )
      let supplied_bindings = local_default_bound_values(supplied)
      assert_true(
        @parameter.bound_value_at(supplied_bindings, 0).unwrap().origin
        is @parameter.Supplied,
      )
      let replacement = local_supplied_parameter_preparation(
        format,
        declarations,
        Some("{\"id\":\"7\"}"),
      )
      assert_not_eq(
        local_parameter_values_identity(defaulted),
        local_parameter_values_identity(replacement),
      )
      assert_eq(
        local_normalization_catalog_cid(
          _issue_prepared_client_legacy_local_normalization(replacement).unwrap().audit,
        ),
        "sha256:105e716b0494553cf970393a550ece0553787fb1967ee01f245ea607b03d0fe1",
      )
      assert_true(
        @execution.completed_cell(local_distinct_execute(replacement), 0, 0)
        is Some(Captured(Signed64(7L))),
      )
    }
  }
}

///|
test "nullable explicit supplied NULL does not select default and missing or invalid bindings remain refused" {
  let declaration = "{\"id\":{\"type\":\"int64\",\"nullable\":true,\"default\":\"9007199254740993\"}}"
  let defaulted = local_supplied_parameter_preparation(
    @source_frontend.Sql,
    declaration,
    None,
  )
  ignore(local_default_parameter_normalization(defaulted))
  let explicit_null = local_supplied_parameter_preparation(
    @source_frontend.Sql,
    declaration,
    Some("{\"id\":null}"),
  )
  assert_true(
    _issue_prepared_client_legacy_local_normalization(explicit_null) is Ok(_),
  )
  assert_true(
    @parameter.bound_value_at(local_default_bound_values(explicit_null), 0).unwrap().origin
    is @parameter.Supplied,
  )
  assert_true(
    @execution.completed_cell(local_distinct_execute(explicit_null), 0, 0)
    is Some(Null),
  )
  for
    supplied in [
      Some("{\"id\":true}"),
      Some("{\"id\":\"9223372036854775808\"}"),
      Some("{\"id\":7}"),
    ] {
    assert_true(
      local_supplied_parameter_preparation_attempt(
        @source_frontend.Sql,
        declaration,
        supplied,
      )
      is Err(_),
    )
  }
  assert_true(
    local_supplied_parameter_preparation_attempt(
      @source_frontend.Sql,
      "{\"id\":{\"type\":\"int64\"}}",
      None,
    )
    is Err(_),
  )
}

///|
test "default provenance never admits equal foreign or copied preparations or predecessor catalogues" {
  let declaration = "{\"id\":{\"type\":\"int64\",\"default\":\"9007199254740993\"}}"
  let original = local_supplied_parameter_preparation(
    @source_frontend.Sql,
    declaration,
    None,
  )
  let proof = local_default_parameter_normalization(original)
  let foreign = local_supplied_parameter_preparation(
    @source_frontend.Sql,
    declaration,
    None,
  )
  assert_eq(
    local_parameter_values_identity(original),
    local_parameter_values_identity(foreign),
  )
  assert_true(
    prepared_client_local_normalization_evidence(foreign, proof)
    is Err(ForeignPreparation),
  )
  let copied = { ..original, }
  assert_true(
    prepared_client_local_normalization_evidence(copied, proof)
    is Err(ForeignPreparation),
  )
  let copied_proof = { ..proof, }
  assert_true(
    prepared_client_local_normalization_evidence(original, copied_proof)
    is Err(ForeignPreparation),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      original,
      proof,
      local_default_parameter_expected_journal,
      local_default_parameter_catalog_cid(),
    )
    is Ok(_),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      original, proof, local_default_parameter_expected_journal, local_distinct_catalog_cid,
    )
    is Err(ForeignCatalog),
  )
}

///|
test "default Take retains independent original SafeInteger count and offset conditions" {
  for format in [@source_frontend.Sql, @source_frontend.Text] {
    let declarations = "{\"count\":{\"type\":\"int64\",\"default\":\"1\"},\"offset\":{\"type\":\"int64\",\"default\":\"0\"}}"
    let original = local_supplied_parameter_preparation(
      format,
      declarations,
      None,
      text="SELECT COUNT(*) AS n LIMIT @count OFFSET @offset",
    )
    ignore(local_default_parameter_normalization(original))
    assert_eq(
      @execution.completed_row_count(local_distinct_execute(original)),
      1,
    )
    for value in ["0", "-1", "9007199254740992", "9223372036854775807"] {
      assert_true(
        local_supplied_parameter_preparation_attempt(
          format,
          "{\"count\":{\"type\":\"int64\",\"default\":\"" + value + "\"}}",
          None,
          text="SELECT COUNT(*) AS n LIMIT @count",
        )
        is Err(_),
      )
    }
  }
}

///|
test "a default retains the same original binding across every checked stage" {
  let document =
    #|{"version":"actql/0.1","id":"default.shared-binding","params":{"increment":{"type":"number","default":7}},"stages":[{"id":"seed","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}},{"id":"finish","inputs":{"input":{"result":{"stage":"seed","result":"rows"}}},"steps":[{"derive":{"value":{"add":[{"field":"id"},{"$param":"increment"}]}},"as":"selected"}],"results":{"out":{"from":"selected","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"finish","result":"out"}}}}
  let original = local_group_original_document(document)
  ignore(local_default_parameter_normalization(original))
  let identity = @checked.source_identity(
    @strategy.graph_program(original.graph),
  )
  let first = @parameters.bound_values(
    @context.stage_identity_parameter_values(
      @context.program_identity_stage_at(identity, 0).unwrap(),
    ),
  )
  let second = @parameters.bound_values(
    @context.stage_identity_parameter_values(
      @context.program_identity_stage_at(identity, 1).unwrap(),
    ),
  )
  assert_true(physical_equal(first, second))
  assert_true(
    @parameter.bound_value_at(first, 0).unwrap().origin is @parameter.Default,
  )
}

///|
test "default invocation binding never replaces actual nonempty Sort completion evidence" {
  let document =
    #|{"version":"actql/0.1","id":"default.completed-sort","params":{"delta":{"type":"number","default":7}},"stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"key":{"type":"string","nullable":false}},"rows":[{"key":"b"},{"key":"a"}]},"as":"input"},{"derive":{"extra":{"$param":"delta"}}},{"group":{"by":["key"],"aggregates":{"n":{"fn":"count"}}}},{"sort":[{"field":"n","dir":"asc","nulls":"last"}],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["key","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let original = local_group_original_document(document)
  let proof = _issue_prepared_client_legacy_local_normalization(original).unwrap()
  guard proof.audit is SortCompletion(inventory) else {
    fail("original Sort completion expected")
  }
  assert_true(
    @checked.local_sort_normalization_inventory_parameters_defaulted(inventory),
  )
  assert_eq(@checked.local_sort_normalization_entry_count(inventory), 1)
  let expected =
    #|{"entries":[{"authored":"[{\"dir\":\"asc\",\"field\":\"n\",\"nulls\":\"last\"}]","canonical":"[{\"dir\":\"asc\",\"field\":\"n\",\"nulls\":\"last\"},{\"dir\":\"asc\",\"field\":\"key\",\"nulls\":\"last\"}]","path":"$.stages[0].steps[3].sort","rule":"sort.candidate_key_completion"}],"journal_cid":"sha256:872840bf3ca6315ca1826a3ab17a78bbc14a5ee2d4d18aa4db56626460c7032a","rule_catalog_cid":"sha256:096c228635c4a08bbe7080f3447a9ca35b439fdb5113a17b0cca2b7735a55d2d","version":"actql-normalization-journal/0.1"}
  assert_eq(
    @publication.run_evidence_value_json(
      prepared_client_local_normalization_evidence(original, proof).unwrap(),
    ),
    expected,
  )
  assert_true(
    restore_prepared_client_local_normalization(
      original,
      proof,
      local_default_parameter_expected_journal,
      local_default_parameter_catalog_cid(),
    )
    is Err(SubstitutedJournal),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      original,
      proof,
      expected,
      local_default_parameter_catalog_cid(),
    )
    is Ok(_),
  )
  let output = local_distinct_execute(original)
  assert_eq(@execution.completed_row_count(output), 2)
  assert_true(@execution.completed_cell(output, 0, 0) is Some(Text("a")))
  assert_true(@execution.completed_cell(output, 1, 0) is Some(Text("b")))
}

///|
test "default correspondence consumes the existing Local audit work without widening completion support" {
  let name = "p".repeat(5000)
  let declarations = "{\"" + name + "\":{\"type\":\"number\",\"default\":7}}"
  let text = "SELECT @" + name + " AS id"
  let defaulted = local_supplied_parameter_preparation(
    @source_frontend.Sql,
    declarations,
    None,
    text~,
  )
  assert_true(
    _issue_prepared_client_legacy_local_normalization(defaulted)
    is Err(Inventory(ProfileNotInstalled)),
  )
  assert_true(defaulted.local_normalization is None)
  let implicit_else = local_supplied_parameter_preparation(
    @source_frontend.Sql,
    "{\"id\":{\"type\":\"number\",\"default\":7}}",
    None,
    text="SELECT CASE WHEN TRUE THEN @id END AS id",
  )
  assert_true(
    _issue_prepared_client_legacy_local_normalization(implicit_else)
    is Err(Inventory(CompletionObserved)),
  )
  assert_true(implicit_else.local_normalization is None)
}

///|
test "mixed supplied and defaulted bindings retain every original selected origin" {
  let original = local_supplied_parameter_preparation(
    @source_frontend.Sql,
    "{\"a\":{\"type\":\"int64\",\"default\":\"9007199254740993\"},\"b\":{\"type\":\"int64\",\"default\":\"1\"}}",
    Some("{\"b\":\"9223372036854775807\"}"),
    text="SELECT @a AS a, @b AS b",
  )
  ignore(local_default_parameter_normalization(original))
  let bindings = local_default_bound_values(original)
  assert_eq(@parameter.bound_value_count(bindings), 2)
  assert_true(
    @parameter.bound_value_at(bindings, 0).unwrap().origin is @parameter.Default,
  )
  assert_true(
    @parameter.bound_value_at(bindings, 1).unwrap().origin
    is @parameter.Supplied,
  )
  let output = local_distinct_execute(original)
  assert_true(
    @execution.completed_cell(output, 0, 0)
    is Some(Captured(Signed64(9007199254740993L))),
  )
  assert_true(
    @execution.completed_cell(output, 0, 1)
    is Some(Captured(Signed64(9223372036854775807L))),
  )
}
