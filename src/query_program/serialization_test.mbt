///|
test "SERIALIZE lowers visible names to an independently authored ordinary Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","select":["x","y"],"as":"aql_serialize_input_0"},{"from":"aql_serialize_input_0","serialize":{"format":"jsonl","fields":["x","y"],"preserve_order":true,"name":"pair.jsonl","bounds":{"max_rows":1,"max_bytes":128}},"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["name","content","media_type","size_bytes","row_count"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let program = compile(
    @query.parse_query(
      "FROM pair |> SERIALIZE FORMAT JSONL PRESERVE ORDER OPTIONS (name = 'pair.jsonl', max_rows = 1, max_bytes = 128)",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(program), semantic(expected))
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    _ => fail("SERIALIZE uses common Program checking")
  }
}

///|
test "terminal RESULT binds the exact Content barrier without a synthetic Compute suffix" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.pipe_slots","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false},"y":{"type":"number","nullable":false}},"rows":[{"x":7,"y":9}]},"as":"pair"},{"from":"pair","select":["x","y"],"as":"aql_serialize_input_0"},{"from":"aql_serialize_input_0","serialize":{"format":"jsonl","fields":["x","y"],"preserve_order":true,"name":"pair.jsonl","bounds":{"max_rows":1,"max_bytes":128}},"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["name","content","media_type","size_bytes","row_count"]}}}],"results":{"file":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  let program = compile(
    @query.parse_query(
      "FROM pair |> SERIALIZE FORMAT JSONL PRESERVE ORDER OPTIONS (name = 'pair.jsonl', max_rows = 1, max_bytes = 128) |> RESULT file",
      syntax_limits(),
    ).unwrap(),
    pair_context(),
    construction_limits(),
  ).unwrap()
  assert_eq(semantic(program), semantic(expected))
  match
    @check.check_parsed(program, check_environment(), None, check_limits()) {
    Checked(_) => ()
    Rejected(diagnostic) => raise @check.diagnostic_cause(diagnostic)
    _ => fail("terminal Content Result uses common checking")
  }
}

///|
test "SERIALIZE profile is checked commonly and its input scope does not survive" {
  for
    text in [
      "FROM pair |> SERIALIZE FORMAT JSONL PRESERVE ORDER OPTIONS (name = 'x') |> SELECT x",
      "FROM pair |> SERIALIZE FORMAT JSONL PRESERVE ORDER OPTIONS (name = x)", "FROM pair |> SERIALIZE FORMAT JSONL PRESERVE ORDER OPTIONS (name = 'x', max_rows = x)",
    ] {
    assert_true(
      compile(
        @query.parse_query(text, syntax_limits()).unwrap(),
        pair_context(),
        construction_limits(),
      )
      is Err(_),
      msg=text,
    )
  }
  for
    text in [
      "FROM pair |> SERIALIZE FORMAT CSV PRESERVE ORDER OPTIONS (name = 'x')", "FROM pair |> SERIALIZE FORMAT JSONL PRESERVE ORDER OPTIONS (name = 'x', header = TRUE)",
      "FROM pair |> SERIALIZE FORMAT CSV PRESERVE ORDER OPTIONS (name = 'x', header = TRUE, null_marker = 'NULL')",
    ] {
    let program = compile(
      @query.parse_query(text, syntax_limits()).unwrap(),
      pair_context(),
      construction_limits(),
    ).unwrap()
    assert_true(
      @check.check_parsed(program, check_environment(), None, check_limits())
      is Rejected(_),
      msg=text,
    )
  }
}
