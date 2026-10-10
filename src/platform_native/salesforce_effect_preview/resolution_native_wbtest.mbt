///|
test "Native attested Effect resolution verifies installed Host and current reviewer" {
  guard @env.get_env_var("ACTQL_TEST_EFFECT_CHECKPOINT_WIRE")
    is Some(checkpoint_wire) &&
    @env.get_env_var("ACTQL_TEST_EFFECT_RESOLUTION_WIRE")
    is Some(resolution_wire) &&
    @env.get_env_var("ACTQL_TEST_EFFECT_VERIFIED_WIRE") is Some(verified_wire) &&
    @env.get_env_var("ACTQL_TEST_EFFECT_HOST_PUBLIC_KEY") is Some(public_key) &&
    @env.get_env_var("ACTQL_TEST_EFFECT_WRONG_PUBLIC_KEY") is Some(wrong_key) &&
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY") is Some(crypto_path) else {
    if @env.get_env_var("ACTQL_REQUIRE_NATIVE_EFFECT_RESOLUTION_TESTS") ==
      Some("1") {
      abort("Native Effect signature fixture is required")
    }
    return
  }
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 65536,
    max_nodes: 4096,
    max_depth: 32,
  }
  let checkpoint = @checkpoint.admit_checkpoint_wire(checkpoint_wire, limits).unwrap()
  let digit = (value : String) => "sha256:" + value.repeat(64)
  let authentication : @checkpoint.HostAuthentication = {
    key_id: "reviewer-key",
    reviewer_id: "native-reviewer",
    expected_authority_scope_cid: digit("5"),
    authority_context_cid: digit("6"),
    policy_cid: digit("7"),
    proof_preimage: @checkpoint.resolution_proof_preimage(
      resolution_wire, limits,
    ).unwrap(),
  }
  let reviewers : Array[@checkpoint.ReviewerAuthority] = [
    { key_id: "reviewer-key", reviewer_id: "native-reviewer", },
  ]
  let crypto = @signature.load_library(crypto_path).unwrap()
  let keys : Array[NativeEffectHostAuthority] = [
    { key_id: "host-key", public_key_pem: public_key, },
  ]
  let admitted = admit_native_effect_resolution(
    crypto,
    checkpoint,
    verified_wire,
    authentication,
    reviewers,
    keys,
    () => true,
    limits,
  ).unwrap()
  assert_eq(admitted.decision, @checkpoint.ResolutionDecision::Approved)
  assert_eq(admitted.checkpoint_cid, checkpoint.checkpoint_cid)
  assert_eq(admitted.wire, verified_wire)
  assert_true(admitted.resume_intent_id is Some(_))
  assert_true(
    admit_native_effect_resolution(
      crypto,
      checkpoint,
      verified_wire,
      authentication,
      reviewers,
      [],
      () => true,
      limits,
    )
    is Err(AttestationRejected),
  )
  assert_true(
    admit_native_effect_resolution(
      crypto,
      checkpoint,
      verified_wire,
      authentication,
      reviewers,
      [keys[0], keys[0]],
      () => true,
      limits,
    )
    is Err(AttestationRejected),
  )
  assert_true(
    admit_native_effect_resolution(
      crypto,
      checkpoint,
      verified_wire,
      authentication,
      reviewers,
      [{ key_id: "host-key", public_key_pem: wrong_key, }],
      () => true,
      limits,
    )
    is Err(AttestationRejected),
  )
  assert_true(
    admit_native_effect_resolution(
      crypto,
      checkpoint,
      verified_wire,
      authentication,
      reviewers,
      [keys[0], { key_id: "host-key", public_key_pem: "", }],
      () => true,
      limits,
    )
    is Err(AttestationRejected),
  )
  let current_calls = Ref(0)
  assert_true(
    admit_native_effect_resolution(
      crypto,
      checkpoint,
      verified_wire,
      authentication,
      reviewers,
      keys,
      () => {
        current_calls.val += 1
        current_calls.val == 1
      },
      limits,
    )
    is Err(AuthorityDenied),
  )
  assert_eq(current_calls.val, 2)
  assert_true(
    admit_native_effect_resolution(
      crypto,
      checkpoint,
      verified_wire,
      { ..authentication, expected_authority_scope_cid: digit("8"), },
      reviewers,
      keys,
      () => true,
      limits,
    )
    is Err(Resolution(_)),
  )
}
