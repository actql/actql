///|
test "expression requirements keep the owning aggregate filter even without filter obligations" {
  let p = base(
    true,
    steps=(
      #|[{"group":{"by":["id"],"aggregates":{"v":{"fn":"sum","expr":"try_number('1')","filter":"id > 0"}}}}]
    ),
  )
  let checked = check(results(p), [None], [capacity(p)], policy(), {
    ..limits(),
    max_steps: 10,
  }).unwrap()
  assert_eq(expression_requirement_count(checked), 2)
  let slots = @pipeline.collect_expression_slots(p, max_work=100, max_slots=100).unwrap()
  assert_eq(@pipeline.expression_slot_count(slots), 2)
  let filter = @pipeline.expression_slot_at(slots, 0).unwrap()
  for i in 0..<2 {
    let requirement = expression_requirement_at(checked, i).unwrap()
    assert_eq(requirement.consumer, @pipeline.AggregateArgument("v"))
    assert_eq(requirement.slot, 1)
    assert_eq(requirement.filter.unwrap().slot, 0)
    assert_true(
      physical_equal(requirement.filter.unwrap().expression, filter.expression),
    )
    assert_eq(@typing.pending_validation_count(filter.expression), 0)
  }
}
