///|
test "COMMAND postlude lowers to the common Effect contract without another row operator" {
  let program = compile_query_script(
    @query.parse_query_script(
      "FROM pair |> RESULT files; EFFECT upload COMMAND FROM RESULT files AS t TARGET t.x CONTRACT `command:files.upload.v1` INPUT (name = 'é\\r\\n', content = t.y);",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"aql_script_seed_1"},{"from":"aql_script_seed_1","select":["x","y"],"as":"aql_script_result"}],"results":{"rows":{"from":"aql_script_result","fields":["x","y"]}},"effects":{"upload":{"command":{"from":{"result":"rows"},"target":{"field":"x"},"contract":"command:files.upload.v1","input":{"name":{"literal":"é\r\n"},"content":{"field":"y"}}}}}}],"results":{"files":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(semantic(program), semantic(expected))
}

///|
test "COMMAND continuation imports the original retained Model Result" {
  let script = @query.parse_query_script(
    "FROM pair |> ASSERT UNIQUE BY (x) |> INFER score ITEM KEY (x) INPUT (n = y) KEEP (x, y) AS assessment |> SELECT x, y |> RESULT classified |> WHERE y > 0 |> RESULT files; EFFECT upload COMMAND FROM RESULT files AS t TARGET t.x CONTRACT c INPUT (n = t.y);",
    syntax_limits(),
  ).unwrap()
  let program = compile_query_script(
    script,
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(@program.stage_count(program), 2)
  let body = semantic(program)
  assert_true(
    body.contains(
      "\"classified\":{\"from\":{\"result\":\"rows\",\"stage\":\"main\"}}",
    ),
  )
  assert_true(
    body.contains(
      "\"files\":{\"from\":{\"result\":\"rows\",\"stage\":\"aql_script_continuation_0\"}}",
    ),
  )
  assert_eq(body.split("\"command\"").length(), 2)
  assert_true(body.contains("\"target\":{\"field\":\"x\"}"))
}

///|
test "COMMAND refuses computed values foreign aliases and undeclared Result fields" {
  for
    tail in [
      "unknown AS t TARGET t.x CONTRACT c INPUT ()", "files AS t TARGET other.x CONTRACT c INPUT ()",
      "files AS t TARGET t.absent CONTRACT c INPUT ()", "files AS t TARGET t.x CONTRACT c INPUT (p = t.y + 1)",
      "files AS t TARGET t.x CONTRACT c INPUT (p = other.y)",
    ] {
    let script = @query.parse_query_script(
      "FROM pair |> RESULT files; EFFECT upload COMMAND FROM RESULT " +
      tail +
      ";",
      syntax_limits(),
    ).unwrap()
    assert_true(
      compile_query_script(script, pair_context(), construction_limits())
      is Err(_),
      msg=tail,
    )
  }
}
