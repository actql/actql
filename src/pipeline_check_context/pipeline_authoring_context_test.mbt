///|
fn authoring_context_fixture(
  ordered? : Bool = false,
) -> (
  PipelineAuthoringClosure,
  PipelineOrderPreparation,
  CapacityStageLimits,
  @wire.Limits,
) raise {
  let pipeline = unbound_profile_pipeline(
    true,
    suffix=if ordered {
      ",{\"sort\":[{\"n\":\"desc\"}]},{\"take\":1},{\"rename\":{\"n\":\"id\"},\"as\":\"output\"}"
    } else {
      ",{\"rename\":{\"n\":\"id\"},\"as\":\"output\"}"
    },
  )
  let profiles = authoring_profile_proof(pipeline)
  let capacity = authoring_capacity()
  let resource = resolve_authoring_values_resources(
    profiles,
    0,
    capacity,
    values_publication_limits(),
  ).unwrap()
  let authoring = close_pipeline_authoring(
    profiles,
    capacity,
    [resource],
    100000,
    100,
    100,
  ).unwrap()
  let results = @results.check(
    pipeline,
    cursor("{\"out\":{\"from\":\"output\",\"fields\":[\"id\"]}}"),
    {
      max_results: 1,
      max_work: 10000,
      max_nodes: 100,
      max_text_bytes: 10000,
      max_depth: 20,
    },
  ).unwrap()
  let orders = @results.resolve_all_orders(results, {
    max_steps: 10,
    max_results: 1,
    max_work: 10000,
    max_text_bytes: 10000,
  }).unwrap()
  let orders = prepare_pipeline_orders(
    orders,
    max_work=100000,
    max_text_bytes=100000,
  ).unwrap()
  (
    authoring,
    orders,
    {
      max_work: 100000,
      max_text_bytes: 100000,
      max_name_bytes: 10000,
      max_input_work: 10000,
      max_operand_work: 10000,
    },
    { max_bytes: 100000, max_nodes: 100000, max_depth: 100, },
  )
}

///|
test "authoring capacity context retains actual unbound orders and Values applications" {
  let (authoring, orders, limits, metadata) = authoring_context_fixture()
  let checked = prepare_pipeline_authoring_context(
    authoring, orders, limits, metadata,
  ).unwrap()
  assert_true(
    physical_equal(pipeline_authoring_context_source(checked), authoring),
  )
  assert_true(
    physical_equal(pipeline_authoring_context_orders(checked), orders),
  )
  let context = pipeline_authoring_context_pipeline(checked)
  assert_true(
    physical_equal(checked_orders(context), prepared_pipeline_orders(orders)),
  )
  assert_true(
    physical_equal(checked_results(context), prepared_pipeline_results(orders)),
  )
  assert_eq(expression_requirement_count(context), 0)
  let closure = checked_capacity(context)
  let coverage = @capacity.application_closure_at(closure, 0).unwrap()
  let applications = @capacity.source_coverage_program(
    @capacity.application_coverage_sources(coverage),
  )
  let bound = @program.application_at(applications, 0).unwrap()
  assert_true(@program.checked_bindings(bound) is None)
  assert_eq(
    @wire.value(@wire.program_proof_witness(@program.checked_proof(bound))),
    1L,
  )
  assert_true(
    physical_equal(
      @program.checked_pipeline(bound),
      @results.pipeline(prepared_pipeline_results(orders)),
    ),
  )
  // Missing x still cannot be projected as execution-ready expression values.
  assert_true(
    check_parameter_bindings(context, max_work=100000, max_text_bytes=100000)
    is Err(_),
  )
  let (work, bytes, nodes) = pipeline_authoring_context_usage(checked)
  assert_true(work > pipeline_authoring_work(authoring))
  assert_true(bytes > 0 && nodes > 0)
  assert_true(
    prepare_pipeline_authoring_context(
      authoring,
      orders,
      { ..limits, max_work: work, },
      metadata,
    )
    is Ok(_),
  )
  assert_true(
    prepare_pipeline_authoring_context(
      authoring,
      orders,
      { ..limits, max_work: work - 1, },
      metadata,
    )
    is Err(_),
  )
  assert_true(
    prepare_pipeline_authoring_context(authoring, orders, limits, {
      ..metadata,
      max_bytes: 0,
    })
    is Err(Values(_)),
  )
}

///|
test "authoring capacity context rejects foreign order owners before preparing evidence" {
  let (authoring, orders, limits, metadata) = authoring_context_fixture()
  let (_, foreign, _, _) = authoring_context_fixture()
  assert_true(
    prepare_pipeline_authoring_context(authoring, foreign, limits, metadata)
    is Err(ForeignOrders),
  )
  assert_true(
    prepare_pipeline_authoring_context(
      authoring,
      orders,
      { ..limits, max_work: 0, },
      metadata,
    )
    is Err(BudgetExceeded),
  )
  assert_true(
    prepare_pipeline_authoring_context(
      authoring,
      orders,
      { ..limits, max_work: -1, },
      metadata,
    )
    is Err(InvalidLimits),
  )
}

///|
test "authoring capacity context does not erase unconnected input obligations" {
  let pipeline = base(true)
  let profiles = authoring_profile_proof(pipeline)
  let authoring = close_pipeline_authoring(
    profiles,
    authoring_capacity(),
    [],
    100000,
    100,
    100,
  ).unwrap()
  let orders = @results.resolve_all_orders(results(pipeline), {
    max_steps: 10,
    max_results: 1,
    max_work: 10000,
    max_text_bytes: 10000,
  }).unwrap()
  let orders = prepare_pipeline_orders(
    orders,
    max_work=100000,
    max_text_bytes=100000,
  ).unwrap()
  let (_, _, limits, metadata) = authoring_context_fixture()
  assert_true(
    prepare_pipeline_authoring_context(authoring, orders, limits, metadata)
    is Err(UnsupportedInputs),
  )
}

///|
test "authoring ordered context uses only its original producer and exact work budget" {
  let (authoring, orders, limits, metadata) = authoring_context_fixture(
    ordered=true,
  )
  let checked = prepare_pipeline_authoring_context(
    authoring, orders, limits, metadata,
  ).unwrap()
  assert_eq(pipeline_authoring_context_order_count(checked), 2)
  for index in 0..<2 {
    let (step, owner, obligation, resolution) = pipeline_authoring_context_order_at(
      checked, index,
    ).unwrap()
    assert_eq(step, 3 + index)
    assert_true(
      @pipeline.operation_order_demand(
        @pipeline.operation_obligations_at(owner, obligation).unwrap(),
      )
      is Some(_),
    )
    assert_true(
      match resolution {
        SortSequence(_) => index == 0
        TakeSequence(_) => index == 1
        _ => false
      },
    )
  }
  assert_true(pipeline_authoring_context_order_at(checked, -1) is None)
  assert_true(pipeline_authoring_context_order_at(checked, 2) is None)
  let work = pipeline_authoring_context_usage(checked).0
  assert_true(
    prepare_pipeline_authoring_context(
      authoring,
      orders,
      { ..limits, max_work: work, },
      metadata,
    )
    is Ok(_),
  )
  assert_true(
    prepare_pipeline_authoring_context(
      authoring,
      orders,
      { ..limits, max_work: work - 1, },
      metadata,
    )
    is Err(_),
  )
  let (_, foreign, _, _) = authoring_context_fixture(ordered=true)
  assert_true(
    prepare_pipeline_authoring_context(authoring, foreign, limits, metadata)
    is Err(ForeignOrders),
  )
}
