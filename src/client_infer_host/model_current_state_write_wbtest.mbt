///|
// Actual original Model and Resource owners with synthetic fixture allowances.
// Writer completion does not prove Store ACK, COMMIT, unpark or public funding.
test "original Model current Writer precharges same census without advancing Model" {
  let (active, scope, _, _, _, _, ledger) = model_resource_park_test_start()
  require_model_call_entry(active).unwrap()
  assert_true(fixture_finish(active) is Waiting(..))
  prepared_call_set(active).unwrap() |> ignore
  let model_work = active.work
  let before = @resources.ledger_usage(ledger)
  assert_eq(before.attempts, 0)
  assert_eq(before.reserved_attempts, 1)
  let quantities = @resources.quantity_usage(ledger)
  let park = park_original_model_resources_for_state_write(active, scope).unwrap()
  let charged = @resources.ledger_usage(ledger)
  // Original read + handed-off Model capacity + the one attempt reserved by
  // ReserveSlots before DispatchSlot: 16 + 3 blocks, no holdings/delegations.
  assert_eq(charged.planning_work - before.planning_work, 19)
  let writer = @encode.writer(10000, 1000, 20)
  let cursor = start_original_model_current_state_write(
    active, scope, park, writer,
  ).unwrap()
  let mut work = 0
  let mut complete = false
  for _ in 0..<19 {
    match
      advance_original_model_current_state_write(active, scope, park, cursor, 1) {
      @resources.StateWriteContinue(work=spent) => work += spent
      @resources.StateWriteComplete(work=spent) => {
        work += spent
        complete = true
      }
      _ => abort("original current-census Writer unexpectedly refused")
    }
  }
  assert_true(complete)
  assert_eq(work, 19)
  assert_eq(active.work, model_work)
  assert_eq(@resources.ledger_usage(ledger), charged)
  assert_eq(@resources.quantity_usage(ledger), quantities)
  assert_true(@encode.finish(writer).contains("\"parked\""))
  assert_true(
    original_model_resource_park_current(active, scope, park) is Some(_),
  )
  assert_true(
    start_original_model_current_state_write(
      active,
      scope,
      park,
      @encode.writer(10000, 1000, 20),
    )
    is Err(@resources.Original(@resources.SpentClaim)),
  )
}

///|
test "original Model current Writer refuses an ordinary or foreign park before progress" {
  let (active, scope, _, _, _, _, ledger) = model_resource_park_test_start()
  require_model_call_entry(active).unwrap()
  assert_true(fixture_finish(active) is Waiting(..))
  prepared_call_set(active).unwrap() |> ignore
  let ordinary = park_original_model_resources(active, scope).unwrap()
  let before = @resources.ledger_usage(ledger)
  let writer = @encode.writer(10000, 1000, 20)
  assert_true(
    start_original_model_current_state_write(active, scope, ordinary, writer)
    is Err(@resources.Original(@resources.SpentClaim)),
  )
  let (other, foreign, _, _, _, _, _) = model_resource_park_test_start()
  assert_true(
    start_original_model_current_state_write(other, foreign, ordinary, writer)
    is Err(@resources.Original(@resources.ChangedOriginalState)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_true(
    original_model_resource_park_current(active, scope, ordinary) is Some(_),
  )
  @encode.cancel_writer(writer)
}
