///|
// An independent finite configuration fixture. No approval, signature
// verification, Provider send or public CLI execution is represented here.
let local_reviewer_selection_wire : String =
  #|{"version":"actql-config/0.1","native":{"effect_reviewer":{"enabled":true,"principal":"operator","connection":"cli","key_id":"release-approver-2026","reviewer_id":"release-approver","public_key_pem":"-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAA6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=\n-----END PUBLIC KEY-----\n"}}}

///|
test "Native Local Reviewer selection has exact explicit fields and no implicit activation" {
  let value = admit_native_local_effect_reviewer_selection(
    local_reviewer_selection_wire,
  ).unwrap()
  assert_true(value.enabled)
  assert_eq(value.principal, "operator")
  assert_eq(value.connection, "cli")
  assert_eq(value.key_id, "release-approver-2026")
  assert_eq(value.reviewer_id, "release-approver")
  assert_eq(
    value.public_key_pem,
    "-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAA6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=\n-----END PUBLIC KEY-----\n",
  )
  assert_false(
    admit_native_local_effect_reviewer_selection(
      local_reviewer_selection_wire.replace_all(
        old="\"enabled\":true",
        new="\"enabled\":false",
      ),
    ).unwrap().enabled,
  )
}

///|
test "Native Local Reviewer selection preserves Unicode and each original line ending" {
  for
    (encoded, expected) in [
      ("e\\u0301", "e\u0301"),
      ("\\u00e9", "\u00e9"),
      ("a\\r", "a\r"),
      ("a\\n", "a\n"),
      ("a\\r\\n", "a\r\n"),
    ] {
    let value = admit_native_local_effect_reviewer_selection(
      local_reviewer_selection_wire.replace_all(old="operator", new=encoded),
    ).unwrap()
    assert_eq(value.principal, expected)
    let key = admit_native_local_effect_reviewer_selection(
      local_reviewer_selection_wire.replace_all(
        old="-----END PUBLIC KEY-----\\n",
        new=encoded,
      ),
    ).unwrap()
    assert_true(key.public_key_pem.has_suffix(expected))
  }
}

///|
test "Native Local Reviewer selection refuses supplied authority identities and private keys" {
  for
    key in [
      "approval_authority_scope_cid", "authority_context_cid", "policy_cid", "site_key",
      "dispatch_cid", "private_key_pem", "automatic_approval",
    ] {
    assert_true(
      admit_native_local_effect_reviewer_selection(
        local_reviewer_selection_wire.replace_all(
          old="\"enabled\":true",
          new="\"enabled\":true,\"" + key + "\":\"not-an-authority\"",
        ),
      )
      is Err(InvalidReviewerSelection),
    )
  }
  assert_true(
    admit_native_local_effect_reviewer_selection(
      local_reviewer_selection_wire.replace_all(
        old="\"enabled\":true",
        new="\"enabled\":true,\"enabled\":false",
      ),
    )
    is Err(InvalidReviewerSelection),
  )
}

///|
test "Native Local Reviewer selection rejects missing null empty and wrongly typed fields" {
  for replacement in ["null", "\"true\"", "1", "{}", "[]"] {
    assert_true(
      admit_native_local_effect_reviewer_selection(
        local_reviewer_selection_wire.replace_all(
          old="\"enabled\":true",
          new="\"enabled\":" + replacement,
        ),
      )
      is Err(InvalidReviewerSelection),
    )
  }
  assert_true(
    admit_native_local_effect_reviewer_selection(
      local_reviewer_selection_wire.replace_all(old="\"enabled\":true,", new=""),
    )
    is Err(InvalidReviewerSelection),
  )
  for
    (key, value) in [
      ("principal", "operator"),
      ("connection", "cli"),
      ("key_id", "release-approver-2026"),
      ("reviewer_id", "release-approver"),
    ] {
    assert_true(
      admit_native_local_effect_reviewer_selection(
        local_reviewer_selection_wire.replace_all(
          old="\"" + key + "\":\"" + value + "\"",
          new="\"" + key + "\":null",
        ),
      )
      is Err(InvalidReviewerSelection),
    )
  }
  for
    original in ["operator", "cli", "release-approver-2026", "release-approver"] {
    assert_true(
      admit_native_local_effect_reviewer_selection(
        local_reviewer_selection_wire.replace_all(
          old="\"" + original + "\"",
          new="\"\"",
        ),
      )
      is Err(InvalidReviewerSelection),
    )
  }
}

///|
test "Native Local Reviewer selection applies finite UTF8 byte limits before ownership or cryptography" {
  assert_true(
    admit_native_local_effect_reviewer_selection(" ".repeat(8193))
    is Err(ReviewerSelectionLimitExceeded),
  )
  for
    (original, replacement) in [
      ("operator", "\u00e9".repeat(257)),
      ("cli", "x".repeat(513)),
      ("release-approver-2026", "x".repeat(129)),
      ("release-approver", "x".repeat(129)),
    ] {
    assert_true(
      admit_native_local_effect_reviewer_selection(
        local_reviewer_selection_wire.replace_all(
          old="\"" + original + "\"",
          new="\"" + replacement + "\"",
        ),
      )
      is Err(ReviewerSelectionLimitExceeded),
    )
  }
}
