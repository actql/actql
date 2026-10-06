///|
test "JSON roots lower to an independently authored typed literal Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_query_expr_0":{"typed_literal":{"type":"json","value":"null"}},"aql_query_expr_1":{"typed_literal":{"type":"json","value":"1.5"}},"aql_query_expr_2":{"typed_literal":{"type":"json","value":"\"x\""}},"aql_query_expr_3":{"typed_literal":{"type":"json","value":"true"}},"aql_query_expr_4":{"typed_literal":{"type":"json","value":"{\"a\":1}"}},"aql_query_expr_5":{"typed_literal":{"type":"json","value":"[null,false]"}}}},{"select":[{"json_null":"aql_query_expr_0"},{"json_number":"aql_query_expr_1"},{"json_string":"aql_query_expr_2"},{"json_boolean":"aql_query_expr_3"},{"json_object":"aql_query_expr_4"},{"json_array":"aql_query_expr_5"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["json_null","json_number","json_string","json_boolean","json_object","json_array"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  for
    source in [
      (
        #|SELECT JSON 'null' AS json_null, JSON '1.5' AS json_number, JSON '"x"' AS json_string, JSON 'true' AS json_boolean, JSON '{"a":1}' AS json_object, JSON '[null,false]' AS json_array
      ),
      (
        #|SELECT json "null" AS json_null, JSON "1.5" AS json_number, JSON r'''"x"''' AS json_string, JSON 'true' AS json_boolean, JSON '{' /* chunks */ '"a":1}' AS json_object, JSON "[null,false]" AS json_array
      ),
    ] {
    let program = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(program), semantic(expected))
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("typed literal query must not acquire inputs")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
  }
}
