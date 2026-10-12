///|
// Real same-Owner/token predicate with synthetic allowances, not a physical
// envelope supplier. Repeated observation must not reserve, mutate or grant.
test "Model parked read capacity keeps original reservation and approval None" {
  let (active, scope, _, _, _, _, ledger) = model_resource_park_test_start()
  require_model_call_entry(active).unwrap()
  assert_true(fixture_finish(active) is Waiting(..))
  prepared_call_set(active).unwrap() |> ignore
  let park = park_original_model_resources(active, scope).unwrap()
  let before = @resources.ledger_usage(ledger)
  let quantities = @resources.quantity_usage(ledger)
  let work = active.work
  assert_true(active.dispatch_admission is None)
  for _ in 0..<2 {
    assert_true(
      original_model_parked_read_capacity_available(active, scope, park, 7L, 5L),
    )
    assert_false(
      original_model_parked_read_capacity_available(active, scope, park, 8L, 5L),
    )
    assert_false(
      original_model_parked_read_capacity_available(active, scope, park, 7L, 6L),
    )
    assert_false(
      original_model_parked_read_capacity_available(
        active, scope, park, -1L, 5L,
      ),
    )
  }
  let (foreign, other, _, _, _, _, _) = model_resource_park_test_start()
  assert_false(
    original_model_parked_read_capacity_available(active, other, park, 7L, 5L),
  )
  assert_false(
    original_model_parked_read_capacity_available(foreign, scope, park, 7L, 5L),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(@resources.quantity_usage(ledger), quantities)
  assert_eq(active.work, work)
  assert_true(active.dispatch_admission is None)
  assert_true(
    original_model_resource_park_current(active, scope, park) is Some(_),
  )
}
