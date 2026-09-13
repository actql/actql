///|
test "Calendar profile survives Stage preparation and imported producer ownership" {
  let bytes = @utf8.encode(
    "{\"conversion_law\":\"actql-calendar-boundaries/0.1\",\"coverage_end_ms\":253402300800000,\"coverage_start_ms\":-62135596800000,\"tzdb_version\":\"test-fixture\",\"version\":\"actql-tzdb-table/0.1\",\"zones\":{\"UTC\":{\"initial_offset_seconds\":0,\"transitions\":[]}}}",
  )
  let profile = @calendar_profile.admit(
    bytes,
    "sha256:9f3724c9d9d160476ee7abf5d8eaa0701bbd5c17f900154496bb8615bf20f4ca",
    "test-fixture",
    {
      max_bytes: 1000,
      max_nodes: 100,
      max_depth: 8,
      max_zones: 1,
      max_transitions: 0,
    },
  ).unwrap()
  let text =
    #|{"version":"actql/0.1","id":"calendar","stages":[{"id":"first","inputs":{},"steps":[{"calendar_series":{"start":"2000-01-01T00:00:00.000Z","end":"2000-01-02T00:00:00.000Z","unit":"day","timezone":"UTC"},"as":"grid"}],"results":{"out":{"from":"grid","fields":["start","end"]}}},{"id":"second","inputs":{"rows":{"result":{"stage":"first","result":"out"}}},"steps":[{"calendar_bucket":{"time":"start","into":"bucket","unit":"month","timezone":"UTC"},"as":"buckets"}],"results":{"out":{"from":"buckets","fields":["start","bucket"]}}}],"results":{"out":{"from":{"stage":"second","result":"out"}}}}
  let source = local_program_parse(text)
  assert_true(
    prepare_local_program(source, local_program_limits()) is Err(Pipeline(0, _)),
  )
  let (wiring, used) = prepare_local_program(
    source,
    local_program_limits(),
    calendar_profile=Some(profile),
  ).unwrap()
  for stage in 0..<2 {
    let owner = wiring_stage_at(wiring, stage).unwrap()
    let pipeline = @collection.pipeline(
      @parameters.collection(stage_port_source(owner)),
    )
    guard @pipeline.step_at(pipeline, 0).unwrap().operation
      is @pipeline.Calendar(operation) else {
      fail("Calendar operation lost")
    }
    assert_true(physical_equal(@calendar.profile(operation), profile))
    if stage == 1 {
      let imported = import_at(
        attached_imports(wiring_imports_at(wiring, stage).unwrap()),
        0,
      ).unwrap()
      assert_true(
        physical_equal(
          input_stage(imported),
          wiring_stage_at(wiring, 0).unwrap(),
        ),
      )
      assert_true(
        physical_equal(
          @pipeline.input_producer(pipeline, 0).unwrap(),
          input_producer(imported),
        ),
      )
    }
  }
  let exact = {
    ..local_program_limits(),
    max_work: used.work,
    max_nodes: used.nodes,
    max_tokens: used.tokens,
    max_text_bytes: used.text_bytes,
    max_steps: used.steps,
    max_results: used.results,
    max_stages: 2,
  }
  assert_true(
    prepare_local_program(source, exact, calendar_profile=Some(profile))
    is Ok(_),
  )
  assert_true(
    prepare_local_program(
      source,
      { ..exact, max_work: exact.max_work - 1, },
      calendar_profile=Some(profile),
    )
    is Err(_),
  )
}
