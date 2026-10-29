///|
fn assert_compilation_geometry_covers(
  bound : (Int, Int, Int),
  value : @canonical.CanonicalValue,
) -> Unit raise {
  let writer = @encode.measuring_writer(1000000, 100000, 100)
  @canonical.emit_value(value, writer)
  let actual = @encode.finish_measurement_usage(writer)
  assert_true(bound.0 >= actual.0)
  assert_true(bound.1 >= actual.1)
  assert_true(bound.2 >= actual.2)
}

///|
test "complete pure compilation construction covers direct ordered and repeated-input long Task artifacts" {
  for
    value in [
      values_compilation_parts_prepared(),
      result_graph_ordered_fixture(),
      task_pipeline_geometry_original(),
    ] {
    let limits = prepared_client_values_sequence_limits(value)
    let measured = measure_prepared_client_pure_compilation_construction(
      value,
      run_materials_manifests(),
      limits,
      1000,
      10000,
      1000000,
      100000,
      100,
    ).unwrap()
    assert_eq(measured.tasks, prepared_client_requires_task_compilation(value))
    assert_eq(
      measured.fragments.length(),
      @strategy.graph_task_count(value.graph),
    )
    assert_eq(measured.results.length(), prepared_client_result_count(value))
    assert_eq(
      measured.projections.length(),
      prepared_client_result_count(value),
    )
    let plan = if measured.tasks {
      issue_prepared_client_task_compilation(
        value,
        run_materials_manifests(),
        limits,
        1000,
        10000,
        1000000,
        100000,
        100,
      ).unwrap().plan.plan
    } else {
      issue_prepared_client_values_compilation(
        value,
        run_materials_manifests(),
        limits,
        1000,
        10000,
        1000000,
        100000,
        100,
      ).unwrap().plan
    }
    let actual = parse_plan_identity_value(plan.wire, 1000000, 100000, 100).unwrap()
    assert_compilation_geometry_covers(measured.executable_plan, actual)
    for
      (name, bound) in [
        ("nodes", measured.nodes),
        ("data_edges", measured.edges),
        ("root_refs", measured.roots),
        ("execution_material", measured.material),
      ] {
      assert_compilation_geometry_covers(
        bound,
        @canonical.object_field(actual, name).unwrap(),
      )
    }
    let manifest = parse_plan_identity_value(
      plan.fact_manifest_wire,
      1000000,
      100000,
      100,
    ).unwrap()
    assert_compilation_geometry_covers(measured.fact_manifest, manifest)
    // Construction selection must not replace the complete original Result
    // inventory or populate a second set of lowered Task owners.
    assert_eq(plan.result_plans.length(), measured.results.length())
    for original in plan.result_plans {
      assert_true(physical_equal(original.owner, value))
      assert_compilation_geometry_covers(
        measured.results[original.result],
        parse_plan_identity_value(original.wire, 1000000, 100000, 100).unwrap(),
      )
    }
  }
}

///|
test "complete pure construction retains nominal codec and fact refusals" {
  let value = values_compilation_parts_prepared()
  let limits = prepared_client_values_sequence_limits(value)
  assert_true(
    measure_prepared_client_pure_compilation_construction(
      value,
      run_materials_manifests(),
      limits,
      0,
      10000,
      1000000,
      100000,
      100,
    )
    is Err(InvalidLimits),
  )
  assert_true(
    measure_prepared_client_pure_compilation_construction(
      value,
      run_materials_manifests(),
      limits,
      1000,
      10000,
      1,
      100000,
      100,
    )
    is Err(_),
  )
  assert_true(
    measure_prepared_client_pure_compilation_construction(
      value,
      run_materials_manifests(),
      limits,
      1,
      10000,
      1000000,
      100000,
      100,
    )
    is Err(Facts(Limits(BudgetExceeded))),
  )
}
