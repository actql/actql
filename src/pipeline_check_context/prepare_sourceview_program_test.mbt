///|
test "selected SourceView registrations construct Stage pipelines and Result imports" {
  let remote = []
  let (_, old_wiring, _, _, _, _) = wired_inputs_fixture(
    true,
    remote=Some(remote),
    repeat_remote=true,
    profile=capacity_profile(false),
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
  let bound = @stage_results.bind_prepared_program(wiring, None, limits).unwrap()
  assert_true(physical_equal(@stage_results.local_source_source(bound), source))
  assert_true(physical_equal(@stage_results.local_source_wiring(bound), wiring))
  let values = @stage_results.local_source_values(bound)
  let materials = capacity_materials_fixture(bound).0
  let context_caps = local_context_limits()
  let selected = prepare_local_context(
    bound,
    materials,
    context_caps,
    sourceviews=Some(views),
  ).unwrap()
  assert_true(
    physical_equal(
      reconciled_sourceviews(policy_context(selected)).unwrap(),
      views,
    ),
  )
  let identity = prepared_selected_identity(selected)
  assert_eq(program_identity_stage_count(identity), 2)
  let context_usage = selected_policy_usage(selected)
  let assembled = prepare_sourceview_context(
    views,
    locals,
    None,
    materials,
    limits,
    context_caps,
  ).unwrap()
  let assembled_usage = selected_policy_usage(assembled)
  assert_true(assembled_usage.work > context_usage.work)
  assert_eq(assembled_usage.text_bytes, context_usage.text_bytes)
  assert_true(
    physical_equal(
      reconciled_sourceviews(policy_context(assembled)).unwrap(),
      views,
    ),
  )
  assert_true(
    physical_equal(
      @stage_results.wiring_source(
        result_wiring(reconciled_wiring(policy_context(assembled))),
      ),
      source,
    ),
  )
  let assembled_caps = {
    ..context_caps,
    stages: {
      ..context_caps.stages,
      max_work: assembled_usage.work,
      max_text_bytes: assembled_usage.text_bytes,
    },
  }
  assert_true(
    prepare_sourceview_context(
      views,
      locals,
      None,
      materials,
      limits,
      assembled_caps,
    )
    is Ok(_),
  )
  for
    short in [
      {
        ..assembled_caps,
        stages: { ..assembled_caps.stages, max_work: assembled_usage.work - 1, },
      },
      {
        ..assembled_caps,
        stages: { ..assembled_caps.stages, max_work: context_usage.work, },
      },
      {
        ..assembled_caps,
        stages: {
          ..assembled_caps.stages,
          max_text_bytes: assembled_usage.text_bytes - 1,
        },
      },
    ] {
    assert_true(
      prepare_sourceview_context(views, locals, None, materials, limits, short)
      is Err(_),
    )
  }
  assert_true(
    prepare_sourceview_context(
      other_views,
      locals,
      None,
      materials,
      limits,
      context_caps,
    )
    is Err(Program(ForeignPartition(0))),
  )
  assert_true(
    prepare_sourceview_context(
      views,
      locals,
      None,
      [materials[0]],
      limits,
      context_caps,
    )
    is Err(Context(Stages(StageCount))),
  )
  let assembled_identity = prepared_selected_identity(assembled)
  assert_eq(program_identity_stage_count(assembled_identity), 2)
  assert_eq(
    program_identity_definition_cid(assembled_identity),
    program_identity_definition_cid(identity),
  )
  assert_eq(
    program_identity_parameter_values_cid(assembled_identity),
    program_identity_parameter_values_cid(identity),
  )
  assert_true(
    prepare_sourceview_context(
      views,
      locals,
      Some(cursor("{\"n\":\"bad\"}")),
      materials,
      limits,
      context_caps,
    )
    is Err(Binding(_)),
  )
  let last = materials[1].length() - 1
  let saved = materials[1][last]
  materials[1][last] = {
    sources: saved.sources,
    consumers: [@capacity.Join(step=0, output=0)],
  }
  assert_true(
    prepare_sourceview_context(
      views,
      locals,
      None,
      materials,
      limits,
      context_caps,
    )
    is Err(Context(Stages(Capacity(1, _, Join(0, WrongOperation))))),
  )
  materials[1][last] = saved
  assert_true(
    prepare_sourceview_context(
      views,
      locals,
      None,
      materials,
      limits,
      context_caps,
    )
    is Ok(_),
  )
  let context_exact = {
    ..context_caps,
    stages: {
      ..context_caps.stages,
      max_work: context_usage.work,
      max_text_bytes: context_usage.text_bytes,
    },
  }
  assert_true(
    prepare_local_context(
      bound,
      materials,
      context_exact,
      sourceviews=Some(views),
    )
    is Ok(_),
  )
  for
    short in [
      {
        ..context_exact,
        stages: { ..context_exact.stages, max_work: context_usage.work - 1, },
      },
      {
        ..context_exact,
        stages: {
          ..context_exact.stages,
          max_text_bytes: context_usage.text_bytes - 1,
        },
      },
    ] {
    assert_true(
      prepare_local_context(bound, materials, short, sourceviews=Some(views))
      is Err(_),
    )
  }
  assert_true(
    prepare_local_context(bound, materials, context_caps)
    is Err(Inputs(Inputs(MissingSourceViews(0)))),
  )
  assert_true(
    prepare_local_context(
      bound,
      materials,
      context_caps,
      sourceviews=Some(other_views),
    )
    is Err(Inputs(Inputs(ForeignSourceViews(0)))),
  )
  assert_eq(@parameter.bound_value_count(values), 1)
  assert_true(
    physical_equal(
      @parameter.bound_declarations(values),
      @stages.declarations(source),
    ),
  )
  let bound_usage = @stage_results.local_source_usage(bound)
  let binding_exact = {
    ..limits,
    max_work: bound_usage.work,
    max_nodes: bound_usage.nodes,
    max_text_bytes: bound_usage.text_bytes,
  }
  assert_true(
    @stage_results.bind_prepared_program(wiring, None, binding_exact) is Ok(_),
  )
  for
    short in [
      { ..binding_exact, max_work: bound_usage.work - 1, },
      { ..binding_exact, max_nodes: bound_usage.nodes - 1, },
      { ..binding_exact, max_text_bytes: bound_usage.text_bytes - 1, },
    ] {
    assert_true(
      @stage_results.bind_prepared_program(wiring, None, short) is Err(_),
    )
  }
  assert_true(
    @stage_results.bind_prepared_program(old_wiring, None, limits)
    is Err(MissingPreparation),
  )
  for stage in 0..<2 {
    let collected = @stage_results.stage_port_source(
      @stage_results.wiring_stage_at(wiring, stage).unwrap(),
    )
    assert_true(
      physical_equal(
        @stages.operations_stage_at(
          @stages.bound_operations(
            @stage_results.local_source_operations(bound),
          ),
          stage,
        ).unwrap(),
        collected,
      ),
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
