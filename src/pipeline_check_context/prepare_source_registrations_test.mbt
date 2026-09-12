///|
test "source registration preparation owns its Source Catalog and mixed input budget" {
  let remote = []
  let (_, wiring, _, _, _, _) = wired_inputs_fixture(
    true,
    remote=Some(remote),
    repeat_remote=true,
  )
  let source = @stage_results.wiring_source(wiring)
  let catalog = @sourceviews.catalog(
    @sourceviews.pipeline_resolution(remote[0]),
  )
  let caps : @local_inputs.Limits = {
    max_work: 1000000,
    max_nodes: 100000,
    max_text_bytes: 1000000,
    max_depth: 100,
  }
  let (views, locals) = prepare_source_registrations(
    source,
    catalog,
    caps,
    max_inputs=2,
    max_views=100,
    max_order_keys=100,
  ).unwrap()
  assert_true(
    physical_equal(
      @sourceviews.catalog(@sourceviews.pipeline_resolution(views)),
      catalog,
    ),
  )
  assert_true(physical_equal(@local_inputs.environment_program(locals), source))
  assert_true(
    physical_equal(
      @sourceviews.pipeline_environment(views),
      @local_inputs.program_environment(locals),
    ),
  )
  assert_eq(@sourceviews.pipeline_input_count(views, 0), Some(2))
  assert_eq(@sourceviews.pipeline_input_count(views, 1), Some(0))
  for stage in 0..<2 {
    let admitted = @local_inputs.program_environment_stage(locals, stage).unwrap()
    let partition = @local_inputs.sourceview_inputs(
      @local_inputs.snapshot_inputs(
        @local_inputs.environment_assertions(admitted),
      ),
    ).unwrap()
    assert_true(
      physical_equal(
        partition,
        @sourceviews.inputs(@sourceviews.pipeline_resolution(views)),
      ),
    )
  }
  let usage = @local_inputs.program_environment_usage(locals)
  let exact : @local_inputs.Limits = {
    max_work: usage.work + @sourceviews.pipeline_inputs_work(views),
    max_nodes: usage.nodes,
    max_text_bytes: usage.text_bytes,
    max_depth: 100,
  }
  assert_true(
    prepare_source_registrations(
      source,
      catalog,
      exact,
      max_inputs=2,
      max_views=100,
      max_order_keys=100,
    )
    is Ok(_),
  )
  for
    short in [
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_nodes: exact.max_nodes - 1, },
      { ..exact, max_text_bytes: exact.max_text_bytes - 1, },
    ] {
    assert_true(
      prepare_source_registrations(
        source,
        catalog,
        short,
        max_inputs=2,
        max_views=100,
        max_order_keys=100,
      )
      is Err(_),
    )
  }
  assert_true(
    prepare_source_registrations(
      source,
      catalog,
      caps,
      max_inputs=1,
      max_views=100,
      max_order_keys=100,
    )
    is Err(Selection({ kind: InputLimit, .. })),
  )
  assert_true(
    prepare_source_registrations(
      source,
      catalog,
      caps,
      max_inputs=2,
      max_views=0,
      max_order_keys=100,
    )
    is Err(Selection({ kind: ViewLimit, .. })),
  )
  assert_true(
    prepare_source_registrations(
      source,
      catalog,
      caps,
      max_inputs=2,
      max_views=100,
      max_order_keys=-1,
    )
    is Err(InvalidLimits),
  )
}
