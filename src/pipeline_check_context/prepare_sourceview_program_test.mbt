///|
test "selected SourceView registrations construct Stage pipelines and Result imports" {
  let remote = []
  let (_, old_wiring, _, _, _, _) = wired_inputs_fixture(
    true,
    remote=Some(remote),
    repeat_remote=true,
  )
  let source = @stage_results.wiring_source(old_wiring)
  let catalog = @sourceviews.catalog(
    @sourceviews.pipeline_resolution(remote[0]),
  )
  let (views, locals) = prepare_source_registrations(
    source,
    catalog,
    {
      max_work: 1000000,
      max_nodes: 100000,
      max_text_bytes: 1000000,
      max_depth: 100,
    },
    max_inputs=2,
    max_views=100,
    max_order_keys=100,
  ).unwrap()
  let limits = local_program_context_source_limits()
  let (wiring, used) = prepare_sourceview_program(views, locals, limits).unwrap()
  let (other_views, other_locals) = prepare_source_registrations(
    source,
    catalog,
    {
      max_work: 1000000,
      max_nodes: 100000,
      max_text_bytes: 1000000,
      max_depth: 100,
    },
    max_inputs=2,
    max_views=100,
    max_order_keys=100,
  ).unwrap()
  assert_true(
    prepare_sourceview_program(other_views, locals, limits)
    is Err(ForeignPartition(0)),
  )
  assert_true(
    prepare_sourceview_program(views, other_locals, limits)
    is Err(ForeignPartition(0)),
  )
  assert_true(physical_equal(@stage_results.wiring_source(wiring), source))
  for stage in 0..<2 {
    let collected = @stage_results.stage_port_source(
      @stage_results.wiring_stage_at(wiring, stage).unwrap(),
    )
    assert_true(
      @sourceviews.attach_pipeline_inputs(views, collected, 1000000) is Ok(_),
    )
  }
  let exact = {
    ..limits,
    max_work: used.work,
    max_nodes: used.nodes,
    max_tokens: used.tokens,
    max_text_bytes: used.text_bytes,
    max_steps: used.steps,
    max_results: used.results,
  }
  assert_true(prepare_sourceview_program(views, locals, exact) is Ok(_))
  for
    short in [
      { ..exact, max_work: used.work - 1, },
      { ..exact, max_nodes: used.nodes - 1, },
      { ..exact, max_text_bytes: used.text_bytes - 1, },
    ] {
    assert_true(prepare_sourceview_program(views, locals, short) is Err(_))
  }
  assert_true(
    @stage_results.prepare_local_program(
      source,
      limits,
      environment=Some(locals),
    )
    is Err(MissingSourceViewRegistrations(0)),
  )
  let malformed : Array[Array[(String, @pipeline.InputContract)]] = [
    [
      @sourceviews.pipeline_input_at(views, 0, 0).unwrap(),
      @sourceviews.pipeline_input_at(views, 0, 0).unwrap(),
    ],
    [],
  ]
  assert_true(
    @stage_results.prepare_local_program(
      source,
      limits,
      environment=Some(locals),
      sourceview_registrations=Some(malformed),
    )
    is Err(InvalidSourceViewRegistration(0, _)),
  )
}
