///|
fn limits() -> LiteralSelectLimits {
  { max_source_bytes: 256, max_columns: 8, max_program_bytes: 4096, }
}

///|
fn syntax_limits() -> @stage.Limits {
  {
    source: { max_input_bytes: 4096, max_nodes: 1000, max_depth: 32, },
    tree: {
      max_nodes: 1000,
      max_depth: 32,
      max_string_bytes: 4096,
      max_total_string_bytes: 4096,
    },
    max_stages: 2,
  }
}

///|
test "literal SELECT emits the independently expected Program document" {
  let compiled = compile_literal_select(
    "SELECT 1 AS id, -2 AS debt;",
    "literal-query-1",
    limits(),
  ).unwrap()
  let output = compiled.document
  assert_eq(compiled.columns, [
    { name: "id", literal_offset: 7, alias_offset: 12, },
    { name: "debt", literal_offset: 16, alias_offset: 22, },
  ])
  let expected =
    #|{"version":"actql/0.1","id":"literal-query-1","stages":[{"id":"sql_source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false},"debt":{"type":"number","nullable":false}},"rows":[{"id":1,"debt":-2}]},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id","debt"]}}}],"results":{"answer":{"from":{"stage":"sql_source","result":"rows"}}}}
  assert_eq(@json.parse(output), @json.parse(expected))
  let parsed = @stage.parse(output, syntax_limits(), format=@stage.Json).unwrap()
  assert_eq(@stage.stage_count(parsed), 1)
  assert_eq(@stage.exports(parsed), [("answer", "sql_source", "rows")])
}

///|
test "literal SELECT rejects unsupported SQL and duplicate aliases" {
  assert_eq(
    compile_literal_select("SELECT 1 AS id FROM t", "query", limits()),
    Err(UnsupportedSyntax(15)),
  )
  assert_eq(
    compile_literal_select("SELECT x AS id", "query", limits()),
    Err(UnsupportedSyntax(7)),
  )
  assert_eq(
    compile_literal_select("SELECT 1 AS id, 2 AS ID", "query", limits()),
    Err(DuplicateColumn(21)),
  )
  assert_eq(
    compile_literal_select("SELECT 2147483648 AS n", "query", limits()),
    Err(InvalidInteger(7)),
  )
  assert_eq(
    compile_literal_select("SELECT 1 AS id", "query", {
      max_source_bytes: 256,
      max_columns: 8,
      max_program_bytes: 32,
    }),
    Err(OutputLimit),
  )
}
