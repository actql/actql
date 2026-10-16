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
test "INSERT emits existing create.from with its original row mapping and one private Result and no implicit public output" {
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
  assert_eq(insert_fields(program), ["name"])
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
  assert_eq(insert_fields(omitted), ["name"])
  assert_true(insert_static_result(omitted, "one") is Ok(_))
}

///|
test "INSERT keeps original Mapping capture after CTE JOIN and complete set continuations" {
  for
    text in [
      "WITH original AS (FROM messages) FROM original |> EFFECT INSERT salesforce.Account (Name) VALUES (body)",
      "FROM messages AS l JOIN messages AS r ON l.id = r.id |> SELECT l.body AS Name |> EFFECT INSERT salesforce.Account (Name) VALUES (Name)",
      "FROM messages |> SELECT body AS Name |> UNION ALL (FROM messages |> SELECT body AS Name) |> EFFECT INSERT salesforce.Account (Name)",
    ] {
    let program = insert_program(text)
    assert_eq(insert_fields(program), ["name"])
    assert_eq(@program.export_count(program), 0)
    assert_true(insert_static_result(program, "one") is Ok(_))
  }
}

///|
test "INSERT does not discard the original Mapping row correspondence for an authored subset" {
  let query = @query.parse_query(
    "FROM messages |> EFFECT INSERT salesforce.Account (Name) VALUES (body)",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(
      query,
      short_command_context(),
      construction_limits(),
      update_targets=Some(insert_publication("subset")),
    )
    is Err(UnsupportedEffect),
  )
}

///|
test "literal-only INSERT VALUES retain a real derived payload without an empty or artificial capture" {
  let program = insert_program(
    "FROM messages |> EFFECT INSERT salesforce.Account (Name) VALUES ('fixed')",
  )
  assert_eq(insert_fields(program), ["name"])
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
