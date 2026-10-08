///|
// Independent complete machine input uses the declared common NEAREST member.
// The source variants must change neither the score type nor KEEP correspondence.
// Three visible KEEP/result slots reserve pipe expression slot 3.
fn nearest_member_control(nested? : Bool = false) -> @program.Program {
  let expression = if nested {
    (
      #|{"property":{"value":{"property":{"value":{"field":"neighbor"},"name":"query_key"}},"name":"request_id"}}
    )
  } else {
    (
      #|{"property":{"value":{"field":"neighbor"},"name":"score"}}
    )
  }
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.nearest_keep","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"request_id":{"type":"string","nullable":false},"embedding":{"type":"vector","dimensions":2,"nullable":false},"note":{"type":"string","nullable":true}},"rows":[{"request_id":"q1","embedding":[1,0],"note":null}]},"as":"queries"},{"values":{"schema":{"item_id":{"type":"string","nullable":false},"embedding":{"type":"vector","dimensions":2,"nullable":false},"label":{"type":"string","nullable":false}},"rows":[{"item_id":"b","embedding":[0,1],"label":"second"},{"item_id":"a","embedding":[1,0],"label":"first"}]},"as":"candidates"},{"from":"queries","select":["request_id","embedding","note"],"as":"aql_nearest_queries_0_2"},{"from":"candidates","select":["item_id","embedding","label"],"as":"aql_nearest_candidates_0_3"},{"from":"aql_nearest_queries_0_2","to_vectors":{"id":"request_id","vector":"embedding"},"as":"aql_nearest_query_vectors_0_4"},{"from":"aql_nearest_candidates_0_3","to_vectors":{"id":"item_id","vector":"embedding"},"as":"aql_nearest_candidate_vectors_0_5"},{"from":"aql_nearest_candidate_vectors_0_5","nearest":{"queries":"aql_nearest_query_vectors_0_4","metric":"dot","k":2}},{"derive":{"aql_nearest_key_7":{"field":"query_id"},"aql_nearest_key_8":{"field":"candidate_id"}}},{"join":{"with":"aql_nearest_queries_0_2","kind":"inner","cardinality":"many_to_one","on":[{"left":"aql_nearest_key_7","right":"request_id"}],"select":{"query_id":"left.query_id","candidate_id":"left.candidate_id","score":"left.score","rank":"left.rank","aql_nearest_key_7":"left.aql_nearest_key_7","aql_nearest_key_8":"left.aql_nearest_key_8","aql_nearest_keep_9":"right.note"}}},{"join":{"with":"aql_nearest_candidates_0_3","kind":"inner","cardinality":"many_to_one","on":[{"left":"aql_nearest_key_8","right":"item_id"}],"select":{"query_id":"left.query_id","candidate_id":"left.candidate_id","score":"left.score","rank":"left.rank","aql_nearest_key_7":"left.aql_nearest_key_7","aql_nearest_key_8":"left.aql_nearest_key_8","aql_nearest_keep_9":"left.aql_nearest_keep_9","aql_nearest_keep_10":"right.label"}}},{"derive":{"aql_nearest_result_11":{"object":{"query_key":{"object":{"request_id":{"field":"aql_nearest_key_7"}}},"candidate_key":{"object":{"item_id":{"field":"aql_nearest_key_8"}}},"score":{"field":"score"},"rank":{"field":"rank"}}}}},{"select":[{"note":"aql_nearest_keep_9"},{"label":"aql_nearest_keep_10"},{"neighbor":"aql_nearest_result_11"}]},{"derive":{"aql_pipe_expr_3":
    ) +
    expression +
    (
      #|}},{"select":["label",{"score":"aql_pipe_expr_3"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["label","score"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn nearest_member_require_checked(program : @program.Program) -> Unit raise {
  match
    @check.check_parsed(
      program,
      check_environment(veca=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => {
      guard @check.diagnostic_cause(error)
        is Source(SourceView(Program(Program(Pipeline(_, issue))))) else {
        raise @check.diagnostic_cause(error)
      }
      match issue.kind {
        Operation(Expression(UnknownField(name))) =>
          fail("common checker rejects member " + name)
        _ => raise @check.diagnostic_cause(error)
      }
    }
    NeedsInputs(_) => fail("closed Values inputs")
  }
}

///|
test "NEAREST member exact independent Program checks before case binding" {
  let expected = nearest_member_control()
  nearest_member_require_checked(expected)
  let actual = nearest_program(
    "KEEP (q.note, c.label) AS neighbor |> SELECT label, neighbor.score AS score",
  ).unwrap()
  nearest_member_require_checked(actual)
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "NEAREST member binding carries common vector output facts to KEEP objects" {
  let expected = nearest_member_control()
  nearest_member_require_checked(expected)
  for
    suffix in [
      "KEEP (q.note, c.label) AS neighbor |> SELECT label, neighbor.SCORE AS score",
      "KEEP (q.note, c.label) AS neighbor |> SELECT label, `neighbor`.`ScOrE` AS score",
    ] {
    let actual = nearest_program(suffix).unwrap()
    nearest_member_require_checked(actual)
    assert_eq(semantic(actual), semantic(expected))
  }
}

///|
test "NEAREST nested key names bind using their common object contracts" {
  let expected = nearest_member_control(nested=true)
  nearest_member_require_checked(expected)
  for
    suffix in [
      "KEEP (q.note, c.label) AS neighbor |> SELECT label, neighbor.QUERY_KEY.REQUEST_ID AS score",
      "KEEP (q.note, c.label) AS neighbor |> SELECT label, `neighbor`.`QuErY_KeY`.`ReQuEsT_iD` AS score",
    ] {
    let actual = nearest_program(suffix).unwrap()
    nearest_member_require_checked(actual)
    assert_eq(semantic(actual), semantic(expected))
  }
}

///|
test "NEAREST member binding leaves unknown members to ordinary checking" {
  let actual = nearest_program(
    "KEEP (q.note, c.label) AS neighbor |> SELECT neighbor.MISSING AS score",
  ).unwrap()
  guard @check.check_parsed(
      actual,
      check_environment(veca=true),
      None,
      check_limits(),
    )
    is Rejected(error) else {
    fail("unknown member must not acquire a type")
  }
  assert_true(
    @check.diagnostic_cause(error)
    is Source(
      SourceView(
        Program(
          Program(
            Pipeline(
              _,
              { kind: Operation(Expression(UnknownField("MISSING"))), .. }
            )
          )
        )
      )
    ),
  )
}
