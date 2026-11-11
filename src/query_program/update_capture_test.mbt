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
fn private_update_issue_label(issue : Issue) -> String {
  match issue {
    InvalidContext => "InvalidContext"
    UnknownRelation => "UnknownRelation"
    UnknownColumn => "UnknownColumn"
    AmbiguousColumn => "AmbiguousColumn"
    DuplicateOutput => "DuplicateOutput"
    UnsupportedEffect => "UnsupportedEffect"
    Admission(_) => "Admission"
    Construction(_) => "Construction"
    Expression(diagnostic) => @debug.to_string(diagnostic.issue)
    ExpressionTyping(_) => "ExpressionTyping"
    BindingPreparation(_) => "BindingPreparation"
    BindingPreparationSource(_, _) => "BindingPreparationSource"
    _ => "other lowering refusal"
  }
}

///|
fn private_update_program(body : String) -> @program.Program raise {
  let parsed = match @query.parse_query(body, syntax_limits()) {
    Ok(parsed) => parsed
    Err(issue) => fail("UPDATE syntax refused: " + @debug.to_string(issue))
  }
  match compile(parsed, private_update_context(), construction_limits()) {
    Ok(program) => program
    Err(issue) =>
      fail("UPDATE compilation refused: " + private_update_issue_label(issue))
  }
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
) -> @check.EffectProgramStaticCandidate raise {
  let environment = update_shorthand_environment()
  let candidate = match
    @check.prepare_effect_computation_candidate(
      program,
      environment,
      None,
      [],
      check_limits(),
      1,
      100,
    ) {
    Ok(candidate) => candidate
    Err(issue) => {
      let reason = match issue {
        InvalidLimits => "InvalidLimits"
        InvalidProgram(_) => "InvalidProgram"
        Headers(_) => "Headers"
        MissingEffects => "MissingEffects"
        Phase(AlreadyConsumed) => "Phase.AlreadyConsumed"
        Computation(cause) =>
          match cause {
            @check.LocalConstructionFailure::InvalidLimits =>
              "Computation.InvalidLimits"
            @check.LocalConstructionFailure::Program(_) => "Computation.Program"
            @check.LocalConstructionFailure::CapacityInputs(_) =>
              "Computation.CapacityInputs"
            @check.LocalConstructionFailure::Environment(_) =>
              "Computation.Environment"
            @check.LocalConstructionFailure::Source(cause) =>
              match cause {
                @check.SourceFailure::Checks(_) => "Computation.Source.Checks"
                @check.SourceFailure::Registration(_) =>
                  "Computation.Source.Registration"
                @check.SourceFailure::Identity(_) =>
                  "Computation.Source.Identity"
                @check.SourceFailure::Requests(_) =>
                  "Computation.Source.Requests"
                @check.SourceFailure::Declarations(_) =>
                  "Computation.Source.Declarations"
                @check.SourceFailure::DeclarationWorkLimit =>
                  "Computation.Source.DeclarationWorkLimit"
                @check.SourceFailure::CapacityMetadataBudget =>
                  "Computation.Source.CapacityMetadataBudget"
                @check.SourceFailure::UnsupportedBindings(_) =>
                  "Computation.Source.UnsupportedBindings"
                @check.SourceFailure::UnsupportedEffects(_) =>
                  "Computation.Source.UnsupportedEffects"
                @check.SourceFailure::RequestForm(_) =>
                  "Computation.Source.RequestForm"
                @check.SourceFailure::SourceView(_) =>
                  "Computation.Source.SourceView"
              }
            @check.LocalConstructionFailure::Closure(_) => "Computation.Closure"
            @check.LocalConstructionFailure::Units(_) => "Computation.Units"
            @check.LocalConstructionFailure::Template(_, _) =>
              "Computation.Template"
          }
      }
      fail("UPDATE checker refused: " + reason)
    }
  }
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
    assert_eq(@program.exports(program).map(entry => entry.0), [
      "early", "answer",
    ])
    assert_false(private_update_fields(program).contains("secret"))
  }
  let source = @wire.open_object(private_update_result(explicit)).unwrap()
  let capture = @wire.text(@wire.required(source, "from").unwrap()).unwrap()
  let body = semantic(explicit)
  let stage = @wire.open_object(
    @program.stage_body(@program.stages(explicit)[0]),
  ).unwrap()
  assert_true(
    @wire.elements(@wire.required(stage, "steps").unwrap())
    .unwrap()
    .any(step => {
      let step = @wire.open_object(step).unwrap()
      @wire.lookup(step, "derive") is Some(_) &&
      @wire.lookup(step, "from")
      .map(value => @wire.text(value) == Ok("aql_result_checkpoint_0"))
      .unwrap_or(false)
    }),
  )
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
      "", "A = id, B = value, C = value, D = '😀\\r\\ntext', E = NULL",
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

///|
test "private UPDATE keeps immutable range bindings after Pipe SET" {
  let program = compile(
    @query.parse_query(
      "FROM pair AS before |> SET y = x |> EFFECT UPDATE TARGET 'connector://c/T' MAPPING m ID x SET (Original = before.y, Current = y + 1)",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  let wire = semantic(program)
  assert_true(wire.contains("\"Original\":{\"field\":\"y\"}"))
  assert_true(
    wire.contains("\"add\":[{\"field\":\"aql_pipe_set_2\"},{\"literal\":1}]"),
  )
  assert_eq(@program.export_count(program), 0)
}

///|
test "computed UPDATE retains nested access and lazy CASE in the common expression" {
  let step = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"id":{"type":"string","nullable":false},"payload":{"type":"object","nullable":false,"fields":{"score":{"type":"number","nullable":true}}}},"rows":[{"id":"original-id","payload":{"score":2}}]},"as":"nested"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let context = {
    ..private_update_context(),
    inputs: [
      {
        relation: [{ value: "nested", quoted: false, }],
        name: "nested",
        source: GeneratedValues(step),
        visible_fields: ["id", "payload"],
        graph_bindings: [],
      },
    ],
  }
  let program = compile(
    @query.parse_query(
      "FROM nested" +
      private_update_tail(
        "", "Name = CASE WHEN payload.score IS NULL THEN 0 ELSE payload.score + 1 END",
      ),
      syntax_limits(),
    ).unwrap(),
    context,
    construction_limits(),
  ).unwrap()
  assert_eq(private_update_fields(program), ["id", "aql_update_value_2"])
  assert_true(semantic(program).contains("\"property\":{\"name\":\"score\""))
  ignore(private_update_static(program))
  // The branch remains present. No frontend evaluation folds it or suppresses
  // a demanded error; execution of CASE laziness remains a separate check.
  let lazy_program = private_update_program(
    "FROM updates_source" +
    private_update_tail(
      "", "Name = CASE WHEN value > 0 THEN value ELSE 1 / 0 END",
    ),
  )
  assert_true(
    semantic(lazy_program).contains(
      "\"divide\":[{\"literal\":1},{\"literal\":0}]",
    ),
  )
  ignore(private_update_static(lazy_program))
}

///|
test "UPDATE expressions reject wrong pure types at the existing checker" {
  let parsed = @query.parse_query(
    "FROM updates_source" + private_update_tail("", "Name = secret + 1"),
    syntax_limits(),
  ).unwrap()
  match compile(parsed, private_update_context(), construction_limits()) {
    Err(_) => ()
    Ok(program) =>
      assert_true(
        @check.prepare_effect_computation_candidate(
          program,
          update_shorthand_environment(),
          None,
          [],
          check_limits(),
          1,
          100,
        )
        is Err(_),
      )
  }
}

///|
test "UPDATE unknown nested members retain the authored expression diagnostic" {
  let source = "/*😀*/\r\nFROM updates_source" +
    private_update_tail("", "Name = missing.member + 1")
  let query = @query.parse_query(
    source,
    syntax_limits(),
    source_path="update-original.sql",
  ).unwrap()
  guard compile(query, private_update_context(), construction_limits())
    is Err(Expression({ origin: Some(origin), .. })) else {
    fail("Expected the ordinary expression diagnostic and original origin")
  }
  let span = @origin.span(origin)
  assert_eq(span.source_path, "update-original.sql")
  assert_true(span.start_byte > 0)
  assert_true(span.end_byte > span.start_byte)
}

///|
test "earlier INFER Result is imported once and retains public tail behavior" {
  let environment = infer_member_environment()
  let prefix = infer_member_source(
    "RESULT early |> WHERE id = 'a' |> RENAME assessment AS later",
  )
  for selection in ["FROM RESULT early ", ""] {
    let expression = if selection == "" {
      "later.value.risk"
    } else {
      "assessment.value.risk"
    }
    let query = @query.parse_query(
      prefix + private_update_tail(selection, "Name = " + expression),
      syntax_limits(),
    ).unwrap()
    let program = compile(
      query,
      infer_member_context(environment),
      construction_limits(),
    ).unwrap()
    assert_eq(@program.exports(program).map(entry => entry.0), [
      "early", "answer",
    ])
    assert_eq(@program.stage_count(program), 2)
    let tail = @program.stages(program)[1]
    let from_early = @program.imports(tail).filter(entry => {
      entry.1 is @program.Result(producer="main", result="rows")
    })
    assert_eq(from_early.length(), 1)
    let mut calls = 0
    for stage in @program.stages(program) {
      let stage = @wire.open_object(@program.stage_body(stage)).unwrap()
      for
        step in @wire.elements(@wire.required(stage, "steps").unwrap()).unwrap() {
        if @wire.lookup(@wire.open_object(step).unwrap(), "infer") is Some(_) {
          calls += 1
        }
      }
    }
    assert_eq(calls, 1)
    assert_false(private_update_fields(program).contains("assessment"))
    assert_false(private_update_fields(program).contains("later"))
  }
}

///|
test "private UPDATE names avoid authored Stage and value slots" {
  let step = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"id":{"type":"string","nullable":false},"value":{"type":"number","nullable":false},"aql_update_value_3":{"type":"number","nullable":false}},"rows":[{"id":"original-id","value":1,"aql_update_value_3":99}]},"as":"aql_update_capture_4"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let base = private_update_context()
  let context = {
    ..base,
    stage_result: "aql_private_update",
    inputs: [
      {
        ..base.inputs[0],
        name: "aql_update_capture_4",
        source: GeneratedValues(step),
        visible_fields: ["id", "value", "aql_update_value_3"],
      },
    ],
  }
  let compiled = compile(
    @query.parse_query(
      "FROM updates_source" + private_update_tail("", "Name = value + 1"),
      syntax_limits(),
    ).unwrap(),
    context,
    construction_limits(),
  )
  let program = match compiled {
    Ok(program) => program
    Err(issue) =>
      fail("UPDATE collision refused: " + private_update_issue_label(issue))
  }
  assert_eq(@program.export_count(program), 0)
  let stage = @program.stages(program)[0]
  assert_eq(@program.result_names(stage), ["aql_private_update_retained"])
  let body = semantic(program)
  assert_true(body.contains("\"as\":\"aql_update_capture_5\""))
  assert_true(body.contains("\"Name\":{\"field\":\"aql_update_value_4\"}"))
  assert_true(body.contains("\"fields\":[\"id\",\"aql_update_value_4\"]"))
}

///|
test "private UPDATE literal assignments retain only their selector" {
  let program = private_update_program(
    "FROM updates_source" + private_update_tail("", "Name = 7"),
  )
  assert_eq(private_update_fields(program), ["id"])
  assert_false(semantic(program).contains("aql_update_value_"))
  ignore(private_update_static(program))
}

///|
test "JOIN set heads do not capture terminal UPDATE before the complete set" {
  let query = @query.parse_query(
    "FROM pair AS l JOIN pair AS r ON l.x = r.x |> SELECT l.x AS x, r.y AS y |> WHERE y > 0 |> UNION ALL (FROM pair) |> EFFECT UPDATE TARGET 'connector://c/T' MAPPING m ID x SET (Name = y + 1)",
    syntax_limits(),
  ).unwrap()
  let program = compile(query, pair_context(), construction_limits()).unwrap()
  let body = semantic(program)
  assert_eq(@program.export_count(program), 0)
  assert_eq(body.split("\"append\":").length() - 1, 1)
  assert_eq(body.split("\"aql_private_update\":{").length() - 1, 1)
  let stages = @program.stages(program)
  let mut capture_aliases = 0
  for stage in stages {
    let stage = @wire.open_object(@program.stage_body(stage)).unwrap()
    for step in @wire.elements(@wire.required(stage, "steps").unwrap()).unwrap() {
      let step = @wire.open_object(step).unwrap()
      if @wire.lookup(step, "as") is Some(binding_name) &&
        @wire.text(binding_name).unwrap().has_prefix("aql_update_capture_") {
        capture_aliases += 1
      }
    }
  }
  assert_eq(capture_aliases, 1)
}
