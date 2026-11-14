///|
fn original_129_finish(active : Execution) -> Poll raise {
  let mut last = active.work
  for _ in 0..<200000 {
    let polled = advance(active, 64).unwrap()
    let work = match polled {
      Continue(work~)
      | Complete(_, work~)
      | Failed(_, work~)
      | Stopped(work~)
      | Waiting(work~)
      | AwaitIo(work~)
      | Settling(_, work~) => work
    }
    assert_true(work >= last && work - last <= 64L)
    last = work
    if !(polled is Continue(..)) {
      return polled
    }
  }
  abort("129 actual fixture exceeded independent finite work ceiling")
}

///|
// Same real prepared129 inventory, configured Task/attempt/token policy and
// deterministic Core provider. No actual installed or real-LLM acceptance.
test "original same Model publication capacity issues all129 completed slots while legacy keeps128" {
  let (active, ledger, consumer, calls) = original_129_snapshot_fixture(
    durable_calls=false,
    token_reservation=65536L,
    duration_ms=129000L,
  )
  assert_true(original_129_finish(active) is Complete(_, ..))
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
  let refused = start_original_observation_issuance(active, small, limits)
  assert_true(refused is Err(Model(@model.Ledger(@resources.RetentionLimit))))
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

///|
test "cancelled129 retains pre-send proof funding until actual stopped traces and cleanup" {
  let (active, ledger, consumer, calls) = original_129_snapshot_fixture(
    durable_calls=false,
    token_reservation=65536L,
    duration_ms=129000L,
  )
  assert_eq(funded_stopped_attempt_count(active), None)
  for _ in 0..<200000 {
    if calls.val == 129 {
      break
    }
    guard advance(active, 1).unwrap() is Continue(..) else {
      abort("all actual129 provider entries must precede cancellation")
    }
  }
  assert_eq(calls.val, 129)
  assert_true(cancel(active))
  assert_true(original_129_finish(active) is Stopped(..))
  assert_eq(funded_stopped_attempt_count(active), Some(129))
  let retained = @resources.ledger_usage(ledger).reserved_retention_bytes
  for index in 0..<129 {
    let slot = stopped_attempt_slot(active, index).unwrap()
    finish_stopped_raw_usage_fixture(active, slot, 1) |> ignore
    let proof = attempt_evidence(active, slot).unwrap()
    assert_true(
      @publication.run_evidence_value_json(
        @model.model_attempt_accounting(proof),
      ).length() >
      0,
    )
  }
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, retained)
  assert_true(cleanup(active).unwrap())
  assert_eq(funded_stopped_attempt_count(active), None)
  assert_eq(calls.val, 129)
  original_composed_test_release(ledger, consumer)
}
