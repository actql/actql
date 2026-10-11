///|
fn preparation_identity_fields() -> LocalPreparationFenceFields {
  {
    client_request_intent_cid: "sha256:" + "1".repeat(64),
    client_request_scope_cid: "sha256:" + "2".repeat(64),
    operation_occurrence_cid: "sha256:" + "3".repeat(64),
    run_invocation_cid: "sha256:" + "4".repeat(64),
    unit_definition_cid: "sha256:" + "5".repeat(64),
  }
}

///|
// Independent standard JSON/UTF-8/SHA-256 vector for the adopted field map;
// generated from authored literals, never from an ActQL encoder/test result.
let preparation_identity_body : String =
  #|{"client_request_intent_cid":"sha256:1111111111111111111111111111111111111111111111111111111111111111","client_request_scope_cid":"sha256:2222222222222222222222222222222222222222222222222222222222222222","operation_occurrence_cid":"sha256:3333333333333333333333333333333333333333333333333333333333333333","run_invocation_cid":"sha256:4444444444444444444444444444444444444444444444444444444444444444","unit_definition_cid":"sha256:5555555555555555555555555555555555555555555555555555555555555555","version":"actql-local-preparation-fence/0.1"}

///|
let preparation_identity_cid : String = "sha256:25682af870e2978302b45578ce9aca8d560549c3c510a073242669a5a3efbf34"

///|
test "Local preparation identity independent exact vector validates identity only" {
  let identity = prepare_local_preparation_fence_identity(
    preparation_identity_fields(),
  ).unwrap()
  assert_eq(local_preparation_fence_json(identity), preparation_identity_body)
  assert_eq(local_preparation_fence_cid(identity), preparation_identity_cid)
  let restored = admit_local_preparation_fence_json(
    preparation_identity_body, preparation_identity_cid,
  ).unwrap()
  assert_eq(
    local_preparation_fence_fields(restored),
    preparation_identity_fields(),
  )
  // Public identity admission cannot substitute for either credential branch.
  assert_true(
    admit_local_credential_grant_json(
      preparation_identity_body, preparation_identity_cid,
    )
    is Err(InvalidCredentialGrant),
  )
  assert_true(
    admit_grant_json(preparation_identity_body, preparation_identity_cid)
    is Err(InvalidCredentialGrant),
  )
}

///|
test "Local preparation identity rejects missing malformed or noncanonical originals" {
  for
    name in [
      "client_request_intent_cid", "client_request_scope_cid", "operation_occurrence_cid",
      "run_invocation_cid", "unit_definition_cid",
    ] {
    let digit = match name {
      "client_request_intent_cid" => "1"
      "client_request_scope_cid" => "2"
      "operation_occurrence_cid" => "3"
      "run_invocation_cid" => "4"
      _ => "5"
    }
    let exact = "\"" + name + "\":\"sha256:" + digit.repeat(64) + "\""
    for replacement in ["null", "\"sha256:bad\"", "7"] {
      assert_true(
        admit_local_preparation_fence_json(
          preparation_identity_body.replace_all(
            old=exact,
            new="\"" + name + "\":" + replacement,
          ),
          preparation_identity_cid,
        )
        is Err(InvalidCredentialGrant),
      )
    }
    assert_true(
      admit_local_preparation_fence_json(
        preparation_identity_body.replace_all(old=exact + ",", new=""),
        preparation_identity_cid,
      )
      is Err(InvalidCredentialGrant),
    )
  }
  for
    body in [
      preparation_identity_body + " ",
      preparation_identity_body.replace_all(
        old="{",
        new="{\"fence_generation\":1,",
      ),
      preparation_identity_body.replace_all(old="/0.1", new="/0.2"),
      preparation_identity_body.replace_all(old="sha256:", new="SHA256:"),
      " ".repeat(4097),
    ] {
    assert_true(
      admit_local_preparation_fence_json(body, preparation_identity_cid)
      is Err(InvalidCredentialGrant),
    )
  }
}

///|
test "Local preparation identity separately binds every original field and rejects a foreign claimed CID" {
  let fields = preparation_identity_fields()
  let different = "sha256:" + "a".repeat(64)
  for
    changed in [
      { ..fields, client_request_intent_cid: different, },
      { ..fields, client_request_scope_cid: different, },
      { ..fields, operation_occurrence_cid: different, },
      { ..fields, run_invocation_cid: different, },
      { ..fields, unit_definition_cid: different, },
    ] {
    let identity = prepare_local_preparation_fence_identity(changed).unwrap()
    assert_false(
      local_preparation_fence_cid(identity) == preparation_identity_cid,
    )
    assert_true(
      admit_local_preparation_fence_json(
        local_preparation_fence_json(identity),
        preparation_identity_cid,
      )
      is Err(CredentialGrantIdentityMismatch),
    )
  }
  assert_true(
    admit_local_preparation_fence_json(preparation_identity_body, different)
    is Err(CredentialGrantIdentityMismatch),
  )
}

///|
test "Local preparation identity leaves the existing Local resume and Remote vectors unchanged" {
  let resume = local_credential_fixture_grant()
  assert_eq(
    local_credential_grant_json(resume),
    Ok(local_credential_expected_body),
  )
  assert_eq(
    local_credential_grant_cid(resume),
    "sha256:d2e42a0c51b75d996bf9c1c87e9b9fe99ea71048769f15393aec553efb8e5423",
  )
  let remote = credential_grant()
  assert_eq(
    credential_grant_cid(remote),
    "sha256:06e4af5fa870fbe558c30211879440b84757b52e5d761cdb80f65c4b0eeb6d1c",
  )
  assert_true(
    admit_local_preparation_fence_json(
      local_credential_expected_body, local_credential_expected_cid,
    )
    is Err(InvalidCredentialGrant),
  )
  assert_true(
    admit_local_preparation_fence_json(
      credential_grant_json(remote).unwrap(),
      credential_grant_cid(remote),
    )
    is Err(InvalidCredentialGrant),
  )
}
