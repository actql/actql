///|
test "installed row basis preserves exact ordered key and recovery preimages" {
  let (preview, binding, _, _, _) = file_ordered_receipt_fixture()
  let scope = binding.scope
  let keys = recover_effect_preview_apply_keys(
    preview, scope, 1, 2, 1000, 256, 32, 8,
  ).unwrap()
  let request = "sha256:" + "c".repeat(64)
  let retention = "sha256:" + "d".repeat(64)
  let unit = "sha256:" + "e".repeat(64)
  let invocation = "sha256:" + "f".repeat(64)
  // The independent fixture keeps raw order B,A and execution order A,B.
  assert_eq(binding.key.cid, keys[0][1].cid)
  let row_cids = [
    "sha256:2bb1bd032e4791127080a468bbca5dc144371bcdfe39efe0bfc44132a8d7f7ac", "sha256:0426447180fcebf4aa8c57983b23050b177e74be6eabf33d1bdf07408cab5a50",
  ]
  for ordinal in 0..<row_cids.length() {
    let original = keys[0][1 - ordinal]
    let (locator, returned, basis) = retained_effect_application_row_basis(
      preview, scope, original, "ProgramOriginal", "UnitOriginal", unit, invocation,
      0, ordinal, request, retention, 64,
    ).unwrap()
    assert_true(physical_equal(returned, original))
    assert_eq(
      locator.item_correlation_wire,
      if ordinal == 0 {
        "\"A\""
      } else {
        "\"B\""
      },
    )
    assert_eq(basis.logical_item_locator_cid, locator.cid)
    assert_eq(basis.dispatch_key_cid, original.cid)
    assert_eq(basis.intent_fingerprint_cid, row_cids[ordinal])
    assert_eq(basis.canonical_request_cid, request)
    assert_eq(basis.retention_contract_cid, retention)
    assert_eq(basis.capability, "unavailable")
    assert_eq(basis.reservation_evidence_cid, "sha256:" + "a".repeat(64))
    // Same independently authored preimage as the existing Native control.
    assert_eq(
      basis.recovery_contract_cid,
      "sha256:8d268a8219c27f2d3c6eec3e91c1df28a0db9eb10bb134017f026123cce379c0",
    )
  }
  for
    (row, key, canonical) in [
      (0, keys[0][0], request),
      (2, keys[0][1], request),
      (0, keys[0][1], "invalid-request"),
    ] {
    assert_true(
      retained_effect_application_row_basis(
        preview, scope, key, "ProgramOriginal", "UnitOriginal", unit, invocation,
        0, row, canonical, retention, 64,
      )
      is Err(_),
    )
  }
}
