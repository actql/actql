///|
// Authored from the same independent NEAREST machine control as nearest_test.
// IF retains the declared dimension-2 vector; it is evaluated before ToVectors.
fn nearest_expression_expected() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.nearest_keep","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"request_id":{"type":"string","nullable":false},"embedding":{"type":"vector","dimensions":2,"nullable":false},"note":{"type":"string","nullable":true}},"rows":[{"request_id":"q1","embedding":[1,0],"note":null}]},"as":"queries"},{"values":{"schema":{"item_id":{"type":"string","nullable":false},"embedding":{"type":"vector","dimensions":2,"nullable":false},"label":{"type":"string","nullable":false}},"rows":[{"item_id":"b","embedding":[0,1],"label":"second"},{"item_id":"a","embedding":[1,0],"label":"first"}]},"as":"candidates"},{"from":"queries","derive":{"aql_nearest_vector_3":{"if":[{"literal":true},{"field":"embedding"},{"field":"embedding"}]}}},{"select":["request_id","embedding","note","aql_nearest_vector_3"],"as":"aql_nearest_queries_0_2"},{"from":"candidates","select":["item_id","embedding","label"],"as":"aql_nearest_candidates_0_3"},{"from":"aql_nearest_queries_0_2","to_vectors":{"id":"request_id","vector":"aql_nearest_vector_3"},"as":"aql_nearest_query_vectors_0_4"},{"from":"aql_nearest_candidates_0_3","to_vectors":{"id":"item_id","vector":"embedding"},"as":"aql_nearest_candidate_vectors_0_5"},{"from":"aql_nearest_candidate_vectors_0_5","nearest":{"queries":"aql_nearest_query_vectors_0_4","metric":"dot","k":2}},{"derive":{"aql_nearest_key_7":{"field":"query_id"},"aql_nearest_key_8":{"field":"candidate_id"}}},{"join":{"with":"aql_nearest_queries_0_2","kind":"inner","cardinality":"many_to_one","on":[{"left":"aql_nearest_key_7","right":"request_id"}],"select":{"query_id":"left.query_id","candidate_id":"left.candidate_id","score":"left.score","rank":"left.rank","aql_nearest_key_7":"left.aql_nearest_key_7","aql_nearest_key_8":"left.aql_nearest_key_8","aql_nearest_keep_9":"right.note"}}},{"join":{"with":"aql_nearest_candidates_0_3","kind":"inner","cardinality":"many_to_one","on":[{"left":"aql_nearest_key_8","right":"item_id"}],"select":{"query_id":"left.query_id","candidate_id":"left.candidate_id","score":"left.score","rank":"left.rank","aql_nearest_key_7":"left.aql_nearest_key_7","aql_nearest_key_8":"left.aql_nearest_key_8","aql_nearest_keep_9":"left.aql_nearest_keep_9","aql_nearest_keep_10":"right.label"}}},{"derive":{"aql_nearest_result_11":{"object":{"query_key":{"object":{"request_id":{"field":"aql_nearest_key_7"}}},"candidate_key":{"object":{"item_id":{"field":"aql_nearest_key_8"}}},"score":{"field":"score"},"rank":{"field":"rank"}}}}},{"select":[{"note":"aql_nearest_keep_9"},{"label":"aql_nearest_keep_10"},{"neighbor":"aql_nearest_result_11"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["note","label","neighbor"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "NEAREST query vector expression retains its evaluated input step" {
  let expected = nearest_expression_expected()
  match
    @check.check_parsed(
      expected,
      check_environment(veca=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    NeedsInputs(_) => fail("closed Values control")
  }
  let text = "FROM queries AS q |> NEAREST candidates AS c " +
    "QUERY KEY (q.request_id) VECTOR IF(TRUE, q.embedding, q.embedding) " +
    "CANDIDATE KEY (c.item_id) VECTOR c.embedding METRIC dot K 2 " +
    "KEEP (q.note, c.label) AS neighbor"
  let actual = compile(
    @query.parse_query(text, syntax_limits()).unwrap(),
    nearest_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
  match
    @check.check_parsed(
      actual,
      check_environment(veca=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    NeedsInputs(_) => fail("closed Values source")
  }
}
