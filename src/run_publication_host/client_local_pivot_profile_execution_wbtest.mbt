///|
test "original Local PIVOT retains its numeric values and Result schema" {
  let assets = client_local_product_assets()
  let environment_body = @decode.open_object(
    scalar_profile_cursor(assets.environment),
  ).unwrap()
  let cid = @decode.text(
    @decode.required(environment_body, "evidence_bundle_cid").unwrap(),
  ).unwrap()
  let environment = admit_local_relation_check_environment(
    assets.environment,
    cid,
  ).unwrap()
  let source =
    #|WITH r AS (
    #|  SELECT 'east' AS side, 1 AS v UNION ALL
    #|  SELECT 'west', 2 UNION ALL SELECT 'west', 3
    #|)
    #|FROM r |> PIVOT(SUM(v) FOR side IN ('east','west'))
  let context = @source_frontend.bind_query_context(
    [],
    @checked.checking_environment_cid(environment),
  ).unwrap()
  let lowered = @source_frontend.lower(source, Text, Some(context)).unwrap()
  let original = match
    prepare_parsed_effect_free_client_program(
      lowered.program.unwrap(),
      environment,
      None,
      client_standard_program_preparation_limits(),
    ) {
    Ok(original) => original
    Err(Check(issue)) => raise @checked.diagnostic_cause(issue)
    Err(_) => fail("original Local PIVOT preparation")
  }
  assert_eq(prepared_client_result_count(original), 1)
  let schema = issue_prepared_client_result_schema(original, 0, {
    max_fields: 2,
    max_bytes: 1000,
    max_nodes: 32,
    max_depth: 8,
  }).unwrap()
  assert_eq(
    @execution.relation_schema_wire(schema),
    (
      #|{"east":{"nullable":true,"type":"number"},"west":{"nullable":true,"type":"number"}}
    ),
  )
  guard @strategy.graph_result_occurrence(original.graph, 0) is Some(occurrence) &&
    @strategy.graph_result_task(original.graph, 0) is Some(task) else {
    fail("original Local PIVOT Result occurrence")
  }
  guard prepared_client_values_task_sequence_limits(original, task)
    is Some(sequence_limits) &&
    prepare_prepared_client_full_sequence(original, task, sequence_limits)
    is Ok(sequence) else {
    fail("original Local PIVOT sequence preparation")
  }
  let generated = local_group_generated(sequence)
  // The physical graph assigns PIVOT to its own operation task and exports
  // the subsequent projection. Both retain the same bound pipeline.
  let numeric_tasks : Array[Int] = []
  for candidate in 0..<@strategy.graph_task_count(original.graph) {
    if @strategy.graph_task_numeric_observation_count(original.graph, candidate).unwrap_or(
        0,
      ) >
      0 {
      numeric_tasks.push(candidate)
    }
  }
  assert_eq(numeric_tasks.length(), 1)
  let pivot_task = numeric_tasks[0]
  guard @strategy.graph_task_owner(original.graph, pivot_task)
    is Some(pivot_owner) &&
    physical_equal(@lower.sequence_owner(sequence), pivot_owner) else {
    fail("original Local PIVOT numeric task owner")
  }
  assert_eq(
    @strategy.graph_task_numeric_observation_count(original.graph, pivot_task),
    Some(2),
  )
  guard @strategy.graph_task_numeric_observation_at(
      original.graph,
      pivot_task,
      0,
    )
    is Some(left) &&
    @strategy.graph_task_numeric_observation_at(original.graph, pivot_task, 1)
    is Some(right) else {
    fail("original Local PIVOT observation slots")
  }
  let step = @strategy.task_numeric_observation_step(left)
  let profile = @strategy.task_numeric_observation_profile(left)
  for observation in [left, right] {
    assert_true(@strategy.task_numeric_observation_family(observation) is Pivot)
    assert_true(
      @strategy.task_numeric_observation_operation(observation) is Sum,
    )
    assert_eq(@strategy.task_numeric_observation_step(observation), step)
    assert_eq(
      @numeric.cid(@strategy.task_numeric_observation_profile(observation)),
      @numeric.cid(profile),
    )
  }
  assert_eq(
    [
      @strategy.task_numeric_observation_name(left),
      @strategy.task_numeric_observation_name(right),
    ],
    ["east", "west"],
  )
  guard @numeric.member_cid_at(profile, 0) is Some(member_cid) &&
    @numeric.select(profile, member_cid) is Ok(reduction) else {
    fail("original Local PIVOT numeric reduction")
  }
  let contributors : Array[(Int, String, Int, Array[Double], Int)] = []
  let seals : Array[(Int, String, Int)] = []
  // Exercise the checked evaluator with the real selected reduction and a
  // finite test observation port. Installed attempt persistence belongs to
  // the consuming wheel test.
  let numeric = @execution.numeric_aggregate_execution_with_seal(
    (actual_step, name, row, values, count, work) => {
      contributors.push((actual_step, name, row, values.copy(), count))
      Some(@numeric.execute(reduction, Sum, values, count, work))
    },
    (actual_step, name, count) => {
      seals.push((actual_step, name, count))
      true
    },
  )
  let completed = match
    @execution.execute_generated_sequence(
      @execution.bind_generated_numeric_execution(generated, numeric),
      [],
      string_try_number_execution_limits(),
    ) {
    Ok(value) => value
    Err(Rows(at, InvalidRows)) =>
      fail("original Local PIVOT rejected rows at step " + at.to_string())
    Err(Rows(at, _)) =>
      fail("original Local PIVOT row execution at step " + at.to_string())
    Err(_) => fail("original Local PIVOT sequence execution")
  }
  assert_eq(contributors, [
    (step, "east", 0, [1.0], 1),
    (step, "west", 0, [2.0, 3.0], 2),
  ])
  assert_eq(seals, [(step, "east", 1), (step, "west", 1)])
  guard @execution.completed_output(
      completed,
      @results.port_target(
        @execution.managed_result_occurrence_port(occurrence),
      ),
    )
    is Some(output) else {
    fail("original Local PIVOT completed Result")
  }
  assert_eq(@execution.completed_row_count(output), 1)
  assert_eq(@execution.completed_column_count(output), 2)
  assert_eq(@execution.completed_column_name(output, 0), Some("east"))
  assert_eq(@execution.completed_column_name(output, 1), Some("west"))
  assert_true(
    @execution.completed_cell(output, 0, 0) is Some(Number(value)) &&
    value == 1.0,
  )
  assert_true(
    @execution.completed_cell(output, 0, 1) is Some(Number(value)) &&
    value == 5.0,
  )
}
