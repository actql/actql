///|
// This focused connection uses a genuinely adopted Host and the existing real
// Source/computation/Preview/Checkpoint holders. The Source fixture's explicit
// backing and target metadata remain component fixtures, not installed CLI or
// whole-engine physical acceptance. Its existing signed rejection retires the
// review obligation separately; it does not certify Local Host attestation.
priv struct PairedInitialReviewerFixture {
  host : @client.NativeLocalHostConnection
  crypto : @signature.Library
  mut binding : @client.NativeLocalEffectReviewerBinding?
  mut restored : Bool
  attest_host : Bool
  probe_approval : Bool
  probe_resume : Bool
  mut resume_claimed : Bool
  mut host_applied : Bool
}

///|
fn paired_initial_reviewer_fixture(
  attest_host? : Bool = false,
  probe_approval? : Bool = false,
  probe_resume? : Bool = false,
) -> PairedInitialReviewerFixture raise {
  let top = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let name = "paired-initial-reviewer-" + @env.now().to_string()
  let parent = @filesystem.open_private_root(top).unwrap()
  parent.create_directory(name).unwrap() |> ignore
  let source = parent.open_child(name).unwrap()
  let account =
    #|{"version":"actql-execution-account-config/0.1","account_id":"operator","entries":[{"entry_id":"independent-resolve","outcome":"allow","principal":{"any_of":["operator"]},"connection":{"any_of":["cli"]},"resource":{"any_of":["run"]},"operation":{"any_of":["resolve"]},"exclusions":[]},{"entry_id":"original-read","outcome":"allow","principal":{"any_of":["operator"]},"connection":{"any_of":["cli"]},"resource":{"any_of":["run"]},"operation":{"any_of":["read"]},"exclusions":[]},{"entry_id":"original-submit","outcome":"allow","principal":{"any_of":["operator"]},"connection":{"any_of":["cli"]},"resource":{"any_of":["run"]},"operation":{"any_of":["submit"]},"exclusions":[]}]}
  let account = if attest_host {
    account.replace_all(
      old="\"entries\":[",
      new="\"entries\":[{\"entry_id\":\"host-attestation-sign\",\"outcome\":\"allow\",\"principal\":{\"any_of\":[\"host-machine\"]},\"connection\":{\"any_of\":[\"host-cli\"]},\"resource\":{\"any_of\":[\"key/initial-host-attestation\"]},\"operation\":{\"any_of\":[\"sign\"]},\"exclusions\":[]},",
    )
  } else {
    account
  }
  // Account wire order is part of its existing admission contract.
  assert_true(@authorization.admit_account_configuration_json(account) is Ok(_))
  for
    (file, body) in [
      ("account.json", account),
      ("host.json", "{\"version\":\"actql-host/0.1\"}"),
    ] {
    let writer = source.create_writer(file + ".stage", 65536L).unwrap()
    writer.append(@utf8.encode(body)).unwrap()
    writer.seal(file).unwrap() |> ignore
  }
  source.close().unwrap()
  parent.close().unwrap()
  let crypto = @signature.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
    diagnostic_ceiling=Some(256),
  ).unwrap()
  let sqlite = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let path = top + "/" + name
  let session = match
    @client.begin_native_local_host_adoption(
      path,
      "store",
      path,
      "account.json",
      "operator",
      crypto,
      configuration_files=["host.json"],
    ) {
    Ok(value) => value
    Err(@client.Configuration(issue)) =>
      fail("paired Reviewer Account refused: " + @debug.to_string(issue))
    Err(_) => fail("paired Reviewer original Host adoption refused")
  }
  let material = session
    .create_initial_signing_material(
      crypto,
      host_signing_subject=if attest_host {
        Some(("host-machine", "host-cli", "key/initial-host-attestation"))
      } else {
        None
      },
    )
    .unwrap()
  // The initializer takes an epoch duration, not a wall-clock timestamp.
  // Keep actual clock reads at the existing issue/current operations below.
  let submission_ttl_ms = 60000.0
  let host = match
    session.open_journal_with_initial_signing_material(
      material,
      @host.client_local_default_signing_bootstrap_policy(),
      sqlite,
      crypto,
      submission_ttl_ms,
      8,
      8388608L,
    ) {
    Ok(value) => value
    Err(@client.InvalidInput) =>
      fail("paired Reviewer Host journal options refused")
    Err(@client.CustodyLost) =>
      fail("paired Reviewer Host journal custody lost")
    Err(@client.TransactionUnknown) =>
      fail("paired Reviewer Host journal transaction unknown")
    Err(@client.DatabasePending(_, _)) =>
      fail("paired Reviewer Host journal has pending database custody")
    Err(_) => fail("paired Reviewer Host journal initialization refused")
  }
  {
    host,
    crypto,
    binding: None,
    restored: false,
    attest_host,
    probe_approval,
    probe_resume,
    resume_claimed: false,
    host_applied: false,
  }
}

///|
fn paired_initial_reviewer_signing(
  fixture : PairedInitialReviewerFixture,
  reference : @client.NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  approval_scope : @resident.ResidentOriginalEffectApprovalScope,
  checkpoint : @checkpoint.SealedCheckpoint,
) -> Unit raise {
  let host = fixture.host
  let original = host.restore_initial_signing_original().unwrap()
  let installed = host
    .install_initial_effect_reviewer(original, "operator", "cli", "host.json")
    .unwrap()
  let key = host
    .acquire_initial_reviewer_signing_key(original, installed)
    .unwrap()
  let binding = host
    .bind_initial_effect_reviewer(
      fixture.crypto,
      original,
      "host.json",
      "operator",
      "cli",
      reference,
      request,
      approval_scope,
      () => @env.now().to_double(),
    )
    .unwrap()
  if fixture.probe_approval {
    paired_initial_approved_proof_probe(
      fixture, binding, key, installed, request, checkpoint,
    )
    // The first real Approved answer is immutable. Do not sign a conflicting
    // rejection merely to reuse this fixture's older branch.
    fixture.binding = Some(binding)
    fixture.restored = true
    return
  }
  let unsigned =
    #|{"version":"actql-checkpoint-resolution/0.1","actor":"operator","checkpoint_id":"@CHECKPOINT_ID@","checkpoint_cid":"@CHECKPOINT_CID@","decided_at":"2026-10-10T00:00:00.000Z","decision":"rejected","required_artifact_cid":"@REQUIRED@","review_projection_cid":"@PROJECTION@","resolution_id":"paired-initial-reviewer-resolution","run_id":"@RUN@","run_definition_cid":"@DEFINITION@"}
  let unsigned = unsigned
    .replace_all(old="@CHECKPOINT_ID@", new=checkpoint.checkpoint.checkpoint_id)
    .replace_all(old="@CHECKPOINT_CID@", new=checkpoint.checkpoint_cid)
    .replace_all(
      old="@REQUIRED@",
      new=checkpoint.checkpoint.required_artifact_cid,
    )
    .replace_all(
      old="@PROJECTION@",
      new=checkpoint.checkpoint.review_projection_cid,
    )
    .replace_all(old="@RUN@", new=checkpoint.checkpoint.run_id().unwrap())
    .replace_all(
      old="@DEFINITION@",
      new=checkpoint.checkpoint.run_definition_cid().unwrap(),
    )
  let unsigned = if fixture.attest_host {
    let now = @values.epoch_milliseconds_timestamp(
      @env.now().reinterpret_as_int64(),
    ).unwrap()
    unsigned.replace_all(old="2026-10-10T00:00:00.000Z", new=now)
  } else {
    unsigned
  }
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 262144,
    max_nodes: 10000,
    max_depth: 64,
  }
  let materials = key
    .prepare_reviewer_proof_materials(binding, unsigned, limits)
    .unwrap()
  let scope = materials
    .prepare_signing_scope("paired-initial-reviewer")
    .unwrap()
  let (invocation, unit) = approval_scope
    .original_signing_subject_for(
      request,
      checkpoint.checkpoint.run_definition_cid().unwrap(),
      checkpoint.checkpoint_cid,
    )
    .unwrap()
  assert_eq(scope.run_invocation_cid, invocation)
  assert_eq(scope.unit_definition_cid, unit)
  assert_eq(
    scope.authority_scope_cid,
    host.authority_scope_cid("operator", "cli", fixture.crypto).unwrap(),
  )
  let signing = materials
    .prepare_initial_resolution_signing("paired-initial-reviewer")
    .unwrap()
  let wire = signing.sign_candidate_once().unwrap()
  assert_true(binding.authenticate_resolution(wire, limits) is Ok(_))
  assert_eq(signing.original_candidate().unwrap(), wire)
  assert_true(signing.sign_candidate_once() is Err(_))
  assert_true(
    binding.restore_initial_resolution_candidate("paired-initial-reviewer")
    is Ok(_),
  )
  assert_true(
    binding.restore_initial_resolution_candidate("missing-paired-operation")
    is Err(_),
  )
  if fixture.attest_host {
    let authenticated = binding.authenticate_resolution(wire, limits).unwrap()
    let host_key = host.restore_initial_host_signing_original().unwrap()
    // Actual Read/Resolve authority must not become Host Sign permission.
    assert_true(
      host.acquire_initial_host_signing_account(
        host_key, installed, "operator", "cli", "key/initial-host-attestation",
      )
      is Err(_),
    )
    // The operational subject now comes only from the authenticated first
    // installation; this caller supplies no actor tuple at signing time.
    let account = host.restore_initial_host_signing_account(installed).unwrap()
    assert_true(
      host.acquire_initial_host_signing_account(
        host_key, installed, "host-machine", "host-cli", "key/different",
      )
      is Err(_),
    )
    let prepared = authenticated
      .prepare_initial_host_attestation(
        account, materials, "paired-initial-host-attestation",
      )
      .unwrap()
    let host_signing = prepared.prepare_signing().unwrap()
    let verified = host_signing.sign_once().unwrap()
    assert_true(host_signing.sign_once() is Err(_))
    assert_eq(host_signing.original_verified_resolution().unwrap(), verified)
    host_signing.close_checked().unwrap()
    // Same original operation restores its original verification instant and
    // complete wrapper, without another physical signature or clock refresh.
    let restored = authenticated
      .prepare_initial_host_attestation(
        account, materials, "paired-initial-host-attestation",
      )
      .unwrap()
      .prepare_signing()
      .unwrap()
    assert_eq(restored.sign_once().unwrap(), verified)
    let applied = match restored.admit_original_resolution() {
      Ok(value) => value
      Err(@client.HostAttestationJournal(@client.Checkpoint(issue))) => {
        let reason = match issue {
          @client.Expired => "Expired"
          @client.InvalidMaterial => "InvalidMaterial"
          @client.StaleRevision => "StaleRevision"
          @client.ConflictingResolution => "ConflictingResolution"
          @client.NeedsOriginalContinuation => "NeedsOriginalContinuation"
          @client.Signature(_) => "Signature"
          @client.State(_) => "State"
          @client.Resume(_) => "Resume"
          @client.Ledger(_) => "Ledger"
          @client.EffectBinding(_) => "EffectBinding"
        }
        fail("initial Host Resolution admission Checkpoint: " + reason)
      }
      Err(@client.HostAttestationJournal(@client.AuthorizationDenied)) =>
        fail("initial Host Resolution admission current authority denied")
      Err(@client.HostAttestationJournal(_)) =>
        fail("initial Host Resolution admission Journal custody")
      Err(@client.HostAttestationReviewer(_)) =>
        fail("initial Host embedded Reviewer authentication")
      Err(@client.HostAttestationBody(issue)) =>
        fail("initial Host wrapper body: " + @debug.to_string(issue))
      Err(@client.HostAttestationUnavailable) =>
        fail("initial Host original signature/current unavailable")
      Err(@client.HostAttestationOriginal(_)) =>
        fail("initial Host original Read construction unavailable")
      Err(@client.HostAttestationAccount(_)) =>
        fail("initial Host explicit Account Sign unavailable")
      Err(@client.HostAttestationProof(_)) =>
        fail("initial Host paired proof current unavailable")
      Err(@client.HostAttestationPhysical(_)) =>
        fail("initial Host physical key current unavailable")
      Err(@client.HostAttestationCredential(_)) =>
        fail("initial Host original use unavailable")
    }
    assert_eq(
      @client.native_client_run_checkpoint_state(applied).unwrap().status,
      @publication.Cancelled,
    )
    restored.close_checked().unwrap()
    fixture.host_applied = true
  }
  signing.close_checked().unwrap()
  // This immutable result was verified against the actual original key and
  // paired scope. It is still neither Host attestation nor applied resolution.
  fixture.binding = Some(binding)
  fixture.restored = true
}

///|
test "adopted initial Reviewer signs and restores the same real paired Checkpoint candidate" {
  // Refuse stale authored Environment bindings before generating keys or any
  // Host/Submission state. The actual Source caller admits this same original.
  assert_true(
    @host.admit_client_check_environment(
      resident_effect_source_environment,
      resident_effect_source_bundle_cid,
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    )
    is Some(_),
    msg="paired Reviewer original Source Environment refused",
  )
  let fixture = paired_initial_reviewer_fixture()
  native_local_effect_capture_acceptance(true, initial_reviewer=Some(fixture))
  assert_true(fixture.restored)
}
