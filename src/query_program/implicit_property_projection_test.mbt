///|
fn implicit_property_context() -> Context {
  let seed = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"id":2,"payload":{"score":20}},{"id":1,"payload":null}]},"as":"objects"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  {
    ..pair_context(),
    inputs: [
      {
        relation: [{ value: "objects", quoted: false, }],
        name: "objects",
        source: GeneratedValues(seed),
        visible_fields: ["id", "payload"],
        graph_bindings: [],
      },
    ],
  }
}

///|
fn implicit_property_expected() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"id":2,"payload":{"score":20}},{"id":1,"payload":null}]},"as":"objects"},{"from":"objects","derive":{"aql_query_expr_0":{"property":{"value":{"field":"payload"},"name":"score"}}}},{"select":[{"score":"aql_query_expr_0"},"id"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["score","id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "implicit property projection independent Program passes common checking" {
  match
    @check.check_parsed(
      implicit_property_expected(),
      check_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    NeedsInputs(_) => fail("typed Values require no acquisition")
  }
}

///|
test "implicit property projection SQL matches the independent Program" {
  let expected = implicit_property_expected()
  for
    path in [
      "payload.score", "objects.payload.score", "`objects`.`payload`.`score`",
    ] {
    let actual = compile(
      @query.parse_query(
        "SELECT " + path + ", id FROM objects",
        syntax_limits(),
      ).unwrap(),
      implicit_property_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
  }
}

///|
test "implicit property projection Pipe matches the independent Program" {
  let actual = compile(
    @query.parse_query(
      "FROM objects |> SELECT payload.score, id",
      syntax_limits(),
    ).unwrap(),
    implicit_property_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(implicit_property_expected()))
}

///|
test "implicit property projection preserves authored output spelling" {
  let actual = compile(
    @query.parse_query(
      "SELECT `ID`, payload.score AS value FROM objects",
      syntax_limits(),
    ).unwrap(),
    implicit_property_context(),
    construction_limits(),
  ).unwrap()
  assert_true(
    semantic(actual).contains(
      "\"select\":[{\"ID\":\"id\"},{\"value\":\"aql_query_expr_1\"}]",
    ),
  )
  for
    text in [
      "SELECT id FROM objects", "FROM objects |> AS current |> SELECT current.payload.score, id",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      implicit_property_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      NeedsInputs(_) =>
        fail("existing column and scoped projection remain source-free")
    }
  }
}

///|
test "implicit property projection preserves missing and ambiguous receiver diagnostics" {
  match
    compile(
      @query.parse_query("SELECT missing.score FROM objects", syntax_limits()).unwrap(),
      implicit_property_context(),
      construction_limits(),
    ) {
    Err(UnknownColumn) => ()
    _ => fail("a leaf name does not make an unknown receiver visible")
  }
  let context = implicit_property_context()
  let input = context.inputs[0]
  let ambiguous_seed = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"payload":{"type":"object","nullable":false,"fields":{"score":{"type":"number","nullable":false}}},"PAYLOAD":{"type":"object","nullable":false,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[]},"as":"objects"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  match
    compile(
      @query.parse_query("SELECT payload.score FROM objects", syntax_limits()).unwrap(),
      {
        ..context,
        inputs: [
          {
            ..input,
            source: GeneratedValues(ambiguous_seed),
            visible_fields: ["payload", "PAYLOAD"],
          },
        ],
      },
      construction_limits(),
    ) {
    Err(AmbiguousColumn) => ()
    _ =>
      fail(
        "case-insensitive receiver ambiguity must not become a property slot",
      )
  }
}

///|
test "implicit property projection retains duplicate output and common property type checks" {
  match
    compile(
      @query.parse_query(
        "SELECT payload.score, objects.payload.score FROM objects",
        syntax_limits(),
      ).unwrap(),
      implicit_property_context(),
      construction_limits(),
    ) {
    Err(DuplicateOutput) => ()
    _ => fail("both paths have the same public leaf name")
  }
  for
    text in [
      "SELECT payload.missing FROM objects", "SELECT id.score FROM objects",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      implicit_property_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(program, check_environment(), None, check_limits())
      is Rejected(_),
      msg="the common checker validates properties and nullable receiver types",
    )
  }
}
