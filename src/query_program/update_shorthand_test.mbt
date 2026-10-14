///|
fn update_shorthand_program(name : String) -> @program.Program {
  compile(
    @query.parse_query(
      "FROM pair |> RESULT updates |> EFFECT " +
      name +
      "UPDATE TARGET 'connector://c/T' MAPPING m FROM RESULT updates ID x SET (Name = y)",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
}

///|
test "anonymous UPDATE has the independently specified stable Program-local name" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","select":["x","y"],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["x","y"]}},"effects":{"aql_update_effect":{"update":{"target":"connector://c/T","mapping":"m","from":{"result":"rows"},"id":"x","set":{"Name":{"field":"y"}}}}}}],"results":{"updates":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let anonymous = update_shorthand_program("")
  assert_eq(semantic(anonymous), semantic(expected))
  for name in ["aql_update_effect ", "`aql_update_effect` ", "/*😀*/\r\n"] {
    assert_eq(
      semantic(update_shorthand_program(name)),
      semantic(expected),
      msg=name,
    )
  }
  for name in ["save ", "`Save.Exact` ", "UPDATE "] {
    assert_false(
      semantic(update_shorthand_program(name)) == semantic(anonymous),
      msg=name,
    )
  }
  // RESULT remains explicitly public; this finite shorthand does not change it.
  assert_eq(@program.export_count(anonymous), 1)
}
