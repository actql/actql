// Ordinary ranges shadow same-named columns, even through parentheses.
// The object operand is the range-qualified payload column.

///|
fn group_receiver_scope_context() -> Context {
  let seed = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"id":{"type":"number","nullable":false},"score":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}}},"rows":[{"id":1,"score":10,"payload":{"score":20}},{"id":2,"score":10,"payload":{"score":30}},{"id":3,"score":20,"payload":null}]},"as":"objects"}
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
        visible_fields: ["id", "score", "payload"],
        graph_bindings: [],
      },
    ],
  }
}

///|
test "GROUP reuse distinguishes an explicit object receiver from a range column" {
  for
    text in [
      "SELECT (payload.payload).score AS object_score, COUNT(*) AS n FROM objects AS payload GROUP BY payload.score",
      "SELECT payload.score AS input_score, COUNT(*) AS n FROM objects AS payload GROUP BY (payload.payload).score",
      "SELECT (payload.payload).score + 1 AS next, COUNT(*) AS n FROM objects AS payload GROUP BY payload.score",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        group_receiver_scope_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: UnknownReference, .. })),
      msg=text,
    )
  }
}

///|
fn group_receiver_scope_expected() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"score":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":true}}}},"rows":[{"id":1,"score":10,"payload":{"score":20}},{"id":2,"score":10,"payload":{"score":30}},{"id":3,"score":20,"payload":null}]},"as":"objects"},{"from":"objects","derive":{"aql_group_key_1":{"property":{"name":"score","value":{"field":"payload"}}}}},{"group":{"by":["score","aql_group_key_1"],"aggregates":{"n":{"fn":"count"}}}},{"select":[{"input_score":"score"},{"object_score":"aql_group_key_1"},"n"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["input_score","object_score","n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "GROUP BY ALL keeps both range and object property keys in an independent Program" {
  let expected = group_receiver_scope_expected()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("both receiver meanings use ordinary checked grouping")
  }
  for
    text in [
      "SELECT payload.score AS input_score, (payload.payload).score AS object_score, COUNT(*) AS n FROM objects AS payload GROUP BY ALL",
      "SELECT payload.score AS input_score, ((`PAYLOAD`.payload)).score AS object_score, COUNT(*) AS n FROM objects AS payload GROUP BY ALL",
      "SELECT payload.score AS input_score, ((payload.payload)).`SCORE` AS object_score, COUNT(*) AS n FROM objects AS payload GROUP BY ALL",
      "SELECT payload.score AS input_score, (payload.payload).score AS object_score, COUNT(*) AS n FROM objects AS payload GROUP BY payload.score, (payload.payload).score",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      group_receiver_scope_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=text)
  }
}

///|
test "grouped computed subtrees retain the object receiver boundary" {
  for
    text in [
      "SELECT (payload.payload).score + 1 AS object_next, COUNT(*) AS n FROM objects AS payload GROUP BY (payload.payload).score + 1",
      "SELECT ((payload.payload).score + 1) * 2 AS object_next, COUNT(*) AS n FROM objects AS payload GROUP BY (payload.payload).score + 1",
      "SELECT payload.score + 1 AS input_next, (payload.payload).score + 1 AS object_next, COUNT(*) AS n FROM objects AS payload GROUP BY ALL",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      group_receiver_scope_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
      msg=text,
    )
  }
  for
    text in [
      "SELECT (payload.payload).score + 1 AS next, COUNT(*) AS n FROM objects AS payload GROUP BY payload.score + 1",
      "SELECT payload.score + 1 AS next, COUNT(*) AS n FROM objects AS payload GROUP BY (payload.payload).score + 1",
      "SELECT COUNT(*) AS n FROM objects AS payload GROUP BY payload.score HAVING (payload.payload).score > 0",
      "SELECT COUNT(*) AS n FROM objects AS payload GROUP BY payload.score ORDER BY (payload.payload).score",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        group_receiver_scope_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: UnknownReference, .. })),
      msg=text,
    )
  }
}
