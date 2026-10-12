///|
// Actual Core transition AFTER an explicit trusted-journal boundary double.
// Physical SQLite/Store and FFI authentication have separate Node evidence.
test "original Model invalidation removes only resource fence during approval wait" {
  let (active, scope, _, _, _, _, ledger) = model_resource_park_test_start()
  require_model_call_entry(active).unwrap()
  assert_true(fixture_finish(active) is Waiting(..))
  prepared_call_set(active).unwrap() |> ignore
  assert_true(active.dispatch_admission is None)
  let park = park_original_model_resources(active, scope).unwrap()
  let before = @resources.ledger_usage(ledger)
  let quantity = @resources.quantity_usage(ledger)
  let work = active.work
  let request = begin_original_model_resource_invalidation(active, scope, park).unwrap()
  assert_true(begin_original_model_resource_invalidation(active, scope, park) is Err(_))
  assert_true(original_model_resource_invalidation_current(active, scope, park, request) is Some(same) && physical_equal(same, request))
  consume_original_model_resource_invalidation(active, scope, park, request).unwrap()
  assert_true(original_model_resource_park_current(active, scope, park) is None)
  assert_true(original_model_resource_invalidation_current(active, scope, park, request) is None)
  assert_true(consume_original_model_resource_invalidation(active, scope, park, request) is Err(_))
  assert_true(active.dispatch_admission is None)
  assert_eq(active.work, work)
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(@resources.quantity_usage(ledger), quantity)
}

///|
test "original Model invalidation rejects foreign and cancelled lifecycle without releasing park" {
  let (active, scope, _, _, _, _, ledger) = model_resource_park_test_start()
  require_model_call_entry(active).unwrap()
  assert_true(fixture_finish(active) is Waiting(..))
  prepared_call_set(active).unwrap() |> ignore
  let park = park_original_model_resources(active, scope).unwrap()
  let request = begin_original_model_resource_invalidation(active, scope, park).unwrap()
  let (other, foreign, _, _, _, _, _) = model_resource_park_test_start()
  let before = @resources.ledger_usage(ledger)
  assert_true(consume_original_model_resource_invalidation(other, foreign, park, request) is Err(_))
  assert_true(original_model_resource_invalidation_current(active, scope, park, request) is Some(_))
  // An Owner-local terminal observation cannot be replaced by a stale check.
  active.cancelled = true
  assert_true(consume_original_model_resource_invalidation(active, scope, park, request) is Err(_))
  assert_true(@publication_host.client_model_resource_invalidation_current(request, park, scope, active.run_binding.unwrap().compiled, active.run_binding.unwrap().definition, active.plan.unwrap()) is Some(_))
  assert_eq(@resources.ledger_usage(ledger), before)
}
