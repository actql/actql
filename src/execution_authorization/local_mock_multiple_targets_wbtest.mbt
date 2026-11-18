///|
test "Local Mock complete inventory scopes each delegate and retains one updates read" {
  let subjects = {
    ..mock_profile_subjects(),
    sources: [("crm", "Accounts"), ("crm", "Contacts"), ("crm", "Control")],
    update_target: None,
  }
  let targets = [("crm", "Contacts"), ("crm", "Accounts")]
  let wire = local_mock_account_configuration_prepared(subjects, targets, _ => {
      true
    })
    .unwrap()
    .unwrap()
  let account = admit_account_configuration_json(wire).unwrap()
  for resource in ["Accounts", "Contacts"] {
    assert_true(
      evaluate_account(account, mock_profile_at("crm", resource, "effect"))
      is Delegate(_),
    )
    assert_true(
      evaluate_account(account, mock_profile_at("crm", resource, "write"))
      is Deny(NoMatch),
    )
  }
  for
    tuple in [
      mock_profile_at("crm", "Control", "effect"),
      mock_profile_at("other", "Accounts", "effect"),
      mock_profile_at("local-host", "result/other", "read"),
    ] {
    assert_true(evaluate_account(account, tuple) is Deny(NoMatch))
  }
  assert_true(
    evaluate_account(
      account,
      mock_profile_at("local-host", "result/updates", "read"),
    )
    is Allow(_),
  )
  assert_eq(wire.split("\"entry_id\":\"local-update-result-read\"").length(), 2)
  assert_eq(
    local_mock_account_configuration_prepared(
      subjects,
      [("crm", "Accounts"), ("crm", "Contacts")],
      _ => true,
    )
    .unwrap()
    .unwrap(),
    wire,
  )
  assert_true(
    local_mock_account_configuration_prepared(
      subjects,
      [("crm", "Accounts"), ("crm", "Accounts")],
      _ => true,
    ).unwrap()
    is Err(DuplicateUpdateTarget),
  )
}

///|
test "Local Mock complete constructor preserves the original single-target preimage" {
  let subjects = mock_profile_subjects()
  let wire = local_mock_account_configuration_prepared(
      subjects,
      [("salesforce", "Account")],
      _ => true,
    )
    .unwrap()
    .unwrap()
  assert_eq(
    admit_account_configuration_json(wire).unwrap().configuration_cid(),
    "sha256:d516378d5284e53e3c9667e62a11ffd020b477111920fa0405d93f73695f2907",
  )
  let calls = Ref(0)
  assert_true(
    local_mock_account_configuration_prepared(
      subjects,
      [("salesforce", "Account"), ("salesforce", "Account")],
      _ => {
        calls.val += 1
        false
      },
    )
    is None,
  )
  assert_eq(calls.val, 1)
}

///|
test "Local Mock complete inventory checks canonical subjects before keys or configuration" {
  let sources = [("crm", "Accounts"), ("crm", "Contacts")]
  let targets = [("crm", "Contacts"), ("crm", "Accounts")]
  let observed : Ref[AccountConfigurationConstruction?] = Ref(None)
  assert_true(
    validate_local_mock_inventory_prepared(
      "local-mock",
      sources,
      [],
      None,
      targets,
      request => {
        observed.val = Some(request)
        true
      },
    ).unwrap()
    is Ok(_),
  )
  let request = observed.val.unwrap()
  assert_eq(request.retained, account_construction_zero)
  assert_true(request.execution.record_headers > 0L)
  assert_true(request.execution.reference_slots > 0L)
  assert_true(
    validate_local_mock_inventory_prepared(
      "local-mock",
      sources,
      [],
      None,
      targets,
      _ => false,
    )
    is None,
  )
  assert_true(
    validate_local_mock_inventory_prepared(
      "local-mock",
      sources,
      [],
      None,
      [("crm", "Accounts"), ("crm", "Accounts")],
      _ => true,
    ).unwrap()
    is Err(DuplicateUpdateTarget),
  )
  assert_true(
    validate_local_mock_inventory_prepared(
      "local-mock",
      [("crm", "e\u{0301}")],
      [],
      None,
      [],
      _ => true,
    ).unwrap()
    is Err(InvalidSubjects),
  )
}

///|
test "Local Mock pre-signing quote matches the real finite key-name constructor shape" {
  let unsigned = { ..mock_profile_subjects(), signing_key_resource: None, }
  let targets = [("salesforce", "Account")]
  let before = local_mock_account_construction_before_signing(
    unsigned, targets, 71,
  ).unwrap()
  // Public name DATA only, not a key, permission, signer or adoption original.
  let named = {
    ..unsigned,
    signing_key_resource: Some("sha256:" + "b".repeat(64)),
  }
  assert_eq(before, local_mock_account_construction(named, targets).unwrap())
  assert_true(before.retained.owned_utf16_units > 0L)
  assert_true(
    before.execution.reference_slots > before.retained.reference_slots,
  )
  assert_true(
    local_mock_account_construction_before_signing(unsigned, targets, 0) is None,
  )
  assert_true(
    local_mock_account_construction_before_signing(named, targets, 71) is None,
  )
}
