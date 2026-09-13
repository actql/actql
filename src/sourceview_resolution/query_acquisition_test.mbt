///|
fn check_query_acquisition_fixture(
  wire : String,
  cid : String,
  input : String,
  supported? : Bool = true,
) -> Unit raise {
  let catalog = fixture_catalog(wire, cid)
  for variant in 0..<5 {
    let extra = match variant {
      1 => ",{\"from\":\"remote\",\"filter\":{\"literal\":true}}"
      2 => ",{\"from\":\"filtered\",\"filter\":{\"literal\":true}}"
      4 => ",{\"from\":\"captured\",\"filter\":{\"literal\":true}}"
      _ => ""
    }
    let body = "{\"id\":\"a\",\"inputs\":{\"remote\":" +
      input +
      "},\"steps\":[{\"filter\":{\"literal\":true},\"as\":\"filtered\"}," +
      "{\"select\":[\"id\"],\"as\":\"captured\"}," +
      "{\"filter\":{\"literal\":true},\"as\":\"consumer\"}" +
      extra +
      "],\"results\":{\"r\":{\"from\":\"" +
      (if variant == 3 { "filtered" } else { "consumer" }) +
      "\",\"fields\":[\"id\"]}}}"
    let source_inputs = fixture_inputs(input, stage_bodies=Some(body))
    let source = @inputs.source(source_inputs)
    let resolved = resolve(source_inputs, catalog, caps()).unwrap()
    let prepared = prepare_pipeline_inputs(resolved, 1000000).unwrap()
    let stage = registered_stage(source, [
      pipeline_input_at(prepared, 0, 0).unwrap(),
    ])
    let operations = @stages.collect_operations(
      source,
      [@collection.pipeline(@stages.collection(stage))],
      {
        max_work: 1000000,
        max_slots: 1000,
        max_references: 1000,
        max_pointer_units: 1000000,
        max_direct_text_bytes: 1000000,
      },
    ).unwrap()
    let attachment = attach_pipeline_inputs(
      prepared,
      @stages.operations_stage_at(operations, 0).unwrap(),
      1000000,
    ).unwrap()
    let results = @stage_results.check(operations, {
      max_results: 100,
      max_work: 1000000,
      max_nodes: 100000,
      max_text_bytes: 1000000,
      max_depth: 100,
    }).unwrap()
    let uses = collect_pipeline_uses(attachment, results, 1000000).unwrap()
    let context = prepare_requests(
      resolved,
      request_slots(source_inputs),
      1000000,
    ).unwrap()
    let parameters = prepare_request_parameters(
      context,
      supplied_values(source_inputs, "{}"),
      1000000,
    ).unwrap()
    let requests = check_pipeline_requests(uses, parameters, request_caps()).unwrap()
    let result = derive_query_acquisition(requests, 0, 1000000)
    if !supported || variant == 1 || variant == 2 || variant == 3 {
      assert_true(result is Err(UnsupportedShape))
    } else {
      let v = result.unwrap()
      assert_true(physical_equal(query_acquisition_owner(v), requests))
      assert_eq(query_acquisition_input(v), @pipeline.Input(0))
      assert_eq(query_acquisition_capture(v), @pipeline.Step(1))
      assert_eq(query_acquisition_filter_index(v), 0)
      assert_eq(query_acquisition_source_index(v), 0)
      assert_eq(query_acquisition_requirement_count(v), 8)
      assert_eq(
        query_acquisition_requirement_at(v, 1),
        Some(WholeScanAdmission),
      )
      assert_eq(query_acquisition_requirement_at(v, -1), None)
      assert_eq(query_acquisition_requirement_at(v, 8), None)
      let work = query_acquisition_work(v)
      assert_true(derive_query_acquisition(requests, 0, work) is Ok(_))
      assert_true(
        derive_query_acquisition(requests, 0, work - 1) is Err(WorkLimit),
      )
      assert_true(
        derive_query_acquisition(requests, 0, -1) is Err(InvalidLimits),
      )
      assert_true(
        derive_query_acquisition(requests, -1, work) is Err(UnsupportedShape),
      )
      assert_true(
        derive_query_acquisition(requests, 1, work) is Err(UnsupportedShape),
      )
    }
  }
}
