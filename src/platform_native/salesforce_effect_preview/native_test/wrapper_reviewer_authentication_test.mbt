///|
// Exact independent checkpoint-resolution-signatures vector used by the prior
// Native proof fixture. No Checkpoint, Host attestation, approval or send is made.
fn wrapper_authentication_native_wire() -> String {
  "{\"version\":\"actql-checkpoint-resolution/0.1\",\"resolution_id\":\"resolution_01\",\"checkpoint_id\":\"checkpoint_run_01_effect_commit\",\"checkpoint_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"run_id\":\"run_01\",\"run_definition_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"decision\":\"rejected\",\"actor\":\"release-approver\",\"decided_at\":\"2026-09-25T00:00:00.000Z\",\"required_artifact_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"review_projection_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"proof\":{\"scheme\":\"ed25519-v1\",\"key_id\":\"release-approver-2026\",\"signature\":\"u2GRgUDJiDrrjYPJiC1z1VVL0JgnG9s9da2xfZlnkrnp034TjxpT9+M+dhhcID03Wa3SpFs+ghI48FICfSr9BQ==\"},\"resolution_cid\":\"sha256:87396910af30eb9f314ff792ef4711502b02f7a38dae5c5e05ca693a74411d01\"}"
}

///|
fn wrapper_authentication_native_library() -> @signature.Library {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY") is Some(path) else {
    abort("actual Native Reviewer cryptography is required")
  }
  @signature.load_library(path).unwrap()
}

///|
fn wrapper_authentication_native_registration() -> @preview.NativeEffectReviewerRegistration {
  {
    selection: {
      principal_id: "original-http-principal",
      checkpoint_cid: "sha256:" + "1".repeat(64),
    },
    key_id: "release-approver-2026",
    reviewer_id: "release-approver",
    public_key_pem: "-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAA6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=\n-----END PUBLIC KEY-----\n",
    approval_authority_scope_cid: "sha256:" + "5".repeat(64),
    authority_context_cid: "sha256:" + "6".repeat(64),
    policy_cid: "sha256:" + "7".repeat(64),
  }
}

///|
fn wrapper_authentication_native_limits() -> @checkpoint.WireLimits {
  { max_wire_bytes: 65536, max_nodes: 4096, max_depth: 32, }
}

///|
test "Native wrapper authenticates exact retained proof with real Ed25519 and checked Library close" {
  let library = wrapper_authentication_native_library()
  let registered = wrapper_authentication_native_registration()
  let installation : @preview.NativeEffectReviewerInstallation = {
    crypto: library,
    current_site: () => true,
    read_current: (selection, key) => {
      if selection == registered.selection && key == registered.key_id {
        Some(registered)
      } else {
        None
      }
    },
  }
  let original = wrapper_authentication_native_wire()
  let wrapper = "{\"resolution\": " + original + "}"
  let actual = @preview.authenticate_native_effect_wrapper_reviewer(
    installation,
    registered.selection,
    wrapper,
    original,
    wrapper_authentication_native_limits(),
  ).unwrap()
  assert_eq(
    actual.proof_preimage,
    "sha256:6a19960b235f700f5a88bcb26f324ad21e7e48d279f15160444fe687f6013dd1",
  )
  assert_eq(actual.key_id, registered.key_id)
  assert_eq(actual.reviewer_id, registered.reviewer_id)
  assert_eq(actual.policy_cid, registered.policy_cid)
  library.close_checked().unwrap()
  assert_true(
    @preview.authenticate_native_effect_wrapper_reviewer(
      installation,
      registered.selection,
      wrapper,
      original,
      wrapper_authentication_native_limits(),
    )
    is Err(@preview.Signature(_)),
  )
}

///|
test "Native wrapper rejects changed proof physical invalid signature and post-verify registration loss" {
  let library = wrapper_authentication_native_library()
  let registered = wrapper_authentication_native_registration()
  let reads = Ref(0)
  let revoked = Ref(false)
  let installation : @preview.NativeEffectReviewerInstallation = {
    crypto: library,
    current_site: () => true,
    read_current: (selection, key) => {
      reads.val += 1
      if selection != registered.selection ||
        key != registered.key_id ||
        (revoked.val && reads.val >= 2) {
        None
      } else {
        Some(registered)
      }
    },
  }
  let original = wrapper_authentication_native_wire()
  let changed = original.replace_all(old="u2GRgUDJiDrr", new="v2GRgUDJiDrr")
  let limits = wrapper_authentication_native_limits()
  assert_eq(
    @checkpoint.resolution_proof_preimage(original, limits),
    @checkpoint.resolution_proof_preimage(changed, limits),
  )
  assert_true(
    @preview.authenticate_native_effect_wrapper_reviewer(
      installation,
      registered.selection,
      "{\"resolution\":" + changed + "}",
      original,
      limits,
    )
    is Err(@preview.AttestationRejected),
  )
  assert_eq(reads.val, 0)
  // Equal expected/embedded bytes still require actual physical verification.
  assert_true(
    @preview.authenticate_native_effect_wrapper_reviewer(
      installation,
      registered.selection,
      "{\"resolution\":" + changed + "}",
      changed,
      limits,
    )
    is Err(@preview.AttestationRejected),
  )
  reads.val = 0
  revoked.val = true
  assert_true(
    @preview.authenticate_native_effect_wrapper_reviewer(
      installation,
      registered.selection,
      "{\"resolution\":" + original + "}",
      original,
      limits,
    )
    is Err(@preview.AuthorityDenied),
  )
  assert_eq(reads.val, 2)
  library.close_checked().unwrap()
}
