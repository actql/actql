///|
test "all stage operation references share collection and indexing budgets" {
  let s = prepared(parsed())
  let a = checked(s, 0, Some(declarations(s)))
  let b = checked(s, 1, Some(declarations(s)))
  let pipelines = [a, b]
  let value = collect_operations(s, pipelines, caps()).unwrap()
  assert_true(physical_equal(operations_source(value), s))
  let refs = operations_index(value)
  assert_true(physical_equal(@references.declarations(refs), declarations(s)))
  assert_eq(@references.reference_count(refs), 2)
  assert_eq(
    @references.reference_at(refs, 0).unwrap().path,
    "/stages/0/steps/0/take",
  )
  assert_eq(
    @references.reference_at(refs, 1).unwrap().path,
    "/stages/1/steps/0/take",
  )
  let local_a = @collection.index(
    collection(operations_stage_at(value, 0).unwrap()),
  )
  let local_b = @collection.index(
    collection(operations_stage_at(value, 1).unwrap()),
  )
  assert_eq(@references.reference_at(local_a, 0).unwrap().path, "/steps/0/take")
  assert_eq(@references.reference_at(local_b, 0).unwrap().path, "/steps/0/take")
  let usage = operations_usage(value)
  assert_eq(usage.slots, 2)
  assert_eq(usage.references, 2)
  assert_eq(
    usage.pointer_units,
    @references.pointer_units(refs) +
    @references.pointer_units(local_a) +
    @references.pointer_units(local_b),
  )
  let exact : @collection.Limits = {
    max_work: usage.work,
    max_slots: usage.slots,
    max_references: usage.references,
    max_pointer_units: usage.pointer_units,
    max_direct_text_bytes: usage.direct_text_bytes,
  }
  assert_true(collect_operations(s, pipelines, exact) is Ok(_))
  for
    limit in [
      { ..exact, max_work: exact.max_work - 1, },
      { ..exact, max_slots: exact.max_slots - 1, },
      { ..exact, max_references: exact.max_references - 1, },
      { ..exact, max_pointer_units: exact.max_pointer_units - 1, },
      { ..exact, max_direct_text_bytes: exact.max_direct_text_bytes - 1, },
    ] {
    assert_true(collect_operations(s, pipelines, limit) is Err(_))
  }
  // Changing the registration array cannot rewrite a completed collection.
  pipelines[0] = b
  assert_true(
    physical_equal(
      @collection.pipeline(collection(operations_stage_at(value, 0).unwrap())),
      a,
    ),
  )
  assert_true(operations_stage_at(value, -1) is None)
  assert_true(operations_stage_at(value, 2) is None)
}

///|
test "all-stage collection rejects missing repeated and reordered registrations" {
  let s = prepared(parsed())
  let a = checked(s, 0, Some(declarations(s)))
  let b = checked(s, 1, Some(declarations(s)))
  assert_true(collect_operations(s, [a], caps()) is Err(PipelineCountMismatch))
  assert_true(
    collect_operations(s, [a, b, a], caps()) is Err(PipelineCountMismatch),
  )
  assert_true(
    collect_operations(s, [a, a], caps()) is Err(Stage(1, ForeignSteps)),
  )
  assert_true(
    collect_operations(s, [b, a], caps()) is Err(Stage(0, ForeignSteps)),
  )
  for
    limit in [
      { ..caps(), max_work: -1, },
      { ..caps(), max_slots: -1, },
      { ..caps(), max_references: -1, },
      { ..caps(), max_pointer_units: -1, },
      { ..caps(), max_direct_text_bytes: -1, },
    ] {
    assert_true(collect_operations(s, [a, b], limit) is Err(InvalidLimits))
  }
}

///|
test "prepared operation collection retains stage owners without re-admitting references" {
  let source = prepared(parsed())
  let pipelines = [
    checked(source, 0, Some(declarations(source))),
    checked(source, 1, Some(declarations(source))),
  ]
  let original = collect_operations(source, pipelines, caps()).unwrap()
  let stages = [
    operations_stage_at(original, 0).unwrap(),
    operations_stage_at(original, 1).unwrap(),
  ]
  let used = operations_usage(original)
  let exact : @collection.Limits = {
    max_work: used.work,
    max_slots: used.slots,
    max_references: used.references,
    max_pointer_units: used.pointer_units,
    max_direct_text_bytes: used.direct_text_bytes,
  }
  let collected = collect_prepared_operations(source, stages, exact).unwrap()
  assert_eq(operations_usage(collected), used)
  for i in 0..<2 {
    assert_true(
      physical_equal(operations_stage_at(collected, i).unwrap(), stages[i]),
    )
    assert_eq(
      @references.reference_at(operations_index(collected), i).unwrap().path,
      @references.reference_at(operations_index(original), i).unwrap().path,
    )
  }
  for
    cap in [
      { ..exact, max_work: used.work - 1, },
      { ..exact, max_slots: used.slots - 1, },
      { ..exact, max_references: used.references - 1, },
      { ..exact, max_pointer_units: used.pointer_units - 1, },
      { ..exact, max_direct_text_bytes: used.direct_text_bytes - 1, },
    ] {
    assert_true(collect_prepared_operations(source, stages, cap) is Err(_))
  }
  assert_true(
    collect_prepared_operations(source, [stages[0]], caps())
    is Err(PipelineCountMismatch),
  )
  assert_true(
    collect_prepared_operations(source, [stages[1], stages[0]], caps())
    is Err(ForeignStage(0)),
  )
  assert_true(
    collect_prepared_operations(source, [stages[0], stages[0]], caps())
    is Err(ForeignStage(1)),
  )
  assert_true(
    collect_prepared_operations(prepared(parsed()), stages, caps())
    is Err(ForeignStage(0)),
  )
  assert_true(
    collect_prepared_operations(source, stages, { ..exact, max_work: -1, })
    is Err(InvalidLimits),
  )
  stages.clear()
  assert_true(operations_stage_at(collected, 1) is Some(_))
}
