///|
fn independent_unpivot_row_label_program() -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","select":["y",{"aql_unpivot_input_2":"x"},{"aql_unpivot_input_3":"x"}]},{"unpivot":{"columns":["aql_unpivot_input_2","aql_unpivot_input_3"],"keep":["y"],"name_column":"aql_unpivot_name_4","value_column":"aql_unpivot_value_5"}},{"derive":{"aql_unpivot_label_6":{"if":[{"eq":[{"field":"aql_unpivot_name_4"},{"literal":"aql_unpivot_input_2"}]},{"literal":"first"},{"literal":"second"}]}}},{"sort":[{"field":"aql_unpivot_label_6","dir":"asc","nulls":"first"}]},{"select":["y",{"value":"aql_unpivot_value_5"},{"label":"aql_unpivot_label_6"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["y","value","label"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "UNPIVOT repeated input labels have an independent checked Program" {
  match
    @check.check_parsed(
      independent_unpivot_row_label_program(),
      check_environment(),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("the independent label projection is closed")
  }
}

///|
test "UNPIVOT repeated input labels lower to independent occurrence slots" {
  let actual = compile(
    @query.parse_query(
      "FROM pair |> UNPIVOT INCLUDE NULLS(value FOR label IN(x AS 'first',x AS 'second')) |> ORDER BY label",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(independent_unpivot_row_label_program()))
}

///|
test "UNPIVOT integer row labels distinguish exact syntax from unsupported lowering" {
  for label in ["1", "9007199254740991", "0x1fffffffffffff"] {
    assert_true(
      compile(
        @query.parse_query(
          "FROM pair |> UNPIVOT(value FOR label IN(x AS " + label + ",y AS 1))",
          syntax_limits(),
        ).unwrap(),
        pair_context(),
        construction_limits(),
      ) is Err(UnsupportedProjection),
    )
  }
  for label in ["9223372036854775807", "9007199254740992", "0x20000000000000"] {
    let text = "FROM pair |> UNPIVOT(value FOR label IN(x AS " + label + ",y AS 1))"
    match @query.parse_query(text, syntax_limits(), source_path="unpivot.sql") {
      Err({ issue: Syntax(message), span: Some(span), }) => {
        assert_eq(message, "UNPIVOT row alias requires a String or integer literal")
        assert_eq(span.source_path, "unpivot.sql")
        // Independent ASCII prefix length before the authored row label.
        assert_eq(span.start_byte, 43)
      }
      _ => fail("unsafe integer aliases must not be rounded before lowering")
    }
  }
}

///|
test "UNPIVOT row labels preserve arbitrary String values and current column defaults" {
  let actual = compile(
    @query.parse_query(
      "FROM pair |> RENAME y AS kept |> UNPIVOT INCLUDE NULLS(value FOR label IN(x AS 'e\\u0301\\r',kept))",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  let wire = semantic(actual)
  assert_true(wire.contains("\"literal\":\"é\\r\""), msg=wire)
  assert_true(wire.contains("\"literal\":\"kept\""), msg=wire)
  assert_false(wire.contains("\"literal\":\"é\\r\""), msg=wire)
  assert_true(
    @check.check_parsed(actual, check_environment(), None, check_limits())
    is Checked(_),
  )
}
