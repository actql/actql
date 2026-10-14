///|
fn carrier_peer_program(text : String) -> @program.Program raise {
  match with_carrier_program(text, nearest_context()) {
    Err(UnknownRelation) =>
      fail("actual UnknownRelation lost the visible candidate peer")
    result => with_demand_program(result)
  }
}

///|
test "Vectors to Relation retains a visible candidate peer for NEAREST" {
  let prefix = "WITH v AS (FROM queries |> to_vectors(id: request_id, vector: embedding)), candidate_rows AS (SELECT item_id, embedding, label FROM candidates) "
  let suffix = " |> NEAREST candidate_rows AS c QUERY KEY (request_id) VECTOR embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding METRIC dot K 2 KEEP (c.label) AS hit"
  let actual = carrier_peer_program(prefix + "FROM v |> vectors()" + suffix)
  let explicit = carrier_peer_program(
    prefix.replace(
      old="candidate_rows AS",
      new="`rows` AS (FROM v |> vectors()), candidate_rows AS",
    ) +
    "FROM rows" +
    suffix,
  )
  for program in [actual, explicit] {
    assert_eq(semantic(program).split("\"values\":{").length(), 3)
    assert_eq(semantic(program).split("\"nearest\":{").length(), 2)
    assert_true(semantic(program).contains("\"cardinality\":\"many_to_one\""))
    match
      @check.check_parsed(
        program,
        check_environment(veca=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) =>
        fail("the declared typed vector controls have no provider")
    }
  }
}

///|
test "a nested candidate peer shadows the outer peer after a Carrier bridge" {
  let prefix = "WITH v AS (FROM queries |> to_vectors(id: request_id, vector: embedding)), candidate_rows AS (SELECT item_id, embedding, label FROM candidates) "
  let actual = carrier_peer_program(
    prefix +
    "FROM (WITH candidate_rows AS (SELECT item_id, embedding, label FROM candidates WHERE item_id = 'a') FROM v |> vectors() |> NEAREST candidate_rows AS c QUERY KEY (request_id) VECTOR embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding METRIC dot K 1 KEEP (c.label) AS hit)",
  )
  assert_eq(semantic(actual).split("\"values\":{").length(), 3)
  assert_true(semantic(actual).contains("\"literal\":\"a\""))
  assert_eq(semantic(actual).split("\"nearest\":{").length(), 2)
  match
    @check.check_parsed(
      actual,
      check_environment(veca=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("a lexical peer does not acquire another input")
  }
  let shadowed = with_carrier_program(
    prefix +
    "FROM (WITH candidate_rows AS (SELECT 1 AS unrelated) FROM v |> vectors() |> NEAREST candidate_rows AS c QUERY KEY (request_id) VECTOR embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding METRIC dot K 1 AS hit)",
    nearest_context(),
  )
  assert_true(
    shadowed is Err(UnknownColumn),
    msg=match shadowed {
      Ok(_) => "actual accepted missing inner roles"
      Err(InvalidQuery) => "actual InvalidQuery"
      Err(UnsupportedNearest) => "actual UnsupportedNearest"
      Err(UnknownColumn) => "actual UnknownColumn"
      Err(BindingPreparation(_)) => "actual BindingPreparation"
      Err(BindingPreparationSource(_, _)) => "actual BindingPreparationSource"
      Err(ExpressionTyping(_)) => "actual ExpressionTyping"
      Err(Expression(diagnostic)) =>
        "actual Expression " + @debug.to_string(diagnostic.issue)
      Err(UnsupportedCte) => "actual UnsupportedCte"
      Err(UnsupportedProjection) => "actual UnsupportedProjection"
      Err(UnsupportedResult) => "actual UnsupportedResult"
      Err(InvalidContext) => "actual InvalidContext"
      Err(UnknownRelation) => "actual UnknownRelation"
      Err(UnresolvedRelation(_)) => "actual UnresolvedRelation"
      Err(AmbiguousColumn) => "actual AmbiguousColumn"
      Err(Admission(_)) => "actual Admission"
      Err(Construction(_)) => "actual Construction"
      Err(_) => "actual other typed refusal"
    },
  )
}

///|
test "a Carrier bridge and its candidate peer reuse one original named input" {
  let actual = carrier_peer_program(
    "WITH v AS (FROM queries |> to_vectors(id: request_id, vector: embedding)), candidate_rows AS (SELECT request_id AS item_id, embedding, 'same' AS label FROM queries) FROM v |> vectors() |> NEAREST candidate_rows AS c QUERY KEY (request_id) VECTOR embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding METRIC dot K 1 KEEP (c.label) AS hit",
  )
  assert_eq(semantic(actual).split("\"values\":{").length(), 2)
  assert_eq(semantic(actual).split("\"nearest\":{").length(), 2)
  match
    @check.check_parsed(
      actual,
      check_environment(veca=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("one original input is reused, not acquired twice")
  }
}

///|
test "the original cosine peer contract agrees with an independent JSON Program" {
  let control = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.carrier_peer_scope","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"request_id":{"type":"string","nullable":false},"embedding":{"type":"vector","dimensions":2,"nullable":false}},"rows":[{"request_id":"q1","embedding":[1,0]}]},"as":"queries"},{"values":{"schema":{"item_id":{"type":"string","nullable":false},"embedding":{"type":"vector","dimensions":2,"nullable":false}},"rows":[{"item_id":"b","embedding":[0,1]},{"item_id":"a","embedding":[1,0]}]},"as":"candidates"},{"from":"queries","to_vectors":{"id":"request_id","vector":"embedding"},"as":"query_vectors"},{"from":"candidates","to_vectors":{"id":"item_id","vector":"embedding"},"as":"candidate_vectors"},{"from":"candidate_vectors","nearest":{"queries":"query_vectors","metric":"cosine","k":1},"as":"matches"},{"from":"matches","derive":{"neighbor":{"object":{"query_key":{"object":{"request_id":{"field":"query_id"}}},"candidate_key":{"object":{"item_id":{"field":"candidate_id"}}},"score":{"field":"score"},"rank":{"field":"rank"}}}}},{"select":["neighbor"],"as":"answer"}],"results":{"rows":{"from":"answer","fields":["neighbor"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let actual = carrier_peer_program(
    "WITH v AS (FROM queries |> to_vectors(id: request_id, vector: embedding)), candidate_rows AS (SELECT item_id, embedding FROM candidates) FROM v |> vectors() |> NEAREST candidate_rows AS c QUERY KEY (request_id) VECTOR embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding METRIC cosine K 1 AS neighbor",
  )
  for program in [control, actual] {
    let nearest = with_carrier_argument(program, "nearest")
    assert_true(nearest.contains("\"metric\":\"cosine\""))
    assert_true(nearest.contains("\"k\":1"))
    match
      @check.check_parsed(
        program,
        check_environment(veca=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(issue) => raise @check.diagnostic_cause(issue)
      NeedsInputs(_) =>
        fail("the independent peer control has no external input")
    }
  }
}
