///|
fn insert_publication(mode : String) -> UpdateTargetPublication {
  let environment = insert_environment(mode)
  let mappings = @environment.check_mapping_contract_shapes(
    @check.checking_environment_wire(environment),
    { max_bytes: 30000, max_nodes: 4000, max_depth: 100, max_members: 100, },
    1000,
  ).unwrap()
  bind_update_target_publication(mappings, [update_target_alias()], 1000).unwrap()
}

///|
fn insert_program(
  text : String,
  mode? : String = "one",
) -> @program.Program raise {
  match
    compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      short_command_context(),
      construction_limits(),
      update_targets=Some(insert_publication(mode)),
    ) {
    Ok(value) => value
    Err(issue) =>
      fail("INSERT normalization: " + store_capture_issue_label(issue))
  }
}

///|
fn insert_static_result(
  program : @program.Program,
  mode : String,
) -> Result[
  @check.EffectProgramStaticCandidate,
  @stage_results.EffectStaticCandidateIssue,
] raise {
  let environment = insert_environment(mode)
  let candidate = match
    @check.prepare_effect_computation_candidate(
      program,
      environment,
      None,
      [],
      check_limits(),
      1,
      1000,
    ) {
    Ok(value) => value
    Err(_) => fail("actual INSERT Common computation")
  }
  let mappings = @environment.check_mapping_contract_shapes(
    @check.checking_environment_wire(environment),
    { max_bytes: 30000, max_nodes: 4000, max_depth: 100, max_members: 100, },
    1000,
  ).unwrap()
  @check.close_effect_computation_static(candidate, mappings, {
    max_members: 1,
    max_work: 1000,
    max_admission_nodes: 100,
    max_admission_depth: 10,
    max_admission_text_bytes: 1000,
  })
}

///|
fn insert_fields(program : @program.Program) -> Array[String] {
  let header = short_command_header(program)
  let result = store_capture_field(
    store_capture_field(
      @program.stage_body(@program.stages(program).last().unwrap()),
      "results",
    ),
    @program.effect_header_source_result(header).unwrap(),
  )
  @wire.elements(store_capture_field(result, "fields"))
  .unwrap()
  .map(value => @wire.text(value).unwrap())
}

///|
fn insert_field_value(program : @program.Program, target : String) -> String {
  let values = @program.effect_header_create_values(
    short_command_header(program),
  ).unwrap()
  @wire.text(store_capture_field(store_capture_field(values, target), "field")).unwrap()
}

///|
test "INSERT resolves create rules including collection-only Mapping without UPDATE promotion" {
  for mode in ["one", "collection"] {
    let publication = insert_publication(mode)
    assert_eq(
      resolve_update_target_binding(
        publication,
        update_target_alias().name,
        None,
        1000,
      ).unwrap_err(),
      UnresolvedMapping,
    )
    let selected = resolve_insert_effect_target_binding(
      publication,
      update_target_alias().name,
      None,
      1000,
    ).unwrap()
    assert_eq(
      resolved_update_target(resolved_insert_target_selection(selected)),
      ("connector://crm/account", "mapping:crm.account.v1"),
    )
    let program = insert_program(
      "FROM messages |> EFFECT INSERT salesforce.Account (Name) VALUES (body)",
      mode~,
    )
    assert_true(insert_static_result(program, mode) is Ok(_))
  }
  assert_eq(
    resolve_insert_effect_target_binding(
      insert_publication("ambiguous"),
      update_target_alias().name,
      None,
      1000,
    ).unwrap_err(),
    AmbiguousMapping,
  )
  assert_eq(
    resolve_insert_effect_target_binding(
      keyed_record_publication("update-only"),
      update_target_alias().name,
      None,
      1000,
    ).unwrap_err(),
    UnresolvedMapping,
  )
  assert_eq(
    resolve_insert_effect_target_binding(
      insert_publication("one"),
      update_target_alias().name,
      None,
      0,
    ).unwrap_err(),
    WorkLimit,
  )
}

///|
test "INSERT emits explicit target values over one original private Result and no implicit public output" {
  let program = insert_program(
    "FROM messages |> EFFECT INSERT salesforce.Account (Name) VALUES (body)",
  )
  let header = short_command_header(program)
  assert_eq(@program.effect_header_kind(header), "create")
  assert_eq(@program.effect_header_id(header), "aql_create_effect")
  assert_eq(
    @program.effect_header_contract_ref(header),
    "mapping:crm.account.v1",
  )
  assert_eq(
    @program.effect_header_source_result(header),
    Some("aql_private_insert"),
  )
  assert_eq(insert_fields(program), ["body"])
  assert_eq(insert_field_value(program, "Name"), "body")
  assert_eq(@program.export_count(program), 0)
  let body = @wire.open_object(@program.effect_header_body(header)).unwrap()
  for field in ["id", "key", "set", "payload"] {
    assert_true(@wire.lookup(body, field) is None)
  }
  assert_true(insert_static_result(program, "one") is Ok(_))
}

///|
test "INSERT omitted VALUES captures same-named fields and keeps explicit public Results" {
  let prefix = "FROM messages |> SELECT body AS Name |> RESULT public_rows |> EFFECT save INSERT salesforce.Account (Name)"
  let omitted = insert_program(prefix)
  let explicit = insert_program(prefix + " VALUES (Name)")
  assert_eq(semantic(omitted), semantic(explicit))
  assert_eq(@program.exports(omitted), [("public_rows", "main", "rows")])
  assert_eq(insert_fields(omitted), ["Name"])
  assert_eq(insert_field_value(omitted, "Name"), "Name")
  assert_true(insert_static_result(omitted, "one") is Ok(_))
}

///|
test "INSERT keeps original Mapping capture after CTE JOIN and complete set continuations" {
  for
    (text, field) in [
      (
        "WITH original AS (FROM messages) FROM original |> EFFECT INSERT salesforce.Account (Name) VALUES (body)",
        "body",
      ),
      (
        "FROM messages AS l JOIN messages AS r ON l.id = r.id |> SELECT l.body AS Name |> EFFECT INSERT salesforce.Account (Name) VALUES (Name)",
        "Name",
      ),
      (
        "FROM messages |> SELECT body AS Name |> UNION ALL (FROM messages |> SELECT body AS Name) |> EFFECT INSERT salesforce.Account (Name)",
        "Name",
      ),
    ] {
    let program = insert_program(text)
    assert_eq(insert_fields(program), [field])
    assert_eq(insert_field_value(program, "Name"), field)
    assert_eq(@program.export_count(program), 0)
    assert_true(insert_static_result(program, "one") is Ok(_))
  }
}

///|
test "INSERT explicit subset retains the complete original Mapping rather than trimming its default correspondence" {
  let program = insert_program(
    "FROM messages |> EFFECT INSERT salesforce.Account (Name) VALUES (body)",
    mode="subset",
  )
  assert_eq(insert_field_value(program, "Name"), "body")
  assert_eq(insert_fields(program), ["body"])
  assert_true(insert_static_result(program, "subset") is Ok(_))
}

///|
test "literal-only INSERT VALUES retain a real derived payload without an empty or artificial capture" {
  let program = insert_program(
    "FROM messages |> EFFECT INSERT salesforce.Account (Name) VALUES ('fixed')",
  )
  assert_eq(insert_fields(program).length(), 1)
  assert_eq(insert_field_value(program, "Name"), insert_fields(program)[0])
  let derives = store_capture_steps(program).filter(step => {
    @wire.lookup(@wire.open_object(step).unwrap(), "derive") is Some(_)
  })
  assert_eq(derives.length(), 1)
  let values = store_capture_field(derives[0], "derive")
  assert_eq(@wire.object_length(values), Some(1))
  assert_eq(
    @wire.text(
      store_capture_field(@wire.field_at(values, 0).unwrap().1, "literal"),
    ).unwrap(),
    "fixed",
  )
  assert_true(insert_static_result(program, "one") is Ok(_))
  assert_eq(@program.export_count(program), 0)
}

///|
test "INSERT binds the original target before expressions and keeps actual Common type rejection" {
  let query = @query.parse_query(
    "FROM messages |> EFFECT INSERT salesforce.Account (Name) VALUES (absent)",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(query, short_command_context(), construction_limits())
    is Err(UpdateTargetBinding(UnresolvedTarget)),
  )
  assert_true(
    compile(
      query,
      short_command_context(),
      construction_limits(),
      update_targets=Some(keyed_record_publication("update-only")),
    )
    is Err(UpdateTargetBinding(UnresolvedMapping)),
  )
  let invalid = insert_program(
    "FROM messages |> EFFECT INSERT salesforce.Account (Name) VALUES (1)",
  )
  guard insert_static_result(invalid, "one") is Err(MappingRules(issue)) else {
    fail("actual original target type refusal")
  }
  assert_eq(
    @stage_results.effect_mapping_rule_issue_kind(issue),
    IncompatibleSourceType("Name"),
  )
}

///|
test "INSERT gives two targets independent values despite a shared original Mapping default source" {
  let program = insert_program(
    "FROM messages |> EFFECT INSERT salesforce.Account (Name, City) VALUES (body, secret)",
    mode="shared",
  )
  assert_eq(insert_fields(program), ["body", "secret"])
  assert_eq(insert_field_value(program, "Name"), "body")
  assert_eq(insert_field_value(program, "City"), "secret")
  assert_eq(@program.export_count(program), 0)
  assert_true(insert_static_result(program, "shared") is Ok(_))
}

///|
test "INSERT may reuse one captured original field without inventing a Mapping column" {
  let program = insert_program(
    "FROM messages |> EFFECT INSERT salesforce.Account (Name, City) VALUES (body, body)",
    mode="subset",
  )
  assert_eq(insert_fields(program), ["body"])
  assert_eq(insert_field_value(program, "Name"), "body")
  assert_eq(insert_field_value(program, "City"), "body")
  assert_true(insert_static_result(program, "subset") is Ok(_))
}
