///|
// The Values seed and expected projection follow the independent INFER fixture.
// The explicit uniqueness assertion supplies the existing ITEM KEY precondition.
// This generated Values context is a compiler control, not a public Source.
fn infer_input_field_context(environment : @check.CheckEnvironment) -> Context {
  let source = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"id":{"type":"string","nullable":false},"text":{"type":"string","nullable":true},"secret":{"type":"string","nullable":false}},"rows":[{"id":"a","text":"urgent","secret":"private-a"},{"id":"b","text":null,"secret":"private-b"}]},"as":"tickets"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  {
    ..infer_member_context(environment),
    program_id: "fixture.infer_keep",
    inputs: [
      {
        relation: [{ value: "tickets", quoted: false, }],
        name: "tickets",
        source: GeneratedValues(source),
        visible_fields: ["id", "text", "secret"],
        graph_bindings: [],
      },
    ],
  }
}

///|
test "INFER INPUT field lookup retains the admitted contract spelling" {
  let environment = infer_member_environment()
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.infer_keep","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"text":{"type":"string","nullable":true},"secret":{"type":"string","nullable":false}},"rows":[{"id":"a","text":"urgent","secret":"private-a"},{"id":"b","text":null,"secret":"private-b"}]},"as":"tickets"},{"from":"tickets","assert_rows":{"unique_by":["id"]}},{"select":["id","text","secret"],"as":"aql_infer_input_1"},{"from":"aql_infer_input_1","infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"aql_infer_outcome_1"},{"derive":{"aql_infer_result_5":{"object":{"input_key":{"object":{"id":{"field":"id"}}},"outcome":{"field":"outcome"},"value":{"field":"value"}}}}},{"select":[{"assessment":"aql_infer_result_5"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["assessment"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match @check.check_parsed(expected, environment, None, check_limits()) {
    Checked(_) => ()
    Rejected(error) =>
      match @check.diagnostic_cause(error) {
        Source(SourceView(Program(Program(Pipeline(_, issue))))) =>
          fail("independent control: " + @debug.to_string(issue.kind))
        other => raise other
      }
    NeedsInputs(_) => fail("closed independent Values control")
  }
  for field in ["text", "TEXT", "`TeXt`"] {
    let text = "FROM tickets AS old |> ASSERT UNIQUE BY (id) |> INFER `model-task:risk-score.v1` " +
      "ITEM KEY (id) INPUT (" +
      field +
      " = text) AS assessment"
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      infer_input_field_context(environment),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=field)
    match @check.check_parsed(actual, environment, None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      NeedsInputs(_) => fail("closed source Values control")
    }
  }
}

///|
test "INFER INPUT binding preserves missing contract and field refusals" {
  let environment = infer_member_environment()
  let prefix = "FROM tickets |> ASSERT UNIQUE BY (id) |> INFER "
  for
    clause in [
      "`model-task:risk-score.v1` ITEM KEY (id) INPUT (absent = text) AS assessment",
      "`MODEL-TASK:RISK-SCORE.V1` ITEM KEY (id) INPUT (TEXT = text) AS assessment",
    ] {
    let actual = compile(
      @query.parse_query(prefix + clause, syntax_limits()).unwrap(),
      infer_input_field_context(environment),
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(actual, environment, None, check_limits())
      is Rejected(_),
      msg=clause,
    )
  }
  assert_true(
    compile(
      @query.parse_query(
        prefix +
        "`model-task:risk-score.v1` ITEM KEY (id) INPUT (text = text, TEXT = text) AS assessment",
        syntax_limits(),
      ).unwrap(),
      infer_input_field_context(environment),
      construction_limits(),
    )
    is Err(DuplicateOutput),
  )
}

///|
test "INFER INPUT contract binding reaches source-free and WITH compilation" {
  let environment = infer_member_environment()
  let context = infer_member_context(environment)
  for
    source in [
      "SELECT DISTINCT 'a' AS id |> EXTEND 'urgent' AS text |> INFER `model-task:risk-score.v1` ITEM KEY (id) INPUT (TEXT = text) AS assessment",
      "WITH seed AS (SELECT DISTINCT 'a' AS id |> EXTEND 'urgent' AS text) FROM seed |> INFER `model-task:risk-score.v1` ITEM KEY (id) INPUT (`TeXt` = text) AS assessment",
    ] {
    let actual = compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      context,
      construction_limits(),
    ).unwrap()
    assert_true(
      semantic(actual).contains("\"input\":{\"text\":{\"field\":"),
      msg=source,
    )
    match @check.check_parsed(actual, environment, None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      NeedsInputs(_) => fail("closed source-free and WITH controls")
    }
  }
}
