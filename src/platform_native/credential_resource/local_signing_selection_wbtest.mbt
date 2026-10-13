///|
// Independent synthetic installation metadata. No key file or Host is opened.
let signing_key_selection_fixture : String =
  #|{"version":"actql-config/0.1","native":{"signing_key":{"enabled":true,"purpose":"reviewer_proof","principal":"reviewer","connection":"review-cli","resource":"key/reviewer-2026","key_id":"reviewer-2026","private_key_file":"reviewer.pem","public_key_pem":"dummy-public-key\r\n","checkpoint_kinds":["effect_set"]}}}

///|
test "Signing selection preserves exact original role and finite configured Checkpoint kinds" {
  let selection = admit_native_local_signing_key_selection(
    signing_key_selection_fixture,
  ).unwrap()
  assert_eq(
    native_local_signing_key_selection_projection(selection),
    (
      true,
      @credential.ReviewerProof,
      "reviewer",
      "review-cli",
      "key/reviewer-2026",
      "reviewer-2026",
      "reviewer.pem",
      "dummy-public-key\r\n",
    ),
  )
  assert_true(
    native_local_signing_key_selection_allows_kind(
      selection,
      @checkpoint.EffectSet,
    ),
  )
  assert_false(
    native_local_signing_key_selection_allows_kind(
      selection,
      @checkpoint.ModelInvocation,
    ),
  )
  let host = admit_native_local_signing_key_selection(
    signing_key_selection_fixture.replace_all(
      old="reviewer_proof",
      new="host_attestation",
    ),
  ).unwrap()
  let (_, purpose, _, _, resource, _, _, _) = native_local_signing_key_selection_projection(
    host,
  )
  assert_eq(purpose, @credential.HostAttestation)
  assert_eq(resource, "key/reviewer-2026")
}

///|
test "Signing selection keeps decomposed Unicode and each original line ending" {
  for
    (encoded, expected) in [
      ("e\\u0301", "e\u0301"),
      ("\\u00e9", "\u00e9"),
      ("x\\r", "x\r"),
      ("x\\n", "x\n"),
      ("x\\r\\n", "x\r\n"),
    ] {
    let selection = admit_native_local_signing_key_selection(
      signing_key_selection_fixture.replace_all(
        old="\"reviewer\"",
        new="\"" + encoded + "\"",
      ),
    ).unwrap()
    let (_, _, principal, _, _, _, _, _) = native_local_signing_key_selection_projection(
      selection,
    )
    assert_eq(principal, expected)
  }
}

///|
test "Signing selection rejects copied authority fields missing or duplicate fields and unknown purpose" {
  for
    (old, replacement) in [
      (
        "\"enabled\":true", "\"enabled\":true,\"authority_scope_cid\":\"copied\"",
      ),
      ("\"enabled\":true", "\"enabled\":true,\"key_generation_cid\":\"copied\""),
      ("\"enabled\":true", "\"enabled\":true,\"enabled\":false"),
      ("\"enabled\":true,", ""),
      ("reviewer_proof", "remote_http"),
      ("\"resource\":\"key/reviewer-2026\"", "\"resource\":null"),
      ("\"resource\":\"key/reviewer-2026\"", "\"resource\":\"\""),
      ("\"enabled\":true", "\"enabled\":\"true\""),
    ] {
    assert_true(
      admit_native_local_signing_key_selection(
        signing_key_selection_fixture.replace_all(old~, new=replacement),
      )
      is Err(InvalidSigningKeySelection),
    )
  }
}

///|
test "Signing selection confines the explicit key basename and rejects malformed kind sets" {
  for
    value in [
      ".", "..", "../reviewer.pem", "/reviewer.pem", "x\\\\reviewer.pem", "x\\u0000y",
    ] {
    assert_true(
      admit_native_local_signing_key_selection(
        signing_key_selection_fixture.replace_all(old="reviewer.pem", new=value),
      )
      is Err(InvalidSigningKeySelection),
    )
  }
  for
    value in [
      "[]", "null", "\"effect_set\"", "[\"effect_set\",\"effect_set\"]", "[\"unknown\"]",
      "[null]",
    ] {
    assert_true(
      admit_native_local_signing_key_selection(
        signing_key_selection_fixture.replace_all(
          old="[\"effect_set\"]",
          new=value,
        ),
      )
      is Err(InvalidSigningKeySelection),
    )
  }
}

///|
test "Signing selection enforces existing finite byte and tree bounds without granting disabled roles" {
  assert_true(
    admit_native_local_signing_key_selection(" ".repeat(8193))
    is Err(SigningKeySelectionLimitExceeded),
  )
  assert_true(
    admit_native_local_signing_key_selection(
      signing_key_selection_fixture.replace_all(
        old="\"reviewer\"",
        new="\"" + "é".repeat(257) + "\"",
      ),
    )
    is Err(SigningKeySelectionLimitExceeded),
  )
  let disabled = admit_native_local_signing_key_selection(
    signing_key_selection_fixture.replace_all(
      old="\"enabled\":true",
      new="\"enabled\":false",
    ),
  ).unwrap()
  let (enabled, _, _, _, _, _, _, _) = native_local_signing_key_selection_projection(
    disabled,
  )
  assert_false(enabled)
}
