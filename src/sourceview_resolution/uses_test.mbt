///|
fn check_pipeline_uses_fixture(
  wire : String,
  cid : String,
  input : String,
) -> Unit raise {
  let catalog = fixture_catalog(wire, cid)
  for empty in [false, true] {
    let steps = if empty {
      "[]"
    } else {
      "[{\"join\":{\"left\":\"a\",\"with\":\"b\",\"kind\":\"left\",\"on\":\"id\",\"select\":{\"id\":\"left.id\"}}}," +
      "{\"filter\":{\"literal\":true},\"from\":\"a\"}," +
      "{\"join\":{\"left\":\"a\",\"with\":\"a\",\"kind\":\"inner\",\"on\":\"id\",\"select\":{\"id\":\"left.id\"}}}," +
      "{\"filter\":{\"literal\":true}}]"
    }
    let body = "{\"id\":\"a\",\"inputs\":{\"a\":" +
      input +
      ",\"b\":" +
      input +
      ",\"c\":" +
      input +
      "},\"from\":\"a\",\"steps\":" +
      steps +
      ",\"results\":{\"r\":{\"from\":\"" +
      (if empty { "b" } else { "a" }) +
      "\",\"fields\":[\"id\"]}}}"
    let source_inputs = fixture_inputs(input, stage_bodies=Some(body))
    let source = @inputs.source(source_inputs)
    let resolved = resolve(source_inputs, catalog, caps()).unwrap()
    let prepared = prepare_pipeline_inputs(resolved, 10000000).unwrap()
    let registrations = [
      pipeline_input_at(prepared, 0, 2).unwrap(),
      pipeline_input_at(prepared, 0, 0).unwrap(),
      pipeline_input_at(prepared, 0, 1).unwrap(),
    ]
    let stage = registered_stage(source, registrations)
    let pipelines = [@collection.pipeline(@stages.collection(stage))]
    let operations = @stages.collect_operations(source, pipelines, {
      max_work: 1000000,
      max_slots: 1000,
      max_references: 1000,
      max_pointer_units: 1000000,
      max_direct_text_bytes: 1000000,
    }).unwrap()
    let attachment = attach_pipeline_inputs(
      prepared,
      @stages.operations_stage_at(operations, 0).unwrap(),
      10000000,
    ).unwrap()
    let results = @stage_results.check(operations, {
      max_results: 100,
      max_work: 1000000,
      max_nodes: 100000,
      max_text_bytes: 1000000,
      max_depth: 100,
    }).unwrap()
    let v = collect_pipeline_uses(attachment, results, 1000000).unwrap()
    let expected : Array[Array[SourceUse]] = if empty {
      [[], [ResultInput(0)], []]
    } else {
      [
        [
          StepInput(0, @pipeline.Left),
          StepInput(1, @pipeline.Primary),
          StepInput(2, @pipeline.Left),
          JoinRight(2),
          ResultInput(0),
        ],
        [JoinRight(0)],
        [],
      ]
    }
    for i in 0..<3 {
      assert_eq(pipeline_use_count(v, i), Some(expected[i].length()))
      for j in 0..<expected[i].length() {
        assert_eq(pipeline_use_at(v, i, j), Some(expected[i][j]))
      }
      assert_true(pipeline_use_at(v, i, expected[i].length()) is None)
    }
    assert_true(pipeline_use_count(v, -1) is None)
    assert_true(pipeline_use_at(v, 3, 0) is None)
    assert_true(physical_equal(pipeline_uses_attachment(v), attachment))
    assert_true(physical_equal(pipeline_uses_results(v), results))
    assert_true(
      collect_pipeline_uses(attachment, results, pipeline_uses_work(v)) is Ok(_),
    )
    assert_true(
      collect_pipeline_uses(attachment, results, pipeline_uses_work(v) - 1)
      is Err(WorkLimit),
    )
    assert_true(
      collect_pipeline_uses(attachment, results, -1) is Err(InvalidLimits),
    )
    let foreign = attach_pipeline_inputs(prepared, stage, 10000000).unwrap()
    assert_true(
      collect_pipeline_uses(foreign, results, 1000000) is Err(ForeignResults),
    )
    registrations.clear()
    pipelines.clear()
    assert_eq(pipeline_use_count(v, 1), Some(1))
  }
}
