///|
fn collection_sql_original(sql : String) -> PreparedClientProgram raise {
  let environment = string_try_number_test_environment()
  let base = @source_frontend.bind_query_context(
    [],
    @checked.checking_environment_cid(environment),
  ).unwrap()
  // Explicit fixture input: original literal rows, not an installed Source or
  // a key inferred from observations. The SQL below authors its own assertion.
  let context = {
    ..base,
    inputs: [
      {
        relation: [{ value: "t", quoted: false, }],
        name: "t",
        source: @update_targets.GeneratedValues(
          scalar_profile_cursor(
            "{\"values\":{\"schema\":{\"n\":{\"type\":\"number\",\"nullable\":false},\"s\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"n\":1,\"s\":\"a\"},{\"n\":2,\"s\":\"b\"},{\"n\":3,\"s\":\"a\"}]},\"as\":\"t\"}",
          ),
        ),
        visible_fields: ["n", "s"],
        graph_bindings: [],
      },
    ],
  }
  let lowered = match @source_frontend.lower(sql, Sql, Some(context)) {
    Ok(value) => value
    Err(QuerySyntax({ issue: Syntax(reason), .. })) =>
      fail("SQL collection syntax: " + reason)
    Err(
      QueryLowering(
        BindingPreparation(LocalProgram(Order(_, PipelineOrder(issue))))
      )
    ) => fail("SQL collection order: " + @debug.to_string(issue.kind))
    Err(_) => fail("SQL collection frontend")
  }
  match
    prepare_parsed_effect_free_client_program(
      lowered.program.unwrap(),
      environment,
      None,
      client_standard_program_preparation_limits(),
    ) {
    Ok(value) => value
    Err(Check(diagnostic)) => raise @checked.diagnostic_cause(diagnostic)
    Err(ValuesProfileUnsupported) =>
      fail("SQL collection ValuesProfileUnsupported")
    Err(Lowering(_)) => fail("SQL collection Lowering")
    Err(Graph(issue)) =>
      fail("SQL collection Graph: " + @debug.to_string(issue))
    Err(_) => fail("SQL collection preparation")
  }
}

///|
fn collection_sql_output(
  original : PreparedClientProgram,
) -> @execution.CompletedOutput raise {
  let sequence = @lower.prepare_sequence(
    @strategy.graph_task_owner(original.graph, 0).unwrap(),
    run_materials_limits().sequence,
  ).unwrap()
  let completed = @execution.execute_generated_sequence(
    local_group_generated(sequence),
    [],
    string_try_number_execution_limits(),
  ).unwrap()
  @execution.completed_output(
    completed,
    @pipeline.Step(@lower.sequence_count(sequence) - 1),
  ).unwrap()
}

///|
fn assert_collection_numbers(
  output : @execution.CompletedOutput,
  row : Int,
  column : Int,
  expected : Array[Double],
) -> Unit raise {
  guard @execution.completed_cell(output, row, column)
    is Some(Captured(@values.Array(items))) else {
    fail("expected original aggregate array")
  }
  assert_eq(@values.element_count(items), expected.length())
  for index in 0..<expected.length() {
    assert_true(
      @values.element_at(items, index) is Some(@values.Number(value)) &&
      value == expected[index],
    )
  }
}

///|
test "explicitly keyed ordered ARRAY_AGG produces exact scalar and grouped SQL Results" {
  let scalar = collection_sql_output(
    collection_sql_original(
      "SELECT n, s FROM t |> ASSERT UNIQUE BY (n) |> AGGREGATE ARRAY_AGG(n ORDER BY n DESC) AS x",
    ),
  )
  assert_eq(@execution.completed_row_count(scalar), 1)
  assert_collection_numbers(scalar, 0, 0, [3, 2, 1])
  let grouped = collection_sql_output(
    collection_sql_original(
      "SELECT n, s FROM t |> ASSERT UNIQUE BY (n) |> AGGREGATE ARRAY_AGG(n ORDER BY n) AS x GROUP BY s |> SELECT s, x |> ORDER BY s",
    ),
  )
  assert_eq(@execution.completed_row_count(grouped), 2)
  assert_true(@execution.completed_cell(grouped, 0, 0) is Some(Text("a")))
  assert_collection_numbers(grouped, 0, 1, [1, 3])
  assert_true(@execution.completed_cell(grouped, 1, 0) is Some(Text("b")))
  assert_collection_numbers(grouped, 1, 1, [2])
}
