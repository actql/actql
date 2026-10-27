///|
test "Parameter quantity stack is funded before observation and same-parent retry retains original facts" {
  let root = funded_parameter_cursor("{\"x\":{\"type\":\"number\"}}")
  let ledger = @resources.create_ledger({
    planning_work: 7,
    attempts: 2,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 21461L,
    execution_bytes: 21479L,
  }).unwrap()
  let input = ["original quantity stack"]
  let capacity : @resources.PreparationCapacity[Array[String], Array[Int]] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    73L,
    91L,
    max_borrowers=1,
  ).unwrap()
  let owner = begin_parameter_declaration_preflight(
    capacity,
    input,
    Some(root),
    funded_parameter_limits(),
  ).unwrap()
  assert_eq(parameter_preflight_initial_bytes, 11816L)
  prepare_parameter_declaration_preflight(owner).unwrap()
  let original = parameter_declaration_preflight_outcome(owner)
  let reader = original.unwrap().0.unwrap()
  reconcile_parameter_declaration_preflight(owner).unwrap()
  prepare_parameter_declaration_header(owner).unwrap()
  assert_eq(owner.body_bytes, 1808L)
  let cursor = @parameters.declaration_read_type_cursor(reader)
  assert_true(@parameters.declaration_read_construction_work(reader) is None)
  assert_eq(parameter_inventory_construction_bytes(3, 1), Some((616L, 1080L)))
  let sibling = @resources.reserve_capacity(ledger, 6069L, 6069L).unwrap()
  assert_true(
    prepare_parameter_declaration_inventory(owner)
    is Err(Capacity(Resource(RetentionLimit))),
  )
  assert_true(owner.phase == InventoryQuoted)
  assert_true(@parameters.declaration_read_construction_work(reader) is None)
  assert_true(@parameters.declaration_read_current_construction(reader) is None)
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((14385L, 14403L)),
  )
  let quote = owner.quote.unwrap()
  assert_eq(quote, (15393L, 15411L))
  @resources.settle_capacity(ledger, sibling).unwrap()
  prepare_parameter_declaration_inventory(owner).unwrap()
  assert_true(physical_equal(quote, owner.quote.unwrap()))
  assert_true(
    physical_equal(original, parameter_declaration_preflight_outcome(owner)),
  )
  assert_true(
    physical_equal(cursor, @parameters.declaration_read_type_cursor(reader)),
  )
  let work = @parameters.declaration_read_construction_work(reader)
  assert_eq(work, Some(12L))
  let facts = @parameters.declaration_read_current_construction(reader)
  assert_eq(facts.unwrap().type_syntax.types, 1)
  assert_true(facts.unwrap().default_value is None)
  assert_eq(
    @parameters.declaration_read_phase(reader),
    @parameters.DeclarationType,
  )
  assert_true(@parameters.declaration_read_pending_syntax(reader) is None)
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((15393L, 15411L)),
  )
  reconcile_parameter_declaration_inventory(owner).unwrap()
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((14313L, 14331L)),
  )
  assert_true(
    physical_equal(work, @parameters.declaration_read_construction_work(reader)),
  )
  assert_true(
    physical_equal(
      work,
      @parameters.observe_declaration_read_construction(reader),
    ),
  )
  assert_true(
    physical_equal(
      facts,
      @parameters.declaration_read_current_construction(reader),
    ),
  )
  assert_true(prepare_parameter_declaration_inventory(owner) is Err(WrongPhase))
  assert_true(
    reconcile_parameter_declaration_inventory(owner) is Err(WrongPhase),
  )
  clear_parameter_declaration_preflight(owner).unwrap()
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok((14313L, 14331L)),
  )
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
}
