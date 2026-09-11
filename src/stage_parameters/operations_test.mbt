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
