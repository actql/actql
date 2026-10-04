///|
test "set ORDER expressions use only evaluated combined output slots" {
  for
    text in [
      "SELECT a, b FROM left_rows UNION ALL SELECT c, d FROM right_rows ORDER BY a + 1, a + 1 DESC, b",
      "SELECT a AS x, b FROM left_rows UNION DISTINCT SELECT c AS y, d FROM right_rows ORDER BY x + 1, b",
      "WITH chosen AS (SELECT a, b FROM left_rows UNION ALL SELECT c, d FROM right_rows ORDER BY a + 1, b) SELECT a, b FROM chosen",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      set_context(),
      construction_limits(),
    ).unwrap()
    match
      @check.check_parsed(program, check_environment(), None, check_limits()) {
      Checked(_) => ()
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
      _ => fail(text)
    }
  }
  let program = compile(
    @query.parse_query(
      "SELECT a, b FROM left_rows UNION ALL SELECT c, d FROM right_rows ORDER BY a + 1, a + 1 DESC, b",
      syntax_limits(),
    ).unwrap(),
    set_context(),
    construction_limits(),
  ).unwrap()
  let wire = semantic(program)
  // Independent final steps: one common add, one reusable hidden slot, and
  // projection back to the authored output. No SELECT expression expansion.
  assert_true(
    wire.contains(
      "\"derive\":{\"aql_set_sort_2\":{\"add\":[{\"field\":\"a\"},{\"literal\":1}]}}",
    ),
  )
  assert_eq(wire.split("\"aql_set_sort_2\":").length(), 2)
  assert_true(
    wire.contains(
      "\"sort\":[{\"dir\":\"asc\",\"field\":\"aql_set_sort_2\",\"nulls\":\"first\"},{\"dir\":\"desc\",\"field\":\"aql_set_sort_2\",\"nulls\":\"last\"},{\"dir\":\"asc\",\"field\":\"b\",\"nulls\":\"first\"}]",
    ),
  )
  assert_true(wire.contains("\"select\":[\"a\",\"b\"]"))
  // This complete final Stage is hand-authored from the ordinary Program
  // contract. The operand Results remain inputs, not expanded expressions.
  let expected_final_stage =
    #|{"id":"main","inputs":{"set_rows":{"result":{"result":"aql_set_merge_0","stage":"aql_set_merge_0"}}},"results":{"rows":{"fields":["a","b"],"from":"aql_set_final_0"}},"steps":[{"as":"aql_set_order_input_0","derive":{"aql_set_sort_2":{"add":[{"field":"a"},{"literal":1}]}},"from":"set_rows"},{"as":"aql_set_ordered_0","from":"aql_set_order_input_0","sort":[{"dir":"asc","field":"aql_set_sort_2","nulls":"first"},{"dir":"desc","field":"aql_set_sort_2","nulls":"last"},{"dir":"asc","field":"b","nulls":"first"}]},{"as":"aql_set_final_0","from":"aql_set_ordered_0","select":["a","b"]}]}
  assert_true(wire.contains(expected_final_stage))
}

///|
test "set ORDER expressions cannot recover operand columns or ranges" {
  for
    text in [
      "SELECT a AS x FROM left_rows UNION ALL SELECT c AS y FROM right_rows ORDER BY a + 1",
      "SELECT a AS x FROM left_rows UNION ALL SELECT c AS y FROM right_rows ORDER BY y + 1",
      "SELECT a AS x FROM left_rows UNION ALL SELECT c AS y FROM right_rows ORDER BY left_rows.a + 1",
      "SELECT a AS x FROM left_rows UNION ALL SELECT c AS y FROM right_rows ORDER BY right_rows.c + 1",
      "SELECT a AS x FROM left_rows UNION ALL SELECT c AS y FROM right_rows ORDER BY -1",
      "SELECT a AS x FROM left_rows UNION ALL SELECT c AS y FROM right_rows ORDER BY 'x'",
      "SELECT a AS x FROM left_rows UNION ALL SELECT c AS y FROM right_rows ORDER BY NULL",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        set_context(),
        construction_limits(),
      )
      is Err(_),
      msg=text,
    )
  }
}

///|
test "set ORDER expression lowering respects the existing work ceiling" {
  let query = @query.parse_query(
    "SELECT a, b FROM left_rows UNION ALL SELECT c, d FROM right_rows ORDER BY a + 1, b",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(query, set_context(), {
      ..construction_limits(),
      max_expression_work: 1,
    })
    is Err(Expression(_)),
  )
}
