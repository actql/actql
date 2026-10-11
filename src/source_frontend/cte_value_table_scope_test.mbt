///|
test "public SQL and text entries preserve CTE scalar value-table receivers" {
  let context = bind_query_context([], "fixture.environment").unwrap()
  for
    source in [
      "WITH a AS (FROM UNNEST([1,2]) old_l) SELECT l AS value FROM a AS l ORDER BY value",
      "WITH a AS (FROM UNNEST([1,2]) old_l) SELECT l AS value FROM a AS l JOIN a AS r ON ((l))=(r) MAX_OUTPUT_ROWS 10 ORDER BY value",
    ] {
    for format in [Format::Sql, Format::Text] {
      let lowered = lower(source, format, Some(context)).unwrap()
      assert_false(lowered.document.contains("\"object\":"), msg=source)
      assert_eq(@program.stage_count(lowered.program.unwrap()), 1)
    }
  }
}

///|
test "public CTE value-table routing preserves ordinary rows and hidden names" {
  let context = bind_query_context([], "fixture.environment").unwrap()
  for format in [Format::Sql, Format::Text] {
    for
      source in [
        "WITH a AS (FROM UNNEST([2,1]) element WITH OFFSET position) SELECT l AS row,l.element AS value,l.position FROM a AS l ORDER BY position",
        "WITH a AS (FROM UNNEST([2,1]) element |> SELECT element AS id) SELECT l AS row,l.id AS value FROM a AS l ORDER BY value",
      ] {
      let lowered = lower(source, format, Some(context)).unwrap()
      assert_true(lowered.document.contains("\"object\":"), msg=source)
    }
    assert_true(
      lower(
        "WITH a AS (FROM UNNEST([1,2]) old_l) SELECT old_l FROM a AS l",
        format,
        Some(context),
      )
      is Err(QueryLowering(Expression({ issue: UnknownReference, .. }))),
    )
  }
}

///|
test "public SQL and text entries preserve nullable object CTE values" {
  let parsed = @source.parse_json(
    "{\"items\":{\"type\":\"array\",\"nullable\":true,\"max_items\":3,\"items\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"id\":{\"type\":\"number\"},\"label\":{\"type\":\"string\",\"nullable\":true}}}}}",
    { max_input_bytes: 1024, max_nodes: 64, max_depth: 8, },
  ).unwrap()
  let cursor = @wire.admit(parsed, {
    max_nodes: 64,
    max_depth: 8,
    max_string_bytes: 1024,
    max_total_string_bytes: 1024,
  }).unwrap()
  let declarations = @parameters.read_declarations(Some(cursor), {
    max_parameters: 10,
    max_nodes: 64,
    max_depth: 8,
    max_text_bytes: 1024,
  }).unwrap()
  let context = bind_query_context(
    [],
    "fixture.environment",
    parameter_declarations=Some(declarations),
  ).unwrap()
  for format in [Format::Sql, Format::Text] {
    let lowered = lower(
      "WITH a AS (FROM UNNEST(@items) old_l) SELECT l AS value,l.id AS id FROM a AS l ORDER BY id NULLS FIRST,value.label NULLS FIRST",
      format,
      Some(context),
    ).unwrap()
    assert_false(lowered.document.contains("\"object\":"))
    assert_eq(@program.stage_count(lowered.program.unwrap()), 1)
  }
}
