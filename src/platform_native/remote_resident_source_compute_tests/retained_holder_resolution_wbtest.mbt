///|
/// The local test issuer signs this holder's actual common-issued Checkpoint.
/// This fixture is not Cloud authorization, a resume claim or a Provider write.
fn retained_holder_admit_resolution(
  work : @effect_provider.NativeResidentEffectReview,
  report : @remote.RemoteEffectCheckpointReport,
) -> (
  String,
  @checkpoint.HostAuthentication,
  Array[@checkpoint.ReviewerAuthority],
  Array[@effect_provider.NativeEffectHostAuthority],
) raise {
  let url = @env.get_env_var("ACTQL_TEST_EFFECT_RESOLUTION_FIXTURE_URL").unwrap()
  let http = @http.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY").unwrap(),
  ).unwrap()
  let client = http
    .create_authenticated_client(
      @env.get_env_var("ACTQL_TEST_NATIVE_HTTP_CA").unwrap(),
      Bearer(@env.get_env_var("ACTQL_TEST_NATIVE_HTTP_SECRET").unwrap()),
      262144L,
      2000,
      5000,
    )
    .unwrap()
  let checkpoint = @remote.remote_effect_checkpoint_report_checkpoint(report)
  println("native-original-resolution: requesting signed fixture")
  let reply = match client.post_json(url, @utf8.encode(checkpoint.wire)) {
    Ok(value) => value
    Err(_) => abort("Native original Resolution fixture HTTP failed")
  }
  assert_eq(reply.status, 200)
  let value = @json.parse(@utf8.decode(reply.body))
  let text = (key : String) => {
    match value {
      Object(fields) =>
        match fields.get(key) {
          Some(String(value)) => value
          _ => abort("Missing signed Resolution fixture field")
        }
      _ => abort("Invalid Resolution fixture response")
    }
  }
  let wire = text("ACTQL_TEST_EFFECT_VERIFIED_WIRE")
  let resolution = text("ACTQL_TEST_EFFECT_RESOLUTION_WIRE")
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 262144,
    max_nodes: 10000,
    max_depth: 64,
  }
  let authentication : @checkpoint.HostAuthentication = {
    key_id: "reviewer-key",
    reviewer_id: "native-reviewer",
    expected_authority_scope_cid: retained_compute_cid("5"),
    authority_context_cid: retained_compute_cid("6"),
    policy_cid: retained_compute_cid("7"),
    proof_preimage: @checkpoint.resolution_proof_preimage(resolution, limits).unwrap(),
  }
  let reviewers : Array[@checkpoint.ReviewerAuthority] = [
    { key_id: "reviewer-key", reviewer_id: "native-reviewer", },
  ]
  let keys : Array[@effect_provider.NativeEffectHostAuthority] = [
    {
      key_id: "host-key",
      public_key_pem: text("ACTQL_TEST_EFFECT_HOST_PUBLIC_KEY"),
    },
  ]
  let at = () => "2026-10-10T00:01:00.000Z"
  // Use the real persisted Review's original subject and the candidate's
  // unsigned body. Existing Checkpoint admission independently checks every
  // binding; the proposed Resolution never supplies an expected Checkpoint.
  let unsigned = match @json.parse(resolution) {
    Object(fields) => {
      fields.remove("proof") |> ignore
      fields.remove("resolution_cid") |> ignore
      Json::Object(fields).stringify()
    }
    _ => fail("Invalid original Resolution fixture body")
  }
  let (prepared, subject) = work
    .prepare_original_resolution_proof(unsigned, () => true)
    .unwrap()
  assert_eq(prepared.checkpoint(), checkpoint)
  assert_eq(prepared.actor(), "native-reviewer")
  assert_eq(prepared.preimage(), authentication.proof_preimage)
  assert_eq(subject, work.original_signing_subject(() => true).unwrap())
  assert_true(
    work.prepare_original_resolution_proof(unsigned, () => false)
    is Err(Unavailable),
  )
  let disclosures = Ref(0)
  assert_true(
    work.prepare_original_resolution_proof(unsigned, () => {
      disclosures.val += 1
      disclosures.val == 1
    })
    is Err(Unavailable),
  )
  assert_eq(disclosures.val, 2)
  let foreign = unsigned.replace_all(
    old=checkpoint.checkpoint_cid,
    new="sha256:" + "f".repeat(64),
  )
  assert_true(
    work.prepare_original_resolution_proof(foreign, () => true)
    is Err(Resolution(CheckpointBindingMismatch(_))),
  )
  assert_eq(work.original_signing_subject(() => true).unwrap(), subject)
  println("native-original-resolution: admitting original Checkpoint")
  let admitted = match
    work.admit_resolution(wire, authentication, reviewers, keys, () => true, at) {
    Ok(value) => value
    Err(Resolution(issue)) =>
      match issue {
        ResolutionIdentityMismatch =>
          abort("Native original Resolution identity mismatch")
        AuthenticationMismatch(field) =>
          abort("Native original Resolution authentication: " + field)
        EvidenceMismatch(field) =>
          abort("Native original Resolution evidence: " + field)
        CheckpointBindingMismatch(field) =>
          abort("Native original Resolution Checkpoint: " + field)
        ResolutionMissingField(field) =>
          abort("Native original Resolution missing field: " + field)
        ResolutionInvalidField(field) =>
          abort("Native original Resolution invalid field: " + field)
        DecisionOutsideWindow =>
          abort("Native original Resolution outside window")
        _ => abort("Native original Resolution common rejection")
      }
    Err(AuthorityDenied) =>
      abort("Native original Resolution current authority rejected")
    Err(Unavailable) => abort("Native original Resolution holder unavailable")
    Err(AttestationRejected) =>
      abort("Native original Resolution Host attestation rejected")
    Err(Signature(_)) => abort("Native original Resolution crypto failed")
    Err(Retention(_)) =>
      abort("Native original Resolution retention unavailable")
  }
  assert_eq(admitted.checkpoint_cid, checkpoint.checkpoint_cid)
  assert_eq(admitted.wire, wire)
  assert_true(admitted.resume_intent_id is Some(_))
  assert_true(
    work.admit_resolution(wire, authentication, reviewers, [], () => true, at)
    is Err(AttestationRejected),
  )
  assert_true(
    work.admit_resolution(
      wire,
      authentication,
      reviewers,
      keys,
      () => false,
      at,
    )
    is Err(Unavailable),
  )
  // A clock callback can revoke independently supplied reviewer authority.
  // A cached authorization result from before that callback is insufficient.
  let reviewer_current = Ref(true)
  assert_true(
    work.admit_resolution(
      wire,
      authentication,
      reviewers,
      keys,
      () => reviewer_current.val,
      () => {
        reviewer_current.val = false
        at()
      },
    )
    is Err(AuthorityDenied),
  )
  assert_true(work.result_capture() is Some(_))
  (wire, authentication, reviewers, keys)
}
