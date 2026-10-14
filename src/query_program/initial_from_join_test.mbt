///|
fn initial_from_compiled(
  text : String,
  context : Context,
) -> @program.Program raise {
  with_demand_program(
    compile_query_script(
      @query.parse_query_script(text, syntax_limits()).unwrap(),
      context,
      construction_limits(),
    ),
  )
}

///|
fn initial_from_graph_inputs() -> String {
  "WITH n AS (SELECT 1 AS node_key), r AS (SELECT 9 AS tag), g AS (GRAPH (NODE TABLES (n AS N KEY (node_key) LABEL Node NO PROPERTIES))) "
}

///|
test "initial JOIN rejects Graph before a later explicit row bridge" {
  for marker in ["", "GRAPH "] {
    let source = initial_from_graph_inputs() +
      "FROM " +
      marker +
      "g CROSS JOIN r MAX_OUTPUT_ROWS 10 |> node_rows() |> SELECT node_key"
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
  ignore(
    initial_from_compiled(
      initial_from_graph_inputs() +
      "FROM g |> node_rows() |> AS nodes |> CROSS JOIN r MAX_OUTPUT_ROWS 10 |> SELECT nodes.node_key",
      { ..fixture_context(), inputs: [], },
    ),
  )
}

///|
fn initial_from_vector_context() -> Context {
  let input =
    #|{"values":{"schema":{"id":{"type":"number","nullable":false},"embedding":{"type":"vector","dimensions":2,"nullable":false}},"rows":[{"id":1,"embedding":[1,0]}]},"as":"candidates"}
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
    ignore(initial_from_compiled(control, initial_from_vector_context()))
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
  let actual = initial_from_compiled(text, initial_from_vector_context())
  let body = semantic(actual)
  assert_eq(body.split("\"cross_join\":").length(), 2)
  assert_eq(body.split("\"to_vectors\":").length(), 2)
  assert_true(body.contains("\"fields\":[\"id\"]"))
  let prefix = text
    .strip_suffix(" |> vectors() |> SELECT id")
    .unwrap()
    .to_owned()
  let scored = initial_from_compiled(
    prefix +
    " |> score_vectors(query: [1, 0], metric: 'dot') |> vectors() |> SELECT id, score",
    initial_from_vector_context(),
  )
  assert_true(semantic(scored).contains("\"fields\":[\"id\",\"score\"]"))
  let pooled = prefix +
    " |> pool_vectors(by: [tag], method: 'mean', output_id: 'pool_id') |> vectors()"
  ignore(
    initial_from_compiled(
      pooled + " |> SELECT tag, pool_id, member_count",
      initial_from_vector_context(),
    ),
  )
  ignore(
    initial_from_compiled(
      prefix + " |> vectors() |> DROP id |> SELECT tag",
      initial_from_vector_context(),
    ),
  )
  for
    invalid in [
      prefix + " |> vectors() |> SELECT c.id",
      prefix + " |> vectors() |> SELECT c.*",
      pooled + " |> SELECT id",
      prefix + " |> vectors() |> DROP id |> SELECT id",
    ] {
    let result = compile_query_script(
      @query.parse_query_script(invalid, syntax_limits()).unwrap(),
      initial_from_vector_context(),
      construction_limits(),
    )
    assert_true(
      result is Err(Expression(_)) ||
      result is Err(UnknownColumn) ||
      result is Err(UnsupportedProjection),
      msg=invalid,
    )
  }
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
    let program = initial_from_compiled(prefix + text, {
      ..fixture_context(),
      inputs: [],
    })
    let steps = @wire.elements(
        @wire.required(
          @wire.open_object(@program.stage_body(@program.stages(program)[0])).unwrap(),
          "steps",
        ).unwrap(),
      )
      .unwrap()
      .length()
    println("Initial JOIN control step count: " + steps.to_string())
    // This expanded literal/UNION fixture uses the existing 64-step checking
    // profile. The ordinary 20-step fixture and production limits are unchanged.
    assert_true(steps <= 64)
    match
      @check.check_parsed(
        program,
        check_environment(),
        None,
        graph_rows_check_limits(),
      ) {
      Checked(_) => ()
      Rejected(error) => graph_rows_rejected(error)
      NeedsInputs(_) => fail("initial JOIN controls have no external Source")
    }
    program
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
