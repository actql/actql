///|
// Same real prepared129 inventory, configured Task/attempt/token policy and
// deterministic Core provider. No actual installed or real-LLM acceptance.
test "original same Model publication capacity issues all129 completed slots while legacy keeps128" {
  let (active, ledger, consumer, calls) = original_129_snapshot_fixture(
    durable_calls=false,
    token_reservation=65536L,
    duration_ms=129000L,
  )
  assert_true(
    fixture_finish(active, initial_work=active.work) is Complete(_, ..),
  )
  assert_eq(calls.val, 129)
  let capture = acquire_capture(active).unwrap()
  assert_eq(@model.verified_model_capture_call_count(capture), Some(129))
  @model.release_verified_model_capture(capture) |> ignore
  let limits : ObservationIssuanceLimits = {
    max_slots: 129,
    max_wire_bytes: 16384,
    max_work: 131,
  }
  let legacy = issuance_ledger(1048576L, work=1000)
  let before = @resources.ledger_usage(legacy)
  assert_true(
    start_observation_issuance(active, legacy, limits) is Err(InvalidAdvance),
  )
  assert_eq(@resources.ledger_usage(legacy), before)
  let required = original_observation_issuance_metadata_bytes(active, limits).unwrap()
  let small = reserve_original_infer_publication_capacity(
    active,
    required - 1L,
    0L,
  ).unwrap()
  assert_true(
    start_original_observation_issuance(active, small, limits)
    is Err(Model(@model.Ledger(@resources.RetentionLimit))),
  )
  assert_true(release_original_infer_publication_capacity(small).unwrap())
  let capacity = reserve_original_infer_publication_capacity(
    active, required, 0L,
  ).unwrap()
  let issued = start_original_observation_issuance(active, capacity, limits).unwrap()
  assert_false(cleanup(active).unwrap())
  issuance_finish(issued)
  assert_eq(
    @publication.model_observation_slot_count(
      observation_issuance_value(issued).unwrap().0,
    ),
    Some(129),
  )
  assert_true(cleanup_observation_issuance(issued).unwrap())
  assert_false(cleanup(active).unwrap())
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  assert_true(cleanup(active).unwrap())
  original_composed_test_release(ledger, consumer)
}
