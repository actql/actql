///|
test "independent comparison traversal shares eager null and RHS accounting" {
  let limits : @execution.FixedInputGuardMeasureLimits = {
    max_work: 4,
    max_bytes: 8,
    max_nodes: 4,
    max_depth: 1,
  }
  let value = prepare_comparison_measurement(comparison_operand("0"), 5, limits).unwrap()
  for
    operand in [
      comparison_operand("1"),
      comparison_operand("null"),
      comparison_operand("-1"),
    ] {
    append_comparison_measurement(value, operand).unwrap()
  }
  let usage = finish_comparison_measurement(value, 1).unwrap()
  assert_eq(usage.rows, 3)
  assert_eq(usage.field_bytes, 7L)
  assert_eq(usage.rhs_bytes, Some(1))
  assert_eq(usage.null_rows, 1)
  assert_eq(usage.false_rows, 1)
  assert_eq(usage.predicate_bytes, 13L)
  assert_eq(usage.physical_work, 4)
  assert_eq(usage.physical_bytes, 8)
  assert_true(finish_comparison_measurement(value, 1) is Err(InvalidState))
}

///|
test "empty comparisons demand no RHS and failed comparisons cannot be reused" {
  let limits : @execution.FixedInputGuardMeasureLimits = {
    max_work: 0,
    max_bytes: 0,
    max_nodes: 0,
    max_depth: 0,
  }
  let empty = prepare_comparison_measurement(
    comparison_operand("123456"),
    0,
    limits,
  ).unwrap()
  let usage = finish_comparison_measurement(empty, 0).unwrap()
  assert_eq(usage.rhs_bytes, None)
  assert_eq(usage.physical_work, 0)
  let failed = prepare_comparison_measurement(
    comparison_operand("0"),
    5,
    limits,
  ).unwrap()
  assert_true(
    append_comparison_measurement(failed, comparison_operand("1"))
    is Err(Operand(0, false, MeasurementWork)),
  )
  assert_true(finish_comparison_measurement(failed, 0) is Err(InvalidState))
  let predicate = prepare_comparison_measurement(comparison_operand("0"), 4, {
    max_work: 2,
    max_bytes: 2,
    max_nodes: 2,
    max_depth: 1,
  }).unwrap()
  append_comparison_measurement(predicate, comparison_operand("1")).unwrap()
  assert_true(
    finish_comparison_measurement(predicate, 0) is Err(Predicate(ValueBytes)),
  )
}

///|
fn comparison_operand(text : String) -> @admitted.Value {
  @admitted.admit(
    @contract.primitive(@contract.NumberType, nullable=true),
    payload(text),
    { max_nodes: 1, max_depth: 1, max_text_bytes: 0, },
  ).unwrap().value
}
