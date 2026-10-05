///|
fn join_property_context() -> Context {
  let inputs : Array[Input] = []
  for
    (name, fields, body) in [
      (
        "objects",
        ["id", "payload"],
        (
          #|{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"id":2,"payload":{"score":10}},{"id":1,"payload":{"score":20}},{"id":3,"payload":null}]},"as":"objects"}
        ),
      ),
      (
        "others",
        ["id", "other"],
        (
          #|{"values":{"schema":{"id":{"type":"number","nullable":false},"other":{"type":"object","nullable":false,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"id":1,"other":{"score":5}},{"id":2,"other":{"score":30}},{"id":3,"other":{"score":15}}]},"as":"others"}
        ),
      ),
    ] {
    let seed = @wire.admit(
      @source.parse_json(body, construction_limits().source.source).unwrap(),
      construction_limits().source.tree,
    ).unwrap()
    inputs.push({
      relation: [{ value: name, quoted: false, }],
      name,
      source: GeneratedValues(seed),
      visible_fields: fields,
      graph_bindings: [],
    })
  }
  { ..pair_context(), inputs, }
}

///|
fn join_property_expected() -> @program.Program {
  // Complete independent Program: join direct ID keys, retain the object
  // receiver, then use the existing property expression and public projection.
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"aql_join_left","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"payload":{"type":"object","nullable":true,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"id":2,"payload":{"score":10}},{"id":1,"payload":{"score":20}},{"id":3,"payload":null}]},"as":"objects"}],"results":{"aql_join_left":{"from":"objects","fields":["id","payload"]}}},{"id":"aql_join_right","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"other":{"type":"object","nullable":false,"fields":{"score":{"type":"number","nullable":false}}}},"rows":[{"id":1,"other":{"score":5}},{"id":2,"other":{"score":30}},{"id":3,"other":{"score":15}}]},"as":"others"}],"results":{"aql_join_right":{"from":"others","fields":["id","other"]}}},{"id":"main","inputs":{"l":{"result":{"stage":"aql_join_left","result":"aql_join_left"}},"r":{"result":{"stage":"aql_join_right","result":"aql_join_right"}}},"steps":[{"from":"l","join":{"with":"r","kind":"inner","on":[{"left":"id","right":"id"}],"max_output_rows":9,"select":{"aql_join_input_5":"left.payload"}},"as":"aql_join_raw"},{"from":"aql_join_raw","derive":{"score":{"property":{"value":{"field":"aql_join_input_5"},"name":"score"}}},"as":"aql_join_derived"},{"from":"aql_join_derived","select":["score"],"as":"aql_join_output"}],"results":{"rows":{"from":"aql_join_output","fields":["score"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn check_join_property(program : @program.Program) -> Unit raise {
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    _ => fail("independent Values JOIN is closed")
  }
}

///|
test "JOIN property independent JSON passes ordinary checking" {
  check_join_property(join_property_expected())
}

///|
test "JOIN property SQL matches the complete independent Program" {
  let actual = compile(
    @query.parse_query(
      "SELECT l.payload.score FROM objects AS l JOIN others AS r ON l.id = r.id",
      syntax_limits(),
    ).unwrap(),
    join_property_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(join_property_expected()))
  check_join_property(actual)
}

///|
test "JOIN property Pipe matches the complete independent Program" {
  let actual = compile(
    @query.parse_query(
      "FROM objects AS l |> JOIN others AS r ON l.id = r.id |> SELECT l.payload.score",
      syntax_limits(),
    ).unwrap(),
    join_property_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(join_property_expected()))
  check_join_property(actual)
}

///|
fn checked_join_property(source : String) -> String raise {
  let actual = compile(
    @query.parse_query(source, syntax_limits()).unwrap(),
    join_property_context(),
    construction_limits(),
  ).unwrap()
  check_join_property(actual)
  semantic(actual)
}

///|
test "JOIN property WHERE uses the input receiver before SELECT aliases" {
  for
    source in [
      "SELECT l.id, r.other AS payload FROM objects AS l JOIN others AS r ON l.id = r.id WHERE payload.score > 15 ORDER BY payload.score",
      "FROM objects AS l |> JOIN others AS r ON l.id = r.id |> WHERE payload.score > 15 |> SELECT l.id, r.other AS payload |> ORDER BY payload.score",
    ] {
    let body = checked_join_property(source)
    assert_true(body.contains("\"filter\":{\"gt\""))
    assert_true(body.contains("left.payload"))
    assert_true(body.contains("right.other"))
    assert_true(body.contains("aql_join_visible"))
    assert_true(body.contains("\"fields\":[\"id\",\"payload\"]"))
  }
}

///|
test "JOIN property ORDER reuses only the same resolved receiver" {
  // An output receiver can win even when the input name is ambiguous.
  ignore(
    checked_join_property(
      "SELECT r.other AS id FROM objects AS l JOIN others AS r ON l.id = r.id ORDER BY id.score",
    ),
  )
  for
    source in [
      "SELECT l.id, payload.score AS original_score, r.other AS payload FROM objects AS l JOIN others AS r ON l.id = r.id ORDER BY payload.score NULLS LAST",
      "SELECT l.id, payload.score AS original_score, r.other AS payload FROM objects AS l JOIN others AS r ON l.id = r.id ORDER BY l.payload.score NULLS LAST",
    ] {
    let body = checked_join_property(source)
    assert_eq(body.split("\"property\":").length(), 3)
    assert_true(body.contains("aql_join_visible"))
    assert_true(
      body.contains("\"fields\":[\"id\",\"original_score\",\"payload\"]"),
    )
  }
  // The identical qualified expression has the same receiver in both clauses.
  let reused = checked_join_property(
    "SELECT l.payload.score AS a, l.payload.score AS b FROM objects AS l JOIN others AS r ON l.id = r.id ORDER BY l.payload.score NULLS LAST",
  )
  assert_eq(reused.split("\"property\":").length(), 3)
  assert_false(reused.contains("aql_join_sort_"))
  assert_true(reused.contains("\"field\":\"a\",\"nulls\":\"last\""))
}

///|
test "JOIN property LEFT output keeps the common nullable receiver contract" {
  ignore(
    checked_join_property(
      "SELECT l.id, r.other.score FROM objects AS l LEFT JOIN others AS r ON l.id = r.id WHERE r.other.score IS NULL ORDER BY l.id",
    ),
  )
}

///|
test "JOIN property missing members and scalar receivers use common checking" {
  for
    source in [
      "SELECT l.payload.missing FROM objects AS l JOIN others AS r ON l.id = r.id",
      "SELECT l.id.score FROM objects AS l JOIN others AS r ON l.id = r.id",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_property_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Rejected(_),
    )
  }
}

///|
test "JOIN property preserves ambiguity and removed DISTINCT input diagnostics" {
  for
    (source, issue) in [
      (
        "SELECT id.score FROM objects AS l JOIN others AS r ON l.id = r.id", "ambiguous",
      ),
      (
        "SELECT missing.score FROM objects AS l JOIN others AS r ON l.id = r.id",
        "unknown",
      ),
      (
        "SELECT DISTINCT l.id FROM objects AS l JOIN others AS r ON l.id = r.id ORDER BY payload.score",
        "ordering",
      ),
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      join_property_context(),
      construction_limits(),
    )
    match actual {
      Err(AmbiguousColumn) => assert_eq(issue, "ambiguous")
      Err(UnknownColumn) => assert_eq(issue, "unknown")
      Err(UnsupportedOrdering) => assert_eq(issue, "ordering")
      _ => fail("the intended scope diagnostic is required")
    }
  }
}

///|
test "JOIN property CTE inputs and pre-JOIN Pipe filters use ordinary expressions" {
  ignore(
    checked_join_property(
      "WITH seed AS (SELECT id, payload FROM objects), peers AS (SELECT id, other FROM others) SELECT l.id, l.payload.score FROM seed AS l JOIN peers AS r ON l.id = r.id ORDER BY r.other.score",
    ),
  )
  ignore(
    checked_join_property(
      "WITH seed AS (SELECT id, payload FROM objects), peers AS (SELECT id, other FROM others) FROM seed AS l |> WHERE l.payload.score > 15 |> JOIN peers AS r ON l.id = r.id |> SELECT l.id, r.other.score",
    ),
  )
}
