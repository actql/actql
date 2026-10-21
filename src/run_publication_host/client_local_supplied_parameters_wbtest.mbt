// Legacy catalogue compatibility cases retain the original recipe issuer.

///|
fn local_supplied_parameter_preparation_attempt(
  format : @source_frontend.Format,
  declarations : String,
  supplied : String?,
  text? : String = "SELECT @id AS id",
) -> Result[PreparedClientProgram, ClientProgramPreparationIssue] {
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let declarations = @parameter.read_declarations(
    Some(scalar_profile_cursor(declarations)),
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
  let original = @source_frontend.lower(text, format, Some(context)).unwrap()

  prepare_parsed_effect_free_client_program(
    original.program.unwrap(),
    environment,
    supplied.map(scalar_profile_cursor),
    client_standard_program_preparation_limits(),
  )
}

///|
fn local_supplied_parameter_preparation(
  format : @source_frontend.Format,
  declarations : String,
  supplied : String?,
  text? : String = "SELECT @id AS id",
) -> PreparedClientProgram {
  local_supplied_parameter_preparation_attempt(
    format,
    declarations,
    supplied,
    text~,
  ).unwrap()
}

///|
fn local_parameter_values_identity(owner : PreparedClientProgram) -> String {
  @context.program_identity_parameter_values_cid(
    @checked.source_identity(@strategy.graph_program(owner.graph)),
  )
}

///|
test "public literal queries retain actually supplied typed parameters through Local normalization" {
  for format in [@source_frontend.Sql, @source_frontend.Text] {
    for
      (declarations, supplied) in [
        ("{\"id\":{\"type\":\"number\",\"nullable\":false}}", "{\"id\":7}"),
        (
          "{\"id\":{\"type\":\"int64\",\"nullable\":false}}", "{\"id\":\"9007199254740993\"}",
        ),
      ] {
      let original = local_supplied_parameter_preparation(
        format,
        declarations,
        Some(supplied),
      )
      guard issue_prepared_client_legacy_local_normalization(original)
        is Ok(issued) else {
        fail(
          "the original explicitly supplied Parameter cannot obtain Local normalization",
        )
      }
      assert_true(
        prepared_client_local_normalization_evidence(original, issued) is Ok(_),
      )
      assert_true(
        physical_equal(
          issued,
          issue_prepared_client_legacy_local_normalization(original).unwrap(),
        ),
      )
    }
  }
}

///|
test "Local normalization distinguishes actual supplied origin from equal defaulted values" {
  let declaration = "{\"id\":{\"type\":\"number\",\"nullable\":false,\"default\":7}}"
  let supplied = local_supplied_parameter_preparation(
    @source_frontend.Sql,
    declaration,
    Some("{\"id\":7}"),
  )
  let defaulted = local_supplied_parameter_preparation(
    @source_frontend.Sql,
    declaration,
    None,
  )
  // Effective-value identities deliberately omit Default/Supplied origin.
  // The new admission must use the actual retained binder, not equal CIDs.
  assert_eq(
    local_parameter_values_identity(supplied),
    local_parameter_values_identity(defaulted),
  )
  assert_true(
    issue_prepared_client_legacy_local_normalization(supplied) is Ok(_),
  )
  ignore(local_default_parameter_normalization(defaulted))
}

///|
test "Local normalization preserves unused declaration refusal and accepts explicit nullable bindings" {
  let declarations = "{\"id\":{\"type\":\"number\"},\"unused\":{\"type\":\"number\",\"default\":9}}"
  // The existing whole-Program reference owner refuses unused declarations
  // before a CheckedProgram exists; supplying them does not bypass that law.
  for supplied in ["{\"id\":7}", "{\"id\":7,\"unused\":9}"] {
    assert_true(
      local_supplied_parameter_preparation_attempt(
        @source_frontend.Text,
        declarations,
        Some(supplied),
      )
      is Err(Check(diagnostic)) &&
      @checked.diagnostic_cause(diagnostic)
      is Source(Identity(References(Usage(UnusedParameter(_))))),
    )
  }
  let nullable = local_supplied_parameter_preparation(
    @source_frontend.Sql,
    "{\"id\":{\"type\":\"number\",\"nullable\":true}}",
    Some("{\"id\":null}"),
  )
  assert_true(
    issue_prepared_client_legacy_local_normalization(nullable) is Ok(_),
  )
}

///|
test "Local supplied-Parameter normalization retains exact catalog journal and foreign-owner refusals" {
  let declarations = "{\"id\":{\"type\":\"number\",\"nullable\":false}}"
  let owner = local_supplied_parameter_preparation(
    @source_frontend.Sql,
    declarations,
    Some("{\"id\":7}"),
  )
  let issued = issue_prepared_client_legacy_local_normalization(owner).unwrap()
  let evidence = prepared_client_local_normalization_evidence(owner, issued).unwrap()
  // Independently hashed complete catalog and journal preimages accompany the
  // new closed applicability alternative; the old parameter-free bytes remain.
  let expected =
    #|{"entries":[],"journal_cid":"sha256:016cfc9cf2e38145078b53c715472cf6a14415c4d40c5bed219cc526797424aa","rule_catalog_cid":"sha256:105e716b0494553cf970393a550ece0553787fb1967ee01f245ea607b03d0fe1","version":"actql-normalization-journal/0.1"}
  assert_eq(@publication.run_evidence_value_json(evidence), expected)
  assert_true(
    restore_prepared_client_local_normalization(
      owner, issued, expected, "sha256:105e716b0494553cf970393a550ece0553787fb1967ee01f245ea607b03d0fe1",
    )
    is Ok(_),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      owner,
      issued,
      expected,
      client_local_completion_free_catalog_cid(),
    )
    is Err(ForeignCatalog),
  )
  let other = local_supplied_parameter_preparation(
    @source_frontend.Sql,
    declarations,
    Some("{\"id\":7}"),
  )
  assert_eq(
    local_parameter_values_identity(owner),
    local_parameter_values_identity(other),
  )
  assert_true(
    prepared_client_local_normalization_evidence(other, issued)
    is Err(ForeignPreparation),
  )
  let copied : ClientLocalNormalization = {
    preparation: issued.preparation,
    audit: issued.audit,
    evidence: issued.evidence,
  }
  assert_true(
    prepared_client_local_normalization_evidence(owner, copied)
    is Err(ForeignPreparation),
  )
  assert_true(
    restore_prepared_client_local_normalization(
      owner,
      issued,
      expected.replace(old="\"entries\":[]", new="\"entries\":[{}]"),
      "sha256:105e716b0494553cf970393a550ece0553787fb1967ee01f245ea607b03d0fe1",
    )
    is Err(SubstitutedJournal),
  )
}

///|
test "Local supplied Parameter inventory joins every original checked stage" {
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  // SQL CTEs deliberately lower to one stage. Use an actual two-stage Program
  // to exercise the existing shared binding owner across both stage identities.
  let document =
    #|{"version":"actql/0.1","id":"supplied-parameters","params":{"increment":{"type":"number","nullable":false}},"stages":[{"id":"seed","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1}]},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}},{"id":"finish","inputs":{"input":{"result":{"stage":"seed","result":"rows"}}},"steps":[{"derive":{"value":{"add":[{"field":"id"},{"$param":"increment"}]}},"as":"selected"}],"results":{"out":{"from":"selected","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"finish","result":"out"}}}}
  let owner = prepare_effect_free_client_program(
    document,
    Json,
    environment,
    Some(scalar_profile_cursor("{\"increment\":7}")),
    client_standard_program_preparation_limits(),
  ).unwrap()
  assert_eq(@checked.unit_count(@strategy.graph_program(owner.graph)), 2)
  let issued = issue_prepared_client_legacy_local_normalization(owner).unwrap()
  assert_true(
    prepared_client_local_normalization_evidence(owner, issued) is Ok(_),
  )
}

///|
test "Parameter-free public Local preparation retains the exact original catalog and journal" {
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let context = @source_frontend.bind_query_context(
    [],
    @checked.checking_environment_cid(environment),
  ).unwrap()
  let lowered = @source_frontend.lower(
    "SELECT 7 AS id",
    @source_frontend.Sql,
    Some(context),
  ).unwrap()
  let owner = prepare_parsed_effect_free_client_program(
    lowered.program.unwrap(),
    environment,
    None,
    client_standard_program_preparation_limits(),
  ).unwrap()
  let issued = issue_prepared_client_legacy_local_normalization(owner).unwrap()
  let evidence = prepared_client_local_normalization_evidence(owner, issued).unwrap()
  let expected =
    #|{"entries":[],"journal_cid":"sha256:068f6d7eefb587836c72426fb4d579406247a97b27120621880cbd4a23874880","rule_catalog_cid":"sha256:690a1e3eea6e0ce89e54937db070a578ec66c2c456061c28a29c7c4dba1b6587","version":"actql-normalization-journal/0.1"}
  assert_eq(@publication.run_evidence_value_json(evidence), expected)
  assert_true(
    restore_prepared_client_local_normalization(
      owner,
      issued,
      expected,
      client_local_completion_free_catalog_cid(),
    )
    is Ok(_),
  )
}
