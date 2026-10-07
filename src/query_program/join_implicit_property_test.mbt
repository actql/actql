///|
fn join_implicit_property_context() -> Context {
  let context = implicit_property_context()
  let seed = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"k":{"type":"number","nullable":false}},"rows":[{"k":2},{"k":1}]},"as":"keys"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  {
    ..context,
    inputs: context.inputs +
    [
      {
        relation: [{ value: "keys", quoted: false, }],
        name: "keys",
        source: GeneratedValues(seed),
        visible_fields: ["k"],
        graph_bindings: [],
      },
    ],
  }
}

///|
// Authored from the existing JOIN, property, projection and sort contracts.
// Allocation starts after the five reserved output/input names, then advances.
// The public leaf name never replaces the nullable receiver's private slot.
fn join_implicit_property_expected() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"aql_join_left","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"id":2,"payload":{"score":20}},{"id":1,"payload":null}]},"as":"objects"}],"results":{"aql_join_left":{"from":"objects","fields":["id","payload"]}}},{"id":"aql_join_right","inputs":{},"steps":[{"values":{"schema":{"k":{"type":"number","nullable":false}},"rows":[{"k":2},{"k":1}]},"as":"keys"}],"results":{"aql_join_right":{"from":"keys","fields":["k"]}}},{"id":"main","inputs":{"l":{"result":{"stage":"aql_join_left","result":"aql_join_left"}},"r":{"result":{"stage":"aql_join_right","result":"aql_join_right"}}},"steps":[{"from":"l","join":{"with":"r","kind":"inner","on":[{"left":"id","right":"k"}],"max_output_rows":4,"select":{"aql_join_input_5":"left.payload","aql_join_input_6":"left.id"}},"as":"aql_join_raw"},{"from":"aql_join_raw","derive":{"score":{"property":{"value":{"field":"aql_join_input_5"},"name":"score"}}},"as":"aql_join_derived"},{"from":"aql_join_derived","select":["score",{"id":"aql_join_input_6"}],"as":"aql_join_output"},{"from":"aql_join_output","sort":[{"field":"score","dir":"asc","nulls":"last"},{"field":"id","dir":"asc","nulls":"first"}],"as":"aql_join_sorted"}],"results":{"rows":{"from":"aql_join_sorted","fields":["score","id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "JOIN implicit property alias matches an independent checked Program" {
  let expected = join_implicit_property_expected()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    NeedsInputs(_) => fail("independent Values control has no external inputs")
  }
  for
    source in [
      "SELECT (l.payload).score, l.id FROM objects AS l JOIN keys AS r ON l.id = r.k ORDER BY score NULLS LAST, id",
      "SELECT (l.`payload`).`score`, l.id FROM objects AS l JOIN keys AS r ON l.id = r.k ORDER BY `score` NULLS LAST, id",
      "FROM objects AS l |> JOIN keys AS r ON l.id = r.k |> SELECT (l.payload).score, l.id |> ORDER BY score NULLS LAST, id",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_implicit_property_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
    match
      @check.check_parsed(actual, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      NeedsInputs(_) => fail("compiled Values control has no external inputs")
    }
  }
}

///|
test "JOIN implicit property alias preserves duplicate and receiver diagnostics" {
  for projection in ["(l.payload).score, (l.payload).score", "(missing).score"] {
    match
      compile(
        @query.parse_query(
          "SELECT " +
          projection +
          " FROM objects AS l JOIN keys AS r ON l.id = r.k",
          syntax_limits(),
        ).unwrap(),
        join_implicit_property_context(),
        construction_limits(),
      ) {
      Err(DuplicateOutput) if projection ==
        "(l.payload).score, (l.payload).score" => ()
      Err(UnknownColumn) if projection == "(missing).score" => ()
      _ => fail("an implicit leaf alias preserves the owned rejection reason")
    }
  }
}

///|
test "JOIN implicit property alias reaches CTE and computed receiver checking" {
  for
    source in [
      "WITH lhs AS (SELECT id, payload FROM objects), rhs AS (SELECT k FROM keys) SELECT (l.payload).score, l.id FROM lhs AS l JOIN rhs AS r ON l.id = r.k MAX_OUTPUT_ROWS 4 ORDER BY score NULLS LAST, id",
      "WITH lhs AS (SELECT id, payload FROM objects), rhs AS (SELECT k FROM keys) FROM lhs AS l |> JOIN rhs AS r ON l.id = r.k MAX_OUTPUT_ROWS 4 |> SELECT (l.payload).score, l.id |> ORDER BY score NULLS LAST, id",
      "SELECT (IF(TRUE, l.payload, NULL)).score, l.id FROM objects AS l JOIN keys AS r ON l.id = r.k ORDER BY score NULLS LAST, id",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_implicit_property_context(),
      construction_limits(),
    ).unwrap()
    check_join_property(actual)
    let body = semantic(actual)
    assert_true(body.contains("\"fields\":[\"score\",\"id\"]"))
    assert_true(body.contains("\"field\":\"score\",\"nulls\":\"last\""))
    assert_true(body.contains("\"name\":\"score\""))
  }
}
