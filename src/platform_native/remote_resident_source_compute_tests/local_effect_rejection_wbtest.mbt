///|
/// The isolated HTTPS fixture signs this actual Checkpoint for rejection.
/// Existing Native signature and common Resolution Owners must admit it; the
/// fixture cannot assert a Run state or authorize a Provider call.
fn native_local_effect_reject_review(
  journal : @client.NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  checkpoint : @checkpoint.SealedCheckpoint,
) -> Unit raise {
  let http = @http.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SALESFORCE_HTTP_LIBRARY").unwrap(),
  ).unwrap()
  let client = http
    .create_authenticated_client(
      @env.get_env_var("ACTQL_TEST_NATIVE_SALESFORCE_HTTP_CA").unwrap(),
      Bearer(
        @env.get_env_var("ACTQL_TEST_NATIVE_SALESFORCE_HTTP_SECRET").unwrap(),
      ),
      262144L,
      2000,
      5000,
    )
    .unwrap()
  let reply = client
    .post_json(
      @env.get_env_var("ACTQL_TEST_NATIVE_SALESFORCE_HTTP_URL").unwrap() +
      "/fixture/native-local-effect-rejection",
      @utf8.encode(checkpoint.wire),
    )
    .unwrap()
  assert_eq(reply.status, 200)
  let value = @json.parse(@utf8.decode(reply.body))
  let text = (key : String) => {
    guard value is Object(fields) && fields.get(key) is Some(String(value)) else {
      abort("Invalid signed Local rejection fixture")
    }
    value
  }
  let wire = text("ACTQL_TEST_EFFECT_VERIFIED_WIRE")
  let limits : @checkpoint.WireLimits = {
    max_wire_bytes: 65536,
    max_nodes: 4096,
    max_depth: 64,
  }
  let crypto = @signature.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
  ).unwrap()
  let authentication : @checkpoint.HostAuthentication = {
    key_id: "reviewer-key",
    reviewer_id: "native-reviewer",
    expected_authority_scope_cid: retained_compute_cid("5"),
    authority_context_cid: retained_compute_cid("6"),
    policy_cid: retained_compute_cid("7"),
    proof_preimage: @checkpoint.resolution_proof_preimage(
      text("ACTQL_TEST_EFFECT_RESOLUTION_WIRE"),
      limits,
    ).unwrap(),
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
  let resolve = (current : Bool) => {
    journal.resolve_effect_checkpoint(
      request,
      crypto,
      wire,
      authentication,
      reviewers,
      keys,
      () => current,
      () => "2026-10-10T00:01:00.000Z",
    )
  }
  assert_true(resolve(false) is Err(@client.AuthorizationDenied))
  let rejected = resolve(true).unwrap()
  assert_eq(
    @client.native_client_run_checkpoint_state(rejected).unwrap().status,
    @publication.Cancelled,
  )
  assert_eq(
    @client.native_client_run_record_revision(resolve(true).unwrap()),
    @client.native_client_run_record_revision(rejected),
  )
}
