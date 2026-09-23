///|
test "typed Effect ledger issuance matches independent prepared identity" {
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
    "unavailable",
    ledger_test_cid("1"),
    ledger_test_cid("2"),
  ).unwrap()
  let prepared = issue_prepared_effect_ledger_entry(basis, 4096, 64, 3).unwrap()
  assert_eq(
    effect_ledger_entry_cid(prepared),
    "sha256:09517d06658bcea4c679a029de58d0cb4dbd512eb4d06473b2502acecd009dca",
  )
  assert_true(effect_ledger_entry_follows(None, prepared))
  let dispatching = issue_next_effect_ledger_entry(
    prepared,
    "dispatching",
    None,
    4096,
    64,
    3,
  ).unwrap()
  assert_true(effect_ledger_entry_follows(Some(prepared), dispatching))
  let unknown = issue_next_effect_ledger_entry(
    dispatching,
    "unknown",
    None,
    4096,
    64,
    3,
  ).unwrap()
  assert_true(effect_ledger_entry_follows(Some(dispatching), unknown))
  let applied = issue_next_effect_ledger_entry(
    unknown,
    "applied",
    Some(ledger_test_cid("3")),
    4096,
    64,
    3,
  ).unwrap()
  assert_true(effect_ledger_entry_follows(Some(unknown), applied))
  assert_true(
    issue_next_effect_ledger_entry(
      applied,
      "failed",
      Some(ledger_test_cid("4")),
      4096,
      64,
      3,
    )
    is Err(InvalidTransition),
  )
}

///|
test "ledger basis refuses mismatched request scope before construction" {
  let first = prepare_logical_request_scope(
    ledger_test_cid("a"),
    "request-1",
    32,
  ).unwrap()
  let second = prepare_logical_request_scope(
    ledger_test_cid("a"),
    "request-2",
    32,
  ).unwrap()
  let key = prepare_effect_dispatch_key(
    first,
    ledger_test_cid("b"),
    "\"row-1\"",
    32,
    8,
    3,
  ).unwrap()
  let locator = prepare_logical_item_locator(
    first, "program-1", "node-1", "WriteOne", "{\"row\":\"record-1\"}", 64, 128,
    8, 3,
  ).unwrap()
  assert_true(
    prepare_effect_ledger_basis(
      second,
      locator,
      key,
      ledger_test_cid("c"),
      ledger_test_cid("d"),
      ledger_test_cid("e"),
      ledger_test_cid("f"),
      ledger_test_cid("0"),
      "unavailable",
      ledger_test_cid("1"),
      ledger_test_cid("2"),
    )
    is Err(InvalidIdentity),
  )
}
