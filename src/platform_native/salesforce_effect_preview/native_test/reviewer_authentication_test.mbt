///|
/// Actual Native verification of the independent signature corpus. This does
/// not execute an Effect, contact Cloud or create a current authority registry.
test "Native Reviewer authentication verifies physical Ed25519 and refuses altered proof" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY") is Some(path) else {
    if @env.get_env_var("ACTQL_REQUIRE_NATIVE_REVIEWER_AUTH_TESTS") == Some("1") {
      abort("Native Reviewer crypto library is required")
    }
    return
  }
  let selected : @preview.NativeEffectReviewerSelection = {
    principal_id: "original-http-principal",
    checkpoint_cid: "sha256:" + "1".repeat(64),
  }
  let registered : @preview.NativeEffectReviewerRegistration = {
    selection: selected,
    key_id: "release-approver-2026",
    reviewer_id: "release-approver",
    public_key_pem: "-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEAA6EHv/POEL4dcN0Y50vAmWfk1jCbpQ1fHdyGZBJVMbg=\n-----END PUBLIC KEY-----\n",
    approval_authority_scope_cid: "sha256:" + "5".repeat(64),
    authority_context_cid: "sha256:" + "6".repeat(64),
    policy_cid: "sha256:" + "7".repeat(64),
  }
  let installation : @preview.NativeEffectReviewerInstallation = {
    crypto: @signature.load_library(path).unwrap(),
    current_site: () => true,
    read_current: (_, _) => Some(registered),
  }
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 65536,
    max_nodes: 4096,
    max_depth: 32,
  }
  let wire = "{\"version\":\"actql-checkpoint-resolution/0.1\",\"resolution_id\":\"resolution_01\",\"checkpoint_id\":\"checkpoint_run_01_effect_commit\",\"checkpoint_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"run_id\":\"run_01\",\"run_definition_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"decision\":\"rejected\",\"actor\":\"release-approver\",\"decided_at\":\"2026-09-25T00:00:00.000Z\",\"required_artifact_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"review_projection_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"proof\":{\"scheme\":\"ed25519-v1\",\"key_id\":\"release-approver-2026\",\"signature\":\"u2GRgUDJiDrrjYPJiC1z1VVL0JgnG9s9da2xfZlnkrnp034TjxpT9+M+dhhcID03Wa3SpFs+ghI48FICfSr9BQ==\"},\"resolution_cid\":\"sha256:87396910af30eb9f314ff792ef4711502b02f7a38dae5c5e05ca693a74411d01\"}"
  let auth = @preview.authenticate_native_effect_reviewer(
    installation, selected, wire, limits,
  ).unwrap()
  assert_eq(
    auth.proof_preimage,
    "sha256:6a19960b235f700f5a88bcb26f324ad21e7e48d279f15160444fe687f6013dd1",
  )
  assert_eq(auth.key_id, registered.key_id)
  assert_eq(auth.reviewer_id, registered.reviewer_id)
  assert_true(
    @preview.authenticate_native_effect_reviewer(
      installation,
      selected,
      wire.replace_all(old="u2GRgUDJiDrr", new="v2GRgUDJiDrr"),
      limits,
    )
    is Err(@preview.AttestationRejected),
  )
  assert_true(
    @preview.authenticate_native_effect_reviewer(
      installation,
      { ..selected, principal_id: "another-http-principal", },
      wire,
      limits,
    )
    is Err(@preview.AuthorityDenied),
  )
}
