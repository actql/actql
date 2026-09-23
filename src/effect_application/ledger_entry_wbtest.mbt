///|
fn ledger_test_cid(digit : String) -> String {
  "sha256:" + digit.repeat(64)
}

///|
fn ledger_test_wire(
  state : String,
  fence : Int,
  attempt : Int,
  prior : String,
  outcome : String,
  self_cid : String,
) -> String {
  let prior_json = if prior.is_empty() { "null" } else { "\"" + prior + "\"" }
  let outcome_json = if outcome.is_empty() {
    "null"
  } else {
    "\"" + outcome + "\""
  }
  "{\"attempt_sequence\":" +
  attempt.to_string() +
  ",\"canonical_request_cid\":\"" +
  ledger_test_cid("1") +
  "\",\"capability\":\"unavailable\",\"dispatch_key\":\"" +
  ledger_test_cid("2") +
  "\",\"effect_preview_cid\":\"" +
  ledger_test_cid("3") +
  "\",\"fence\":" +
  fence.to_string() +
  ",\"intent_fingerprint_cid\":\"" +
  ledger_test_cid("4") +
  "\",\"logical_item_locator_cid\":\"" +
  ledger_test_cid("5") +
  "\",\"logical_request_scope_cid\":\"" +
  ledger_test_cid("6") +
  "\",\"original_membership_cid\":\"" +
  ledger_test_cid("7") +
  "\",\"outcome_receipt_cid\":" +
  outcome_json +
  ",\"prior_entry_cid\":" +
  prior_json +
  ",\"recovery_contract_cid\":\"" +
  ledger_test_cid("8") +
  "\",\"reservation_evidence_cid\":\"" +
  ledger_test_cid("9") +
  "\",\"retention_contract_cid\":\"" +
  ledger_test_cid("a") +
  "\",\"self_cid\":\"" +
  self_cid +
  "\",\"state\":\"" +
  state +
  "\",\"unit_definition_cid\":\"" +
  ledger_test_cid("b") +
  "\",\"version\":\"actql-logical-item-ledger-entry/0.1\"}"
}

///|
test "Effect ledger entry checks independent preimages and exact chain" {
  let prepared_cid = "sha256:349ed4835945b58a37a980a9acae09bbfd5703f10cc7b6aa8f6a308933f207d8"
  let dispatching_cid = "sha256:d0b361ababb602bf89c3bc02ae796dd88fa1c2d9c65b1cd26f1468939f9e27f0"
  let applied_cid = "sha256:f727a04dddbe1c00a69a9fb5e6d64d6931305b6fea29d6e78f2503afae497ad5"
  let prepared = admit_effect_ledger_entry(
    ledger_test_wire("prepared", 1, 0, "", "", prepared_cid),
    4096,
    64,
    3,
  ).unwrap()
  let dispatching = admit_effect_ledger_entry(
    ledger_test_wire("dispatching", 2, 1, prepared_cid, "", dispatching_cid),
    4096,
    64,
    3,
  ).unwrap()
  let applied = admit_effect_ledger_entry(
    ledger_test_wire(
      "applied",
      3,
      1,
      dispatching_cid,
      ledger_test_cid("c"),
      applied_cid,
    ),
    4096,
    64,
    3,
  ).unwrap()
  assert_eq(effect_ledger_entry_cid(prepared), prepared_cid)
  assert_eq(effect_ledger_entry_cid(dispatching), dispatching_cid)
  assert_eq(effect_ledger_entry_cid(applied), applied_cid)
  assert_true(effect_ledger_entry_follows(None, prepared))
  assert_true(effect_ledger_entry_follows(Some(prepared), dispatching))
  assert_true(effect_ledger_entry_follows(Some(dispatching), applied))
  assert_true(!effect_ledger_entry_follows(Some(prepared), applied))
  assert_true(!effect_ledger_entry_follows(Some(applied), dispatching))
}

///|
test "Effect ledger entry refuses altered or noncanonical physical facts" {
  let prepared_cid = "sha256:349ed4835945b58a37a980a9acae09bbfd5703f10cc7b6aa8f6a308933f207d8"
  let prepared_wire = ledger_test_wire("prepared", 1, 0, "", "", prepared_cid)
  let changed = prepared_wire.replace(
    old=ledger_test_cid("4"),
    new=ledger_test_cid("f"),
  )
  assert_true(
    admit_effect_ledger_entry(changed, 4096, 64, 3) is Err(InvalidIdentity),
  )
  let expanded = prepared_wire.replace(
    old="\"version\":\"actql-logical-item-ledger-entry/0.1\"}",
    new="\"version\":\"actql-logical-item-ledger-entry/0.1\",\"extra\":true}",
  )
  assert_true(
    admit_effect_ledger_entry(expanded, 4096, 64, 3) is Err(InvalidWire) ||
    admit_effect_ledger_entry(expanded, 4096, 64, 3) is Err(InvalidShape),
  )
  assert_true(admit_effect_ledger_entry("{}", 4096, 64, 3) is Err(InvalidShape))
}
