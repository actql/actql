///|
// Key-side candidate metadata only: this cannot construct a paired approval
// scope, an original Submission/Checkpoint, a proof material or a signing use.
fn initial_proof_key_candidate(
  key : NativeLocalInitialReviewerSigningKey,
) -> @credential.LocalSigningCredentialScope {
  let fields = key.fields
  {
    account_configuration_cid: fields.account_configuration_cid,
    account_id: fields.account_id,
    attempt_id: "key-correspondence-only",
    authority_scope_cid: fields.authority_scope_cid,
    checkpoint_cid: "sha256:" + "1".repeat(64),
    checkpoint_id: "candidate-only-checkpoint",
    checkpoint_kind: @checkpoint.EffectSet,
    host_adoption_cid: fields.host_adoption_cid,
    key_configuration_cid: fields.key_configuration_cid,
    key_generation_cid: fields.key_generation_cid,
    key_id: fields.key_id,
    key_public_key_cid: fields.key_public_key_cid,
    preimage: "sha256:" + "2".repeat(64),
    principal: fields.principal,
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
test "initial proof key retains authenticated Store generation and independent Reviewer without reading a secret or issuing" {
  let (host, file) = initial_reviewer_fixture("initial-proof-key-original")
  let original = host.restore_initial_signing_original().unwrap()
  let installed = host
    .install_initial_effect_reviewer(original, "machine-user", "cli", file)
    .unwrap()
  let before = host.database
    .read("client_local_grant_custody", "issued")
    .unwrap()
  let key = host
    .acquire_initial_reviewer_signing_key(original, installed)
    .unwrap()
  let candidate = initial_proof_key_candidate(key)
  let metadata_match = InitialReviewerKey(key).require_signing_key_scope(
      candidate,
    )
    is Ok(_)
  let original_control = host.database
    .read("client_local_installation_custody", "host")
    .unwrap()
  let configuration_exact = candidate.key_configuration_cid ==
    local_adoption_digest(host.epoch.crypto, original_control.body).unwrap()
  let generation_exact = candidate.key_generation_cid ==
    local_adoption_digest(host.epoch.crypto, original.exported).unwrap()
  let identity_exact = candidate.key_id == original.public_key().unwrap().cid() &&
    candidate.key_public_key_cid == candidate.key_id &&
    candidate.principal == "machine-user"
  let denied = host.authorize({
      principal: "machine-user",
      connection: "cli",
      resource: "credential/" + original.issuer_identity().unwrap(),
      operation: "issue",
    })
    is Ok(@authorization.Deny(_))
  let after = host.database
    .read("client_local_grant_custody", "issued")
    .unwrap()
  host.close().unwrap()
  assert_true(
    metadata_match &&
    configuration_exact &&
    generation_exact &&
    identity_exact &&
    denied,
  )
  assert_eq(before.body, after.body)
  assert_eq(before.revision, after.revision)
  assert_true(key.require_current() is Err(SigningOriginalUnavailable))
}

///|
test "initial proof key refuses every changed original key role and actor field" {
  let (host, file) = initial_reviewer_fixture("initial-proof-key-fields")
  let original = host.restore_initial_signing_original().unwrap()
  let installed = host
    .install_initial_effect_reviewer(original, "machine-user", "cli", file)
    .unwrap()
  let key = host
    .acquire_initial_reviewer_signing_key(original, installed)
    .unwrap()
  let exact = initial_proof_key_candidate(key)
  let other = "sha256:" + "f".repeat(64)
  let variants = [
    { ..exact, purpose: @credential.HostAttestation, },
    { ..exact, checkpoint_kind: @checkpoint.ModelInvocation, },
    { ..exact, account_configuration_cid: other, },
    { ..exact, account_id: "other-account", },
    { ..exact, authority_scope_cid: other, },
    { ..exact, host_adoption_cid: other, },
    { ..exact, key_configuration_cid: other, },
    { ..exact, key_generation_cid: other, },
    { ..exact, key_id: "another-key", },
    { ..exact, key_public_key_cid: other, },
    { ..exact, principal: "other-actor", },
  ]
  let key_view = InitialReviewerKey(key)
  let refused = variants.map(scope => {
    key_view.require_signing_key_scope(scope) is Err(ProofUnavailable)
  })
  host.close().unwrap()
  assert_eq(refused.length(), 11)
  assert_true(refused.all(value => value))
}

///|
test "initial proof key refuses another physical Host and a configured source-root Reviewer registration" {
  let (host, file) = initial_reviewer_fixture("initial-proof-key-own")
  let original = host.restore_initial_signing_original().unwrap()
  let installed = host
    .install_initial_effect_reviewer(original, "machine-user", "cli", file)
    .unwrap()
  let (foreign, foreign_file) = initial_reviewer_fixture(
    "initial-proof-key-foreign",
  )
  let foreign_original = foreign.restore_initial_signing_original().unwrap()
  let foreign_installed = foreign
    .install_initial_effect_reviewer(
      foreign_original, "machine-user", "cli", foreign_file,
    )
    .unwrap()
  let foreign_host = foreign.acquire_initial_reviewer_signing_key(
      original, installed,
    )
    is Err(SigningOriginalUnavailable)
  let foreign_registration = host.acquire_initial_reviewer_signing_key(
      original, foreign_installed,
    )
    is Err(SigningOriginalUnavailable)
  foreign.close().unwrap()
  let (configured_host, configured_key) = reviewer_signing_scope_key_fixture(
    "initial-proof-key-configured",
  )
  let configured = configured_key.account.reviewer.unwrap()
  let configured_refused = host.acquire_initial_reviewer_signing_key(
      original, configured,
    )
    is Err(SigningOriginalUnavailable)
  configured_host.close().unwrap()
  host.close().unwrap()
  assert_true(foreign_host && foreign_registration && configured_refused)
}

///|
test "initial proof key detects adopted Host configuration and physical Store key replacement" {
  let (host, file) = initial_reviewer_fixture("initial-proof-key-host-change")
  let original = host.restore_initial_signing_original().unwrap()
  let installed = host
    .install_initial_effect_reviewer(original, "machine-user", "cli", file)
    .unwrap()
  let key = host
    .acquire_initial_reviewer_signing_key(original, installed)
    .unwrap()
  let (_, generation) = local_adoption_read(
    host.session.source_root,
    file,
    65536L,
  ).unwrap()
  host.session.source_root.reclaim_generation(file, generation).unwrap()
  let writer = host.session.source_root
    .create_writer("changed-host.stage", 65536L)
    .unwrap()
  writer.append(installed.original_bytes).unwrap()
  writer.seal(file).unwrap() |> ignore
  let changed_host = key.require_current() is Err(SigningOriginalUnavailable)
  let changed_terminal_host = key.finish_original_projection()
    is Err(SigningOriginalUnavailable)
  host.close().unwrap()
  let (host, file) = initial_reviewer_fixture(
    "initial-proof-key-generation-change",
  )
  let original = host.restore_initial_signing_original().unwrap()
  let installed = host
    .install_initial_effect_reviewer(original, "machine-user", "cli", file)
    .unwrap()
  let key = host
    .acquire_initial_reviewer_signing_key(original, installed)
    .unwrap()
  let root = host.session.root
  let (bytes, generation) = local_adoption_read(
    root, "local-signing-key.pem", 119L,
  ).unwrap()
  root.reclaim_generation("local-signing-key.pem", generation).unwrap()
  let writer = root.create_writer("changed-key.stage", 119L).unwrap()
  writer.append(bytes).unwrap()
  writer.seal("local-signing-key.pem").unwrap() |> ignore
  let changed_key = key.require_current() is Err(SigningOriginalUnavailable)
  let changed_terminal_key = key.finish_original_projection()
    is Err(SigningOriginalUnavailable)
  host.close().unwrap()
  assert_true(
    changed_host && changed_terminal_host && changed_key && changed_terminal_key,
  )
}
