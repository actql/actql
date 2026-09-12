///|
fn capacity_materials_fixture(
  prepared : @stage_results.PreparedLocalSource,
) -> (Array[Array[CapacityMaterial]], Int) {
  let count = @stages.stage_count(@stage_results.local_source_source(prepared))
  let mut names = 0
  let materials : Array[Array[CapacityMaterial]] = []
  for stage in 0..<count {
    let port = @stage_results.wiring_stage_at(
      @stage_results.local_source_wiring(prepared),
      stage,
    ).unwrap()
    let orders = @results.checked_producer_orders(
      @results.ports_orders(@stage_results.stage_port_publications(port)),
    )
    let entries : Array[CapacityMaterial] = []
    for visit in 0..<@pipeline.contextual_closure_count(orders) {
      let pipeline = @pipeline.contextual_orders_pipeline(
        @pipeline.contextual_closure_at(orders, visit).unwrap(),
      )
      for input in 0..<@pipeline.input_count(pipeline) {
        // This fixture's authored input names are ASCII.
        names += @pipeline.input_at(pipeline, input).unwrap().0.length()
      }
      entries.push({ sources: empty_capacity_sources(), consumers: [], })
    }
    materials.push(entries)
  }
  (materials, names)
}

///|
test "capacity Stage preparation shares budgets and retains source owners" {
  let prepared = prepared_local_source_fixture(third_stage=true)
  let (materials, names) = capacity_materials_fixture(prepared)
  let caps : CapacityStageLimits = {
    max_work: 10000000,
    max_text_bytes: 10000000,
    max_name_bytes: names,
    max_input_work: 0,
    max_operand_work: 0,
  }
  let checked = prepare_local_stage_contexts(
    prepared,
    materials,
    policy(),
    caps,
  ).unwrap()
  assert_true(
    physical_equal(
      stage_operations(checked),
      @stage_results.local_source_operations(prepared),
    ),
  )
  assert_true(
    physical_equal(
      stage_results(checked),
      @stage_results.local_source_results(prepared),
    ),
  )
  assert_true(stage_context_at(checked, 2) is Some(_))
  let exact : CapacityStageLimits = {
    ..caps,
    max_work: stage_usage(checked).0,
    max_text_bytes: stage_usage(checked).1,
  }
  assert_true(
    prepare_local_stage_contexts(prepared, materials, policy(), exact) is Ok(_),
  )
  assert_true(
    prepare_local_stage_contexts(prepared, materials, policy(), {
      ..exact,
      max_work: exact.max_work - 1,
    })
    is Err(_),
  )
  assert_true(
    prepare_local_stage_contexts(prepared, materials, policy(), {
      ..exact,
      max_text_bytes: exact.max_text_bytes - 1,
    })
    is Err(_),
  )
  assert_true(
    prepare_local_stage_contexts(prepared, materials, policy(), {
      ..exact,
      max_name_bytes: names - 1,
    })
    is Err(Capacity(_, _, Graph(BudgetExceeded))),
  )
  assert_true(
    prepare_local_stage_contexts(prepared, materials, policy(), {
      ..exact,
      max_input_work: -1,
    })
    is Err(InvalidLimits),
  )
  assert_true(
    prepare_local_stage_contexts(
      prepared,
      materials,
      policy(),
      exact,
      proof_owners=Some([[]]),
    )
    is Err(StageCount),
  )
  materials.clear()
  assert_true(stage_context_at(checked, 2) is Some(_))
}

///|
test "capacity Stage preparation rejects missing visits and invalid later consumers" {
  let prepared = prepared_local_source_fixture()
  let (materials, _) = capacity_materials_fixture(prepared)
  let caps : CapacityStageLimits = {
    max_work: 10000000,
    max_text_bytes: 10000000,
    max_name_bytes: 1000000,
    max_input_work: 1000000,
    max_operand_work: 1000000,
  }
  assert_true(
    prepare_local_stage_contexts(prepared, [materials[0]], policy(), caps)
    is Err(StageCount),
  )
  assert_true(
    prepare_local_stage_contexts(prepared, [materials[0], []], policy(), caps)
    is Err(VisitCount(1)),
  )
  let original = materials[1][0]
  materials[1][0] = {
    sources: original.sources,
    consumers: [@capacity.Join(step=0, output=0)],
  }
  assert_true(
    prepare_local_stage_contexts(prepared, materials, policy(), caps)
    is Err(Capacity(1, 0, Join(0, WrongOperation))),
  )
  materials[1][0] = original
  assert_true(
    prepare_local_stage_contexts(prepared, materials, policy(), caps) is Ok(_),
  )
}
