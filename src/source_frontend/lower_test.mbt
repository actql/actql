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
fn alias_limits() -> @syntax.LexicalLimits {
  {
    max_source_bytes: 256,
    max_tokens: 32,
    max_literal_bytes: 256,
    max_work: 512,
  }
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
test "retired structural envelopes reject without context or a fallback" {
  for
    document in [
      "AQL '0.1'; PROGRAM 'old' { STAGE s { STEP {}; } }", "-- retired\n /* prefix */ aQl '0.1'; PROGRAM 'old' {}",
      "PROGRAM 'old' {}", "STAGE main { STEP {}; }", "STEP {\"values\":{}};", "OP values {};",
    ] {
    let formats : Array[Format] = [Text, Sql]
    for format in formats {
      assert_true(lower(document, format, None) is Err(WrongQueryForm))
      assert_true(
        lower(document, format, Some(test_context())) is Err(WrongQueryForm),
      )
    }
  }
}

///|
test "query and machine input routes retain explicit formats and declarations" {
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
  let declared = {
    ..context,
    parameter_declarations: Some(test_declarations()),
  }
  let program = lower(
    "SELECT id FROM records WHERE id = @p",
    Sql,
    Some(declared),
  ).unwrap()
  assert_true(
    program.document.contains("\"params\":{\"p\":{\"type\":\"number\"}}"),
  )
  let machine = "{\"version\":\"actql/0.1\",\"id\":\"retained\"}"
  assert_eq(lower(machine, Json, None).unwrap().document, machine)
  assert_true(lower(machine, Json, None).unwrap().program is None)
  let yaml = "version: actql/0.1\nid: retained\n"
  assert_eq(lower(yaml, Yaml, None).unwrap().document, yaml)
  assert_true(lower(yaml, Yaml, None).unwrap().program is None)
}

///|
fn lookup(cursor : @wire.Cursor, key : String) -> @wire.Cursor {
  @wire.lookup(@wire.open_object(cursor).unwrap(), key).unwrap()
}

///|
test "unresolved column projection exposes only retained authored identifier origins" {
  // Independent byte expectations preserve the original four-byte scalar and
  // CRLF. The existing lowerer owns name resolution and its typed conclusion.
  for
    (text, start, end) in [
      ("SELECT missing AS n", 7, 14),
      ("/*😀*/\r\nSELECT missing AS n", 17, 24),
    ] {
    for format in [Format::Sql, Format::Text] {
      let issue = match
        lower(text, format, Some(test_context()), source_path="submitted.sql") {
        Err(issue) => issue
        Ok(_) => fail("the existing lowerer must reject an unknown column")
      }
      assert_true(
        issue is QueryLowering(Expression({ issue: UnknownReference, .. })),
      )
      let origin = unknown_column_origin(issue).unwrap()
      assert_eq(@origin.kind(origin), @origin.Authored)
      let span = @origin.span(origin)
      assert_eq(span.source_path, "submitted.sql")
      assert_eq(span.start_byte, start)
      assert_eq(span.end_byte, end)
    }
  }
  for format in [Format::Sql, Format::Text] {
    let issue = match
      lower("SELECT missing AS n FROM protected", format, Some(test_context())) {
      Err(issue) => issue
      Ok(_) => fail("an unpublished Source must remain unresolved")
    }
    assert_true(issue is QueryLowering(UnknownRelation))
    assert_true(unknown_column_origin(issue) is None)
  }
  // The unaliased optimization currently carries no original origin. Do not
  // invent a span by inspecting the input after the lowerer has rejected it.
  let unlocated = match lower("SELECT missing", Sql, Some(test_context())) {
    Err(issue) => issue
    Ok(_) => fail("the existing lowerer must reject an unknown column")
  }
  assert_true(unlocated is QueryLowering(UnknownColumn))
  assert_true(unknown_column_origin(unlocated) is None)
  assert_true(
    unknown_column_origin(
      QueryLowering(Expression({ issue: UnknownReference, origin: None, })),
    )
    is None,
  )
  let document = @origin.document("missing", 64).unwrap()
  let generated = @origin.range(document, 0, 7, kind=Generated).unwrap()
  assert_true(
    unknown_column_origin(
      QueryLowering(
        Expression({ issue: UnknownReference, origin: Some(generated), }),
      ),
    )
    is None,
  )
}

///|
test "retained query Program keeps authored unknown-Parameter spans through the existing checker" {
  // Fixed byte expectations include four-byte Unicode and an unmodified CRLF.
  // They are authored independently of lowerer output and token positions.
  for
    (text, start, end) in [
      ("SELECT @missing AS n", 7, 15),
      ("/*😀*/\r\nSELECT @missing AS n", 17, 25),
    ] {
    for format in [Format::Sql, Format::Text] {
      let lowered = lower(
        text,
        format,
        Some(test_context()),
        source_path="submitted.sql",
      ).unwrap()
      let program = lowered.program.unwrap()
      let stage = @program.stages(program)[0]
      let steps = @wire.elements(lookup(@program.stage_body(stage), "steps")).unwrap()
      let expression = lookup(lookup(steps[1], "derive"), "aql_query_expr_0")
      let admitted = @expression.admit(expression, {
        max_nodes: 64,
        max_depth: 16,
        max_text_bytes: 1024,
        max_tokens: 64,
        tree: {
          max_nodes: 64,
          max_depth: 16,
          max_string_bytes: 1024,
          max_total_string_bytes: 1024,
        },
      }).unwrap()
      match
        @typing.check(
          admitted,
          { fields: None, left: None, right: None, parameters: None, },
          {
            max_nodes: 64,
            max_depth: 16,
            max_work: 1024,
            max_text_bytes: 1024,
          },
        ) {
        Err(issue) => {
          assert_eq(issue.kind, @typing.UnknownParameter("missing"))
          let span = @wire.cursor_span(issue.location.source)
          assert_eq(span.source_path, "submitted.sql")
          assert_eq(span.start_byte, start)
          assert_eq(span.end_byte, end)
          assert_true(issue.location.range is None)
        }
        Ok(_) => fail("the common checker must reject the undeclared Parameter")
      }
    }
  }
}

///|
test "published query names bind one environment generation" {
  let input = test_context().inputs[0]
  let parsed = @syntax.parse_relation_path("crm.`Records`", alias_limits()).unwrap()
  assert_eq(parsed.length(), 2)
  assert_eq(parsed[0].value, "crm")
  assert_eq(parsed[1].value, "Records")
  assert_true(parsed[1].quoted)
  assert_true(
    @syntax.parse_relation_path("records.extra more", alias_limits()) is Err(_),
  )
  assert_true(@syntax.parse_relation_path("records.", alias_limits()) is Err(_))
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

///|
test "unified source dependency refuses legacy Graph inputs before Program preparation" {
  let context = test_context()
  for
    document in [
      "FROM GRAPH g |> MATCH WALK (a)-[]->(b) |> SELECT *", "FROM GRAPH g |> MATCH WALK (a) |> SELECT a.id",
      "FROM GRAPH g LABELS {\"node\":{\"field\":\"name\"}} |> MATCH WALK (a:Person) |> SELECT a.id",
    ] {
    assert_true(
      lower(document, Text, Some(context))
      is Err(QueryLowering(@query.UnsupportedGraph)),
      msg=document,
    )
  }
}

///|
test "query syntax admission is bounded and independent of semantic context" {
  for format in [Format::Sql, Format::Text] {
    assert_true(parse_query("SELECT @p AS n", format) is Ok(_))
    assert_true(parse_query("SELECT missing FROM protected", format) is Ok(_))
    assert_true(parse_query("SELECT FROM WHERE", format) is Err(QuerySyntax(_)))
    let many = "SELECT " + Array::make(4200, "1").join(",")
    assert_true(
      parse_query(many, format) is Err(QuerySyntax({ issue: Limit(_), .. })),
    )
  }
  assert_true(
    parse_query("FROM records |> SELECT id", Sql) is Err(WrongQueryForm),
  )
  assert_true(parse_query("FROM records |> SELECT id", Text) is Ok(_))
  assert_true(parse_query("{}", Json) is Err(InvalidFormat))
}
