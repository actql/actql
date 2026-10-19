///|
fn authoring_profile_proof(
  pipeline : @pipeline.CheckedPipeline,
) -> PipelineOperationProfileChecks {
  check_pipeline_operation_profiles(
    pipeline,
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    { text_time: true, veca: false, },
    100000,
  ).unwrap()
}

///|
test "pipeline authoring requires completed static resource selection from the exact owner" {
  let pipeline = unbound_profile_pipeline(true)
  let profiles = authoring_profile_proof(pipeline)
  let capacity = authoring_capacity()
  let resource = resolve_authoring_values_resources(
    profiles,
    0,
    capacity,
    values_publication_limits(),
  ).unwrap()
  let resources = [resource]
  let closure = close_pipeline_authoring(
    profiles, capacity, resources, 100000, 100, 100,
  ).unwrap()
  assert_true(physical_equal(pipeline_authoring_profiles(closure), profiles))
  assert_true(
    physical_equal(
      @pipeline.expression_slots_pipeline(
        pipeline_authoring_expressions(closure),
      ),
      pipeline,
    ),
  )
  assert_eq(pipeline_authoring_runtime_count(closure), 0)
  assert_eq(pipeline_authoring_values_count(closure), 1)
  assert_true(
    physical_equal(pipeline_authoring_values_at(closure, 0).unwrap(), resource),
  )
  let exact = pipeline_authoring_work(closure)
  assert_true(
    close_pipeline_authoring(profiles, capacity, resources, exact, 100, 100)
    is Ok(_),
  )
  assert_true(
    close_pipeline_authoring(profiles, capacity, resources, exact - 1, 100, 100)
    is Err(BudgetExceeded),
  )
  assert_true(
    close_pipeline_authoring(profiles, capacity, resources, 0, 100, 100)
    is Err(BudgetExceeded),
  )
  assert_true(
    close_pipeline_authoring(profiles, capacity, resources, -1, 100, 100)
    is Err(InvalidLimits),
  )
  assert_true(
    close_pipeline_authoring(profiles, capacity, resources, 100000, 0, 100)
    is Err(ExpressionSlots(SlotLimit)),
  )
  // A raw resource obligation is not an already selected future check.
  assert_true(
    close_pipeline_authoring(profiles, capacity, [], 100000, 100, 100)
    is Err(PendingOperation(0, _, 0)),
  )
  assert_true(
    close_pipeline_authoring(
      profiles,
      capacity,
      [resource, resource],
      100000,
      100,
      100,
    )
    is Err(ForeignValues(0)),
  )
  let foreign_profiles = authoring_profile_proof(pipeline)
  assert_true(
    close_pipeline_authoring(
      foreign_profiles, capacity, resources, 100000, 100, 100,
    )
    is Err(ForeignValues(0)),
  )
  let foreign_pipeline = unbound_profile_pipeline(true)
  assert_true(
    close_pipeline_authoring(
      authoring_profile_proof(foreign_pipeline),
      capacity,
      resources,
      100000,
      100,
      100,
    )
    is Err(ForeignValues(0)),
  )
  assert_true(
    close_pipeline_authoring(
      profiles,
      authoring_capacity(),
      resources,
      100000,
      100,
      100,
    )
    is Err(ForeignValues(0)),
  )
  assert_true(physical_equal(pipeline_authoring_capacity(closure), capacity))
  resources.clear()
  assert_eq(pipeline_authoring_values_count(closure), 1)
}

///|
test "pipeline authoring cannot certify unresolved expressions or unconnected operations" {
  let pattern = unbound_profile_pipeline(
    false,
    expression=Some("regex_match(NULL, 'a')"),
  )
  let profiles = authoring_profile_proof(pattern)
  let capacity = authoring_capacity()
  let resource = resolve_authoring_values_resources(
    profiles,
    0,
    capacity,
    values_publication_limits(),
  ).unwrap()
  assert_true(
    close_pipeline_authoring(profiles, capacity, [resource], 100000, 100, 100)
    is Err(PendingExpression(1, _)),
  )
  let unconnected = unbound_profile_pipeline(
    true,
    suffix=",{\"dedupe_rows\":{\"by\":[\"n\"],\"order_by\":[{\"n\":\"asc\"}]}}",
  )
  let profiles = authoring_profile_proof(unconnected)
  let capacity = authoring_capacity()
  let resource = resolve_authoring_values_resources(
    profiles,
    0,
    capacity,
    values_publication_limits(),
  ).unwrap()
  assert_true(
    close_pipeline_authoring(profiles, capacity, [resource], 100000, 100, 100)
    is Err(UnsupportedOperation(3)),
  )
  let cell = unbound_profile_pipeline(true, value_cell=true)
  assert_true(
    close_pipeline_authoring(
      authoring_profile_proof(cell),
      capacity,
      [],
      100000,
      100,
      100,
    )
    is Err(PendingOperation(0, _, 0)),
  )
}
