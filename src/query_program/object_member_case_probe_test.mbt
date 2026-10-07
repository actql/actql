///|
fn member_case_control() -> @program.Program {
  // Independent machine input: exact field names and nullable receiver type.
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"id":2,"payload":{"score":20}},{"id":1,"payload":null}]},"as":"objects"},{"from":"objects","derive":{"aql_query_expr_0":{"property":{"value":{"field":"payload"},"name":"score"}}}},{"select":[{"value":"aql_query_expr_0"},"id"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["value","id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn member_case_require_checked(
  program : @program.Program,
  description : String,
) -> Unit raise {
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(diagnostic) => {
      guard @check.diagnostic_cause(diagnostic)
        is Source(SourceView(Program(Program(Pipeline(_, issue))))) else {
        raise @check.diagnostic_cause(diagnostic)
      }
      match issue.kind {
        Operation(Expression(UnknownField(name))) =>
          fail(
            description +
            ": common checker rejects unchanged member spelling " +
            name,
          )
        _ => raise @check.diagnostic_cause(diagnostic)
      }
    }
    _ => fail("Values control requires no Source or parameter acquisition")
  }
}

///|
test "member case probe independent exact machine control" {
  let expected = member_case_control()
  member_case_require_checked(expected, "independent machine control")
  let actual = compile(
    @query.parse_query(
      "SELECT payload.score AS value, id FROM objects",
      syntax_limits(),
    ).unwrap(),
    implicit_property_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "member case probe unquoted source preserves declared field name" {
  let expected = member_case_control()
  member_case_require_checked(expected, "independent machine control")
  let actual = compile(
    @query.parse_query(
      "SELECT payload.SCORE AS value, id FROM objects",
      syntax_limits(),
    ).unwrap(),
    implicit_property_context(),
    construction_limits(),
  ).unwrap()
  member_case_require_checked(
    actual, "unquoted SCORE must resolve declared score",
  )
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "member case probe quoted qualified source preserves declared field name" {
  let expected = member_case_control()
  member_case_require_checked(expected, "independent machine control")
  let actual = compile(
    @query.parse_query(
      "SELECT `objects`.`payload`.`SCORE` AS value, id FROM objects",
      syntax_limits(),
    ).unwrap(),
    implicit_property_context(),
    construction_limits(),
  ).unwrap()
  member_case_require_checked(
    actual, "quoted SCORE must resolve declared score",
  )
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "member case probe computed receiver preserves declared field name" {
  let expected = member_case_control()
  member_case_require_checked(expected, "independent machine control")
  let actual = compile(
    @query.parse_query(
      "SELECT (COALESCE(payload, payload)).SCORE AS value, id FROM objects",
      syntax_limits(),
    ).unwrap(),
    implicit_property_context(),
    construction_limits(),
  ).unwrap()
  member_case_require_checked(
    actual, "computed nullable receiver has declared score",
  )
}

///|
test "member case binding retains aliases qualified receivers and current Pipe scope" {
  for
    text in [
      "SELECT id, payload.SCORE AS original_score, other AS payload FROM objects ORDER BY payload.SCORE NULLS LAST, id",
      "SELECT id, payload.SCORE AS original_score, other AS payload FROM objects ORDER BY objects.payload.SCORE NULLS LAST, id",
      "FROM objects AS original |> SET payload = other |> SELECT id, original.payload.SCORE AS before, payload.SCORE AS current |> ORDER BY id",
      "WITH chosen AS (SELECT id, payload FROM objects) SELECT payload.SCORE AS score FROM chosen ORDER BY id",
      "SELECT o.payload.SCORE AS score FROM objects AS o JOIN pair AS p ON o.id = p.x ORDER BY score",
      "SELECT payload.SCORE AS score, COUNT(*) AS n FROM objects GROUP BY payload.SCORE ORDER BY score",
      "SELECT id, LAG(payload.SCORE) OVER (ORDER BY id) AS previous FROM objects ORDER BY id",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      {
        ..analytic_property_context(),
        inputs: analytic_property_context().inputs + pair_context().inputs,
      },
      construction_limits(),
    ).unwrap()
    member_case_require_checked(program, text)
    assert_false(semantic(program).contains("\"name\":\"SCORE\""))
  }
  assert_true(
    compile(
      @query.parse_query(
        "FROM objects AS original |> SELECT id |> SELECT original.payload.SCORE AS score",
        syntax_limits(),
      ).unwrap(),
      analytic_property_context(),
      construction_limits(),
    )
    is Err(Expression({ issue: UnknownReference, .. })),
  )
}

///|
test "member case binding refuses folded ambiguity without changing JSON machine lookup" {
  let context = implicit_property_context()
  let seed = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":false},"SCORE":{"type":"string","nullable":false}}}},"rows":[]},"as":"objects"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let context = {
    ..context,
    inputs: [{ ..context.inputs[0], source: GeneratedValues(seed), }],
  }
  for
    text in [
      "SELECT payload.score AS value FROM objects", "SELECT payload.`SCORE` AS value FROM objects",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        context,
        construction_limits(),
      )
      is Err(AmbiguousColumn),
    )
  }
  let source = semantic(member_case_control()).replace(
    old="\"name\":\"score\"",
    new="\"name\":\"SCORE\"",
  )
  let machine = @program.parse(
    source,
    construction_limits().program,
    format=Json,
  ).unwrap()
  guard @check.check_parsed(machine, check_environment(), None, check_limits())
    is Rejected(diagnostic) else {
    fail("machine input remains exact")
  }
  assert_true(
    @check.diagnostic_cause(diagnostic)
    is Source(
      SourceView(
        Program(
          Program(
            Pipeline(
              _,
              { kind: Operation(Expression(UnknownField("SCORE"))), .. }
            )
          )
        )
      )
    ),
  )
}

///|
test "member case binding uses declared mixed spelling for parameter receivers" {
  let raw = @wire.admit(
    @source.parse_json(
      (
        #|{"p":{"type":"object","nullable":true,"fields":{"Score":{"type":"number","nullable":false}}}}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let declarations = @parameters.read_declarations(Some(raw), {
    max_parameters: 2,
    max_nodes: 100,
    max_depth: 20,
    max_text_bytes: 1000,
  }).unwrap()
  let context = {
    ..implicit_property_context(),
    parameter_declarations: Some(declarations),
  }
  let program = compile(
    @query.parse_query(
      "SELECT (@p).sCoRe AS value FROM objects WHERE FALSE",
      syntax_limits(),
    ).unwrap(),
    context,
    construction_limits(),
  ).unwrap()
  let wire = semantic(program)
  assert_true(wire.contains("\"name\":\"Score\""))
  assert_true(
    wire.contains("\"Score\":{\"nullable\":false,\"type\":\"number\"}"),
  )
  assert_false(wire.contains("\"name\":\"score\""))
}
