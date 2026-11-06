///|
fn model_requirements_quote(
  prepared : @publication_host.PreparedClientProgram,
  captured : Bool,
) -> ClientLocalRequirements? {
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  if captured {
    prepare_captured_local_requirements(
      prepared,
      contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
    )
  } else {
    prepare_source_free_local_requirements(
      prepared,
      contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
    )
  }
}

///|
test "ordinary requirements refuse a later-stage captured Model occurrence" {
  let (prepared, _, _, _) = original_prefix_execution_fixture(source=true)
  let occurrences = @publication_host.prepared_client_composed_infer_occurrences(
    prepared,
  ).unwrap()
  assert_eq(occurrences.length(), 1)
  assert_true(
    @publication_host.client_infer_occurrence_coordinates(occurrences[0]).0 > 0,
  )
  assert_eq(@publication_host.prepared_client_acquisition_count(prepared), 1)
  assert_true(model_requirements_quote(prepared, true) is None)
}

///|
test "ordinary requirements refuse a task-zero Model after several steps" {
  let (prepared, _, _, _) = original_prefix_execution_fixture()
  let occurrences = @publication_host.prepared_client_composed_infer_occurrences(
    prepared,
  ).unwrap()
  assert_eq(occurrences.length(), 1)
  let (task, _, step) = @publication_host.client_infer_occurrence_coordinates(
    occurrences[0],
  )
  assert_eq(task, 0)
  assert_true(
    step >
    @strategy.graph_task_count(
      @publication_host.prepared_client_graph(prepared),
    ),
  )
  assert_eq(@publication_host.prepared_client_acquisition_count(prepared), 0)
  assert_true(model_requirements_quote(prepared, false) is None)
}

///|
test "ordinary requirements preserve source-free and captured graphs with no Model" {
  assert_true(
    model_requirements_quote(single_installed_prepared(), true) is Some(_),
  )
  assert_true(
    model_requirements_quote(source_free_requirements_prepared(), false)
    is Some(_),
  )
}
