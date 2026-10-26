// Legacy catalogue compatibility cases retain the original recipe issuer.

///|
let local_default_set_expected_journal : String =
  #|{"entries":[],"journal_cid":"sha256:09ac554868a1d4a15b7ea357702b7da4b633024d38a2537fa6aea8f560866b81","rule_catalog_cid":"sha256:a9d402c6c62d80cc8aed4a55d0753acec16dab22e7cd31399f4bc5459a248d45","version":"actql-normalization-journal/0.1"}

///|
fn local_default_set_normalization(
  owner : PreparedClientProgram,
) -> ClientLocalNormalization raise {
  let proof = _issue_prepared_client_legacy_local_normalization(owner).unwrap()
  guard proof.audit is CompletionFree(inventory) else {
    fail("original default SET inventory expected")
  }
  assert_true(
    @checked.local_completion_free_inventory_parameters_defaulted(inventory),
  )
  assert_true(@checked.local_completion_free_inventory_uses_set(inventory))
  assert_eq(
    local_normalization_catalog_cid(proof.audit),
    local_default_set_catalog_cid(),
  )
  assert_eq(
    @publication.run_evidence_value_json(
      prepared_client_local_normalization_evidence(owner, proof).unwrap(),
    ),
    local_default_set_expected_journal,
  )
  proof
}

///|
test "public SQL and Pipe SET preserve one original Default binding across all lowered stages" {
  for
    (format, text) in [
      (@source_frontend.Sql, "SELECT @id AS id UNION ALL SELECT @id AS id"),
      (
        @source_frontend.Text,
        "SELECT @id AS id |> UNION ALL (SELECT @id AS id)",
      ),
    ] {
    let declaration = "{\"id\":{\"type\":\"int64\",\"default\":\"9007199254740993\"}}"
    let owner = local_supplied_parameter_preparation(
      format,
      declaration,
      None,
      text~,
    )
    let proof = local_default_set_normalization(owner)
    let original = local_default_bound_values(owner)
    let identity = @checked.source_identity(
      @strategy.graph_program(owner.graph),
    )
    assert_eq(@context.program_identity_stage_count(identity), 6)
    for index in 0..<@context.program_identity_stage_count(identity) {
      let values = @parameters.bound_values(
        @context.stage_identity_parameter_values(
          @context.program_identity_stage_at(identity, index).unwrap(),
        ),
      )
      assert_true(physical_equal(values, original))
      assert_true(
        @parameter.bound_value_at(values, 0).unwrap().origin
        is @parameter.Default,
      )
    }
    let supplied = local_supplied_parameter_preparation(
      format,
      declaration,
      Some("{\"id\":\"9007199254740993\"}"),
      text~,
    )
    assert_eq(
      local_parameter_values_identity(owner),
      local_parameter_values_identity(supplied),
    )
    ignore(local_set_normalization(supplied))
    assert_true(
      prepared_client_local_normalization_evidence(supplied, proof)
      is Err(ForeignPreparation),
    )
    assert_true(
      restore_prepared_client_local_normalization(
        owner,
        proof,
        local_default_set_expected_journal,
        local_default_set_catalog_cid(),
      )
      is Ok(_),
    )
    assert_true(
      restore_prepared_client_local_normalization(
        owner,
        proof,
        local_default_set_expected_journal,
        local_default_parameter_catalog_cid(),
      )
      is Err(ForeignCatalog),
    )
  }
}

///|
fn local_default_set_rows(completed_sort : Bool) -> PreparedClientProgram raise {
  let ending = if completed_sort {
    ",\"as\":\"combined\"},{\"group\":{\"by\":[\"key\"],\"aggregates\":{\"n\":{\"fn\":\"count\"}}}},{\"sort\":[{\"field\":\"n\",\"dir\":\"asc\",\"nulls\":\"last\"}],\"as\":\"selected\"}"
  } else {
    ",\"as\":\"selected\"}"
  }
  let fields = if completed_sort {
    "[\"key\",\"n\"]"
  } else {
    "[\"key\",\"id\"]"
  }
  let document = "{\"version\":\"actql/0.1\",\"id\":\"default.set.rows\",\"params\":{\"id\":{\"type\":\"int64\",\"default\":\"9007199254740993\"}},\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{\"key\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"key\":\"b\"}]},\"as\":\"left_values\"},{\"derive\":{\"id\":{\"$param\":\"id\"}},\"as\":\"left\"},{\"values\":{\"schema\":{\"key\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"key\":\"a\"}]},\"as\":\"right_values\"},{\"derive\":{\"id\":{\"$param\":\"id\"}},\"as\":\"right\"},{\"from\":\"left\",\"append\":{\"with\":\"right\"}" +
    ending +
    "],\"results\":{\"rows\":{\"from\":\"selected\",\"fields\":" +
    fields +
    "}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}"
  local_group_original_document(document)
}

///|
test "actual Append executes both original Default rows without Number conversion" {
  let original = local_default_set_rows(false)
  ignore(local_default_set_normalization(original))
  let output = local_distinct_execute(original)
  assert_eq(@execution.completed_row_count(output), 2)
  assert_eq(@execution.completed_column_name(output, 0), Some("id"))
  assert_eq(@execution.completed_column_name(output, 1), Some("key"))
  for row in 0..<2 {
    assert_true(
      @execution.completed_cell(output, row, 0)
      is Some(Captured(Signed64(9007199254740993L))),
    )
  }
}

///|
test "Default with SET retains actual Sort completion and rejects an empty journal" {
  let original = local_default_set_rows(true)
  let proof = _issue_prepared_client_legacy_local_normalization(original).unwrap()
  guard proof.audit is SortCompletion(inventory) else {
    fail("actual completed SET Sort expected")
  }
  assert_true(
    @checked.local_sort_normalization_inventory_parameters_defaulted(inventory),
  )
  assert_true(@checked.local_sort_normalization_inventory_uses_set(inventory))
  assert_eq(@checked.local_sort_normalization_entry_count(inventory), 1)
  let expected =
    #|{"entries":[{"authored":"[{\"dir\":\"asc\",\"field\":\"n\",\"nulls\":\"last\"}]","canonical":"[{\"dir\":\"asc\",\"field\":\"n\",\"nulls\":\"last\"},{\"dir\":\"asc\",\"field\":\"key\",\"nulls\":\"last\"}]","path":"$.stages[0].steps[6].sort","rule":"sort.candidate_key_completion"}],"journal_cid":"sha256:13721f13c13d6ec3ce58e32ccb9e9bfce1cdf8dce311cddff9259b12c1cbcbef","rule_catalog_cid":"sha256:a9d402c6c62d80cc8aed4a55d0753acec16dab22e7cd31399f4bc5459a248d45","version":"actql-normalization-journal/0.1"}
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
      local_default_set_expected_journal,
      local_default_set_catalog_cid(),
    )
    is Err(SubstitutedJournal),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      original,
      proof,
      expected,
      local_default_set_catalog_cid(),
    )
    is Ok(_),
  )
  let output = local_distinct_execute(original)
  assert_eq(@execution.completed_row_count(output), 2)
  assert_true(@execution.completed_cell(output, 0, 0) is Some(Text("a")))
  assert_true(@execution.completed_cell(output, 1, 0) is Some(Text("b")))
}
