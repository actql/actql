///|
test "Effect apply checks exact selected route and failure policy" {
  let a = preview_footprint_test_cid("a")
  let authoring = "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a"
  let scope = prepare_logical_request_scope(a, "request-1", 32).unwrap()
  let (halt_wire, _) = preview_apply_test_wire(scope, "halt")
  let halt = @publication.admit_effect_preview_identity(
    halt_wire, a, authoring, 8192, 256, 12,
  ).unwrap()
  let single = prepare_effect_apply_capability_observation(
    a,
    SingleSerial,
    PerItem,
    PerItemFailure,
    true,
    true,
    UnavailableIdempotency,
    ManualReconciliation,
  ).unwrap()
  assert_eq(effect_apply_capability_idempotency_mode(single), "unavailable")
  assert_eq(effect_apply_capability_reconciliation_mode(single), "manual")
  assert_true(
    check_effect_preview_apply_capabilities(halt, [single], 1, 1) is Ok(_),
  )
  let collection = prepare_effect_apply_capability_observation(
    a,
    CollectionContinue,
    PerItem,
    PerItemFailure,
    true,
    true,
    UnavailableIdempotency,
    ManualReconciliation,
  ).unwrap()
  assert_true(
    check_effect_preview_apply_capabilities(halt, [collection], 1, 1)
    is Err(UnsupportedPolicy(0)),
  )
  let (continue_wire, _) = preview_apply_test_wire(scope, "continue")
  let continued = @publication.admit_effect_preview_identity(
    continue_wire, a, authoring, 8192, 256, 12,
  ).unwrap()
  assert_true(
    check_effect_preview_apply_capabilities(continued, [collection], 1, 1)
    is Ok(_),
  )
  assert_true(
    check_effect_preview_apply_capabilities(continued, [], 1, 1)
    is Err(InventoryMismatch),
  )
  let foreign = prepare_effect_apply_capability_observation(
    preview_footprint_test_cid("b"),
    SingleSerial,
    PerItem,
    PerItemFailure,
    true,
    true,
    UnavailableIdempotency,
    ManualReconciliation,
  ).unwrap()
  assert_true(
    check_effect_preview_apply_capabilities(halt, [foreign], 1, 1)
    is Err(ForeignEvidence(0)),
  )
  let unknown = prepare_effect_apply_capability_observation(
    a,
    SingleSerial,
    PerItem,
    PerItemFailure,
    true,
    true,
    UnavailableIdempotency,
    NoReconciliation,
  ).unwrap()
  assert_true(
    check_effect_preview_apply_capabilities(halt, [unknown], 1, 1)
    is Err(UnknownWithoutReconciliation(0)),
  )
  let batch_atomic = prepare_effect_apply_capability_observation(
    a,
    CollectionContinue,
    ProviderBatchAtomic,
    PerItemFailure,
    true,
    true,
    UnavailableIdempotency,
    ManualReconciliation,
  ).unwrap()
  assert_true(
    check_effect_preview_apply_capabilities(continued, [batch_atomic], 1, 1)
    is Err(UnsupportedPolicy(0)),
  )
  let no_row_identity = prepare_effect_apply_capability_observation(
    a,
    CollectionContinue,
    PerItem,
    PerItemFailure,
    false,
    true,
    UnavailableIdempotency,
    ManualReconciliation,
  ).unwrap()
  assert_true(
    check_effect_preview_apply_capabilities(continued, [no_row_identity], 1, 1)
    is Err(UnsupportedPolicy(0)),
  )
  let unordered = prepare_effect_apply_capability_observation(
    a,
    SingleSerial,
    PerItem,
    PerItemFailure,
    true,
    false,
    UnavailableIdempotency,
    ManualReconciliation,
  ).unwrap()
  assert_true(
    check_effect_preview_apply_capabilities(halt, [unordered], 1, 1)
    is Err(UnsupportedPolicy(0)),
  )
  let whole_request = prepare_effect_apply_capability_observation(
    a,
    CollectionContinue,
    PerItem,
    WholeRequestFailure,
    true,
    true,
    UnavailableIdempotency,
    ManualReconciliation,
  ).unwrap()
  assert_true(
    check_effect_preview_apply_capabilities(continued, [whole_request], 1, 1)
    is Err(UnsupportedPolicy(0)),
  )
  assert_true(
    prepare_effect_apply_capability_from_codes(a, 0, 0, 0, true, true, 3, 1)
    is Err(InvalidCode),
  )
  assert_true(
    check_effect_preview_apply_capabilities(halt, [single], 1, 0)
    is Err(InvalidLimits),
  )
}
