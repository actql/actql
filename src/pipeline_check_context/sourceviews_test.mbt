///|
fn sourceview_catalog(
  environment : @environment.WireEnvironment,
) -> @environment.SourceRequestContracts {
  let caps : @environment.Limits = {
    max_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 100,
    max_members: 1000,
  }
  let registry = @environment.check_contract_registry(environment, caps).unwrap()
  let contents = @environment.check_catalog_contents(registry, caps).unwrap()
  let references = @environment.check_catalog_references(contents, {
    max_work: 1000000,
    max_references: 10000,
  }).unwrap()
  let policies = @environment.check_source_data_policies(references, {
    max_work: 1000000,
    max_policies: 1000,
  }).unwrap()
  let values = @environment.check_protocol_value_contracts(policies, {
    max_envelopes: 1000,
    contracts: { max_nodes: 100000, max_depth: 100, max_text_bytes: 1000000, },
  }).unwrap()
  let shapes = @environment.check_source_view_shapes(values, {
    max_work: 1000000,
    max_views: 1000,
  }).unwrap()
  let modes = @environment.check_source_read_modes(shapes, 1000000).unwrap()
  let carriers = @environment.check_carrier_schemas(modes, {
    max_work: 1000000,
    max_schemas: 1000,
    bodies: { max_bytes: 1000000, max_nodes: 100000, max_depth: 100, },
  }).unwrap()
  @environment.check_source_request_contracts(carriers, {
    max_work: 1000000,
    max_roles: 10000,
  }).unwrap()
}

///|
test "reconciled Program inputs retain SourceView registrations and the same environment" {
  let remote = []
  let (stages, wiring, _, _, locals, evidence) = wired_inputs_fixture(
    true,
    remote=Some(remote),
  )
  let views = remote[0]
  let snapshots = evidence.unwrap()
  let wired = attach_result_wiring(
    stages,
    wiring,
    max_work=1000000,
    max_text_bytes=1000000,
  ).unwrap()
  let result = attach_reconciled_inputs(
    wired,
    snapshots,
    locals,
    sourceviews=Some(views),
    max_work=1000000,
    max_text_bytes=1000000,
    max_local_input_nodes=100000,
  ).unwrap()
  assert_true(physical_equal(reconciled_sourceviews(result).unwrap(), views))
  assert_true(
    physical_equal(
      @sourceviews.pipeline_environment(views),
      @local_inputs.program_environment(snapshots),
    ),
  )
  for i in 0..<2 {
    let attached = reconciled_sourceview_stage(result, i).unwrap()
    let uses = reconciled_sourceview_uses(result, i).unwrap()
    assert_true(
      physical_equal(@sourceviews.pipeline_uses_attachment(uses), attached),
    )
    assert_true(
      physical_equal(
        @sourceviews.pipeline_uses_results(uses),
        stage_results(stages),
      ),
    )
    assert_eq(
      @sourceviews.pipeline_use_count(uses, 0),
      if i == 0 {
        Some(0)
      } else {
        None
      },
    )
    assert_true(
      physical_equal(@sourceviews.attached_pipeline_inputs(attached), views),
    )
    assert_true(
      physical_equal(
        @sourceviews.attached_pipeline_stage(attached),
        @local_inputs.reconciled_stage(locals[i]),
      ),
    )
  }
  assert_true(reconciled_sourceview_stage(result, -1) is None)
  assert_true(reconciled_sourceview_stage(result, 2) is None)
  let usage = reconciled_usage(result)
  let prior = @local_inputs.program_environment_usage(snapshots)
  let (wired_work, wired_text) = wired_usage(wired)
  let mut expected_work = wired_work +
    prior.work +
    @sourceviews.pipeline_inputs_work(views)
  for i in 0..<2 {
    let stage = @local_inputs.reconciled_stage(locals[i])
    expected_work += 1 +
      @local_inputs.reconciled_work(locals[i]) -
      @stages.collection_work(stage) -
      @local_inputs.environment_usage(
        @local_inputs.reconciled_inputs(locals[i]),
      ).work
    expected_work += @sourceviews.pipeline_attachment_work(
        reconciled_sourceview_stage(result, i).unwrap(),
      ) -
      @sourceviews.pipeline_inputs_work(views) -
      @stages.collection_work(stage)
    expected_work += @sourceviews.pipeline_uses_work(
      reconciled_sourceview_uses(result, i).unwrap(),
    )
  }
  assert_eq(usage, {
    work: expected_work,
    text_bytes: wired_text + prior.text_bytes,
    local_input_nodes: prior.nodes,
  })
  assert_true(
    attach_reconciled_inputs(
      wired,
      snapshots,
      locals,
      sourceviews=Some(views),
      max_work=usage.work,
      max_text_bytes=usage.text_bytes,
      max_local_input_nodes=usage.local_input_nodes,
    )
    is Ok(_),
  )
  assert_true(
    attach_reconciled_inputs(
      wired,
      snapshots,
      locals,
      sourceviews=Some(views),
      max_work=usage.work - 1,
      max_text_bytes=usage.text_bytes,
      max_local_input_nodes=usage.local_input_nodes,
    )
    is Err(BudgetExceeded),
  )
  assert_true(
    attach_reconciled_inputs(
      wired,
      snapshots,
      locals,
      max_work=1000000,
      max_text_bytes=1000000,
      max_local_input_nodes=100000,
    )
    is Err(MissingSourceViews(0)),
  )
  let original = @sourceviews.pipeline_resolution(views)
  let source = @local_inputs.environment_program(snapshots)
  let foreign_source = @stages.prepare(@stages.program(source), {
    max_parameters: 100,
    max_nodes: 10000,
    max_depth: 100,
    max_text_bytes: 100000,
  }).unwrap()
  let foreign_inputs = @source_inputs.collect(foreign_source, {
    max_work: 100000,
    max_order_keys: 100,
  }).unwrap()
  let foreign_program = @sourceviews.prepare_pipeline_inputs(
    @sourceviews.resolve(foreign_inputs, @sourceviews.catalog(original), {
      max_work: 1000000,
      max_inputs: 100,
      max_views: 100,
    }).unwrap(),
    1000000,
  ).unwrap()
  assert_true(
    attach_reconciled_inputs(
      wired,
      snapshots,
      locals,
      sourceviews=Some(foreign_program),
      max_work=1000000,
      max_text_bytes=1000000,
      max_local_input_nodes=100000,
    )
    is Err(ForeignProgram),
  )
  let recollected = @source_inputs.collect(source, {
    max_work: 100000,
    max_order_keys: 100,
  }).unwrap()
  let other = @sourceviews.prepare_pipeline_inputs(
    @sourceviews.resolve(recollected, @sourceviews.catalog(original), {
      max_work: 1000000,
      max_inputs: 100,
      max_views: 100,
    }).unwrap(),
    1000000,
  ).unwrap()
  assert_true(
    attach_reconciled_inputs(
      wired,
      snapshots,
      locals,
      sourceviews=Some(other),
      max_work=1000000,
      max_text_bytes=1000000,
      max_local_input_nodes=100000,
    )
    is Err(ForeignSourceViews(0)),
  )
  let (foreign_environment, _) = sourceview_snapshot_fixture()
  let wrong_environment = @sourceviews.prepare_pipeline_inputs(
    @sourceviews.resolve(
      @sourceviews.inputs(original),
      sourceview_catalog(foreign_environment),
      { max_work: 1000000, max_inputs: 100, max_views: 100, },
    ).unwrap(),
    1000000,
  ).unwrap()
  assert_true(
    attach_reconciled_inputs(
      wired,
      snapshots,
      locals,
      sourceviews=Some(wrong_environment),
      max_work=1000000,
      max_text_bytes=1000000,
      max_local_input_nodes=100000,
    )
    is Err(ForeignSourceEnvironment),
  )
  // Even in the same environment, rereading Carrier contracts creates different
  // registrations from the ones retained by the already checked pipeline.
  let wrong_carriers = @sourceviews.prepare_pipeline_inputs(
    @sourceviews.resolve(
      @sourceviews.inputs(original),
      sourceview_catalog(@sourceviews.pipeline_environment(views)),
      { max_work: 1000000, max_inputs: 100, max_views: 100, },
    ).unwrap(),
    1000000,
  ).unwrap()
  assert_true(
    attach_reconciled_inputs(
      wired,
      snapshots,
      locals,
      sourceviews=Some(wrong_carriers),
      max_work=1000000,
      max_text_bytes=1000000,
      max_local_input_nodes=100000,
    )
    is Err(SourceViewAttachment(0, @sourceviews.ForeignInput("remote"))),
  )
  remote.clear()
  locals.clear()
  assert_true(physical_equal(reconciled_sourceviews(result).unwrap(), views))
}
