///|
// Independent existing Program control. Neither expected expression nor field
// order comes from the source compiler under test.
test "array constructors lower to the existing finite array expression" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_query_expr_0":{"array":[{"literal":2},{"literal":1},{"literal":2}]}}},{"select":[{"items":"aql_query_expr_0"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["items"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("finite source-free array requires no acquisition")
    Rejected(error) => raise @check.diagnostic_cause(error)
  }
  for text in ["SELECT [2, 1, 2] AS items", "SELECT ARRAY[2, 1, 2] AS items"] {
    let query = @query.parse_query(text, syntax_limits()).unwrap()
    let actual = compile(
      query,
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=text)
  }
}

///|
test "array source expansion preserves duplicate elements and explicit offsets" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_unnest_array_3":{"array":[{"literal":2},{"literal":1},{"literal":2}]}}},{"unnest":{"column":"aql_unnest_array_3","as":"aql_unnest_element_4","with_index":"aql_unnest_offset_5"}},{"sort":[{"field":"aql_unnest_offset_5","dir":"asc","nulls":"first"}]},{"select":[{"element":"aql_unnest_element_4"},{"position":"aql_unnest_offset_5"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["element","position"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
    msg="independent array expansion must already be supported",
  )
  for
    text in [
      "SELECT element, position FROM UNNEST([2, 1, 2]) element WITH OFFSET position ORDER BY position",
      "FROM UNNEST(ARRAY[2, 1, 2]) element WITH OFFSET position |> SELECT element, position |> ORDER BY position",
    ] {
    let actual = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=text)
  }
}

///|
test "empty array type follows the existing common conditional context" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_query_expr_0":{"if":[{"literal":true},{"array":[]},{"array":[{"literal":"x"}]}]}}},{"select":[{"items":"aql_query_expr_0"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["items"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  match
    @check.check_parsed(expected, check_environment(), None, check_limits()) {
    Checked(_) => ()
    NeedsInputs(_) => fail("contextual array requires no acquisition")
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
  }
  let actual = compile(
    @query.parse_query("SELECT IF(TRUE, [], ['x']) AS items", syntax_limits()).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
  assert_true(
    @check.check_parsed(actual, check_environment(), None, check_limits())
    is Checked(_),
  )
}

///|
test "explicit array item declarations are checked by the ordinary Program owner" {
  for
    (text, expression) in [
      (
        "ARRAY<STRING>[]",
        (
          #|{"empty_array":{"items":{"type":"string","nullable":false}}}
        ),
      ),
      (
        "ARRAY<FLOAT64>[2, 1, 2]",
        (
          #|{"if":[{"literal":true},{"array":[{"literal":2},{"literal":1},{"literal":2}]},{"empty_array":{"items":{"type":"number","nullable":false}}}]}
        ),
      ),
      (
        "ARRAY<BOOL>[TRUE, NULL]",
        (
          #|{"if":[{"literal":true},{"array":[{"literal":true},{"literal":null}]},{"empty_array":{"items":{"type":"boolean","nullable":false}}}]}
        ),
      ),
      (
        "ARRAY<BOOL>[NULL]",
        (
          #|{"if":[{"literal":true},{"array":[{"literal":null}]},{"empty_array":{"items":{"type":"boolean","nullable":false}}}]}
        ),
      ),
    ] {
    // The expected expression is authored from the existing array, typed
    // empty_array and lazy-if contracts, independently of the source lowerer.
    let expected = @program.parse(
      "{\"version\":\"actql/0.1\",\"id\":\"fixture.query_pair\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"as\":\"aql_source_free\",\"values\":{\"schema\":{\"aql_source_free_unit\":{\"type\":\"boolean\",\"nullable\":false}},\"rows\":[{\"aql_source_free_unit\":true}]}},{\"from\":\"aql_source_free\",\"derive\":{\"aql_query_expr_0\":" +
      expression +
      "}},{\"select\":[{\"items\":\"aql_query_expr_0\"}],\"as\":\"aql_gen_0\"}],\"results\":{\"rows\":{\"from\":\"aql_gen_0\",\"fields\":[\"items\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
      construction_limits().program,
      format=Json,
    ).unwrap()
    match
      @check.check_parsed(expected, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("typed array control has no acquisition")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
    let actual = compile(
      @query.parse_query("SELECT " + text + " AS items", syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected), msg=text)
    assert_true(
      @check.check_parsed(actual, check_environment(), None, check_limits())
      is Checked(_),
      msg=text,
    )
  }
}

///|
// This is a common-contract dependency probe, not positive source acceptance.
// GoogleSQL ARRAY<JSON> cannot bypass ordinary constructor capability checks.
test "JSON array source preserves its value before the common capability rejection" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_query_expr_0":{"if":[{"literal":true},{"array":[{"typed_literal":{"type":"json","value":"null"}}]},{"empty_array":{"items":{"type":"json","nullable":false}}}]}}},{"select":[{"items":"aql_query_expr_0"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["items"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let actual = compile(
    @query.parse_query(
      "SELECT ARRAY<JSON>[JSON 'null'] AS items",
      syntax_limits(),
    ).unwrap(),
    { ..fixture_context(), inputs: [], },
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
  for program in [expected, actual] {
    guard @check.check_parsed(
        program,
        check_environment(),
        None,
        check_limits(),
      )
      is Rejected(diagnostic) else {
      fail("JSON constructor capability dependency must remain explicit")
    }
    guard @check.diagnostic_cause(diagnostic)
      is Source(SourceView(Program(Program(Pipeline(_, issue))))) else {
      raise @check.diagnostic_cause(diagnostic)
    }
    assert_true(issue.kind is Operation(Expression(ForbiddenConstructorValue)))
  }
}

///|
test "checked machine arrays retain recursive types while the source profile rejects direct nesting" {
  let control = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_query_expr_0":{"array":[{"array":[{"literal":2},{"literal":1},{"literal":2}]}]}}},{"select":[{"items":"aql_query_expr_0"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["items"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  guard @check.check_parsed(control, check_environment(), None, check_limits())
    is Checked(checked) else {
    fail("recursive machine array control must remain admissible")
  }
  guard @frontend.check_array_profile(checked, max_work=4096, max_slots=64)
    is Err(UnsupportedNestedArray(unit, step, source)) else {
    fail("source-only profile must use the checked nested item type")
  }
  assert_eq(unit, 0)
  assert_eq(step, 1)
  assert_eq(@expression_syntax.location_path(source), [
    @source.Key("stages"),
    @source.Index(0),
    @source.Key("steps"),
    @source.Index(1),
    @source.Key("derive"),
    @source.Key("aql_query_expr_0"),
  ])
  assert_true(
    @frontend.check_array_profile(checked, max_work=0, max_slots=64)
    is Err(BudgetExceeded),
  )
  assert_true(
    @frontend.check_array_profile(checked, max_work=4096, max_slots=0)
    is Err(BudgetExceeded),
  )
  assert_true(
    @frontend.check_array_profile(checked, max_work=-1, max_slots=64)
    is Err(InvalidLimits),
  )
}

///|
test "source profile checks admitted Relation producer types beyond constructors" {
  let controls = [
    (
      #|{"version":"actql/0.1","id":"fixture.array_reference","stages":[{"id":"main","inputs":{},"steps":[{"as":"rows","values":{"schema":{"id":{"type":"number","nullable":false},"matrix":{"type":"array","nullable":false,"max_items":1,"items":{"type":"array","nullable":false,"max_items":2,"items":{"type":"number","nullable":false}}}},"rows":[{"id":1,"matrix":[[1,2]]}]}},{"sort":[{"field":"id","dir":"asc","nulls":"first"}]},{"select":["id","matrix"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","matrix"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    (
      #|{"version":"actql/0.1","id":"fixture.array_aggregate","stages":[{"id":"main","inputs":{},"steps":[{"as":"rows","values":{"schema":{"id":{"type":"number","nullable":false},"xs":{"type":"array","nullable":false,"max_items":2,"items":{"type":"number","nullable":false}}},"rows":[{"id":1,"xs":[1,2]}]}},{"assert_rows":{"unique_by":["id"]}},{"group":{"by":["id"],"aggregates":{"items":{"fn":"array_agg","expr":{"field":"xs"},"order_by":[{"field":"id","dir":"asc","nulls":"first"}],"max_items":2}}},"as":"grouped"},{"sort":[{"field":"id","dir":"asc","nulls":"first"}],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","items"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
  ]
  for index, text in controls {
    let control = @program.parse(
      text,
      construction_limits().program,
      format=Json,
    ).unwrap()
    let checked = match
      @check.check_parsed(control, check_environment(), None, check_limits()) {
      Checked(checked) => checked
      NeedsInputs(_) => fail("machine controls contain no acquisition")
      Rejected(diagnostic) =>
        match @check.diagnostic_cause(diagnostic) {
          Source(SourceView(Program(Program(Order(_, PipelineOrder(issue)))))) =>
            fail("control \{index}: " + @debug.to_string(issue.kind))
          Source(SourceView(Program(Program(Order(_, ResultOrder(issue)))))) =>
            fail("control \{index}: " + @debug.to_string(issue.kind))
          cause => raise cause
        }
    }
    guard @frontend.check_array_profile(checked, max_work=4096, max_slots=64)
      is Err(UnsupportedNestedArrayColumn(unit, target, name)) else {
      fail("source profile must inspect the admitted producer output")
    }
    assert_eq(unit, 0)
    if index == 0 {
      assert_eq(target, @pipeline.Step(0))
      assert_eq(name, "matrix")
    } else {
      assert_eq(target, @pipeline.Step(2))
      assert_eq(name, "items")
    }
  }
}
