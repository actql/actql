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
    assert_compilation_shape_covers(
      measured.parser_geometry.executable_plan,
      actual,
    )
    for
      (name, bound, shape) in [
        ("nodes", measured.nodes, measured.parser_geometry.nodes),
        ("data_edges", measured.edges, measured.parser_geometry.edges),
        ("root_refs", measured.roots, measured.parser_geometry.roots),
        (
          "execution_material",
          measured.material,
          measured.parser_geometry.material,
        ),
      ] {
      assert_compilation_geometry_covers(
        bound,
        @canonical.object_field(actual, name).unwrap(),
      )
      assert_compilation_shape_covers(
        shape,
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

///|
fn assert_compilation_shape_covers(
  shape : @encode.EncodingConstructionGeometry?,
  original : @canonical.CanonicalValue,
) -> Unit raise {
  guard shape is Some(shape) else { fail("Missing same-role codec geometry") }
  let extent = @canonical.representation_extent(original, 100000, 100, 1000000).unwrap()
  let pending = [original]
  let mut fields = 0L
  let mut largest = 0
  while pending.pop() is Some(value) {
    match value {
      @canonical.Object(_) => {
        let members = @canonical.object_fields(value).unwrap()
        fields += members.length().to_int64()
        largest = Int::max(largest, members.length())
        for (_, child) in members {
          pending.push(child)
        }
      }
      @canonical.Array(items) =>
        for child in @canonical.array_values(items) {
          pending.push(child)
        }
      _ => ()
    }
  }
  assert_true(shape.arrays.to_int64() >= extent.arrays)
  assert_true(shape.objects.to_int64() >= extent.objects)
  assert_true(shape.fields.to_int64() >= fields)
  assert_true(shape.largest_object >= largest)
  assert_true(shape.strings.to_int64() + fields >= extent.strings)
  assert_true(shape.text_units.to_int64() >= extent.text_utf16_units)
}

///|
test "unobserved codec role cannot borrow another same-sized subtree shape" {
  let array = @encode.construction_measuring_writer(100, 10, 5)
  @encode.begin_array(array)
  @encode.number_value(array, 12345.0)
  @encode.end_array(array)
  let observed = measured_client_compilation_geometry(
    @encode.finish_construction_measurement(array),
  )
  let object = @encode.measuring_writer(100, 10, 5)
  @encode.begin_object(object)
  @encode.key(object, "a")
  @encode.number_value(object, 1.0)
  @encode.end_object(object)
  let unobserved = unknown_client_compilation_geometry(
    @encode.finish_measurement_usage(object),
  )
  assert_eq(observed.usage, unobserved.usage)
  assert_true(unobserved.shape is None)
  let combined = measure_client_compilation_array([observed, unobserved])
  let shape = combined.shape.unwrap()
  assert_true(shape.fields >= 1 && shape.objects >= 1)
  assert_true(shape.arrays >= 2)
}
