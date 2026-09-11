///|
test "aggregate consumers retain their own filter root including equal predicates" {
  let p = join_pipeline(
    (
      #|[{"derive":{"v":"amount"},"from":"l"},{"group":{"by":["id"],"aggregates":{"a":{"fn":"sum","expr":"amount","filter":"amount > 0"},"b~/":{"fn":"sum","expr":"amount","filter":"amount > 0"},"c":{"fn":"count","filter":"amount > 0"}}}}]
    ),
  ).unwrap()
  let slots = collect_expression_slots(p, max_work=100, max_slots=100).unwrap()
  assert_eq(expression_slot_count(slots), 6)
  assert_eq(
    expression_slot_at(slots, 0).unwrap().consumer,
    DerivedField("v", None),
  )
  for (base, name) in [(1, "a"), (3, "b~/")] {
    let filter = expression_slot_at(slots, base).unwrap()
    let argument = expression_slot_at(slots, base + 1).unwrap()
    assert_eq(filter.consumer, AggregateFilter(name))
    assert_eq(argument.consumer, AggregateArgument(name))
    assert_true(filter.filter is None)
    let dependency = argument.filter.unwrap()
    assert_eq(dependency.slot, base)
    assert_eq(filter.step, argument.step)
    assert_true(physical_equal(dependency.expression, filter.expression))
    assert_false(physical_equal(dependency.expression, argument.expression))
  }
  let last = expression_slot_at(slots, 5).unwrap()
  assert_eq(last.consumer, AggregateFilter("c"))
  assert_true(last.filter is None)
  let exact = expression_slots_work(slots)
  assert_true(collect_expression_slots(p, max_work=exact, max_slots=6) is Ok(_))
  assert_true(
    collect_expression_slots(p, max_work=exact - 1, max_slots=6)
    is Err(WorkLimit),
  )
  assert_true(
    collect_expression_slots(p, max_work=exact, max_slots=5) is Err(SlotLimit),
  )
}

///|
test "analytic and ordered derive consumers preserve distinct evaluation scopes" {
  let p = join_pipeline(
    (
      #|[{"derive":[{"x":"amount"},{"y":"x + 1"}],"from":"l"},{"analytic":{"partition_by":[],"order_by":[{"id":"asc"}],"frame":{"start":"current_row","end":"current_row"},"functions":{"a":{"fn":"sum","expr":"amount","filter":"amount > 0"},"b":{"fn":"lag","expr":"amount"},"c":{"fn":"rank"}}}}]
    ),
  ).unwrap()
  let slots = collect_expression_slots(p, max_work=100, max_slots=100).unwrap()
  assert_eq(expression_slot_count(slots), 5)
  assert_eq(
    expression_slot_at(slots, 0).unwrap().consumer,
    DerivedField("x", Some(0)),
  )
  assert_eq(
    expression_slot_at(slots, 1).unwrap().consumer,
    DerivedField("y", Some(1)),
  )
  let filter = expression_slot_at(slots, 2).unwrap()
  let argument = expression_slot_at(slots, 3).unwrap()
  assert_eq(filter.consumer, AnalyticFilter("a"))
  assert_eq(argument.consumer, AnalyticArgument("a"))
  assert_eq(argument.filter.unwrap().slot, 2)
  assert_true(
    physical_equal(argument.filter.unwrap().expression, filter.expression),
  )
  let lag = expression_slot_at(slots, 4).unwrap()
  assert_eq(lag.consumer, AnalyticArgument("b"))
  assert_true(lag.filter is None)
  let p = join_pipeline(
    (
      #|[{"filter":"amount > 0","from":"l"},{"assert_rows":{"where":"amount > 0"}}]
    ),
  ).unwrap()
  let slots = collect_expression_slots(p, max_work=4, max_slots=2).unwrap()
  assert_eq(expression_slot_at(slots, 0).unwrap().consumer, RowFilter)
  assert_eq(expression_slot_at(slots, 1).unwrap().consumer, RowAssertion)
}
