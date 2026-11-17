///|
test "explanation Values and input-only facts bind the exact original compilation" {
  let prepared = input_result_prepared(input_result_document)
  let compiled = issue_prepared_client_task_compilation(
    prepared,
    run_materials_manifests(),
    run_materials_limits().sequence,
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  let values = client_task_operation_explanation(prepared, compiled, 0, 0).unwrap()
  let occurrence = client_operation_explanation_occurrence(values, prepared).unwrap()
  assert_eq(occurrence.stage_ordinal, 0)
  assert_eq(occurrence.occurrence_ordinal, 0)
  assert_false(occurrence.input_only)
  assert_eq(
    occurrence.compiled_plan_cid,
    @publication.publication_contract_identity(
      client_task_compilation_compiled_plan(compiled),
    ),
  )
  assert_eq(
    occurrence.program_definition_cid,
    prepared_client_identity(prepared).program_definition_cid,
  )
  assert_eq(
    occurrence.parameter_values_cid,
    prepared_client_identity(prepared).parameter_values_cid,
  )
  guard client_operation_explanation_meaning(values, prepared).unwrap()
    is Values(row_count~, schema~) else {
    fail("missing checked VALUES facts")
  }
  assert_eq(row_count, 1)
  assert_eq(@schema.field_reference_name_at(schema, 0), Some("A"))
  let input = client_task_operation_explanation(prepared, compiled, 1, 0).unwrap()
  assert_true(
    client_operation_explanation_occurrence(input, prepared).unwrap().input_only,
  )
  assert_true(
    client_operation_explanation_meaning(input, prepared).unwrap()
    is InputOutput,
  )
}

///|
test "explanation filter and projection borrow the original typed predicate and field order" {
  let document =
    #|{"version":"actql/0.1","id":"explanation-filter-project","stages":[{"id":"main","inputs":{},"steps":[{"as":"original","values":{"schema":{"id":{"type":"number","nullable":false},"label":{"type":"string","nullable":false}},"rows":[{"id":1,"label":"first"},{"id":2,"label":"é"}]}},{"from":"original","filter":"id > 1","as":"filtered"},{"from":"filtered","select":["label","id"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["label","id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let prepared = input_result_prepared(document)
  let compiled = issue_prepared_client_values_compilation(
    prepared,
    run_materials_manifests(),
    run_materials_limits().sequence,
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  let checked = @strategy.graph_program(prepared_client_graph(prepared))
  let pipeline = @checked.unit_pipeline(checked, 0).unwrap()
  guard @pipeline.step_at(pipeline, 1).unwrap().operation
    is @pipeline.Unary(original_filter) else {
    fail("expected original checked filter")
  }
  let filter = client_values_operation_explanation(prepared, compiled, 0, 1).unwrap()
  guard client_operation_explanation_meaning(filter, prepared).unwrap()
    is Filter(predicate) else {
    fail("missing typed predicate")
  }
  assert_true(
    physical_equal(
      predicate,
      @relation.binding_expression_at(original_filter, 0).unwrap(),
    ),
  )
  assert_true(@expression.result_type(predicate).shape is @contract.Boolean)
  let projection = client_values_operation_explanation(prepared, compiled, 0, 2).unwrap()
  guard client_operation_explanation_meaning(projection, prepared).unwrap()
    is Projection(fields) else {
    fail("missing checked projection")
  }
  assert_eq(@relation.operation(fields), @relation.Select)
  assert_eq(@relation.projection_field_count(fields), 2)
  assert_eq(
    @schema.reference_name(
      @relation.projection_field_at(fields, 0).unwrap().output,
    ),
    "label",
  )
  assert_eq(
    @schema.reference_name(
      @relation.projection_field_at(fields, 1).unwrap().output,
    ),
    "id",
  )
}

///|
test "explanation JOIN reads the checked kind and original left and right keys" {
  let document =
    #|{"version":"actql/0.1","id":"explanation-join","stages":[{"id":"main","inputs":{},"steps":[{"as":"original","values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1},{"id":2}]}},{"from":"original","join":{"with":"original","kind":"inner","on":[{"left":"id","right":"id"}],"max_output_rows":4,"select":{"id":"left.id"}},"as":"joined"}],"results":{"rows":{"from":"joined","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let prepared = input_result_prepared(document)
  let compiled = issue_prepared_client_task_compilation(
    prepared,
    run_materials_manifests(),
    run_materials_limits().sequence,
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  let explanation = client_task_operation_explanation(prepared, compiled, 0, 1).unwrap()
  guard client_operation_explanation_meaning(explanation, prepared).unwrap()
    is Join(join) else {
    fail("missing checked JOIN facts")
  }
  assert_eq(@join.kind(join), @join.Inner)
  assert_eq(@join.key_count(join), 1)
  let key = @join.key_at(join, 0).unwrap()
  assert_eq(@schema.reference_name(key.left), "id")
  assert_eq(@schema.reference_name(key.right), "id")
}

///|
test "explanation refuses an equal but foreign preparation and missing occurrences" {
  let prepared = input_result_prepared(input_result_document)
  let foreign = input_result_prepared(input_result_document)
  let compiled = issue_prepared_client_task_compilation(
    prepared,
    run_materials_manifests(),
    run_materials_limits().sequence,
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  assert_true(
    client_task_operation_explanation(foreign, compiled, 0, 0)
    is Err(ForeignCompilation),
  )
  let original = client_task_operation_explanation(prepared, compiled, 0, 0).unwrap()
  assert_true(
    client_operation_explanation_meaning(original, foreign)
    is Err(ForeignCompilation),
  )
  assert_true(
    client_operation_explanation_occurrence(original, foreign)
    is Err(ForeignCompilation),
  )
  for coordinate in [(-1, 0), (2, 0), (0, -1), (0, 1), (1, 1)] {
    assert_true(
      client_task_operation_explanation(
        prepared,
        compiled,
        coordinate.0,
        coordinate.1,
      )
      is Err(MissingCheckedOccurrence),
    )
  }
}

///|
test "explanation absence does not refuse a supported checked operation" {
  let prepared = task_pipeline_geometry_original()
  let compiled = issue_prepared_client_task_compilation(
    prepared,
    run_materials_manifests(),
    prepared_client_values_sequence_limits(prepared),
    1000,
    1000,
    1000000,
    100000,
    100,
  ).unwrap()
  let explanation = client_task_operation_explanation(prepared, compiled, 0, 1).unwrap()
  assert_true(
    client_operation_explanation_meaning(explanation, prepared).unwrap()
    is NotProjected,
  )
  assert_eq(
    client_operation_explanation_occurrence(explanation, prepared).unwrap().occurrence_ordinal,
    1,
  )
}
