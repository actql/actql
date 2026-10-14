///|
// Real private Root, authenticated installation journal and public PEM original;
// the descriptor contains no private key. This fixture covers the key side
// only, not a fabricated paired capture or a successful signing operation.
fn reviewer_signing_scope_key_fixture(
  name : String,
) -> (NativeLocalHostConnection, NativeLocalSigningKeyOriginal) {
  let key_file = name + ".key.json"
  let descriptor = name + ".descriptor"
  let reviewer_file = name + ".reviewer.json"
  let account_file = name + ".account.json"
  signing_original_write(
    key_file,
    @utf8.encode(
      signing_original_configuration(
        descriptor,
        signing_original_public_a,
        reviewer=true,
      ),
    ),
  )
  signing_original_write(descriptor, b"synthetic-file-projection-only")
  signing_original_write(
    reviewer_file,
    @utf8.encode(
      local_reviewer_selection_wire
      .replace_all(old="\"operator\"", new="\"reviewer\"")
      .replace_all(old="\"cli\"", new="\"review-cli\""),
    ),
  )
  signing_original_write(account_file, @utf8.encode(local_reviewer_account))
  let crypto = @crypto.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
    diagnostic_ceiling=Some(64),
  ).unwrap()
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let host = begin_native_local_host_adoption(
      path,
      name + ".host",
      path,
      account_file,
      "operator",
      crypto,
      configuration_files=[key_file, reviewer_file],
    )
    .unwrap()
    .open_journal(local_journal_test_library(), crypto, 100.0, 8, 8388608L)
    .unwrap()
  let reviewer = host
    .install_effect_reviewer(configuration_file=Some(reviewer_file))
    .unwrap()
  let key = host
    .acquire_signing_key_account(
      crypto,
      key_file,
      @checkpoint.EffectSet,
      reviewer=Some(reviewer),
    )
    .unwrap()
    .capture_signing_key_original()
    .unwrap()
  (host, key)
}

///|
// Subject fields below are deliberately only candidate metadata. They cannot
// construct NativeLocalReviewerProofMaterials or its original approval scope.
fn reviewer_signing_scope_key_candidate(
  key : NativeLocalSigningKeyOriginal,
) -> @credential.LocalSigningCredentialScope {
  let account = key.account
  {
    account_configuration_cid: account.account_configuration_cid,
    account_id: "operator",
    attempt_id: "explicit-reviewer-attempt",
    authority_scope_cid: account.scope,
    checkpoint_cid: "sha256:" + "1".repeat(64),
    checkpoint_id: "candidate-only-checkpoint",
    checkpoint_kind: @checkpoint.EffectSet,
    host_adoption_cid: account.host.adoption_cid,
    key_configuration_cid: account.file.content_cid,
    key_generation_cid: key.generation_cid(),
    key_id: "release-approver-2026",
    key_public_key_cid: signing_original_public_a_cid,
    preimage: "sha256:" + "2".repeat(64),
    principal: "reviewer",
    request_cid: "sha256:" + "3".repeat(64),
    request_scope_cid: "sha256:" + "4".repeat(64),
    run_definition_cid: "sha256:" + "5".repeat(64),
    run_invocation_cid: "sha256:" + "6".repeat(64),
    submission_scope_cid: "sha256:" + "7".repeat(64),
    unit_definition_cid: "sha256:" + "8".repeat(64),
    purpose: @credential.ReviewerProof,
  }
}

///|
test "Reviewer scope key correspondence uses authenticated originals without issuing a grant" {
  let (host, key) = reviewer_signing_scope_key_fixture("scope-key-original")
  let candidate = reviewer_signing_scope_key_candidate(key)
  assert_eq(key.account.account_id, "operator")
  let before = host.database
    .read("client_local_installation_originals", key.account.file.name)
    .unwrap()
  let count = host.installation_custody().unwrap().0
  key.require_reviewer_signing_key_scope(candidate).unwrap()
  key.require_reviewer_signing_key_scope(candidate).unwrap()
  // The separate subject fence remains necessary: key correspondence is not
  // evidence that a caller's request/Run/Checkpoint metadata is authenticated.
  key
  .require_reviewer_signing_key_scope({
    ..candidate,
    submission_scope_cid: candidate.request_scope_cid,
  })
  .unwrap()
  let after = host.database
    .read("client_local_installation_originals", key.account.file.name)
    .unwrap()
  assert_eq(after.body, before.body)
  assert_eq(after.revision, before.revision)
  assert_eq(host.installation_custody().unwrap().0, count)
  assert_true(
    host.database.scan_after("client_local_grant_originals", "")
    is Err(@sqlite.NotFound),
  )
  host.close().unwrap()
}

///|
test "Reviewer scope rejects substituted key Account role generation and public identity" {
  let (host, key) = reviewer_signing_scope_key_fixture("scope-key-substituted")
  let candidate = reviewer_signing_scope_key_candidate(key)
  let foreign = "sha256:" + "f".repeat(64)
  for
    changed in [
      { ..candidate, account_configuration_cid: foreign, },
      { ..candidate, account_id: "foreign-account", },
      { ..candidate, authority_scope_cid: foreign, },
      { ..candidate, host_adoption_cid: foreign, },
      { ..candidate, key_configuration_cid: foreign, },
      { ..candidate, key_generation_cid: foreign, },
      { ..candidate, key_id: "foreign-key", },
      { ..candidate, key_public_key_cid: foreign, },
      { ..candidate, principal: "operator", },
      { ..candidate, purpose: @credential.HostAttestation, },
      { ..candidate, checkpoint_kind: @checkpoint.ModelInvocation, },
    ] {
    assert_true(
      key.require_reviewer_signing_key_scope(changed) is Err(ProofUnavailable),
    )
  }
  key.require_reviewer_signing_key_scope(candidate).unwrap()
  host.close().unwrap()
}

///|
test "Reviewer scope cannot borrow another original Host and cannot outlive its key generation" {
  let (host, key) = reviewer_signing_scope_key_fixture("scope-key-generation")
  let candidate = reviewer_signing_scope_key_candidate(key)
  let (other_host, other_key) = reviewer_signing_scope_key_fixture(
    "scope-key-other-host",
  )
  assert_true(
    other_key.require_reviewer_signing_key_scope(candidate)
    is Err(ProofUnavailable),
  )
  other_host.close().unwrap()
  let file = "scope-key-generation.descriptor"
  let root = host.session.source_root
  root
  .reclaim_generation(file, root.inspect_generation(file).unwrap().unwrap())
  .unwrap()
  let writer = root.create_writer("scope-key-replacement.stage", 8192L).unwrap()
  writer.append(b"synthetic-file-projection-only").unwrap()
  writer.seal(file).unwrap() |> ignore
  assert_true(
    key.require_reviewer_signing_key_scope(candidate) is Err(ProofKey(_)),
  )
  assert_eq(host.installation_custody().unwrap().0, 1)
  host.close().unwrap()
}

///|
test "Reviewer scope rejects closed original custody before returning matching metadata" {
  let (host, key) = reviewer_signing_scope_key_fixture("scope-key-closed")
  let candidate = reviewer_signing_scope_key_candidate(key)
  key.require_reviewer_signing_key_scope(candidate).unwrap()
  host.close().unwrap()
  assert_true(
    key.require_reviewer_signing_key_scope(candidate) is Err(ProofKey(_)),
  )
}
