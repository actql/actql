///|
// Shared authored Program bytes, not a second lowering or generated oracle.
extern "js" fn native_file_task_boundary_document() -> String =
  #|() => process.getBuiltinModule('node:fs').readFileSync(process.cwd() + '/scripts/fixtures/native-file-task-boundary.json', 'utf8')

///|
// Real checked task coordinates for the exact normal CLI Program. The common
// declaration uses the template's three fields; this is not Native File I/O,
// the complete installed catalogue/keys, a Run, or physical cleanup evidence.
test "normal File boundary fixture retains thirty three checked tasks in thirty Units" {
  let declaration_result = @row_source_host.generate_row_declaration(
    "snowflake",
    "fixture",
    "fixture/0.1",
    [
      {
        resource: "usage_30d",
        resource_kind: "table",
        fields: [
          { name: "account_id", value_type: "string", nullable: false, },
          { name: "active_users", value_type: "number", nullable: false, },
          { name: "trend", value_type: "string", nullable: false, },
        ],
      },
    ],
    {
      max_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 100,
      max_views: 1,
      max_fields: 3,
    },
  )
  let declaration = match declaration_result {
    Ok(value) => value
    Err(issue) => fail(@debug.to_string(issue))
  }
  let preparation = @publication_host.prepare_effect_free_client_program(
    native_file_task_boundary_document(),
    Json,
    pure_provider_environment(declaration),
    None,
    @publication_host.client_standard_program_preparation_limits(),
  )
  let prepared = match preparation {
    Ok(value) => value
    Err(Syntax(issue)) => fail("Syntax " + @debug.to_string(issue))
    Err(Check(issue)) =>
      fail("Check " + @debug.to_string(@checked.diagnostic_category(issue)))
    Err(Graph(issue)) => fail("Graph " + @debug.to_string(issue))
    Err(_) => fail("Other preparation refusal")
  }
  let graph = @publication_host.prepared_client_graph(prepared)
  assert_eq(@publication_host.prepared_client_acquisition_count(prepared), 1)
  assert_eq(@strategy.graph_captured_prefix(graph), 1)
  assert_eq(@strategy.graph_task_count(graph), 33)
  assert_eq(@strategy.graph_result_count(graph), 1)
  assert_eq(@strategy.graph_result_task(graph, 0), Some(32))
  assert_false(@strategy.graph_program_has_effects(graph))
  assert_true(
    @publication_host.prepared_client_composed_infer_occurrences(prepared)
    .unwrap()
    .is_empty(),
  )
  assert_true(
    @publication_host.prepared_client_serialization_occurrences(prepared).is_empty(),
  )
  let coordinates = []
  for task in 0..<33 {
    let unit = if task == 0 { 0 } else if task < 5 { 1 } else { task - 3 }
    assert_eq(@strategy.graph_task_original_index(graph, task), Some(task))
    assert_eq(@strategy.graph_task_unit_index(graph, task), Some(unit))
    assert_true(@strategy.graph_task_owner(graph, task) is Some(_))
    coordinates.push(
      (
        task,
        unit,
        @strategy.graph_task_selected_step(graph, task),
        @strategy.graph_task_prefix_end(graph, task),
      ),
    )
  }
  // Retain actual original task/Unit/selected-step/fused-prefix coordinates in
  // component output; do not infer task count from source spelling or rows.
  println("Native File checked coordinates: " + @debug.to_string(coordinates))
}
