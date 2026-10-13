///|
fn pipe_edit_collision_expected(
  steps : String,
  fields : String,
) -> @program.Program {
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},
    ) +
    steps +
    (
      #|],"results":{"rows":{"from":"aql_gen_0","fields":
    ) +
    fields +
    (
      #|}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "Pipe RENAME refuses a current column hidden by its range name" {
  for
    source in [
      "FROM pair AS x |> RENAME x AS `current` |> SELECT current", "FROM pair AS `X` |> RENAME `x` AS `current` |> SELECT current",
      "FROM pair |> AS x |> RENAME x AS `current` |> SELECT current",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        pair_context(),
        construction_limits(),
      )
      is Err(AmbiguousColumn),
      msg=source,
    )
  }
}

///|
test "Pipe SET replaces a same-named range with the current typed value" {
  // The current x is a new object. Its member must not reuse original row x=7.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","params":{"replacement":{"type":"object","nullable":false,"fields":{"x":{"type":"number","nullable":false}}}},"stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","derive":{"aql_pipe_set_2":{"$param":"replacement"}}},{"derive":{"aql_pipe_expr_3":{"property":{"value":{"field":"aql_pipe_set_2"},"name":"x"}}}},{"select":[{"value":"aql_pipe_expr_3"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_true(
    @check.check_parsed(
      expected,
      check_environment(),
      Some(aggregate_order_parameter_values("{\"replacement\":{\"x\":99}}")),
      check_limits(),
    )
    is Checked(_),
  )
  for
    source in [
      "FROM pair AS x |> SET x = @replacement |> SELECT x.x AS value", "FROM pair AS `X` |> SET `x` = @replacement |> SELECT `X`.`x` AS value",
      "FROM pair AS x |> SET x = @replacement |> RENAME x AS `current` |> SELECT current.x AS value",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      {
        ..pair_context(),
        parameter_declarations: Some(
          parameter_reference_declarations(
            "{\"replacement\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"x\":{\"type\":\"number\",\"nullable\":false}}}}",
          ),
        ),
      },
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(expected))
  }
}

///|
test "Pipe DROP removes a same-named range along with the current column" {
  for
    source in [
      "FROM pair AS x |> DROP x |> SELECT x.y", "FROM pair AS `X` |> DROP `x` |> SELECT `X`.`y`",
      "FROM pair |> AS x |> DROP x |> WHERE x.y > 0 |> SELECT y",
    ] {
    assert_true(
      compile(
        @query.parse_query(source, syntax_limits()).unwrap(),
        pair_context(),
        construction_limits(),
      )
      is Err(Expression({ issue: UnknownReference, .. })),
      msg=source,
    )
  }
}

///|
test "Pipe SET siblings use the range before the target removes its name" {
  let expected = pipe_edit_collision_expected(
    (
      #|{"from":"pair","derive":{"aql_pipe_set_2":{"literal":99},"aql_pipe_set_3":{"field":"y"}}},{"select":[{"current":"aql_pipe_set_2"},{"original_y":"aql_pipe_set_3"}],"as":"aql_gen_0"}
    ),
    "[\"current\",\"original_y\"]",
  )
  assert_true(
    @check.check_parsed(expected, check_environment(), None, check_limits())
    is Checked(_),
  )
  let actual = compile(
    @query.parse_query(
      "FROM pair AS x |> SET x = 99, y = x.y |> SELECT x AS `current`, y AS original_y",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(actual), semantic(expected))
}

///|
test "Pipe edits retain range names different from their targets" {
  let projection = pipe_edit_collision_expected(
    (
      #|{"from":"pair","select":[{"original":"x"},{"retained":"y"}],"as":"aql_gen_0"}
    ),
    "[\"original\",\"retained\"]",
  )
  for
    source in [
      "FROM pair AS old |> DROP x |> SELECT old.x AS original, y AS retained", "FROM pair AS x |> RENAME y AS z |> SELECT x.x AS original, z AS retained",
    ] {
    let actual = compile(
      @query.parse_query(source, syntax_limits()).unwrap(),
      pair_context(),
      construction_limits(),
    ).unwrap()
    assert_eq(semantic(actual), semantic(projection))
  }
}
