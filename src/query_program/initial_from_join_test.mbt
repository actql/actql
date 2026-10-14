///|
fn initial_from_graph_inputs() -> String {
  "WITH n AS (SELECT 1 AS id), r AS (SELECT 9 AS tag), g AS (GRAPH (NODE TABLES (n AS N KEY (id) LABEL Node NO PROPERTIES))) "
}

///|
test "initial JOIN rejects Graph before a later explicit row bridge" {
  for marker in ["", "GRAPH "] {
    let source = initial_from_graph_inputs() +
      "FROM " +
      marker +
      "g CROSS JOIN r MAX_OUTPUT_ROWS 10 |> node_rows() |> SELECT id"
    let script = @query.parse_query_script(source, syntax_limits()).unwrap()
    assert_true(
      compile_query_script(
        script,
        { ..fixture_context(), inputs: [], },
        construction_limits(),
      )
      is Err(UnsupportedJoin),
    )
  }
  // A proper bridge before JOIN is an existing Relation producer, not an
  // implicit bridge inserted to rescue a non-Relation JOIN operand.
  assert_true(
    compile_query_script(
      @query.parse_query_script(
        initial_from_graph_inputs() +
        "FROM g |> node_rows() |> AS nodes |> CROSS JOIN r MAX_OUTPUT_ROWS 10 |> SELECT nodes.id",
        syntax_limits(),
      ).unwrap(),
      { ..fixture_context(), inputs: [], },
      construction_limits(),
    )
    is Ok(_),
  )
}

///|
fn initial_from_vector_context() -> Context {
  let input =
    #|{"values":{"schema":{"id":{"type":"number","nullable":false},"embedding":{"type":"vector","element_type":"f32","dimensions":2,"nullable":false}},"rows":[{"id":1,"embedding":[1,0]}]},"as":"candidates"}
  {
    ..fixture_context(),
    inputs: [
      {
        relation: [{ value: "candidates", quoted: false, }],
        name: "candidates",
        source: GeneratedValues(
          @wire.admit(
            @source.parse_json(input, construction_limits().source.source).unwrap(),
            construction_limits().source.tree,
          ).unwrap(),
        ),
        visible_fields: ["id", "embedding"],
        graph_bindings: [],
      },
    ],
  }
}

///|
test "initial JOIN does not discard Vectors or Events before their bridge" {
  for
    (prefix, name, bridge, field) in [
      (
        "WITH typed AS (FROM candidates |> to_vectors(id: id, vector: embedding)), r AS (SELECT 9 AS tag) ",
        "typed", "vectors()", "id",
      ),
      (
        "WITH data AS (SELECT 1 AS id, 0 AS occurred_ms), typed AS (FROM data |> to_events(id: id, time: occurred_ms)), r AS (SELECT 9 AS tag) ",
        "typed", "events()", "id",
      ),
    ] {
    let control = prefix +
      "FROM " +
      name +
      " |> " +
      bridge +
      " |> SELECT " +
      field
    assert_true(
      compile_query_script(
        @query.parse_query_script(control, syntax_limits()).unwrap(),
        initial_from_vector_context(),
        construction_limits(),
      )
      is Ok(_),
      msg=control,
    )
    let invalid = prefix +
      "FROM " +
      name +
      " CROSS JOIN r MAX_OUTPUT_ROWS 10 |> " +
      bridge +
      " |> SELECT " +
      field
    assert_true(
      compile_query_script(
        @query.parse_query_script(invalid, syntax_limits()).unwrap(),
        initial_from_vector_context(),
        construction_limits(),
      )
      is Err(_),
      msg=invalid,
    )
  }
}

///|
test "initial Relation JOIN stays in the prefix before a typed Carrier call" {
  let text = "WITH r AS (SELECT 9 AS tag) FROM candidates AS c CROSS JOIN r MAX_OUTPUT_ROWS 10 |> to_vectors(id: c.id, vector: c.embedding) |> vectors() |> SELECT id"
  let actual = compile_query_script(
    @query.parse_query_script(text, syntax_limits()).unwrap(),
    initial_from_vector_context(),
    construction_limits(),
  ).unwrap()
  let body = semantic(actual)
  assert_eq(body.split("\"cross_join\":").length(), 2)
  assert_eq(body.split("\"to_vectors\":").length(), 2)
}

///|
test "three initial JOIN forms retain the same logical Values and nullable output" {
  let prefix = "WITH left_input AS (SELECT 1 AS id, 10 AS amount UNION ALL SELECT 1 AS id, CAST(NULL AS FLOAT64) AS amount UNION ALL SELECT 2 AS id, 20 AS amount), right_input AS (SELECT 1 AS id, 'x' AS tag UNION ALL SELECT 1 AS id, 'y' AS tag UNION ALL SELECT 3 AS id, 'z' AS tag) "
  let join = "JOIN right_input AS r ON l.id = r.id MAX_OUTPUT_ROWS 10"
  let forms = [
    "SELECT l.id AS id, l.amount AS amount, r.tag AS tag FROM left_input AS l " +
    join +
    " ORDER BY amount ASC NULLS FIRST, tag",
    "FROM left_input AS l " +
    join +
    " |> SELECT l.id AS id, l.amount AS amount, r.tag AS tag |> ORDER BY amount ASC NULLS FIRST, tag",
    "FROM left_input AS l |> " +
    join +
    " |> SELECT l.id AS id, l.amount AS amount, r.tag AS tag |> ORDER BY amount ASC NULLS FIRST, tag",
  ]
  let programs = forms.map(text => {
    checked_with_join(prefix + text, { ..fixture_context(), inputs: [], })
  })
  for program in programs {
    assert_eq(@program.stage_count(program), 1)
    let body = semantic(program)
    assert_eq(body.split("\"join\":").length(), 2)
    assert_true(body.contains("\"fields\":[\"id\",\"amount\",\"tag\"]"))
    assert_true(body.contains("\"max_output_rows\":10"))
  }
  // Runtime rows are independently fixed as (1,NULL,x), (1,NULL,y),
  // (1,10,x), (1,10,y). This static test does not claim their execution.
}
