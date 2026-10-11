///|
// Independently specified Script binding names applied to the preexisting
// handwritten nearest Program. No expected body is read from compile output.
fn nearest_script_expected() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.nearest_keep","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"request_id":{"type":"string","nullable":false},"embedding":{"type":"vector","dimensions":2,"nullable":false},"note":{"type":"string","nullable":true}},"rows":[{"request_id":"q1","embedding":[1,0],"note":null}]},"as":"aql_script_seed_3"},{"values":{"schema":{"item_id":{"type":"string","nullable":false},"embedding":{"type":"vector","dimensions":2,"nullable":false},"label":{"type":"string","nullable":false}},"rows":[{"item_id":"b","embedding":[0,1],"label":"second"},{"item_id":"a","embedding":[1,0],"label":"first"}]},"as":"aql_script_seed_5"},{"from":"aql_script_seed_3","select":["request_id","embedding","note"],"as":"aql_nearest_queries_0_2"},{"from":"aql_script_seed_5","select":["item_id","embedding","label"],"as":"aql_nearest_candidates_0_3"},{"from":"aql_nearest_queries_0_2","to_vectors":{"id":"request_id","vector":"embedding"},"as":"aql_nearest_query_vectors_0_4"},{"from":"aql_nearest_candidates_0_3","to_vectors":{"id":"item_id","vector":"embedding"},"as":"aql_nearest_candidate_vectors_0_5"},{"from":"aql_nearest_candidate_vectors_0_5","nearest":{"queries":"aql_nearest_query_vectors_0_4","metric":"dot","k":2}},{"derive":{"aql_nearest_key_7":{"field":"query_id"},"aql_nearest_key_8":{"field":"candidate_id"}}},{"join":{"with":"aql_nearest_queries_0_2","kind":"inner","cardinality":"many_to_one","on":[{"left":"aql_nearest_key_7","right":"request_id"}],"select":{"query_id":"left.query_id","candidate_id":"left.candidate_id","score":"left.score","rank":"left.rank","aql_nearest_key_7":"left.aql_nearest_key_7","aql_nearest_key_8":"left.aql_nearest_key_8","aql_nearest_keep_9":"right.note"}}},{"join":{"with":"aql_nearest_candidates_0_3","kind":"inner","cardinality":"many_to_one","on":[{"left":"aql_nearest_key_8","right":"item_id"}],"select":{"query_id":"left.query_id","candidate_id":"left.candidate_id","score":"left.score","rank":"left.rank","aql_nearest_key_7":"left.aql_nearest_key_7","aql_nearest_key_8":"left.aql_nearest_key_8","aql_nearest_keep_9":"left.aql_nearest_keep_9","aql_nearest_keep_10":"right.label"}}},{"derive":{"aql_nearest_result_11":{"object":{"query_key":{"object":{"request_id":{"field":"aql_nearest_key_7"}}},"candidate_key":{"object":{"item_id":{"field":"aql_nearest_key_8"}}},"score":{"field":"score"},"rank":{"field":"rank"}}}}},{"select":[{"note":"aql_nearest_keep_9"},{"label":"aql_nearest_keep_10"},{"neighbor":"aql_nearest_result_11"}],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["note","label","neighbor"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
fn nearest_script_source() -> String {
  "DATA qs = FROM queries; DATA cs = FROM candidates; " +
  "FROM qs AS q |> NEAREST cs AS c QUERY KEY (q.request_id) VECTOR q.embedding " +
  "CANDIDATE KEY (c.item_id) VECTOR c.embedding METRIC dot K 2 " +
  "KEEP (q.note, c.label) AS neighbor"
}

///|
test "DATA NEAREST resolves both retained Relation producers" {
  // The independent common Program fixes two matches, pair-key uniqueness,
  // nullable KEEP and nested typed key objects before frontend compilation.
  match
    @check.check_parsed(
      nearest_shared_program(true),
      check_environment(veca=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    NeedsInputs(_) => fail("independent closed machine control must check")
  }
  let actual = compile_query_script(
    @query.parse_query_script(nearest_script_source(), syntax_limits()).unwrap(),
    nearest_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(nearest_script_expected()))
  match
    @check.check_parsed(
      actual,
      check_environment(veca=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    NeedsInputs(_) => fail("DATA must retain existing input bindings")
  }
}

///|
test "NEAREST CTE candidate reports the separate current scope-validation gap" {
  let source = nearest_script_source().replace(
    old="DATA qs = FROM queries; DATA cs = FROM candidates; ",
    new="WITH qs AS (FROM queries), cs AS (FROM candidates) ",
  )
  // This pre-cutover caller still retains its original refusal expectation.
  // The unified owner already counts NEAREST producer references; this fixture
  // is retired separately with the remaining accepted WITH callers.
  assert_true(
    compile_query_script(
      @query.parse_query_script(source, syntax_limits()).unwrap(),
      nearest_context(),
      construction_limits(),
    )
    is Err(UnsupportedCte),
  )
}

///|
test "NEAREST DATA aliases retain one shared seed with both key roles" {
  let source = "DATA qs = FROM queries; DATA cs = FROM qs; " +
    "FROM qs AS q |> NEAREST cs AS c QUERY KEY (q.request_id) VECTOR q.embedding " +
    "CANDIDATE KEY (c.request_id) VECTOR c.embedding METRIC dot K 2 " +
    "KEEP (q.note AS query_note, c.note AS candidate_note) AS neighbor"
  let actual = compile_query_script(
    @query.parse_query_script(source, syntax_limits()).unwrap(),
    nearest_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual).split("\"values\":").length(), 2)
  assert_true(semantic(actual).contains("\"cardinality\":\"many_to_one\""))
  assert_false(semantic(actual).contains("\"cardinality\":\"one_to_one\""))
  match
    @check.check_parsed(
      actual,
      check_environment(veca=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    NeedsInputs(_) => fail("shared DATA alias must not acquire another input")
  }
}

///|
test "NEAREST Script rejects undeclared and forward candidate references" {
  for
    source in [
      nearest_script_source().replace(old="NEAREST cs", new="NEAREST absent"),
      "DATA matched = FROM queries AS q |> NEAREST later AS c " +
      "QUERY KEY (q.request_id) VECTOR q.embedding " +
      "CANDIDATE KEY (c.item_id) VECTOR c.embedding METRIC dot K 2 AS neighbor; " +
      "DATA later = FROM candidates; FROM matched",
    ] {
    assert_true(
      compile_query_script(
        @query.parse_query_script(source, syntax_limits()).unwrap(),
        nearest_context(),
        construction_limits(),
      )
      is Err(UnknownRelation),
    )
  }
}
