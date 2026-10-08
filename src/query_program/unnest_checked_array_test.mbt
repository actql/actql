///|
// Complete controls are authored from common ARRAY/IF/UNNEST operations, not
// from compiler output. Only the varying source expression is interpolated.
fn checked_array_control(expression : String) -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.query_pair","stages":[{"id":"main","inputs":{},"steps":[{"as":"aql_source_free","values":{"schema":{"aql_source_free_unit":{"type":"boolean","nullable":false}},"rows":[{"aql_source_free_unit":true}]}},{"from":"aql_source_free","derive":{"aql_unnest_array_3":
    ) +
    expression +
    (
      #|}},{"unnest":{"column":"aql_unnest_array_3","as":"aql_unnest_element_4","with_index":"aql_unnest_offset_5"}},{"sort":[{"field":"aql_unnest_offset_5","dir":"asc","nulls":"first"}]},{"select":[{"element":"aql_unnest_element_4"},{"position":"aql_unnest_offset_5"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["element","position"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "UNNEST checked ARRAY expressions preserve contextual and explicit item contracts" {
  for
    (source, expression) in [
      (
        "ARRAY<STRING>[]",
        (
          #|{"empty_array":{"items":{"type":"string","nullable":false}}}
        ),
      ),
      (
        "IF(TRUE, [], ['x'])",
        (
          #|{"if":[{"literal":true},{"array":[]},{"array":[{"literal":"x"}]}]}
        ),
      ),
      (
        "IF(FALSE, [NULL], [TRUE, NULL])",
        (
          #|{"if":[{"literal":false},{"array":[{"literal":null}]},{"array":[{"literal":true},{"literal":null}]}]}
        ),
      ),
      (
        "ARRAY<BOOL>[NULL]",
        (
          #|{"if":[{"literal":true},{"array":[{"literal":null}]},{"empty_array":{"items":{"type":"boolean","nullable":false}}}]}
        ),
      ),
    ] {
    let expected = checked_array_control(expression)
    match
      @check.check_parsed(expected, check_environment(), None, check_limits()) {
      Checked(_) => ()
      NeedsInputs(_) => fail("independent control must not acquire a Source")
      Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    }
    for
      text in [
        "SELECT * FROM UNNEST(" +
        source +
        ") element WITH OFFSET position ORDER BY position",
        "FROM UNNEST(" +
        source +
        ") element WITH OFFSET position |> SELECT * |> ORDER BY position",
      ] {
      let actual = compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      ).unwrap()
      assert_eq(semantic(actual), semantic(expected), msg=text)
    }
  }
}

///|
test "UNNEST checked ARRAY scope never guesses unresolved or inadmissible element types" {
  for
    text in [
      "SELECT * FROM UNNEST([]) element", "SELECT * FROM UNNEST([NULL]) element",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      )
      is Err(UnsupportedProjection),
      msg=text,
    )
  }
  for text in [
    "SELECT * FROM UNNEST([1, 'wrong']) element",
    "SELECT * FROM UNNEST(ARRAY<BOOL>[1]) element",
  ] {
    assert_true(compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      { ..fixture_context(), inputs: [], }, construction_limits(),
    ) is Err(ExpressionTyping({kind: TypeMismatch(_), ..})), msg=text)
  }
}

///|
test "UNNEST scalar qualified star retains its existing unknown-column refusal" {
  assert_true(
    compile(
      @query.parse_query(
        "SELECT element.* FROM UNNEST([1, 2]) element",
        syntax_limits(),
      ).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    )
    is Err(UnknownColumn),
  )
}
