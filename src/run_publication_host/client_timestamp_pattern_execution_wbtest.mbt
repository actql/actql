///|
fn timestamp_sql_original(
  sql : String,
  declarations? : String = "{}",
  supplied? : String? = None,
) -> PreparedClientProgram {
  let environment = string_try_number_test_environment(max_pattern_bytes=100)
  let has_parameters = declarations != "{}"
  let declarations = @parameter.read_declarations(
    if declarations == "{}" {
      None
    } else {
      Some(scalar_profile_cursor(declarations))
    },
    {
      max_parameters: 100,
      max_nodes: 1000,
      max_depth: 32,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let context = @source_frontend.bind_query_context(
    [],
    @checked.checking_environment_cid(environment),
    parameter_declarations=if has_parameters {
      Some(declarations)
    } else {
      None
    },
  ).unwrap()
  let lowered = @source_frontend.lower(sql, Sql, Some(context)).unwrap()
  prepare_parsed_effect_free_client_program(
    lowered.program.unwrap(),
    environment,
    supplied.map(scalar_profile_cursor),
    client_standard_program_preparation_limits(),
  ).unwrap()
}

///|
fn timestamp_sql_output(
  original : PreparedClientProgram,
) -> @execution.CompletedOutput {
  let sequence = @lower.prepare_sequence(
    @strategy.graph_task_owner(original.graph, 0).unwrap(),
    run_materials_limits().sequence,
  ).unwrap()
  let completed = @execution.execute_generated_sequence(
    local_explicit_cast_generated(sequence),
    [],
    string_try_number_execution_limits(),
  ).unwrap()
  @execution.completed_output(
    completed,
    @pipeline.Step(@lower.sequence_count(sequence) - 1),
  ).unwrap()
}

///|
test "SQL format-first timestamp functions consume actual checked pattern fragments and return independent results" {
  let parsed = timestamp_sql_original(
    "SELECT PARSE_TIMESTAMP('yyyy-MM-dd', '2026-01-02') AS value",
  )
  let output = timestamp_sql_output(parsed)
  assert_eq(@execution.completed_row_count(output), 1)
  assert_true(
    @execution.completed_cell(output, 0, 0)
    is Some(Captured(@values.Timestamp("2026-01-02T00:00:00.000Z"))),
  )
  let formatted = timestamp_sql_original(
    "SELECT FORMAT_TIMESTAMP('yyyy', CAST('2026-01-02T03:04:05.123456789Z' AS TIMESTAMP)) AS value",
  )
  assert_true(
    @execution.completed_cell(timestamp_sql_output(formatted), 0, 0)
    is Some(Text("2026")),
  )
}

///|
test "SQL timestamp pattern Parameter remains bound to its original checked preparation" {
  let declarations = "{\"pattern\":{\"type\":\"string\",\"default\":\"yyyy-MM-dd\"},\"value\":{\"type\":\"string\",\"default\":\"2026-01-02\"}}"
  let original = timestamp_sql_original(
    "SELECT PARSE_TIMESTAMP(@pattern, @value) AS value",
    declarations~,
    supplied=Some("{\"pattern\":\"dd/MM/yyyy\",\"value\":\"03/02/2024\"}"),
  )
  assert_true(
    @execution.completed_cell(timestamp_sql_output(original), 0, 0)
    is Some(Captured(@values.Timestamp("2024-02-03T00:00:00.000Z"))),
  )
  let defaulted = timestamp_sql_original(
    "SELECT PARSE_TIMESTAMP(@pattern, @value) AS value",
    declarations~,
  )
  assert_true(
    @execution.completed_cell(timestamp_sql_output(defaulted), 0, 0)
    is Some(Captured(@values.Timestamp("2026-01-02T00:00:00.000Z"))),
  )
  let closure = @checked.expression_closure(
    @strategy.graph_program(original.graph),
  ).unwrap()
  let owner = @lower.sequence_owner(
    @lower.prepare_sequence(
      @strategy.graph_task_owner(defaulted.graph, 0).unwrap(),
      run_materials_limits().sequence,
    ).unwrap(),
  )
  assert_true(
    @lower.bind_program_expression_closure(owner, closure, 0, 100000)
    is Err({ kind: BindingOwnerMismatch, .. }),
  )
}
