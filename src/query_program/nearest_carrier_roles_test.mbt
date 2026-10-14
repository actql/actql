///|
fn nearest_carrier_role_program(text : String) -> @program.Program raise {
  with_demand_program(with_carrier_program(text, nearest_context()))
}

///|
// Authored from the native candidate-current/query-argument contract. Producer
// names differ intentionally; neither Program nor schema comes from lowering.
fn nearest_typed_control() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.nearest_typed_control","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"request_id":{"type":"string","nullable":false},"embedding":{"type":"vector","dimensions":2,"nullable":false},"note":{"type":"string","nullable":true}},"rows":[{"request_id":"q1","embedding":[1,0],"note":null}]},"as":"queries"},{"from":"queries","to_vectors":{"id":"request_id","vector":"embedding"},"as":"query_vectors"},{"values":{"schema":{"item_id":{"type":"string","nullable":false},"embedding":{"type":"vector","dimensions":2,"nullable":false},"label":{"type":"string","nullable":false}},"rows":[{"item_id":"b","embedding":[0,1],"label":"second"},{"item_id":"a","embedding":[1,0],"label":"first"}]},"as":"candidates"},{"from":"candidates","to_vectors":{"id":"item_id","vector":"embedding"},"as":"candidate_vectors"},{"from":"candidate_vectors","nearest":{"queries":"query_vectors","metric":"dot","k":2}},{"derive":{"hit":{"object":{"query_key":{"object":{"request_id":{"field":"query_id"}}},"candidate_key":{"object":{"item_id":{"field":"candidate_id"}}},"score":{"field":"score"},"rank":{"field":"rank"}}}}},{"select":["hit"],"as":"out"}],"results":{"rows":{"from":"out","fields":["hit"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "typed NEAREST agrees with an independent machine Program output contract" {
  let actual = nearest_carrier_role_program(
    "WITH qv AS (FROM queries |> to_vectors(id: request_id, vector: embedding)), cv AS (FROM candidates |> to_vectors(id: item_id, vector: embedding)) FROM qv |> NEAREST cv AS c METRIC dot K 2 AS hit |> SELECT hit",
  )
  let schemas = [actual, nearest_typed_control()].map(program => {
    guard @check.check_parsed(
        program,
        check_environment(veca=true),
        None,
        check_limits(),
      )
      is Checked(checked) else {
      fail("native control and frontend use the normal common checker")
    }
    let results = @stage_results.stage_at(
      @check.checked_stage_results(checked),
      0,
    ).unwrap()
    let result = @relation_results.lookup(results, "rows").unwrap()
    assert_eq(@relation_results.fields(result), ["hit"])
    @schema.fields(@relation_results.output_schema(result))
  })
  assert_eq(
    schemas[0].map(field => field.name),
    schemas[1].map(field => field.name),
  )
  for i in 0..<schemas[0].length() {
    assert_eq(schemas[0][i].presence, schemas[1][i].presence)
    assert_true(
      @contract.type_equal(
        schemas[0][i].contract,
        schemas[1][i].contract,
        10000,
      ),
    )
  }
}

///|
test "typed NEAREST keeps the four Relation and Vectors operand combinations" {
  let prefix = "WITH qv AS (FROM queries |> to_vectors(id: request_id, vector: embedding)), cv AS (FROM candidates |> to_vectors(id: item_id, vector: embedding)) "
  for
    (query, candidate, roles, vector_builds) in [
      (
        "queries", "candidates", "QUERY KEY (request_id) VECTOR embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding ",
        2,
      ),
      ("queries", "cv", "QUERY KEY (request_id) VECTOR embedding ", 2),
      ("qv", "candidates", "CANDIDATE KEY (c.item_id) VECTOR c.embedding ", 2),
      ("qv", "cv", "", 2),
    ] {
    println("NEAREST_CARRIER_PAIR " + query + "/" + candidate)
    let actual = nearest_carrier_role_program(
      prefix +
      "FROM " +
      query +
      " |> NEAREST " +
      candidate +
      " AS c " +
      roles +
      "METRIC dot K 2 KEEP (c.label) AS hit",
    )
    assert_eq(
      semantic(actual).split("\"to_vectors\":{").length(),
      vector_builds + 1,
    )
    assert_eq(semantic(actual).split("\"nearest\":{").length(), 2)
    assert_true(semantic(actual).contains("\"cardinality\":\"many_to_one\""))
    match
      @check.check_parsed(
        actual,
        check_environment(veca=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) =>
        fail("both inputs come from the original typed Values controls")
    }
  }
}

///|
test "Vectors NEAREST permits exact role restatement and a normal output tail" {
  let prefix = "WITH qv AS (FROM queries |> to_vectors(id: request_id, vector: embedding)), cv AS (FROM candidates |> to_vectors(id: item_id, vector: embedding)) "
  for
    roles in [
      "", "QUERY KEY (qv.request_id) VECTOR qv.embedding ", "CANDIDATE KEY (c.item_id) VECTOR c.embedding ",
      "QUERY KEY (request_id) VECTOR ((embedding)) CANDIDATE KEY (c.item_id) VECTOR c.embedding ",
    ] {
    let actual = nearest_carrier_role_program(
      prefix +
      "FROM qv |> NEAREST cv AS c " +
      roles +
      "METRIC dot K 2 KEEP (c.label) AS hit |> SELECT label, hit.score AS score |> ORDER BY score DESC",
    )
    match
      @check.check_parsed(
        actual,
        check_environment(veca=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) => fail("all typed inputs are closed")
    }
  }
  for
    roles in [
      "QUERY KEY (note) VECTOR embedding ", "QUERY KEY (request_id) VECTOR note ",
      "CANDIDATE KEY (c.label) VECTOR c.embedding ", "CANDIDATE KEY (c.item_id) VECTOR c.label ",
    ] {
    assert_true(
      with_carrier_program(
        prefix + "FROM qv |> NEAREST cv AS c " + roles + "METRIC dot K 1 AS hit",
        nearest_context(),
      )
      is Err(InvalidQuery),
    )
  }
  assert_true(
    with_carrier_program(
      prefix + "FROM qv AS q |> NEAREST cv AS c METRIC dot K 1 AS hit",
      nearest_context(),
    )
    is Err(RangeAliasRequiresRelation),
  )
  let removed = with_carrier_program(
    prefix + "FROM qv |> NEAREST cv AS c METRIC dot K 1 AS hit |> SELECT qv.hit",
    nearest_context(),
  )
  // Ordinary expression resolution owns an absent receiver. Require its
  // adopted UnknownReference and original authored position, not any error.
  assert_true(
    removed
    is Err(
      Expression({ issue: @expression.UnknownReference, origin: Some(_), })
    ),
  )
}

///|
test "Relation completion refuses missing original key evidence" {
  for
    text in [
      "WITH c AS (FROM candidates |> to_vectors(id: item_id, vector: embedding)) FROM queries |> NEAREST c AS corpus METRIC dot K 1 AS hit",
      "WITH q AS (FROM queries |> to_vectors(id: request_id, vector: embedding)) FROM q |> NEAREST candidates AS c METRIC dot K 1 AS hit",
    ] {
    assert_true(
      with_carrier_program(text, nearest_context()) is Err(UnsupportedNearest),
    )
  }
}

///|
test "normalized Vectors and repeated operand occurrences keep original roles" {
  let actual = nearest_carrier_role_program(
    "WITH qv AS (FROM queries |> to_vectors(id: request_id, vector: embedding)) FROM qv |> normalize_vectors() |> NEAREST qv AS c METRIC dot K 1 AS hit",
  )
  assert_eq(semantic(actual).split("\"values\":{").length(), 2)
  assert_eq(semantic(actual).split("\"to_vectors\":{").length(), 2)
  assert_eq(semantic(actual).split("\"normalize_vectors\":true").length(), 2)
  match
    @check.check_parsed(
      actual,
      check_environment(veca=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("both occurrences use the same original input")
  }
}
