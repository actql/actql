///|
test "effect driver initialization retains its original method closures" {
  let original = effect_driver_construction_capacity().unwrap()
  assert_true(@execution.execution_capacity_retained_bytes(original) > 0L)
  assert_eq(
    @execution.execution_capacity_execution_bytes(original),
    @execution.execution_capacity_retained_bytes(original),
  )
}

///|
test "effect recovery Preview stays on the same temporary capture workspace" {
  let selected = effect_recovery_preview_construction_capacity(8192, 256, 12).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(selected), 0L)
  let parser = @decode.preserving_json_parser_construction_inventory(
    8192, 256, 12,
  ).unwrap()
  // This is a private constructor in addition to the original preserving
  // parser, with the SAME current tariff; no copied byte-price table.
  assert_true(
    @execution.execution_capacity_execution_bytes(selected) >
    @execution.preparation_representation_cost({
      record_headers: parser.record_headers,
      reference_slots: parser.reference_slots,
      scalar_words: parser.scalar_words,
      owned_utf16_units: parser.owned_utf16_units,
      owned_wire_bytes: 0L,
    }).unwrap(),
  )
  assert_true(effect_recovery_preview_construction_capacity(0, 256, 12) is None)
}

///|
test "effect request retains the constructed prefix before path refusal" {
  let body : @catalog.WriteBodyLimits = {
    max_bytes: 128,
    max_nodes: 32,
    max_depth: 8,
  }
  let request : @catalog.WriteRequestLimits = {
    max_path_bytes: 2048,
    max_target_bytes: 64,
    max_body_bytes: 128,
  }
  let accepted_path = effect_request_construction_capacity(
    body, request, 2, 12, 5, 14,
  ).unwrap()
  let refused_path = effect_request_construction_capacity(
    body,
    { ..request, max_path_bytes: 1, },
    2,
    12,
    5,
    14,
  ).unwrap()
  // The actual constructor concatenates API/resource prefix before checking
  // max_path_bytes. Refusal cannot reduce that already-live construction.
  assert_eq(
    @execution.execution_capacity_retained_bytes(accepted_path),
    @execution.execution_capacity_retained_bytes(refused_path),
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(accepted_path),
    @execution.execution_capacity_execution_bytes(refused_path),
  )
  let long_original = effect_request_construction_capacity(
    body, request, 2, 12, 5, 255,
  ).unwrap()
  assert_true(
    @execution.execution_capacity_execution_bytes(long_original) >
    @execution.execution_capacity_execution_bytes(refused_path),
  )
}

///|
test "effect target borrows field metadata and keeps preserving parser failure" {
  let limits : @catalog.TargetObservationLimits = {
    max_bytes: 128,
    max_nodes: 32,
    max_depth: 8,
    max_identity_bytes: 256,
  }
  let one = effect_target_construction_capacity(limits, 1).unwrap()
  let many = effect_target_construction_capacity(limits, 100).unwrap()
  // Sorted field references are temporary; output borrows the SAME original
  // request/Catalog and cannot retain100 independent metadata payloads.
  assert_eq(
    @execution.execution_capacity_retained_bytes(one),
    @execution.execution_capacity_retained_bytes(many),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(many) >
    @execution.execution_capacity_execution_bytes(one),
  )
  let parser = sf_initialization_decoded_construction(128, 32, 8, false).unwrap()
  assert_true(
    @execution.execution_capacity_execution_bytes(one) -
    @execution.execution_capacity_retained_bytes(one) >=
    @execution.preparation_representation_cost(parser).unwrap(),
  )
  // These are constructor refusals, never an absent/zero capacity success.
  assert_true(effect_target_construction_capacity(limits, 0) is None)
  assert_true(
    effect_target_construction_capacity({ ..limits, max_bytes: 0, }, 1) is None,
  )
}

///|
test "effect response retains provider data but borrows declared field metadata" {
  let limits : @catalog.WriteCollectionResponseLimits = {
    max_bytes: 128,
    max_nodes: 32,
    max_depth: 8,
    max_rows: 1,
  }
  let one = effect_response_construction_capacity(limits, 256, 1).unwrap()
  let many = effect_response_construction_capacity(limits, 256, 100).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(one),
    @execution.execution_capacity_retained_bytes(many),
  )
  assert_true(
    @execution.execution_capacity_execution_bytes(many) >
    @execution.execution_capacity_execution_bytes(one),
  )
  let parser = sf_initialization_decoded_construction(128, 32, 8, false).unwrap()
  assert_true(
    @execution.execution_capacity_execution_bytes(one) -
    @execution.execution_capacity_retained_bytes(one) >
    @execution.preparation_representation_cost(parser).unwrap(),
  )
  assert_true(effect_response_construction_capacity(limits, 0, 1) is None)
}
