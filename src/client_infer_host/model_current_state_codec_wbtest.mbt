///|
// Actual original Owners with synthetic allowances, not a physical byte policy.
test "Model current codec cannot finish before complete or for a foreign park" {
  let (active, scope, _, _, _, _, ledger) = model_resource_park_test_start()
  require_model_call_entry(active).unwrap()
  assert_true(fixture_finish(active) is Waiting(..))
  prepared_call_set(active).unwrap() |> ignore
  let park = park_original_model_resources_for_state_write(active, scope).unwrap()
  let value = prepare_original_model_current_state_writer(active, scope, park, 10000, 1000, 20).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_eq(finish_original_model_current_state_writer(active, scope, park, value), Err(@resources.Terminal))
  let (other, foreign, _, _, _, _, _) = model_resource_park_test_start()
  require_model_call_entry(other).unwrap()
  assert_true(fixture_finish(other) is Waiting(..))
  prepared_call_set(other).unwrap() |> ignore
  let other_park = park_original_model_resources(other, foreign).unwrap()
  assert_true(advance_original_model_current_state_writer(other, foreign, other_park, value, 1) is @resources.StateWriteFailed(@resources.Original(@resources.ChangedOriginalState), work=0))
  for index in 0..<19 {
    let poll = advance_original_model_current_state_writer(active, scope, park, value, 1)
    if index == 18 {
      assert_true(poll is @resources.StateWriteComplete(work=1))
    } else {
      assert_true(poll is @resources.StateWriteContinue(work=1))
    }
  }
  assert_true(finish_original_model_current_state_writer(other, foreign, other_park, value) is Err(@resources.Original(@resources.ChangedOriginalState)))
  let wire = finish_original_model_current_state_writer(active, scope, park, value).unwrap()
  assert_true(wire.contains("\"parked\""))
  assert_true(value.park is None && value.cursor is None && value.writer is None)
  assert_true(finish_original_model_current_state_writer(active, scope, park, value) is Err(_))
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(original_model_resource_park_current(active, scope, park) is Some(_))
}

///|
test "Model current codec bounded failure and cancel retain original park and spent work" {
  let (active, scope, _, _, _, _, ledger) = model_resource_park_test_start()
  require_model_call_entry(active).unwrap()
  assert_true(fixture_finish(active) is Waiting(..))
  prepared_call_set(active).unwrap() |> ignore
  let park = park_original_model_resources_for_state_write(active, scope).unwrap()
  let value = prepare_original_model_current_state_writer(active, scope, park, 1, 1000, 20).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(advance_original_model_current_state_writer(active, scope, park, value, 1) is @resources.StateWriteFailed(@resources.Encoding, work=1))
  assert_true(finish_original_model_current_state_writer(active, scope, park, value) is Err(@resources.Terminal))
  cancel_original_model_current_state_writer(value)
  cancel_original_model_current_state_writer(value)
  assert_true(value.park is None && value.cursor is None && value.writer is None)
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(original_model_resource_park_current(active, scope, park) is Some(_))
  assert_true(prepare_original_model_current_state_writer(active, scope, park, 10000, 1000, 20) is Err(@resources.Original(@resources.SpentClaim)))
}
