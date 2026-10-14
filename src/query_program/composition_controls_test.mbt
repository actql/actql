///|
test "composition assertion and Effect retain the existing named Result owner" {
  let text = "FROM pair |> ASSERT UNIQUE BY (x) |> RESULT updates |> EFFECT save UPDATE TARGET 'connector://crm-main/Test_Record__c' MAPPING `mapping:fixture.v1` FROM RESULT updates ID x SET (Name = y)"
  let program = compile(
    @query.parse_query(text, syntax_limits()).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  let body = semantic(program)
  assert_true(body.contains("\"assert_rows\":{\"unique_by\":[\"x\"]}"))
  assert_true(
    body.contains(
      "\"effects\":{\"save\":{\"update\":{\"from\":{\"result\":\"rows\"},\"id\":\"x\",\"mapping\":\"mapping:fixture.v1\",\"set\":{\"Name\":{\"field\":\"y\"}},\"target\":\"connector://crm-main/Test_Record__c\"}}}",
    ),
  )
  assert_eq(@program.export_count(program), 1)
  assert_true(
    body.contains(
      "\"updates\":{\"from\":{\"result\":\"rows\",\"stage\":\"main\"}}",
    ),
  )
}

///|
test "Effect evaluates pure SET values and refuses foreign Result inputs" {
  let prefix = "FROM pair |> RESULT updates |> EFFECT save UPDATE TARGET 'connector://c/T' MAPPING m FROM RESULT "
  let refused = [
    "unknown ID x SET (Name = y)",
    "updates ID missing SET (Name = y)",
    "updates ID x SET (Name = y, Name = x)",
  ]
  for index in 0..<refused.length() {
    let result = compile(
      @query.parse_query(prefix + refused[index], syntax_limits()).unwrap(),
      pair_context(), construction_limits(),
    )
    match (index, result) {
      (0, Err(UnsupportedEffect)) | (1, Err(UnknownColumn)) |
      (2, Err(DuplicateOutput)) => ()
      _ => fail("wrong refusal for " + refused[index])
    }
  }
  // The adopted pure-SET contract evaluates against the selected Result in
  // the ordinary Relation owner, then supplies a field to the closed Effect.
  let computed = compile(
    @query.parse_query(prefix + "updates ID x SET (Name = y + 1)", syntax_limits()).unwrap(),
    pair_context(), construction_limits(),
  ).unwrap()
  assert_eq(@program.exports(computed), [("updates", "main", "rows")])
  let stage = @wire.open_object(@program.stage_body(@program.stages(computed).last().unwrap())).unwrap()
  let ports = @wire.open_object(@wire.required(stage, "results").unwrap()).unwrap()
  let capture = @wire.open_object(@wire.required(ports, "aql_private_update").unwrap()).unwrap()
  let fields = @wire.elements(@wire.required(capture, "fields").unwrap()).unwrap()
    .map(field => @wire.text(field).unwrap())
  assert_eq(fields.length(), 2)
  assert_eq(fields[0], "x")
  assert_true(fields[1] != "x" && fields[1] != "y")
  let steps = @wire.elements(@wire.required(stage, "steps").unwrap()).unwrap()
  let derives = steps.filter(step => {
    let step = @wire.open_object(step).unwrap()
    @wire.lookup(step, "derive").map(body => {
      @wire.lookup(@wire.open_object(body).unwrap(), fields[1]) is Some(_)
    }).unwrap_or(false)
  })
  assert_eq(derives.length(), 1)
  let derive_step = @wire.open_object(derives[0]).unwrap()
  let derive = @wire.open_object(@wire.required(derive_step, "derive").unwrap()).unwrap()
  let expression = @wire.open_object(@wire.required(derive, fields[1]).unwrap()).unwrap()
  let operands = @wire.elements(@wire.required(expression, "add").unwrap()).unwrap()
  assert_eq(operands.length(), 2)
  assert_eq(@wire.text(@wire.required(@wire.open_object(operands[0]).unwrap(), "field").unwrap()).unwrap(), "y")
  assert_eq(@wire.number(@wire.required(@wire.open_object(operands[1]).unwrap(), "literal").unwrap()).unwrap(), 1.0)
  let public = @wire.open_object(@wire.required(ports, "rows").unwrap()).unwrap()
  assert_eq(@wire.text(@wire.required(derive_step, "from").unwrap()),
    @wire.text(@wire.required(public, "from").unwrap()))
  let effect = @wire.open_object(@wire.required(@wire.open_object(@wire.required(stage, "effects").unwrap()).unwrap(), "save").unwrap()).unwrap()
  let update = @wire.open_object(@wire.required(effect, "update").unwrap()).unwrap()
  assert_eq(@wire.text(@wire.required(@wire.open_object(@wire.required(update, "from").unwrap()).unwrap(), "result").unwrap()).unwrap(), "aql_private_update")
  assert_eq(@wire.text(@wire.required(update, "id").unwrap()).unwrap(), "x")
  let assignment = @wire.open_object(@wire.required(@wire.open_object(@wire.required(update, "set").unwrap()).unwrap(), "Name").unwrap()).unwrap()
  assert_eq(@wire.text(@wire.required(assignment, "field").unwrap()).unwrap(), fields[1])
  assert_eq(semantic(computed).split("\"values\":{").length(), 2)
  let actual = compile(
    @query.parse_query(
      prefix + "updates ID x SET (Name = 'é\\r\\n')",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_true(semantic(actual).contains("\"literal\":\"é\\r\\n\""))
}

///|
test "unshared WITH retains its ordinary Source predicate exactly once" {
  let actual = compile_query_script(
    @query.parse_query_script(
      "WITH kept AS (FROM orders |> WHERE id = id |> SELECT id) FROM kept |> SELECT id",
      syntax_limits(),
    ).unwrap(),
    { ..fixture_context(), captured_stage: Some("capture"), },
    construction_limits(),
  ).unwrap()
  let body = semantic(actual)
  assert_true(
    body.contains("\"filter\":{\"eq\":[{\"field\":\"id\"},{\"field\":\"id\"}]}"),
  )
  assert_false(body.contains("\"filter\":{\"literal\":true}"))
  assert_eq(body.split("\"eq\"").length(), 2)
  assert_eq(@program.stage_count(actual), 2)
}

///|
test "WITH JOIN retains the authored output guard rather than the frontend default" {
  let text = "WITH joined AS (SELECT l.x AS x FROM pair AS l JOIN pair AS r ON l.x = r.x MAX_OUTPUT_ROWS 10) FROM joined |> RESULT updates"
  let script = @query.parse_query_script(text, syntax_limits()).unwrap()
  let actual = compile_query_script(
    script,
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_true(semantic(actual).contains("\"max_output_rows\":10"))
  assert_true(
    compile_query_script(script, pair_context(), {
      ..construction_limits(),
      max_join_output_rows: 9L,
    })
    is Err(_),
  )
}

///|
test "text Effect continuation keeps a retained Result at its own Stage boundary" {
  let text = "FROM pair |> ASSERT UNIQUE BY (x) |> INFER score ITEM KEY (x) INPUT (n = y) KEEP (x, y) AS assessment |> SELECT x, y |> RESULT classified |> WHERE y > 0 |> EXTEND 'next' AS next_name |> RESULT updates |> EFFECT save UPDATE TARGET 'connector://c/T' MAPPING m FROM RESULT updates ID x SET (Name = next_name)"
  let actual = compile(
    @query.parse_query(text, syntax_limits()).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(@program.stage_count(actual), 2)
  assert_eq(@program.export_count(actual), 2)
  let body = semantic(actual)
  assert_true(
    body.contains(
      "\"classified\":{\"from\":{\"result\":\"rows\",\"stage\":\"main\"}}",
    ),
  )
  assert_true(
    body.contains(
      "\"updates\":{\"from\":{\"result\":\"rows\",\"stage\":\"aql_script_continuation_0\"}}",
    ),
  )
}

///|
test "Model Result continuation cannot discard immutable range carriers or earlier roots" {
  let infer = " |> ASSERT UNIQUE BY (x) |> INFER score ITEM KEY (x) INPUT (n = y) KEEP (x, y) AS assessment"
  let effect = " |> RESULT classified |> WHERE y > 0 |> RESULT updates |> EFFECT save UPDATE TARGET 'connector://c/T' MAPPING m FROM RESULT updates ID x SET (Name = y)"
  for
    text in [
      "FROM pair" + infer + " |> AS original |> SET y = x" + effect,
      "FROM pair |> RESULT before" + infer + " |> SELECT x, y" + effect,
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        pair_context(),
        construction_limits(),
      )
      is Err(UnsupportedEffect),
      msg=text,
    )
  }
}
