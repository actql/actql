///|
test "original unparked covers keeps approval wait legitimate and rejects new park" {
  let (active, scope, _, _, _, _, ledger) = model_resource_park_test_start()
  assert_false(
    original_model_unparked_read_capacity_available(active, scope, 7L, 5L),
  )
  require_model_call_entry(active).unwrap()
  assert_true(fixture_finish(active) is Waiting(..))
  prepared_call_set(active).unwrap() |> ignore
  assert_true(active.dispatch_admission is None)
  let before = @resources.ledger_usage(ledger)
  let work = active.work
  assert_true(
    original_model_unparked_read_capacity_available(active, scope, 7L, 5L),
  )
  assert_false(
    original_model_unparked_read_capacity_available(active, scope, 8L, 5L),
  )
  assert_false(
    original_model_unparked_read_capacity_available(active, scope, 7L, 6L),
  )
  let (_, foreign, _, _, _, _, _) = model_resource_park_test_start()
  assert_false(
    original_model_unparked_read_capacity_available(active, foreign, 7L, 5L),
  )
  let park = park_original_model_resources(active, scope).unwrap()
  assert_false(
    original_model_unparked_read_capacity_available(active, scope, 7L, 5L),
  )
  assert_true(
    original_model_parked_read_capacity_available(active, scope, park, 7L, 5L),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(active.work, work)
  assert_true(active.dispatch_admission is None)
}
