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
