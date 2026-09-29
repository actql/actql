///|
fn test_context() -> @query.Context {
  let parsed = @source.parse_json(
    "{\"connector\":\"crm/main\",\"resource\":\"records\"}",
    { max_input_bytes: 1024, max_nodes: 64, max_depth: 8, },
  ).unwrap()
  let declaration = @wire.admit(parsed, {
    max_nodes: 64,
    max_depth: 8,
    max_string_bytes: 1024,
    max_total_string_bytes: 1024,
  }).unwrap()
  {
    program_id: "frontend.route",
    stage_id: "main",
    stage_result: "rows",
    result_name: "answer",
    captured_stage: Some("capture"),
    parameter_declarations: None,
    inputs: [
      {
        relation: [{ value: "records", quoted: false, }],
        name: "source",
        source: @query.Captured(declaration),
        visible_fields: ["id"],
        graph_bindings: [],
      },
    ],
    graph_inputs: [],
  }
}

///|
fn test_declarations() -> @parameters.Declarations {
  let parsed = @source.parse_json("{\"p\":{\"type\":\"number\"}}", {
    max_input_bytes: 1024,
    max_nodes: 64,
    max_depth: 8,
  }).unwrap()
  let cursor = @wire.admit(parsed, {
    max_nodes: 64,
    max_depth: 8,
    max_string_bytes: 1024,
    max_total_string_bytes: 1024,
  }).unwrap()
  @parameters.read_declarations(Some(cursor), {
    max_parameters: 10,
    max_nodes: 64,
    max_depth: 8,
    max_text_bytes: 1024,
  }).unwrap()
}

///|
test "explicit format aliases retain the structured route" {
  assert_true(select_format("json") is Ok(Json))
  assert_true(select_format("aql-json") is Ok(Json))
  assert_true(select_format("yaml") is Ok(Yaml))
  assert_true(select_format("aql-yaml") is Ok(Yaml))
  assert_true(select_format("auto") is Err(InvalidFormat))
}

///|
test "structural AQL and query-only AQL use distinct parsers" {
  let structural =
    #|AQL '0.1'; PROGRAM 'frontend.route' {
    #| STAGE main {
    #|  DATA source = OP values {"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":2}]};
    #|  RESULT rows = {"from":"source"};
    #| }
    #| RESULT answer = {"from":{"stage":"main","result":"rows"}};
    #|}
  let first = lower(structural, Text, None).unwrap()
  assert_eq(first.format, @program.Json)
  assert_true(first.document.contains("\"frontend.route\""))
  let context = test_context()
  let sql = lower("SELECT id FROM records WHERE id > 1", Sql, Some(context)).unwrap()
  let pipe = lower(
    "FROM records |> WHERE id > 1 |> SELECT id",
    Text,
    Some(context),
  ).unwrap()
  assert_eq(sql.document, pipe.document)
  assert_true(
    lower("SELECT id FROM", Sql, Some(context)) is Err(QuerySyntax(_)),
  )
  assert_true(
    lower("SELECT id FROM records", Sql, None) is Err(MissingQueryContext),
  )
  assert_true(
    lower("FROM records |> SELECT id", Sql, Some(context))
    is Err(WrongQueryForm),
  )
  assert_true(
    lower("AQL '0.1'; PROGRAM 'broken' {", Text, None) is Err(SourceSyntax(_)),
  )
  let declared = {
    ..test_context(),
    parameter_declarations: Some(test_declarations()),
  }
  assert_true(
    lower(structural, Text, Some(declared))
    is Err(ExternalDeclarationsOnProgram),
  )
  assert_true(
    lower("SELECT id FROM records WHERE id = @p", Sql, Some(declared)) is Ok(_),
  )
}

///|
test "published query names bind one environment generation" {
  let input = test_context().inputs[0]
  let entry : PublishedAlias = {
    name: input.relation,
    source_ref: "connector://crm/main/records#snapshot",
    environment_cid: "sha256:1111111111111111111111111111111111111111111111111111111111111111",
    input: Relation(input),
  }
  let accepted = bind_query_context([entry], entry.environment_cid).unwrap()
  assert_eq(accepted.program_id, "adhoc.query")
  assert_eq(accepted.inputs.length(), 1)
  assert_true(
    bind_query_context([entry], "sha256:other") is Err(EnvironmentMismatch),
  )
  let conflicting = { ..entry, name: [{ value: "RECORDS", quoted: false, }], }
  assert_true(
    bind_query_context([entry, conflicting], entry.environment_cid)
    is Err(ConflictingName),
  )
  let wrong_input = { ..entry, name: [{ value: "other", quoted: false, }], }
  assert_true(
    bind_query_context([wrong_input], entry.environment_cid)
    is Err(InputNameMismatch),
  )
  let quoted = {
    ..entry,
    name: [{ value: "RECORDS", quoted: true, }],
    input: Relation({
      ..input,
      relation: [{ value: "RECORDS", quoted: true, }],
    }),
  }
  assert_true(
    bind_query_context([entry, quoted], entry.environment_cid) is Ok(_),
  )
}
