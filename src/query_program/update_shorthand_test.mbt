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
  // The adopted Script owner binds the original input as seed_1 (one reserved
  // input) and emits its fixed private result; all values and public names stay.
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","select":["x","y"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["x","y"]}},"effects":{"aql_update_effect":{"update":{"target":"connector://c/T","mapping":"m","from":{"result":"rows"},"id":"x","set":{"Name":{"field":"y"}}}}}}],"results":{"updates":{"from":{"stage":"main","result":"rows"}}}}
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
  for
    (name, exact) in [
      ("save ", "save"),
      ("`Save.Exact` ", "Save.Exact"),
      ("UPDATE ", "UPDATE"),
    ] {
    assert_false(
      semantic(update_shorthand_program(name)) == semantic(anonymous),
      msg=name,
    )
    assert_true(
      semantic(update_shorthand_program(name)).contains(
        "\"effects\":{\"" + exact + "\":{\"update\":",
      ),
    )
  }
  // RESULT remains explicitly public; this finite shorthand does not change it.
  assert_eq(@program.export_count(anonymous), 1)
}

///|
test "the anonymous UPDATE name does not collide across separate Result and Effect namespaces" {
  let actual = compile(
    @query.parse_query(
      "FROM pair |> RESULT aql_update_effect |> EFFECT UPDATE TARGET 'connector://c/T' MAPPING m FROM RESULT aql_update_effect ID x SET (Name = y)",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  let body = semantic(actual)
  assert_true(body.contains("\"effects\":{\"aql_update_effect\":{\"update\":"))
  assert_true(
    body.contains(
      "\"results\":{\"aql_update_effect\":{\"from\":{\"result\":\"rows\",\"stage\":\"main\"}}}",
    ),
  )
}
