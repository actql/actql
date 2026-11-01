///|
fn original_context_input_fixture() -> (
  @sourceviews.PipelineInputs,
  @local_inputs.ProgramEnvironmentInputs,
  @stage_results.ResultWiring,
) {
  let remote = []
  let (_, wiring, _, _, _, _) = wired_inputs_fixture(
    true,
    remote=Some(remote),
    repeat_remote=true,
    profile=capacity_profile(false),
  )
  let source = @stage_results.wiring_source(wiring)
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
  (views, locals, wiring)
}

///|
test "original SourceView Context entrance retains the same source and continues once with unchanged work and identity" {
  let (views, locals, old_wiring) = original_context_input_fixture()
  let source_limits = local_program_context_source_limits()
  let limits = local_context_limits()
  let (wiring, _) = prepare_sourceview_program(views, locals, source_limits).unwrap()
  let bound = @stage_results.bind_prepared_program(wiring, None, source_limits).unwrap()
  let materials = capacity_materials_fixture(bound).0
  let original = prepare_sourceview_context_input(
    views, locals, source_limits, limits,
  ).unwrap()
  assert_true(
    physical_equal(
      sourceview_context_input_source(original),
      @stage_results.wiring_source(old_wiring),
    ),
  )
  let entry_work = sourceview_context_input_work(original)
  assert_true(entry_work > 0)
  let selected = prepare_sourceview_context_from_input(
    original,
    None,
    materials,
  ).unwrap()
  assert_true(
    prepare_sourceview_context_from_input(original, None, materials)
    is Err(Program(Unavailable)),
  )
  assert_eq(sourceview_context_input_work(original), entry_work)
  let ordinary = prepare_sourceview_context(
    views,
    locals,
    None,
    materials,
    source_limits,
    limits,
  ).unwrap()
  assert_eq(selected_policy_usage(selected), selected_policy_usage(ordinary))
  assert_eq(
    program_identity_definition_cid(prepared_selected_identity(selected)),
    program_identity_definition_cid(prepared_selected_identity(ordinary)),
  )
}

///|
test "original Context input keeps invalid limit and foreign partition refusals before topology or binding" {
  let (views, locals, _) = original_context_input_fixture()
  let source_limits = local_program_context_source_limits()
  let limits = local_context_limits()
  assert_true(
    prepare_sourceview_context_input(views, locals, source_limits, {
      ..limits,
      stages: { ..limits.stages, max_work: -1, },
    })
    is Err(InvalidLimits),
  )
  assert_true(
    prepare_sourceview_context_input(
      views,
      locals,
      { ..source_limits, max_work: 0, },
      limits,
    )
    is Err(Program(BudgetExceeded)),
  )
  let source = @source_inputs.source(
    @sourceviews.inputs(@sourceviews.pipeline_resolution(views)),
  )
  let catalog = @sourceviews.catalog(@sourceviews.pipeline_resolution(views))
  let (_, foreign_locals) = prepare_source_registrations(
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
    prepare_sourceview_context_input(
      views, foreign_locals, source_limits, limits,
    )
    is Err(Program(ForeignPartition(0))),
  )
}
