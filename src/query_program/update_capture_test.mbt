///|
fn private_update_context() -> Context {
  let source = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"id":{"type":"string","nullable":false},"value":{"type":"number","nullable":false},"secret":{"type":"string","nullable":false}},"rows":[{"id":"original-id","value":1,"secret":"not-an-effect-input"}]},"as":"updates_source"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  {
    ..pair_context(),
    program_id: "fixture.update_private",
    inputs: [
      {
        relation: [{ value: "updates_source", quoted: false, }],
        name: "updates_source",
        source: GeneratedValues(source),
        visible_fields: ["id", "value", "secret"],
        graph_bindings: [],
      },
    ],
  }
}

///|
fn private_update_program(body : String) -> @program.Program {
  compile(
    @query.parse_query(body, syntax_limits()).unwrap(),
    private_update_context(),
    construction_limits(),
  ).unwrap()
}

///|
fn private_update_tail(selection : String, assignments : String) -> String {
  " |> EFFECT UPDATE TARGET 'connector://crm/account' MAPPING `mapping:crm.account.v1` " +
  selection +
  "ID id SET (" +
  assignments +
  ")"
}

///|
fn private_update_result(program : @program.Program) -> @wire.Cursor {
  let stage = @program.stages(program).last().unwrap()
  let body = @wire.open_object(@program.stage_body(stage)).unwrap()
  let ports = @wire.open_object(@wire.required(body, "results").unwrap()).unwrap()
  @wire.required(ports, "aql_private_update").unwrap()
}

///|
fn private_update_fields(program : @program.Program) -> Array[String] {
  let result = @wire.open_object(private_update_result(program)).unwrap()
  @wire.elements(@wire.required(result, "fields").unwrap())
  .unwrap()
  .map(field => @wire.text(field).unwrap())
}

///|
fn private_update_static(
  program : @program.Program,
) -> @check.EffectProgramStaticCandidate {
  let environment = update_shorthand_environment()
  let candidate = @check.prepare_effect_computation_candidate(
    program,
    environment,
    None,
    [],
    check_limits(),
    1,
    100,
  ).unwrap()
  let mappings = @environment.check_mapping_contract_shapes(
    @check.checking_environment_wire(environment),
    { max_bytes: 20000, max_nodes: 2000, max_depth: 100, max_members: 100, },
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
test "implicit UPDATE has one minimal private Result and no public export" {
  let program = private_update_program(
    "FROM updates_source" + private_update_tail("", "Name = value"),
  )
  assert_eq(@program.export_count(program), 0)
  assert_eq(@program.result_names(@program.stages(program)[0]), [
    "aql_private_update",
  ])
  assert_eq(private_update_fields(program), ["id", "value"])
  assert_eq(@program.stage_table_input_count(@program.stages(program)[0]), 0)
  let actual = private_update_static(program)
  assert_eq(
    @program.effect_header_count(@check.effect_program_static_headers(actual)),
    1,
  )
}

///|
test "private UPDATE canonical identity matches an independently expanded Program" {
  let actual = private_update_program(
    "FROM updates_source" + private_update_tail("", "Name = value + 1"),
  )
  // Authored from the private capture contract, not a snapshot of compiler output.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.update_private","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"value":{"type":"number","nullable":false},"secret":{"type":"string","nullable":false}},"rows":[{"id":"original-id","value":1,"secret":"not-an-effect-input"}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","select":["id","value","secret"],"as":"aql_update_input_5"},{"from":"aql_update_input_5","select":["id","value","secret"],"as":"aql_script_result"},{"from":"aql_update_input_5","derive":{"aql_update_value_3":{"add":[{"field":"value"},{"literal":1}]}}},{"select":["id","aql_update_value_3"],"as":"aql_update_capture_4"}],"results":{"aql_private_update":{"from":"aql_update_capture_4","fields":["id","aql_update_value_3"]}},"effects":{"aql_update_effect":{"update":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"aql_private_update"},"id":"id","set":{"Name":{"field":"aql_update_value_3"}}}}}}],"results":{}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
  let actual = private_update_static(actual)
  let expected = private_update_static(expected)
  assert_shorthand_checked_identity(
    @check.effect_program_static_checked_computation(actual),
    @check.effect_program_static_checked_computation(expected),
  )
  assert_eq(
    @check.effect_program_static_definition_cid(actual),
    @check.effect_program_static_definition_cid(expected),
  )
  assert_eq(
    @check.effect_program_static_semantics_cid(actual),
    @check.effect_program_static_semantics_cid(expected),
  )
}

///|
test "authored terminal Result stays public and contains no SET helper" {
  let program = private_update_program(
    "FROM updates_source |> RESULT public_rows" +
    private_update_tail("FROM RESULT public_rows ", "Name = value + 1"),
  )
  assert_eq(@program.exports(program), [("public_rows", "main", "rows")])
  assert_eq(private_update_fields(program), ["id", "aql_update_value_3"])
  let stage = @wire.open_object(
    @program.stage_body(@program.stages(program)[0]),
  ).unwrap()
  let ports = @wire.open_object(@wire.required(stage, "results").unwrap()).unwrap()
  let public = @wire.open_object(@wire.required(ports, "rows").unwrap()).unwrap()
  assert_eq(
    @wire.elements(@wire.required(public, "fields").unwrap())
    .unwrap()
    .map(field => @wire.text(field).unwrap()),
    ["id", "value", "secret"],
  )
  let implicit = private_update_program(
    "FROM updates_source" + private_update_tail("", "Name = value + 1"),
  )
  assert_false(semantic(program) == semantic(implicit))
}

///|
test "explicit earlier UPDATE expressions do not bind a renamed filtered tail" {
  let prefix = "FROM updates_source |> RESULT early |> WHERE value > 10 |> RENAME value AS changed"
  let explicit = private_update_program(
    prefix + private_update_tail("FROM RESULT early ", "Name = value + 1"),
  )
  let implicit = private_update_program(
    prefix + private_update_tail("", "Name = changed + 1"),
  )
  for program in [explicit, implicit] {
    assert_eq(@program.exports(program).map(export => export.0), [
      "early", "answer",
    ])
    assert_false(private_update_fields(program).contains("secret"))
  }
  let source = @wire.open_object(private_update_result(explicit)).unwrap()
  let capture = @wire.text(@wire.required(source, "from").unwrap()).unwrap()
  let body = semantic(explicit)
  assert_true(body.contains("\"from\":\"aql_result_checkpoint_0\",\"derive\":"))
  assert_true(body.contains("\"as\":\"" + capture + "\""))
  assert_true(
    compile(
      @query.parse_query(
        prefix + private_update_tail("", "Name = value + 1"),
        syntax_limits(),
      ).unwrap(),
      private_update_context(),
      construction_limits(),
    )
    is Err(_),
  )
}

///|
test "UPDATE captures repeated source fields once and leaves literals sealed" {
  let program = private_update_program(
    "FROM updates_source" +
    private_update_tail(
      "", "A = id, B = value, C = value, D = '😀\r\ntext', E = NULL",
    ),
  )
  assert_eq(private_update_fields(program), ["id", "value"])
  assert_true(
    semantic(program).contains("\"D\":{\"literal\":\"😀\\r\\ntext\"}"),
  )
  assert_true(semantic(program).contains("\"E\":{\"literal\":null}"))
}

///|
test "UPDATE SET targets do not become sibling expression bindings" {
  for
    assignments in [
      "NewName = value + 1, Other = NewName + 2", "Name = value, name = value",
    ] {
    let parsed = @query.parse_query(
      "FROM updates_source" + private_update_tail("", assignments),
      syntax_limits(),
    ).unwrap()
    assert_true(
      compile(parsed, private_update_context(), construction_limits()) is Err(_),
      msg=assignments,
    )
  }
}

///|
test "UPDATE rejects missing inputs and forbidden function expressions" {
  for
    body in [
      "FROM updates_source" + private_update_tail("", "Name = missing + 1"),
      "FROM updates_source" +
      private_update_tail("FROM RESULT absent ", "Name = value"),
      "FROM updates_source" + private_update_tail("", "Name = HTTP(value)"),
    ] {
    let parsed = @query.parse_query(body, syntax_limits()).unwrap()
    assert_true(
      compile(parsed, private_update_context(), construction_limits()) is Err(_),
      msg=body,
    )
  }
}

///|
test "private UPDATE uses the existing expression construction budget" {
  let query = @query.parse_query(
    "FROM updates_source" + private_update_tail("", "Name = value + 1"),
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(query, private_update_context(), {
      ..construction_limits(),
      max_expression_work: 0,
    })
    is Err(_),
  )
}

///|
test "implicit UPDATE captures completed set output rather than a set head" {
  let query = @query.parse_query(
    "SELECT id, value FROM updates_source UNION ALL SELECT id, value FROM updates_source" +
    private_update_tail("", "Name = value + 1"),
    syntax_limits(),
  ).unwrap()
  let program = compile(query, private_update_context(), construction_limits()).unwrap()
  assert_eq(@program.export_count(program), 0)
  assert_eq(@program.result_names(@program.stages(program)[0]), [
    "aql_private_update",
  ])
  assert_eq(private_update_fields(program), ["id", "aql_update_value_2"])
}
