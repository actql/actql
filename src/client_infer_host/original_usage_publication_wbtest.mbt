///|
// Actual original Model/Read/Resource, with the existing synthetic provider.
// This establishes common ordering/custody, not physical Sink or normal I/O.
test "usage continuation holds same publication through record and pending child cleanup" {
  let (active, ledger, _) = original_observation_test_start()
  assert_true(fixture_finish(active) is Complete(_, ..))
  let capture = acquire_capture(active).unwrap()
  let capacity = reserve_original_infer_publication_capacity(active, 1L, 1L).unwrap()
  let usage = begin_original_infer_usage_publication(
    active, capacity, capture, 9L, 9L, 4096,
  ).unwrap()
  let quantities = @resources.quantity_usage(ledger)
  let retain = next_original_infer_usage_action(usage).unwrap().unwrap()
  assert_eq(@model.original_model_usage_action_kind(retain), Some("retain"))
  assert_false(release_original_infer_publication_capacity(capacity).unwrap())
  assert_true(
    next_original_infer_usage_action(usage) is Err(Model(@model.OutputIdentity)),
  )
  assert_true(
    observe_original_infer_usage_action(usage, retain, @model.Recorded)
    is Err(Model(@model.OutputIdentity)),
  )
  observe_original_infer_usage_action(usage, retain, @model.CopyRetained).unwrap()
  assert_true(
    observe_original_infer_usage_action(usage, retain, @model.CopyRetained)
    is Err(Model(@model.OutputIdentity)),
  )
  let authorize = next_original_infer_usage_action(usage).unwrap().unwrap()
  let slot_cid = @publication.run_evidence_value_identity(
    @model.verified_model_capture_call_at(capture, 0).unwrap(),
  )
  let attempt = @model.model_execution_attempt_evidence(
    active.model.unwrap(),
    0,
  ).unwrap()
  let attempt_cid = @publication.run_evidence_value_identity(
    @model.model_attempt_identity(attempt),
  )
  assert_false(
    original_infer_usage_binding_matches(usage, authorize, slot_cid, "foreign"),
  )
  assert_true(
    observe_original_infer_usage_action(usage, authorize, @model.Authorized)
    is Err(Model(@model.OutputIdentity)),
  )
  assert_true(
    original_infer_usage_binding_matches(
      usage, authorize, slot_cid, attempt_cid,
    ),
  )
  observe_original_infer_usage_action(usage, authorize, @model.Authorized).unwrap()
  let capture_action = next_original_infer_usage_action(usage).unwrap().unwrap()
  assert_eq(
    @model.original_model_usage_action_kind(capture_action),
    Some("capture"),
  )
  assert_true(
    @model.original_model_usage_action_wire(capture_action)
    .unwrap()
    .contains("input_tokens"),
  )
  observe_original_infer_usage_action(
    usage,
    capture_action,
    @model.CaptureComplete,
  ).unwrap()
  let record = next_original_infer_usage_action(usage).unwrap().unwrap()
  assert_eq(@model.original_model_usage_action_kind(record), Some("record"))
  assert_eq(original_infer_usage_completion(usage), @model.Complete)
  assert_eq(original_infer_usage_item_count(usage), 1)
  assert_false(release_original_infer_publication_capacity(capacity).unwrap())
  observe_original_infer_usage_action(usage, record, @model.Recorded).unwrap()
  let retire = next_original_infer_usage_action(usage).unwrap().unwrap()
  let before = @resources.ledger_usage(ledger)
  observe_original_infer_usage_action(usage, retire, @model.CleanupPending).unwrap()
  assert_false(release_original_infer_publication_capacity(capacity).unwrap())
  assert_eq(@resources.ledger_usage(ledger), before)
  observe_original_infer_usage_action(usage, retire, @model.CleanupComplete).unwrap()
  assert_true(next_original_infer_usage_action(usage).unwrap() is None)
  assert_eq(@resources.quantity_usage(ledger), quantities)
  assert_true(@model.release_verified_model_capture(capture))
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  assert_true(cleanup(active).unwrap())
}

///|
test "usage refusal and stop preserve same child without a capture or resend" {
  for adopted in [false, true] {
    let (active, ledger, _) = original_observation_test_start()
    assert_true(fixture_finish(active) is Complete(_, ..))
    let capture = acquire_capture(active).unwrap()
    let capacity = reserve_original_infer_publication_capacity(active, 1L, 1L).unwrap()
    let usage = begin_original_infer_usage_publication(
      active, capacity, capture, 9L, 9L, 4096,
    ).unwrap()
    let before = @resources.quantity_usage(ledger)
    let retain = next_original_infer_usage_action(usage).unwrap().unwrap()
    if adopted {
      observe_original_infer_usage_action(usage, retain, @model.CopyRetained).unwrap()
      let authorize = next_original_infer_usage_action(usage).unwrap().unwrap()
      stop_original_infer_usage_publication(usage)
      // Cancel is a request. It does not consume an outstanding callback.
      assert_false(
        release_original_infer_publication_capacity(capacity).unwrap(),
      )
      assert_true(
        next_original_infer_usage_action(usage)
        is Err(Model(@model.OutputIdentity)),
      )
      observe_original_infer_usage_action(
        usage,
        authorize,
        @model.CallbackFailed,
      ).unwrap()
    } else {
      observe_original_infer_usage_action(usage, retain, @model.CopyRefused).unwrap()
    }
    let retire = next_original_infer_usage_action(usage).unwrap().unwrap()
    assert_eq(@model.original_model_usage_action_kind(retire), Some("retire"))
    assert_eq(
      original_infer_usage_completion(usage),
      @model.RequiredUnavailable,
    )
    observe_original_infer_usage_action(usage, retire, @model.CleanupPending).unwrap()
    assert_false(release_original_infer_publication_capacity(capacity).unwrap())
    observe_original_infer_usage_action(usage, retire, @model.CleanupComplete).unwrap()
    assert_eq(@resources.quantity_usage(ledger), before)
    assert_true(@model.release_verified_model_capture(capture))
    assert_true(release_original_infer_publication_capacity(capacity).unwrap())
    assert_true(cleanup(active).unwrap())
  }
}

///|
test "usage None carrier reserves its structural reference before construction exact and one short" {
  // Independently: the added optional reference is 8 bytes on both existing
  // retained/execution axes. The supplied payload remains 1/1, hence 9/9.
  for
    (remaining_retained, remaining_execution) in [(9L, 9L), (8L, 9L), (9L, 8L)] {
    let (active, _, _, _, _, _, ledger) = model_resource_park_test_start(
      max_reservations=5,
    )
    assert_true(fixture_finish(active) is Complete(_, ..))
    let limits = @resources.ledger_limits(ledger)
    let before = @resources.ledger_usage(ledger)
    let filler = @resources.reserve_capacity(
      ledger,
      limits.retained_bytes -
      before.held_bytes -
      before.reserved_retention_bytes -
      remaining_retained,
      limits.execution_bytes -
      before.reserved_execution_bytes -
      remaining_execution,
    ).unwrap()
    let before = @resources.ledger_usage(ledger)
    let result = reserve_original_infer_publication_capacity(active, 1L, 1L)
    if remaining_retained == 9L && remaining_execution == 9L {
      let capacity = result.unwrap()
      assert_eq(@model.original_model_publication_retained_bytes(capacity), 9L)
      assert_eq(@model.original_model_publication_execution_bytes(capacity), 9L)
      assert_eq(
        @resources.ledger_usage(ledger).reserved_retention_bytes,
        before.reserved_retention_bytes + 9L,
      )
      assert_true(
        release_original_infer_publication_capacity(capacity).unwrap(),
      )
    } else {
      assert_true(result is Err(Model(@model.Ledger(_))))
      assert_eq(@resources.ledger_usage(ledger), before)
    }
    @resources.settle_capacity(ledger, filler).unwrap()
    assert_true(cleanup(active).unwrap())
  }
}

///|
test "usage continuation admission exact and one short precedes its action construction" {
  // Independent one-call census: original Host window 28H/136R/28W;
  // continuation/action/array/items/selection frames yield 41H/174R/56W.
  // Measuring retains its three scalars and one tuple. Use the existing
  // measuring-writer recipe, never a measured product return as the oracle.
  let writer = @encode.measuring_writer_construction_extent(7, 1).unwrap()
  let required = @relation.preparation_execution_capacity({
    retained: {
      record_headers: 42L,
      reference_slots: 174L,
      scalar_words: 59L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    workspace: {
      record_headers: writer.record_headers + 6L,
      reference_slots: writer.reference_slots + 8L,
      scalar_words: writer.scalar_words + 8L,
      owned_utf16_units: 40L,
      owned_wire_bytes: 0L,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  }).unwrap()
  let retained = @relation.execution_capacity_retained_bytes(required)
  let execution = @relation.execution_capacity_execution_bytes(required)
  for trial in [0, 1, 2] {
    let (active, ledger, _) = original_observation_test_start(
      spare_publication_slot=true,
    )
    assert_true(fixture_finish(active) is Complete(_, ..))
    let capture = acquire_capture(active).unwrap()
    let capacity = reserve_original_infer_publication_capacity(active, 1L, 1L).unwrap()
    let limits = @resources.ledger_limits(ledger)
    let before = @resources.ledger_usage(ledger)
    let filler = @resources.reserve_capacity(
      ledger,
      limits.retained_bytes -
      before.held_bytes -
      before.reserved_retention_bytes -
      retained +
      (if trial == 1 { 1L } else { 0L }),
      limits.execution_bytes -
      before.reserved_execution_bytes -
      execution +
      (if trial == 2 { 1L } else { 0L }),
    ).unwrap()
    let before = @resources.ledger_usage(ledger)
    let result = begin_original_infer_usage_publication(
      active, capacity, capture, 9L, 9L, 4096,
    )
    if trial == 0 {
      let value = result.unwrap()
      let action = next_original_infer_usage_action(value).unwrap().unwrap()
      observe_original_infer_usage_action(value, action, @model.CopyRefused).unwrap()
      let retire = next_original_infer_usage_action(value).unwrap().unwrap()
      observe_original_infer_usage_action(value, retire, @model.CleanupComplete).unwrap()
    } else {
      assert_true(result is Err(Model(@model.Ledger(_))))
      assert_eq(@resources.ledger_usage(ledger), before)
    }
    assert_true(@model.release_verified_model_capture(capture))
    assert_true(release_original_infer_publication_capacity(capacity).unwrap())
    @resources.settle_capacity(ledger, filler).unwrap()
    assert_true(cleanup(active).unwrap())
  }
}

///|
test "usage retirement returns original capacity after original Read revocation without a new grant" {
  let (active, ledger, consumer) = original_observation_test_start()
  assert_true(fixture_finish(active) is Complete(_, ..))
  let capture = acquire_capture(active).unwrap()
  let capacity = reserve_original_infer_publication_capacity(active, 1L, 1L).unwrap()
  let value = begin_original_infer_usage_publication(
    active, capacity, capture, 9L, 9L, 4096,
  ).unwrap()
  let retain = next_original_infer_usage_action(value).unwrap().unwrap()
  observe_original_infer_usage_action(value, retain, @model.CopyRetained).unwrap()
  let authorize = next_original_infer_usage_action(value).unwrap().unwrap()
  let before = @resources.quantity_usage(ledger)
  @publication_host.stop_client_model_read_consumer(consumer).unwrap()
  observe_original_infer_usage_action(value, authorize, @model.CallbackFailed).unwrap()
  let retire = next_original_infer_usage_action(value).unwrap().unwrap()
  assert_eq(@model.original_model_usage_action_kind(retire), Some("retire"))
  assert_eq(original_infer_usage_completion(value), @model.RequiredUnavailable)
  assert_false(release_original_infer_publication_capacity(capacity).unwrap())
  observe_original_infer_usage_action(value, retire, @model.CleanupComplete).unwrap()
  assert_true(@model.release_verified_model_capture(capture))
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  assert_eq(@resources.quantity_usage(ledger), before)
  assert_true(cleanup(active).unwrap())
}

///|
test "usage observation rejects a foreign original INFER child without retiring either owner" {
  let (first, ledger, _) = original_observation_test_start()
  let (second, other_ledger, _) = original_observation_test_start()
  assert_true(fixture_finish(first) is Complete(_, ..))
  assert_true(fixture_finish(second) is Complete(_, ..))
  let capture = acquire_capture(first).unwrap()
  let other_capture = acquire_capture(second).unwrap()
  let capacity = reserve_original_infer_publication_capacity(first, 1L, 1L).unwrap()
  let other_capacity = reserve_original_infer_publication_capacity(
    second, 1L, 1L,
  ).unwrap()
  let value = begin_original_infer_usage_publication(
    first, capacity, capture, 9L, 9L, 4096,
  ).unwrap()
  let other = begin_original_infer_usage_publication(
    second, other_capacity, other_capture, 9L, 9L, 4096,
  ).unwrap()
  let action = next_original_infer_usage_action(value).unwrap().unwrap()
  let before = @resources.ledger_usage(ledger)
  let before_other = @resources.ledger_usage(other_ledger)
  assert_true(
    observe_original_infer_usage_action(other, action, @model.CopyRetained)
    is Err(Model(@model.OutputIdentity)),
  )
  assert_eq(@resources.ledger_usage(ledger), before)
  assert_eq(@resources.ledger_usage(other_ledger), before_other)
  observe_original_infer_usage_action(value, action, @model.CopyRefused).unwrap()
  let action = next_original_infer_usage_action(other).unwrap().unwrap()
  observe_original_infer_usage_action(other, action, @model.CopyRefused).unwrap()
  for original in [value, other] {
    let retire = next_original_infer_usage_action(original).unwrap().unwrap()
    observe_original_infer_usage_action(
      original,
      retire,
      @model.CleanupComplete,
    ).unwrap()
  }
  assert_true(@model.release_verified_model_capture(capture))
  assert_true(@model.release_verified_model_capture(other_capture))
  assert_true(release_original_infer_publication_capacity(capacity).unwrap())
  assert_true(
    release_original_infer_publication_capacity(other_capacity).unwrap(),
  )
  assert_true(cleanup(first).unwrap())
  assert_true(cleanup(second).unwrap())
}
