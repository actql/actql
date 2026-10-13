///|
// Native definitions only until separately allocated. These fixtures create
// synthetic configuration, never a private signing key or credential claim.
let local_signing_account_key_wire : String =
  #|{"version":"actql-config/0.1","native":{"signing_key":{"enabled":true,"purpose":"host_attestation","principal":"host-signer","connection":"host-cli","resource":"key/host-attestation-2026","key_id":"host-attestation-2026","private_key_file":"host-attestation.pem","public_key_pem":"dummy-host-public-key","checkpoint_kinds":["effect_set"]}}}

///|
let local_signing_account_wire : String =
  #|{"version":"actql-execution-account-config/0.1","account_id":"operator","entries":[{"entry_id":"original-host-key-sign","outcome":"allow","principal":{"any_of":["host-signer"]},"connection":{"any_of":["host-cli"]},"resource":{"any_of":["key/host-attestation-2026"]},"operation":{"any_of":["sign"]},"exclusions":[]}]}

///|
fn local_signing_account_fixture(
  name : String,
  key_wire? : String = local_signing_account_key_wire,
  account? : String = local_signing_account_wire,
) -> (NativeLocalHostConnection, String) {
  let root = @filesystem.open_private_root(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap(),
  ).unwrap()
  let file = name + ".signing-key.json"
  let writer = root.create_writer(name + ".key.stage", 8192L).unwrap()
  writer.append(@utf8.encode(key_wire)).unwrap()
  writer.seal(file).unwrap() |> ignore
  (
    policy_host_fixture(name, files=[file], account_body=@utf8.encode(account)),
    file,
  )
}

///|
test "Local Host key Account uses exact adopted resource sign and no read issue or submit substitute" {
  for operation in ["sign", "read", "write", "issue", "submit"] {
    let (host, file) = local_signing_account_fixture(
      "signing-account-" + operation,
      account=local_signing_account_wire.replace_all(
        old="\"sign\"",
        new="\"" + operation + "\"",
      ),
    )
    let result = host.acquire_signing_key_account(
      epoch_test_crypto(),
      file,
      @checkpoint.EffectSet,
    )
    if operation == "sign" {
      let binding = result.unwrap()
      assert_eq(binding.file.body, @utf8.encode(local_signing_account_key_wire))
      assert_eq(binding.account_id, "operator")
      assert_true(binding.require_current_account() is Ok(_))
      assert_true(
        host.acquire_signing_key_account(
          epoch_test_crypto(),
          file,
          @checkpoint.ModelInvocation,
        )
        is Err(SigningUnavailable),
      )
      assert_true(
        host.acquire_signing_key_account(
          epoch_test_crypto(),
          "unselected.json",
          @checkpoint.EffectSet,
        )
        is Err(SigningUnavailable),
      )
      host.close().unwrap()
      assert_true(binding.require_current_account() is Err(SigningUnavailable))
    } else {
      assert_true(result is Err(SigningUnavailable))
      host.close().unwrap()
    }
  }
  let (host, file) = local_signing_account_fixture(
    "signing-account-foreign-resource",
    account=local_signing_account_wire.replace_all(
      old="key/host-attestation-2026",
      new="key/other",
    ),
  )
  assert_true(
    host.acquire_signing_key_account(
      epoch_test_crypto(),
      file,
      @checkpoint.EffectSet,
    )
    is Err(SigningUnavailable),
  )
  host.close().unwrap()
}

///|
test "Local signing Account has no automatic Reviewer registration or disabled activation" {
  for
    (name, wire) in [
      (
        "missing-reviewer",
        local_signing_account_key_wire.replace_all(
          old="host_attestation",
          new="reviewer_proof",
        ),
      ),
      (
        "disabled",
        local_signing_account_key_wire.replace_all(
          old="\"enabled\":true",
          new="\"enabled\":false",
        ),
      ),
    ] {
    let (host, file) = local_signing_account_fixture(
      "signing-account-" + name,
      key_wire=wire,
    )
    assert_true(
      host.acquire_signing_key_account(
        epoch_test_crypto(),
        file,
        @checkpoint.EffectSet,
      )
      is Err(SigningUnavailable),
    )
    host.close().unwrap()
  }
}

///|
test "Local Reviewer key Account retains independent registration resolve and original key selection" {
  let name = "signing-account-reviewer"
  let root = @filesystem.open_private_root(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap(),
  ).unwrap()
  let reviewer_file = name + ".reviewer.json"
  let key_file = name + ".key.json"
  // Independent original public fixture; no private key bytes exist here.
  let public_key_wire = "-----BEGIN PUBLIC KEY-----\\nMCowBQYDK2VwAyEAA6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=\\n-----END PUBLIC KEY-----\\n"
  let key_wire = local_signing_account_key_wire
    .replace_all(old="host_attestation", new="reviewer_proof")
    .replace_all(old="host-signer", new="reviewer")
    .replace_all(old="host-cli", new="review-cli")
    .replace_all(old="host-attestation-2026", new="release-approver-2026")
    .replace_all(old="dummy-host-public-key", new=public_key_wire)
  let reviewer_wire = local_reviewer_selection_wire
    .replace_all(old="\"operator\"", new="\"reviewer\"")
    .replace_all(old="\"cli\"", new="\"review-cli\"")
  for (file, body) in [(reviewer_file, reviewer_wire), (key_file, key_wire)] {
    let writer = root.create_writer(file + ".stage", 8192L).unwrap()
    writer.append(@utf8.encode(body)).unwrap()
    writer.seal(file).unwrap() |> ignore
  }
  let host = policy_host_fixture(
    name,
    files=[reviewer_file, key_file],
    account_body=@utf8.encode(local_reviewer_account),
  )
  let installed = host
    .install_effect_reviewer(configuration_file=Some(reviewer_file))
    .unwrap()
  assert_true(
    host.acquire_signing_key_account(
      epoch_test_crypto(),
      key_file,
      @checkpoint.EffectSet,
    )
    is Err(SigningUnavailable),
  )
  let binding = host
    .acquire_signing_key_account(
      epoch_test_crypto(),
      key_file,
      @checkpoint.EffectSet,
      reviewer=Some(installed),
    )
    .unwrap()
  assert_true(binding.require_current_account() is Ok(_))
  assert_true(
    host.authorize({
      principal: "reviewer",
      connection: "review-cli",
      resource: "run",
      operation: "read",
    })
    is Ok(@authorization.Deny(_)),
  )
  host.close().unwrap()
  assert_true(binding.require_current_account() is Err(SigningUnavailable))
}
