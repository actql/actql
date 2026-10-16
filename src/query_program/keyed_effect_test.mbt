///|
fn keyed_record_publication(mode : String) -> UpdateTargetPublication {
  let environment = keyed_record_environment(mode)
  let mappings = @environment.check_mapping_contract_shapes(
    @check.checking_environment_wire(environment),
    { max_bytes: 30000, max_nodes: 4000, max_depth: 100, max_members: 100, },
    1000,
  ).unwrap()
  bind_update_target_publication(mappings, [update_target_alias()], 1000).unwrap()
}

///|
fn keyed_record_program(
  text : String,
  mode? : String = "all",
) -> @program.Program raise {
  let query = @query.parse_query(text, syntax_limits()).unwrap()
  match
    compile(
      query,
      short_command_context(),
      construction_limits(),
      update_targets=Some(keyed_record_publication(mode)),
    ) {
    Ok(program) => program
    Err(issue) =>
      fail("keyed record lowering: " + store_capture_issue_label(issue))
  }
}

///|
fn keyed_record_static(
  program : @program.Program,
  mode : String,
) -> @check.EffectProgramStaticCandidate raise {
  let environment = keyed_record_environment(mode)
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
    Err(_) => fail("actual Common computation preparation")
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
  }).unwrap()
}

///|
test "keyed operation selection uses complete original Mapping rules rather than UPDATE eligibility" {
  for
    (mode, kind) in [
      ("upsert-only", @query.KeyedEffectKind::Upsert),
      ("delete-only", Delete),
    ] {
    let publication = keyed_record_publication(mode)
    assert_eq(
      resolve_update_target_binding(
        publication,
        update_target_alias().name,
        None,
        1000,
      ).unwrap_err(),
      UnresolvedMapping,
    )
    let selected = resolve_keyed_effect_target_binding(
      publication,
      kind,
      update_target_alias().name,
      None,
      1000,
    ).unwrap()
    assert_eq(
      resolved_update_target(selected),
      ("connector://crm/account", "mapping:crm.account.v1"),
    )
    let concrete = resolve_concrete_keyed_effect_target_binding(
      publication, kind, "connector://crm/account", "mapping:crm.account.v1", 1000,
    ).unwrap()
    assert_eq(
      resolved_update_target_identity(selected),
      resolved_update_target_identity(concrete),
    )
  }
  for kind in [@query.KeyedEffectKind::Upsert, Delete] {
    assert_eq(
      resolve_keyed_effect_target_binding(
        keyed_record_publication("update-only"),
        kind,
        update_target_alias().name,
        None,
        1000,
      ).unwrap_err(),
      UnresolvedMapping,
    )
    assert_eq(
      resolve_keyed_effect_target_binding(
        keyed_record_publication("all"),
        kind,
        update_target_alias().name,
        None,
        0,
      ).unwrap_err(),
      WorkLimit,
    )
  }
}

///|
test "keyed Mapping ambiguity keeps differently permissioned candidates and exact explicit selection" {
  let publication = keyed_record_publication("ambiguous")
  assert_eq(
    resolve_keyed_effect_target_binding(
      publication,
      Upsert,
      update_target_alias().name,
      None,
      1000,
    ).unwrap_err(),
    AmbiguousMapping,
  )
  for mapping in ["mapping:crm.account.v1", "mapping:crm.account.other.v1"] {
    let selected = resolve_keyed_effect_target_binding(
      publication,
      Upsert,
      update_target_alias().name,
      Some({ value: mapping, quoted: true, }),
      1000,
    ).unwrap()
    assert_eq(resolved_update_target(selected).1, mapping)
  }
  assert_eq(
    resolve_keyed_effect_target_binding(
      keyed_record_publication("foreign"),
      Delete,
      update_target_alias().name,
      None,
      1000,
    ).unwrap_err(),
    UnresolvedMapping,
  )
}

///|
test "UPSERT and DELETE emit existing canonical selectors and minimal private capture" {
  for (word, selector, expected_fields, mode) in [
    ("UPSERT", "key", ["id", "body"], "upsert-only"),
    ("DELETE", "id", ["id"], "delete-only"),
  ] {
    let program = keyed_record_program("FROM messages |> EFFECT " + word + " salesforce.Account ID id" + if word == "UPSERT" {" SET (Name = body)"} else {""}, mode~)
    let header = short_command_header(program)
    assert_eq(@program.effect_header_kind(header), if word == "UPSERT" {"upsert"} else {"delete"})
    assert_eq(@program.effect_header_id(header), if word == "UPSERT" {"aql_upsert_effect"} else {"aql_delete_effect"})
    assert_eq(@wire.text(store_capture_field(@program.effect_header_body(header), selector)).unwrap(), "id")
    assert_eq(private_update_fields(program), expected_fields)
    assert_eq(@program.export_count(program), 0)
    if word == "DELETE" {
      assert_true(@wire.lookup(@wire.open_object(@program.effect_header_body(header)).unwrap(), "set") is None)
    }
    let checked = keyed_record_static(program, mode)
    assert_eq(@program.effect_header_count(@check.effect_program_static_headers(checked)), 1)
  }
}

///|
test "keyed SET expressions are evaluated once before capture and preserve authored public Results" {
  let program = keyed_record_program(
    "FROM messages |> RESULT authored |> EFFECT change UPSERT salesforce.Account ID messages.id SET (Name = CONCAT(body, '!'))",
  )
  assert_eq(@program.exports(program), [("authored", "main", "rows")])
  assert_eq(@program.effect_header_id(short_command_header(program)), "change")
  let fields = private_update_fields(program)
  assert_eq(fields.length(), 2)
  assert_eq(fields[0], "id")
  let derives = store_capture_steps(program).filter(step => {
    @wire.lookup(@wire.open_object(step).unwrap(), "derive") is Some(_)
  })
  assert_eq(derives.length(), 1)
  assert_eq(
    @wire.object_length(store_capture_field(derives[0], "derive")),
    Some(1),
  )
  let checked = keyed_record_static(program, "all")
  assert_eq(
    @program.effect_header_count(@check.effect_program_static_headers(checked)),
    1,
  )
}

///|
test "keyed static selection precedes expression lowering and never infers an installation" {
  let query = @query.parse_query(
    "FROM messages |> EFFECT UPSERT salesforce.Account ID absent SET (Name = absent)",
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
  let duplicate = @query.parse_query(
    "FROM messages |> EFFECT UPSERT salesforce.Account ID id SET (Name = body, Name = 'other')",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(
      duplicate,
      short_command_context(),
      construction_limits(),
      update_targets=Some(keyed_record_publication("all")),
    )
    is Err(DuplicateOutput),
  )
}
