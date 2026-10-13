///|
fn reviewer_signing_test_cid(digit : String) -> String {
  "sha256:" + digit.repeat(64)
}

///|
// Matching Native definitions only. These pure correspondence fixtures do not
// execute key access, a Current supplier, a credential claim or a signature.
fn reviewer_signing_current_fixture() -> (
  @credential_resource.NativeLocalSigningKeySelection,
  NativeLocalEffectReviewerSelection,
  @effect_resolution.NativeEffectReviewerRegistration,
) {
  let installed = admit_native_local_effect_reviewer_selection(
    local_reviewer_selection_wire,
  ).unwrap()
  let wire = local_signing_account_key_wire
    .replace_all(old="host_attestation", new="reviewer_proof")
    .replace_all(old="host-signer", new="operator")
    .replace_all(old="host-cli", new="cli")
    .replace_all(old="host-attestation-2026", new="release-approver-2026")
    .replace_all(old="dummy-host-public-key", new=signing_original_public_a)
  let selection = @credential_resource.admit_native_local_signing_key_selection(
    wire,
  ).unwrap()
  let registration : @effect_resolution.NativeEffectReviewerRegistration = {
    selection: {
      principal_id: "operator",
      checkpoint_cid: reviewer_signing_test_cid("1"),
    },
    key_id: "release-approver-2026",
    reviewer_id: "release-approver",
    public_key_pem: installed.public_key_pem,
    approval_authority_scope_cid: reviewer_signing_test_cid("2"),
    authority_context_cid: reviewer_signing_test_cid("3"),
    policy_cid: reviewer_signing_test_cid("4"),
  }
  (selection, installed, registration)
}

///|
test "Reviewer key correspondence separates Client Approval and Reviewer authority contexts" {
  let (selection, installed, registration) = reviewer_signing_current_fixture()
  assert_true(
    local_reviewer_signing_registration_matches(
      selection,
      reviewer_signing_test_cid("3"),
      reviewer_signing_test_cid("4"),
      registration.selection,
      installed,
      registration,
    ),
  )
  assert_false(
    local_reviewer_signing_registration_matches(
      selection,
      registration.approval_authority_scope_cid,
      reviewer_signing_test_cid("4"),
      registration.selection,
      installed,
      registration,
    ),
  )
}

///|
test "Reviewer key correspondence rejects foreign checkpoint registration key and policy" {
  let (selection, installed, original) = reviewer_signing_current_fixture()
  for
    foreign in [
      {
        ..original,
        selection: {
          principal_id: "other",
          checkpoint_cid: reviewer_signing_test_cid("1"),
        },
      },
      {
        ..original,
        selection: {
          principal_id: "operator",
          checkpoint_cid: reviewer_signing_test_cid("5"),
        },
      },
      { ..original, key_id: "other-key", },
      { ..original, reviewer_id: "other-reviewer", },
      { ..original, public_key_pem: "other-public-original", },
      { ..original, authority_context_cid: reviewer_signing_test_cid("5"), },
      { ..original, policy_cid: reviewer_signing_test_cid("5"), },
    ] {
    assert_false(
      local_reviewer_signing_registration_matches(
        selection,
        reviewer_signing_test_cid("3"),
        reviewer_signing_test_cid("4"),
        original.selection,
        installed,
        foreign,
      ),
    )
  }
}

///|
test "Reviewer key correspondence rejects Host role and foreign connection without permission synthesis" {
  let (_, installed, registration) = reviewer_signing_current_fixture()
  let host_role = @credential_resource.admit_native_local_signing_key_selection(
    local_signing_account_key_wire,
  ).unwrap()
  assert_false(
    local_reviewer_signing_registration_matches(
      host_role,
      reviewer_signing_test_cid("3"),
      reviewer_signing_test_cid("4"),
      registration.selection,
      installed,
      registration,
    ),
  )
  let (selection, _, _) = reviewer_signing_current_fixture()
  for
    foreign in [
      { ..installed, enabled: false, },
      { ..installed, connection: "foreign-cli", },
      { ..installed, principal: "foreign-principal", },
    ] {
    assert_false(
      local_reviewer_signing_registration_matches(
        selection,
        reviewer_signing_test_cid("3"),
        reviewer_signing_test_cid("4"),
        registration.selection,
        foreign,
        registration,
      ),
    )
  }
}
