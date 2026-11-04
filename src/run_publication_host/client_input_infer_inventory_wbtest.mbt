///|
test "input-only INFER inventory retains the original pure Input carrier" {
  for
    document in [
      input_result_document,
      input_result_document.replace(old="[{\"A\":0}]", new="[]"),
    ] {
    let prepared = input_result_prepared(document)
    let graph = prepared_client_graph(prepared)
    assert_eq(@strategy.graph_task_target(graph, 1), Some(@pipeline.Input(0)))
    assert_eq(client_task_output_target(graph, 1), Some(@pipeline.Input(0)))
    assert_eq(
      prepared_client_composed_infer_occurrences(prepared).unwrap().length(),
      0,
    )
    assert_true(prepared_client_composed_infer_occurrence(prepared) is None)
  }
}

///|
test "input-only INFER inventory keeps Model occurrences between real Input carriers" {
  let document =
    #|{"version":"actql/0.1","id":"input-only-infer-inventory","stages":[{"id":"producer","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"string","nullable":false},"text":{"type":"string","nullable":true}},"rows":[{"id":"a","text":"hello"}]},"as":"items"}],"results":{"rows":{"from":"items","fields":["id","text"]}}},{"id":"identity","inputs":{"rows":{"result":{"stage":"producer","result":"rows"}}},"steps":[],"results":{"rows":{"from":"rows","fields":["id","text"]}}},{"id":"model","inputs":{"rows":{"result":{"stage":"identity","result":"rows"}}},"steps":[{"assert_rows":{"unique_by":["id"]}},{"infer":{"contract":"model-task:risk-score.v1","key":"id","input":{"text":{"field":"text"}}},"as":"assessment"}],"results":{"rows":{"from":"assessment","fields":["id","outcome","value"]}}},{"id":"sink","inputs":{"rows":{"result":{"stage":"model","result":"rows"}}},"steps":[],"results":{"rows":{"from":"rows","fields":["id","outcome","value"]}}}],"results":{"answer":{"from":{"stage":"sink","result":"rows"}}}}
  let prepared = client_composed_infer_test_program(authored=Some(document))
  let graph = prepared_client_graph(prepared)
  assert_eq(client_task_output_target(graph, 1), Some(@pipeline.Input(0)))
  assert_eq(client_task_output_target(graph, 3), Some(@pipeline.Input(0)))
  let occurrences = prepared_client_composed_infer_occurrences(prepared).unwrap()
  assert_eq(occurrences.length(), 1)
  assert_eq(client_infer_occurrence_coordinates(occurrences[0]), (2, 2, 1))
  assert_true(client_infer_occurrence_matches(occurrences[0], prepared))
  assert_true(physical_equal(occurrences[0].owner, prepared))
  let multiple = client_two_independent_infer_test_program()
  assert_eq(
    prepared_client_composed_infer_occurrences(multiple).unwrap().length(),
    2,
  )
  assert_true(prepared_client_composed_infer_occurrence(multiple) is None)
}
