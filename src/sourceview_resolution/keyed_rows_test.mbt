///|
fn check_keyed_rows_fixture(
  wire : String,
  cid : String,
  lookup? : Int = 0,
  batch? : Int = 1,
) -> Unit raise {
  let catalog = fixture_catalog(wire, cid)
  for zero in [false, true] {
    let complete = "{\"connector\":\"crm/main\",\"resource\":\"r\",\"request\":{\"id\":1,\"tenant\":null}}"
    let start = if zero {
      "{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[]},\"as\":\"bounded\"}"
    } else {
      "{\"take\":3,\"as\":\"bounded\"}"
    }
    let body = "{\"id\":\"a\",\"inputs\":{\"a\":" +
      complete +
      ",\"b\":{\"connector\":\"crm/main\",\"resource\":\"r\",\"request\":{\"tenant\":null}}},\"from\":\"a\",\"steps\":[" +
      start +
      ",{\"filter\":{\"literal\":true},\"as\":\"left\"},{\"join\":{\"left\":\"left\",\"with\":\"b\",\"on\":\"id\",\"kind\":\"left\",\"select\":{\"id\":\"left.id\"}}}],\"results\":{\"r\":{\"from\":\"bounded\",\"fields\":[\"id\"]}}}"
    let declarations = fixture_inputs(complete, stage_bodies=Some(body))
    let source = @inputs.source(declarations)
    let resolved = resolve(declarations, catalog, caps()).unwrap()
    let prepared = prepare_pipeline_inputs(resolved, 1000000).unwrap()
    let stage = registered_stage(source, [
      pipeline_input_at(prepared, 0, 0).unwrap(),
      pipeline_input_at(prepared, 0, 1).unwrap(),
    ])
    let pipeline = @collection.pipeline(@stages.collection(stage))
    let operations = @stages.collect_operations(source, [pipeline], {
      max_work: 1000000,
      max_slots: 1000,
      max_references: 1000,
      max_pointer_units: 1000000,
      max_direct_text_bytes: 1000000,
    }).unwrap()
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
      request_slots(declarations),
      1000000,
    ).unwrap()
    let parameters = prepare_request_parameters(
      context,
      supplied_values(declarations, "{}"),
      1000000,
    ).unwrap()
    let requests = check_pipeline_requests(uses, parameters, request_caps()).unwrap()
    let joins = check_keyed_joins(requests, 1000000).unwrap()
    let facts = @environment.check_lookup_capacities(
      pipeline_catalog_references(prepared),
      { max_work: 1000000, max_facts: 100, },
    ).unwrap()
    let checked_facts = check_keyed_facts(joins, facts, 1000000).unwrap()
    let bound = @capacity.check(
      pipeline,
      0,
      if zero {
        keyed_rows_proof_0()
      } else {
        keyed_rows_proof_3()
      },
    ).unwrap()
    let target = @capacity.check_target_rows(
      pipeline,
      @pipeline.Step(1),
      bound,
      100,
    ).unwrap()
    assert_eq(
      check_keyed_row_bounds(checked_facts, [], 100).unwrap_err(),
      CountMismatch,
    )
    assert_eq(
      check_keyed_row_bounds(checked_facts, [target, target], 100).unwrap_err(),
      CountMismatch,
    )
    assert_eq(
      check_keyed_row_bounds(checked_facts, [target], -1).unwrap_err(),
      InvalidLimits,
    )
    if zero {
      assert_eq(
        check_keyed_row_bounds(checked_facts, [target], 100).unwrap_err(),
        NonPositiveBound(0),
      )
    } else {
      let arguments = [target]
      let checked = check_keyed_row_bounds(checked_facts, arguments, 3).unwrap()
      arguments.clear()
      assert_eq(keyed_rows_count(checked), 1)
      assert_eq(keyed_rows_work(checked), 3)
      assert_true(physical_equal(keyed_rows_facts(checked), checked_facts))
      assert_true(physical_equal(keyed_rows_at(checked, 0).unwrap(), target))
      assert_true(keyed_rows_at(checked, 1) is None)
      let policy = @environment.check_lookup_execution(
        pipeline_environment(prepared),
        { max_work: 100000, max_bytes: 10000, },
      ).unwrap()
      let result = check_lookup_bounds(checked, policy, 1)
      if lookup == 0 {
        assert_true(result is Err(MissingPolicy(2)))
      } else if lookup == 2 {
        assert_true(result is Err(DecodedResponseLimit(2)))
      } else {
        let resolved = result.unwrap()
        assert_true(physical_equal(lookup_bounds_rows(resolved), checked))
        assert_true(physical_equal(lookup_bounds_policy(resolved), policy))
        assert_eq(lookup_bounds_work(resolved), 1)
        assert_eq(lookup_bounds_count(resolved), 1)
        let counts = lookup_bounds_at(resolved, 0).unwrap()
        assert_eq(counts.input_rows, 3)
        assert_eq(counts.distinct_keys, 3)
        assert_eq(counts.keys_per_batch, batch.to_int64())
        assert_eq(counts.batches, if batch == 1 { 3L } else { 2L })
        assert_eq(counts.pages_per_batch, 3)
        assert_eq(counts.requests, if batch == 1 { 9L } else { 6L })
        assert_eq(counts.network_attempts, if batch == 1 { 27L } else { 18L })
        assert_eq(counts.rows_per_key, 2)
        assert_eq(counts.response_rows, 6)
        assert_eq(
          counts.decoded_response_bytes,
          if batch == 1 {
            36864L
          } else {
            24576L
          },
        )
        assert_true(lookup_bounds_at(resolved, 1) is None)
      }
      assert_true(check_lookup_bounds(checked, policy, 0) is Err(WorkLimit))
      assert_true(
        check_lookup_bounds(checked, policy, -1) is Err(InvalidLimits),
      )
      let foreign = @environment.read(@utf8.encode(wire), cid, {
        max_bytes: 1000000,
        max_nodes: 100000,
        max_depth: 100,
        max_members: 1000,
      }).unwrap()
      let foreign_policy = @environment.check_lookup_execution(foreign, {
        max_work: 100000,
        max_bytes: 10000,
      }).unwrap()
      assert_true(
        check_lookup_bounds(checked, foreign_policy, 1)
        is Err(ForeignEnvironment),
      )
      assert_eq(
        check_keyed_row_bounds(checked_facts, [target], 2).unwrap_err(),
        WorkLimit(0),
      )
      let wrong = @capacity.check_target_rows(
        pipeline,
        @pipeline.Step(0),
        bound,
        10,
      ).unwrap()
      assert_eq(
        check_keyed_row_bounds(checked_facts, [wrong], 100).unwrap_err(),
        WrongTarget(0),
      )
      let other = registered_stage(source, [
        pipeline_input_at(prepared, 0, 0).unwrap(),
        pipeline_input_at(prepared, 0, 1).unwrap(),
      ])
      let other_pipeline = @collection.pipeline(@stages.collection(other))
      let other_bound = @capacity.check(other_pipeline, 0, keyed_rows_proof_3()).unwrap()
      let other_target = @capacity.check_target_rows(
        other_pipeline,
        @pipeline.Step(1),
        other_bound,
        10,
      ).unwrap()
      assert_eq(
        check_keyed_row_bounds(checked_facts, [other_target], 100).unwrap_err(),
        ForeignPipeline(0),
      )
    }
  }
}
