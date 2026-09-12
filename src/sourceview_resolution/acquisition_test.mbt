///|
fn check_acquisition_fixture(
  wire : String,
  cid : String,
  arity : Int,
) -> Unit raise {
  let catalog = fixture_catalog(wire, cid)
  for variant in 0..<8 {
    let base = "\"connector\":\"crm/main\",\"resource\":\"r\""
    let keys = "\"id\":1," + (if arity == 2 { "\"other\":2," } else { "" })
    let complete = "{" + base + ",\"request\":{" + keys + "\"tenant\":null}}"
    let right = match variant {
      1 => complete
      5 =>
        "{" +
        base +
        ",\"scan\":{\"mode\":\"snapshot\"},\"request\":{\"tenant\":null}}"
      6 => "{" + base + "}"
      7 => "{" + base + ",\"request\":{\"id\":1,\"tenant\":null}}"
      _ => "{" + base + ",\"request\":{\"tenant\":null}}"
    }
    let steps = if variant == 2 || variant == 3 {
      "[]"
    } else {
      "[{\"join\":{\"left\":\"a\",\"with\":\"b\",\"on\":\"id\",\"kind\":\"left\",\"select\":{\"id\":\"left.id\"}}}" +
      (if variant == 4 {
        ",{\"from\":\"b\",\"filter\":{\"literal\":true}}"
      } else {
        ""
      }) +
      "]"
    }
    let body = "{\"id\":\"a\",\"inputs\":{\"a\":" +
      complete +
      ",\"b\":" +
      right +
      ",\"c\":" +
      complete +
      "},\"from\":\"a\",\"steps\":" +
      steps +
      ",\"results\":{\"r\":{\"from\":\"" +
      (if variant == 2 { "b" } else { "a" }) +
      "\",\"fields\":[\"id\"]}}}"
    let source_inputs = fixture_inputs(complete, stage_bodies=Some(body))
    let source = @inputs.source(source_inputs)
    let resolved = resolve(source_inputs, catalog, caps()).unwrap()
    let prepared = prepare_pipeline_inputs(resolved, 10000000).unwrap()
    let stage = registered_stage(source, [
      pipeline_input_at(prepared, 0, 2).unwrap(),
      pipeline_input_at(prepared, 0, 1).unwrap(),
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
      10000000,
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
    let outcome = check_pipeline_requests(uses, parameters, request_caps())
    match variant {
      2 | 4 => assert_true(outcome is Err(InvalidKeyedConsumer(1, _)))
      3 => assert_true(outcome is Err(MissingKeyedConsumer(1)))
      5 =>
        assert_true(outcome is Err(Mode(1, e)) && e.kind == AuthoredKeyedScan)
      6 =>
        assert_true(
          outcome is Err(Request(1, e)) && e.kind == MissingField("tenant"),
        )
      7 if arity == 2 => assert_true(outcome is Err(PartialCorrelation(1)))
      _ => {
        let v = outcome.unwrap()
        assert_true(physical_equal(pipeline_requests_uses(v), uses))
        assert_true(physical_equal(pipeline_requests_parameters(v), parameters))
        assert_eq(pipeline_requests_count(v), 3)
        assert_true(pipeline_request_at(v, 0) is Some(Direct(_, _)))
        assert_true(pipeline_request_at(v, 2) is Some(Direct(_, _)))
        if variant == 0 {
          assert_true(pipeline_request_at(v, 1) is Some(Keyed(_, _)))
        } else {
          assert_true(pipeline_request_at(v, 1) is Some(Direct(_, _)))
        }
        assert_true(pipeline_request_at(v, -1) is None)
        assert_true(pipeline_request_at(v, 3) is None)
        let (work, pairs, nodes, text) = pipeline_requests_usage(v)
        let exact : RequestLimits = {
          max_work: work,
          max_pairs: pairs,
          values: {
            ..request_caps().values,
            max_nodes: nodes,
            max_text_bytes: text,
          },
        }
        assert_true(check_pipeline_requests(uses, parameters, exact) is Ok(_))
        assert_true(
          check_pipeline_requests(uses, parameters, {
            ..exact,
            max_work: work - 1,
          })
          is Err(_),
        )
        assert_true(
          check_pipeline_requests(uses, parameters, {
            ..exact,
            values: { ..exact.values, max_nodes: nodes - 1, },
          })
          is Err(_),
        )
      }
    }
    assert_true(
      check_pipeline_requests(uses, parameters, {
        ..request_caps(),
        max_work: -1,
      })
      is Err(InvalidLimits),
    )
    let other = resolve(source_inputs, catalog, caps()).unwrap()
    let other_context = prepare_requests(
      other,
      request_slots(source_inputs),
      1000000,
    ).unwrap()
    let other_parameters = prepare_request_parameters(
      other_context,
      supplied_values(source_inputs, "{}"),
      1000000,
    ).unwrap()
    assert_true(
      check_pipeline_requests(uses, other_parameters, request_caps())
      is Err(ForeignRequests),
    )
  }
}
