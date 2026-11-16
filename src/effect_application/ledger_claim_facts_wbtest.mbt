///|
fn claim_facts_fixture(
  capability : String,
) -> (
  LogicalRequestScope,
  LogicalItemLocator,
  EffectDispatchKey,
  EffectLedgerBasis,
) {
  let scope = prepare_logical_request_scope(
    ledger_test_cid("a"),
    "request-1",
    32,
  ).unwrap()
  let key = prepare_effect_dispatch_key(
    scope,
    ledger_test_cid("b"),
    "\"row-1\"",
    32,
    8,
    3,
  ).unwrap()
  let locator = prepare_logical_item_locator(
    scope, "program-1", "node-1", "WriteOne", "{\"row\":\"record-1\"}", 64, 128,
    8, 3,
  ).unwrap()
  let basis = prepare_effect_ledger_basis(
    scope,
    locator,
    key,
    ledger_test_cid("c"),
    ledger_test_cid("d"),
    ledger_test_cid("e"),
    ledger_test_cid("f"),
    ledger_test_cid("0"),
    capability,
    ledger_test_cid("1"),
    ledger_test_cid("2"),
  ).unwrap()
  (scope, locator, key, basis)
}

///|
fn legacy_claim_facts_match(
  basis : EffectLedgerBasis,
  scope : LogicalRequestScope,
  locator : LogicalItemLocator,
  key : EffectDispatchKey,
  intent : String,
  request : String,
  expected_scope : String,
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> Bool? {
  let prepared = match
    issue_prepared_effect_ledger_entry(basis, bytes, nodes, depth) {
    Ok(value) => value
    Err(_) => return None
  }
  let dispatching = match
    issue_next_effect_ledger_entry(
      prepared,
      "dispatching",
      None,
      bytes,
      nodes,
      depth,
    ) {
    Ok(value) => value
    Err(_) => return None
  }
  Some(
    effect_ledger_entry_scope_cid(prepared) == expected_scope &&
    effect_ledger_entry_admits_dispatch(
      dispatching, scope, locator, key, request,
    ) &&
    effect_row_recovery_action_from_entry(
      locator,
      intent,
      key,
      request,
      Some(prepared),
      false,
    ) ==
    1,
  )
}

///|
test "pure claim facts retain independent closed codec boundaries and actual legacy identities" {
  // Independent 0.1 geometry: nineteen scalar fields plus root; no escaped
  // CID or capability text. These are public wire bounds, not body snapshots.
  for
    (capability, prepared_bytes, dispatch_bytes) in [
      ("native", 1334, 1406),
      ("stamped", 1335, 1407),
      ("natural_key", 1339, 1411),
      ("unavailable", 1339, 1411),
    ] {
    let (scope, locator, key, basis) = claim_facts_fixture(capability)
    let expected_scope = logical_request_scope_cid(scope)
    let prepared = issue_prepared_effect_ledger_entry(
      basis, prepared_bytes, 20, 1,
    ).unwrap()
    let dispatching = issue_next_effect_ledger_entry(
      prepared,
      "dispatching",
      None,
      dispatch_bytes,
      20,
      1,
    ).unwrap()
    assert_eq(effect_ledger_entry_wire(prepared).length(), prepared_bytes)
    assert_eq(effect_ledger_entry_wire(dispatching).length(), dispatch_bytes)
    if capability == "unavailable" {
      // Existing independent prepared identity from the issuance vector.
      assert_eq(
        effect_ledger_entry_cid(prepared),
        "sha256:09517d06658bcea4c679a029de58d0cb4dbd512eb4d06473b2502acecd009dca",
      )
    }
    for
      bytes in [dispatch_bytes - 1, dispatch_bytes, dispatch_bytes + 1, 1000000] {
      let status = effect_ledger_claim_facts_status(
        basis,
        scope,
        locator,
        key,
        ledger_test_cid("e"),
        ledger_test_cid("f"),
        expected_scope,
        bytes,
        20,
        1,
      )
      let legacy = legacy_claim_facts_match(
        basis,
        scope,
        locator,
        key,
        ledger_test_cid("e"),
        ledger_test_cid("f"),
        expected_scope,
        bytes,
        20,
        1,
      )
      if bytes < dispatch_bytes {
        assert_eq(status, 0)
        assert_eq(legacy, None)
      } else {
        assert_eq(status, 1)
        assert_eq(legacy, Some(true))
      }
    }
  }
}

///|
test "pure claim facts fallback preserves tight invalid and unsupported codec precedence" {
  let (scope, locator, key, basis) = claim_facts_fixture("unavailable")
  for
    (bytes, nodes, depth) in [
      (0, 20, 1),
      (1410, 20, 1),
      (1411, 19, 1),
      (1411, 20, 0),
      (1000001, 20, 1),
      (1411, 1001, 1),
      (1411, 20, 33),
    ] {
    // Mismatched facts must not replace the earlier legacy codec refusal.
    assert_eq(
      effect_ledger_claim_facts_status(
        basis,
        scope,
        locator,
        key,
        ledger_test_cid("9"),
        ledger_test_cid("8"),
        ledger_test_cid("7"),
        bytes,
        nodes,
        depth,
      ),
      0,
    )
    assert_eq(
      legacy_claim_facts_match(
        basis,
        scope,
        locator,
        key,
        ledger_test_cid("9"),
        ledger_test_cid("8"),
        ledger_test_cid("7"),
        bytes,
        nodes,
        depth,
      ),
      None,
    )
  }
  assert_eq(
    effect_ledger_claim_facts_status(
      basis,
      scope,
      locator,
      key,
      ledger_test_cid("e"),
      ledger_test_cid("f"),
      logical_request_scope_cid(scope),
      1411,
      1000,
      32,
    ),
    1,
  )
  // Forged private fields are negative geometry only, not issued authority.
  for
    invalid in [
      { ..basis, capability: "new-provider", },
      { ..basis, original_membership_cid: "not-a-CID", },
    ] {
    assert_eq(
      effect_ledger_claim_facts_status(
        invalid,
        scope,
        locator,
        key,
        ledger_test_cid("e"),
        ledger_test_cid("f"),
        logical_request_scope_cid(scope),
        4096,
        64,
        3,
      ),
      0,
    )
  }
}

///|
test "pure claim facts reject foreign scope locator key Preview request and intent exactly like actual issuance" {
  let (scope, locator, key, basis) = claim_facts_fixture("native")
  let other_scope = prepare_logical_request_scope(
    ledger_test_cid("a"),
    "request-2",
    32,
  ).unwrap()
  let other_locator = prepare_logical_item_locator(
    scope, "program-1", "node-1", "WriteOne", "{\"row\":\"other\"}", 64, 128, 8,
    3,
  ).unwrap()
  let other_key = prepare_effect_dispatch_key(
    scope,
    ledger_test_cid("b"),
    "\"other-row\"",
    32,
    8,
    3,
  ).unwrap()
  let other_preview = prepare_effect_dispatch_key(
    scope,
    ledger_test_cid("0"),
    "\"row-1\"",
    32,
    8,
    3,
  ).unwrap()
  let foreign_scope_key = prepare_effect_dispatch_key(
    other_scope,
    ledger_test_cid("b"),
    "\"row-1\"",
    32,
    8,
    3,
  ).unwrap()
  for
    (s, l, k, intent, request, expected_scope) in [
      (
        other_scope,
        locator,
        key,
        ledger_test_cid("e"),
        ledger_test_cid("f"),
        logical_request_scope_cid(scope),
      ),
      (
        scope,
        other_locator,
        key,
        ledger_test_cid("e"),
        ledger_test_cid("f"),
        logical_request_scope_cid(scope),
      ),
      (
        scope,
        locator,
        other_key,
        ledger_test_cid("e"),
        ledger_test_cid("f"),
        logical_request_scope_cid(scope),
      ),
      (
        scope,
        locator,
        other_preview,
        ledger_test_cid("e"),
        ledger_test_cid("f"),
        logical_request_scope_cid(scope),
      ),
      (
        scope,
        locator,
        foreign_scope_key,
        ledger_test_cid("e"),
        ledger_test_cid("f"),
        logical_request_scope_cid(scope),
      ),
      (
        scope,
        locator,
        key,
        ledger_test_cid("9"),
        ledger_test_cid("f"),
        logical_request_scope_cid(scope),
      ),
      (
        scope,
        locator,
        key,
        ledger_test_cid("e"),
        ledger_test_cid("9"),
        logical_request_scope_cid(scope),
      ),
      (
        scope,
        locator,
        key,
        ledger_test_cid("e"),
        ledger_test_cid("f"),
        ledger_test_cid("9"),
      ),
    ] {
    assert_eq(
      effect_ledger_claim_facts_status(
        basis, s, l, k, intent, request, expected_scope, 4096, 64, 3,
      ),
      2,
    )
    assert_eq(
      legacy_claim_facts_match(
        basis, s, l, k, intent, request, expected_scope, 4096, 64, 3,
      ),
      Some(false),
    )
  }
  // Other immutable fields remain the fresh head-to-basis checker's duty.
  // A valid different Unit is not invented as a mismatch by this scalar seam.
  let prepared = issue_prepared_effect_ledger_entry(basis, 4096, 64, 3).unwrap()
  let foreign_basis = { ..basis, unit_definition_cid: ledger_test_cid("9"), }
  assert_eq(
    effect_ledger_claim_facts_status(
      foreign_basis,
      scope,
      locator,
      key,
      ledger_test_cid("e"),
      ledger_test_cid("f"),
      logical_request_scope_cid(scope),
      4096,
      64,
      3,
    ),
    1,
  )
  assert_false(effect_ledger_entry_matches_basis(prepared, foreign_basis))
}
