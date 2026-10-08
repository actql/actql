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
test "pipeline authoring retains exact pending execution owners without binding values" {
  for cell in [false, true] {
    let pipeline = unbound_profile_pipeline(true, value_cell=cell)
    let profiles = authoring_profile_proof(pipeline)
    let closure = close_pipeline_authoring(profiles, 100000, 100, 100).unwrap()
    assert_true(physical_equal(pipeline_authoring_profiles(closure), profiles))
    assert_true(
      physical_equal(
        @pipeline.expression_slots_pipeline(
          pipeline_authoring_expressions(closure),
        ),
        pipeline,
      ),
    )
    assert_eq(
      pipeline_authoring_runtime_count(closure),
      if cell {
        2
      } else {
        1
      },
    )
    let resource = pipeline_authoring_runtime_at(closure, 0).unwrap()
    assert_eq(resource.step, 0)
    assert_true(
      @pipeline.operation_obligations_at(resource.owner, resource.index)
      is Some(@pipeline.ValuesRequirement(@values.ResolvePublicationResources)),
    )
    if cell {
      let binding = pipeline_authoring_runtime_at(closure, 1).unwrap()
      assert_eq(binding.step, 0)
      assert_true(
        @pipeline.operation_obligations_at(binding.owner, binding.index)
        is Some(@pipeline.ValuesRequirement(@values.BindCell("x"))),
      )
    }
    let exact = pipeline_authoring_work(closure)
    assert_eq(
      pipeline_authoring_work(
        close_pipeline_authoring(profiles, exact, 100, 100).unwrap(),
      ),
      exact,
    )
    assert_true(
      close_pipeline_authoring(profiles, exact - 1, 100, 100)
      is Err(BudgetExceeded),
    )
    assert_true(
      close_pipeline_authoring(profiles, 0, 100, 100) is Err(BudgetExceeded),
    )
    assert_true(
      close_pipeline_authoring(profiles, -1, 100, 100) is Err(InvalidLimits),
    )
    assert_true(
      close_pipeline_authoring(profiles, 100000, 100, 0) is Err(BudgetExceeded),
    )
    assert_true(
      close_pipeline_authoring(profiles, 100000, 0, 100)
      is Err(ExpressionSlots(SlotLimit)),
    )
  }
}

///|
test "pipeline authoring cannot certify unresolved expressions or unconnected operations" {
  let pattern = unbound_profile_pipeline(
    false,
    expression=Some("regex_match(NULL, 'a')"),
  )
  assert_true(
    close_pipeline_authoring(authoring_profile_proof(pattern), 100000, 100, 100)
    is Err(PendingExpression(1, _)),
  )
  let unconnected = unbound_profile_pipeline(true, suffix=",{\"take\":1}")
  assert_true(
    close_pipeline_authoring(
      authoring_profile_proof(unconnected),
      100000,
      100,
      100,
    )
    is Err(UnsupportedOperation(3)),
  )
}
