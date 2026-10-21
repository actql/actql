///|
let common_local_empty_journal : String =
  #|{"entries":[],"journal_cid":"sha256:e245b445e5014e5764dab4bf1b9ddc3b3abdf821ddf75950f9bee9df29007164","rule_catalog_cid":"sha256:f93d91b468d850cbc63a8c8350578af8431a2256eb2b1ef3f60586fdc640561d","version":"actql-normalization-journal/0.1"}

///|
test "common journal encoding cannot exceed its reserved remaining work" {
  let owner = local_explicit_cast_original(text="SELECT ABS(-3) AS value")
  let inventory = @checked.local_program_common_normalization_inventory(
    @strategy.graph_program(owner.graph),
    10000,
  ).unwrap()
  let wire = local_common_normalization_journal_body(inventory, 1024).unwrap()
  let bytes = @utf8.encode(wire).length()
  assert_true(
    local_common_normalization_journal_body(inventory, bytes) is Ok(_),
  )
  assert_true(
    local_common_normalization_journal_body(inventory, bytes - 1)
    is Err(CommonInventory(BudgetExceeded)),
  )
  assert_true(owner.local_normalization is None)
}

///|
test "fresh fixed scalar Join Group and ordinary Sort share one normalization identity" {
  for
    original in [
      local_explicit_cast_original(
        text="SELECT ABS(CAST(-3 AS NUMBER)) AS value",
      ),
      local_explicit_cast_original(text=local_join_public_sql),
      local_explicit_cast_original(text=local_decimal_sum_public_sql),
      local_explicit_cast_original(
        text="SELECT 1 AS k, COUNT(*) AS n GROUP BY k ORDER BY k ASC NULLS LAST",
      ),
    ] {
    let proof = issue_prepared_client_local_normalization(original).unwrap()
    assert_eq(
      local_normalization_catalog_cid(proof.audit),
      local_common_normalization_catalog_cid(),
    )
    assert_eq(
      @publication.run_evidence_value_json(
        prepared_client_local_normalization_evidence(original, proof).unwrap(),
      ),
      common_local_empty_journal,
    )
    assert_true(
      physical_equal(
        proof,
        issue_prepared_client_local_normalization(original).unwrap(),
      ),
    )
  }
}

///|
test "common Join audit keeps original Default and Supplied values without a new catalog" {
  let declarations = "{\"cap\":{\"type\":\"int64\",\"nullable\":false,\"default\":\"4\"}}"
  let text = "WITH left_rows AS (SELECT @cap AS id), right_rows AS (SELECT @cap AS id) SELECT l.id AS id FROM left_rows AS l JOIN right_rows AS r ON l.id = r.id MAX_OUTPUT_ROWS 4"
  let defaulted = local_supplied_parameter_preparation(
    @source_frontend.Sql,
    declarations,
    None,
    text~,
  )
  let supplied = local_supplied_parameter_preparation(
    @source_frontend.Sql,
    declarations,
    Some("{\"cap\":\"4\"}"),
    text~,
  )
  let proof = issue_prepared_client_local_normalization(defaulted).unwrap()
  let other = issue_prepared_client_local_normalization(supplied).unwrap()
  assert_eq(
    local_parameter_values_identity(defaulted),
    local_parameter_values_identity(supplied),
  )
  assert_true(
    @parameter.bound_value_at(local_default_bound_values(defaulted), 0).unwrap().origin
    is @parameter.Default,
  )
  assert_true(
    @parameter.bound_value_at(local_default_bound_values(supplied), 0).unwrap().origin
    is @parameter.Supplied,
  )
  assert_eq(
    @publication.run_evidence_value_json(
      prepared_client_local_normalization_evidence(defaulted, proof).unwrap(),
    ),
    common_local_empty_journal,
  )
  assert_eq(
    @publication.run_evidence_value_json(
      prepared_client_local_normalization_evidence(supplied, other).unwrap(),
    ),
    common_local_empty_journal,
  )
  assert_true(
    prepared_client_local_normalization_evidence(supplied, proof)
    is Err(ForeignPreparation),
  )
}

///|
let common_local_sort_journal : String = "{\"entries\":[{\"authored\":\"[{\\\"dir\\\":\\\"asc\\\",\\\"field\\\":\\\"n\\\",\\\"nulls\\\":\\\"last\\\"}]\",\"canonical\":\"[{\\\"dir\\\":\\\"asc\\\",\\\"field\\\":\\\"n\\\",\\\"nulls\\\":\\\"last\\\"},{\\\"dir\\\":\\\"asc\\\",\\\"field\\\":\\\"key\\\",\\\"nulls\\\":\\\"last\\\"}]\",\"path\":\"$.stages[0].steps[2].sort\",\"rule\":\"sort.candidate_key_completion\"}],\"journal_cid\":\"sha256:e344b4ba74ce5e4e2f2608554e2a6a0fcfe0771a0050dd27b5fa8a8c4b238465\",\"rule_catalog_cid\":\"sha256:f93d91b468d850cbc63a8c8350578af8431a2256eb2b1ef3f60586fdc640561d\",\"version\":\"actql-normalization-journal/0.1\"}"

///|
test "common audit emits the real Sort completion and never substitutes empty evidence" {
  let original = local_completed_sort_original()
  let proof = issue_prepared_client_local_normalization(original).unwrap()
  guard proof.audit is Common(inventory) else {
    fail("same common audit expected")
  }
  assert_eq(@checked.local_common_normalization_entry_count(inventory), 1)
  let wire = @publication.run_evidence_value_json(
    prepared_client_local_normalization_evidence(original, proof).unwrap(),
  )
  assert_eq(wire, common_local_sort_journal)
  assert_true(
    restore_prepared_client_local_normalization(
      original,
      proof,
      wire,
      local_common_normalization_catalog_cid(),
    )
    is Ok(_),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      original,
      proof,
      common_local_empty_journal,
      local_common_normalization_catalog_cid(),
    )
    is Err(SubstitutedJournal),
  )
  let foreign = local_completed_sort_original()
  assert_true(
    prepared_client_local_normalization_evidence(foreign, proof)
    is Err(ForeignPreparation),
  )
}

///|
test "legacy original restore keeps its exact issued catalogue after fresh defaults change" {
  let original = local_explicit_cast_original(text="SELECT ABS(-3) AS value")
  let old = issue_prepared_client_legacy_local_normalization(original).unwrap()
  let old_wire = @publication.run_evidence_value_json(
    prepared_client_local_normalization_evidence(original, old).unwrap(),
  )
  assert_eq(old_wire, local_checked_expression_journal)
  assert_true(
    physical_equal(
      old,
      issue_prepared_client_local_normalization(original).unwrap(),
    ),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      original, old, old_wire, local_checked_expression_catalog_cid,
    )
    is Ok(_),
  )
  let fresh = local_explicit_cast_original(text="SELECT ABS(-3) AS value")
  let current = issue_prepared_client_local_normalization(fresh).unwrap()
  assert_eq(
    local_normalization_catalog_cid(current.audit),
    local_common_normalization_catalog_cid(),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      fresh, current, old_wire, local_checked_expression_catalog_cid,
    )
    is Err(ForeignCatalog),
  )
}

///|
test "one original public Join Group Sort and scalar Parameter combination has one common audit" {
  let declarations = "{\"cap\":{\"type\":\"number\",\"nullable\":false,\"default\":4}}"
  let text = "WITH left_rows AS (SELECT ABS(CAST(@cap AS NUMBER)) AS id), right_rows AS (SELECT ABS(CAST(@cap AS NUMBER)) AS id) SELECT l.id AS id, COUNT(*) AS n FROM left_rows AS l JOIN right_rows AS r ON l.id = r.id MAX_OUTPUT_ROWS 4 GROUP BY l.id ORDER BY n ASC NULLS LAST"
  for supplied in [None, Some("{\"cap\":4}")] {
    let owner = local_supplied_parameter_preparation(
      @source_frontend.Sql,
      declarations,
      supplied,
      text~,
    )
    let proof = issue_prepared_client_local_normalization(owner).unwrap()
    guard proof.audit is Common(inventory) else {
      fail("one common original expected")
    }
    assert_eq(
      local_normalization_catalog_cid(proof.audit),
      local_common_normalization_catalog_cid(),
    )
    assert_true(
      @checked.local_common_normalization_inventory_matches(
        inventory,
        @strategy.graph_program(owner.graph),
      ),
    )
    assert_true(@checked.local_common_normalization_entry_count(inventory) > 0)
  }
}

///|
test "common audit never supplies an int64 to Number CAST conversion" {
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let declarations = @parameter.read_declarations(
    Some(
      scalar_profile_cursor(
        "{\"cap\":{\"type\":\"int64\",\"nullable\":false,\"default\":\"4\"}}",
      ),
    ),
    {
      max_parameters: 100,
      max_nodes: 1000,
      max_depth: 32,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let context = @source_frontend.bind_query_context(
    [],
    @checked.checking_environment_cid(environment),
    parameter_declarations=Some(declarations),
  ).unwrap()
  let source = "WITH left_rows AS (SELECT ABS(CAST(@cap AS NUMBER)) AS id), right_rows AS (SELECT ABS(CAST(@cap AS NUMBER)) AS id) SELECT l.id AS id, COUNT(*) AS n FROM left_rows AS l JOIN right_rows AS r ON l.id = r.id MAX_OUTPUT_ROWS 4 GROUP BY l.id ORDER BY n ASC NULLS LAST"
  assert_true(
    @source_frontend.lower(source, @source_frontend.Sql, Some(context))
    is Err(
      QueryLowering(
        BindingPreparation(
          LocalProgram(
            Pipeline(
              _,
              { kind: Operation(Expression(TypeMismatch("cast input"))), .. }
            )
          )
        )
      )
    ),
  )
}
