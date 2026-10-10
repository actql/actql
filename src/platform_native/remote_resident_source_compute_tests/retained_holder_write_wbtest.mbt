///|
/// Execute the exact original reviewed row through real SQLite and HTTPS.
/// The current resume facts use the common Owner under a local trusted fixture;
/// this is not a durable Cloud claim or public approval acceptance.
fn retained_holder_write_row(
  work : @effect_provider.NativeResidentEffectReview,
  report : @remote.RemoteEffectCheckpointReport,
  signed : (
    String,
    @checkpoint.HostAuthentication,
    Array[@checkpoint.ReviewerAuthority],
    Array[@effect_provider.NativeEffectHostAuthority],
  ),
  invocation : @publication.PublicationContract,
  journal_path : String,
  consumer : @resident.ResidentSourceCompute,
  result : @resident.ResidentEffectResultCapture,
) -> Unit raise {
  let (wire, authentication, reviewers, keys) = signed
  let at = () => "2026-10-10T00:01:00.000Z"
  let resolution = work
    .admit_resolution(wire, authentication, reviewers, keys, () => true, at)
    .unwrap()
  let binding : @checkpoint.ResumeBinding = {
    authorization_context_cid: authentication.authority_context_cid,
    environment_binding_cid: authentication.policy_cid,
  }
  let pending : @checkpoint.ResumeIntentView = {
    state: @checkpoint.ResumePending,
    generation: 0L,
    claimant: "",
    lease_expires_ms: 0L,
  }
  let claimant = "native-trusted-resume-fixture"
  let now = 1791590460000L
  guard @checkpoint.decide_effect_resume_claim(
      pending, claimant, now, 60000L, binding, binding, false,
    )
    is Ok(@checkpoint.ClaimIntent(generation, expiry)) else {
    fail("common resume Owner refused the local trusted fixture")
  }
  let observed : @effect_provider.NativeEffectResumeObservation = {
    checkpoint_cid: resolution.checkpoint_cid,
    resolution_cid: resolution.resolution_cid,
    resume_intent_id: resolution.resume_intent_id.unwrap(),
    view: {
      state: @checkpoint.ResumeClaimed,
      generation,
      claimant,
      lease_expires_ms: expiry,
    },
    claim: { generation, claimant, },
    now_ms: now,
    settlement_only: false,
  }
  let allowed = Ref(true)
  let current_resume = Ref(observed)
  let limits : @effect_provider.NativeResidentEffectWriteLimits = {
    response: { max_bytes: 4096, max_nodes: 128, max_depth: 16, max_rows: 1, },
    ledger: { max_wire_bytes: 65536, max_nodes: 1000, max_depth: 32, },
  }
  let prepare = () => {
    work.prepare_approved_row(
      wire,
      authentication,
      reviewers,
      keys,
      () => allowed.val,
      () => Some(current_resume.val),
      at,
      limits,
    )
  }
  allowed.val = false
  assert_true(prepare() is Err(Resolution(_)))
  allowed.val = true
  current_resume.val = { ..observed, settlement_only: true, }
  assert_true(prepare() is Err(AuthorityDenied))
  current_resume.val = { ..observed, resume_intent_id: "foreign-intent", }
  assert_true(prepare() is Err(AuthorityDenied))
  current_resume.val = observed
  let row = prepare().unwrap()
  assert_true(physical_equal(row, prepare().unwrap()))
  let request = row.request()
  assert_eq(@catalog.single_write_request_body(request), "{\"Count__c\":3}")
  let origin = retained_runtime_required_env(
    "ACTQL_TEST_NATIVE_HTTP_BEARER_URL",
  )
  // The write has a separate current grant; Source/observe permission is not reused.
  let scope : @resource.NativeCredentialScope = {
    principal: "principal-a",
    namespace_id: "namespace-a",
    environment: "test",
    site_key: "retained-native",
    site_generation: 1,
    runtime_bundle_cid: retained_runtime_required_env(
      "ACTQL_TEST_NATIVE_REMOTE_RUNTIME_BUNDLE_CID",
    ),
    connector_registration: "salesforce",
    connector_revision: "salesforce/0.1",
    resource_origin: origin,
    operation: "salesforce:record:update",
    run_invocation_cid: @publication.publication_contract_identity(invocation),
    task_attempt: 1,
    dispatch_request_cid: @remote.dispatch_request_identity(
      @remote.remote_effect_checkpoint_report_dispatch(report),
    ),
  }
  let grant = @credential.prepare_grant(
    "credential-authority-a",
    scope.principal,
    scope.namespace_id,
    scope.environment,
    scope.site_key,
    scope.site_generation,
    scope.runtime_bundle_cid,
    scope.connector_registration,
    scope.connector_revision,
    scope.resource_origin,
    scope.operation,
    scope.run_invocation_cid,
    scope.task_attempt,
    scope.dispatch_request_cid,
    2000000000000L,
    1,
  ).unwrap()
  let sqlite = @sqlite.load_library(
    retained_runtime_required_env("ACTQL_TEST_NATIVE_SQLITE_LIBRARY"),
  ).unwrap()
  let database = sqlite
    .open_database(journal_path + ".write-credential", 65536L)
    .unwrap()
  let peer = sqlite.open_database(journal_path, 1048576L).unwrap()
  let http = @http.load_library(
    retained_runtime_required_env("ACTQL_TEST_NATIVE_HTTP_LIBRARY"),
  ).unwrap()
  let secret = retained_runtime_required_env(
      "ACTQL_TEST_NATIVE_HTTP_BEARER_ROOT",
    ) +
    "/control"
  let client = http
    .create_authenticated_client(
      retained_runtime_required_env("ACTQL_TEST_NATIVE_HTTP_CA"),
      @http.Bearer(secret),
      4096L,
      2000,
      5000,
    )
    .unwrap()
  let cleanup_blocked = Ref(false)
  let storage_blocked = Ref(false)
  let service = @resource.install_native_credential_resource_service(
    database,
    client,
    [
      {
        resource_origin: origin,
        operation: scope.operation,
        path: @catalog.single_write_request_path(request),
        secret_path: secret,
        verb: @http.Patch,
        max_request_bytes: 1024,
      },
    ],
    authorization => {
      if authorization.stage == "send" {
        cleanup_blocked.val = work.retry_cleanup() is Err(Unavailable)
        peer.begin_immediate().unwrap()
        storage_blocked.val = true
      }
      true
    },
  ).unwrap()
  let access : @effect_provider.NativeSalesforceTargetAccess = {
    service,
    grant,
    use_id: "original-approved-row",
    scope,
    credential_org_id: "00D000000000001EAA",
  }
  allowed.val = false
  assert_true(row.send(access) is Err(AuthorityDenied))
  allowed.val = true
  assert_true(
    row.send({ ..access, scope: { ..scope, site_generation: 2, }, })
    is Err(ForeignRequest),
  )
  assert_true(row.dispatch_entry() is None)
  let before = consumer.usage().reserved_retention_bytes
  println("native-approved-row: sending original checked request")
  assert_true(row.send(access) is Err(Journal(Physical(_))))
  assert_true(cleanup_blocked.val && storage_blocked.val)
  assert_true(work.retry_cleanup() is Err(Unavailable))
  assert_eq(consumer.usage().reserved_retention_bytes, before)
  let dispatching = row.dispatch_entry().unwrap()
  let cid = @effect.effect_ledger_entry_cid(dispatching)
  assert_true(
    peer.read("site_effect_response_meta", cid) is Err(@sqlite.NotFound),
  )
  let observed_use = @resource.query_native_credential_use(
    service,
    grant,
    access.use_id,
    scope,
  ).unwrap()
  assert_eq(observed_use.outcome, "succeeded")
  assert_eq(observed_use.status, Some(204))
  assert_true(row.send(access) is Err(ReconciliationRequired))
  peer.rollback().unwrap()
  println("native-approved-row: retrying original raw response custody")
  assert_eq(row.retry_response_custody().unwrap(), true)
  assert_eq(row.retry_response_custody().unwrap(), false)
  assert_eq(peer.read("site_effect_response_bytes", cid).unwrap().body, b"")
  // Current write permission is gone. Historical custody remains observable
  // and can settle its exact saved response without another approval or send.
  allowed.val = false
  current_resume.val = { ..observed, settlement_only: true, }
  let restored = work.restore_row_custody(limits.ledger).unwrap().unwrap()
  assert_eq(@effect.effect_ledger_entry_cid(restored.dispatching.unwrap()), cid)
  assert_eq(restored.response.unwrap().status_code, 204)
  assert_eq(restored.response.unwrap().credential_use_cid, observed_use.use_cid)
  assert_eq(restored.response.unwrap().body, b"")
  assert_true(prepare() is Err(Resolution(_)))
  assert_true(work.retry_cleanup() is Err(Unavailable))
  assert_eq(consumer.usage().reserved_retention_bytes, before)
  let dispatch_head = peer
    .read(
      "site_effect_ledger_head",
      @effect.effect_ledger_entry_locator_cid(dispatching),
    )
    .unwrap()
  peer.begin_immediate().unwrap()
  println(
    "native-approved-row: retaining responsibility after terminal save failure",
  )
  assert_true(work.settle_saved_row(limits) is Err(Journal(Physical(_))))
  assert_true(work.retry_cleanup() is Err(Unavailable))
  assert_eq(consumer.usage().reserved_retention_bytes, before)
  let pending_head = peer
    .read(
      "site_effect_ledger_head",
      @effect.effect_ledger_entry_locator_cid(dispatching),
    )
    .unwrap()
  assert_eq(pending_head.revision, dispatch_head.revision)
  assert_eq(pending_head.body, dispatch_head.body)
  assert_true(row.send(access) is Err(ReconciliationRequired))
  peer.rollback().unwrap()
  let (receipt, terminal) = work.settle_saved_row(limits).unwrap()
  assert_eq(row.retry_response_custody().unwrap(), false)
  assert_true(terminal.state is @effect.Applied)
  assert_eq(
    @publication.effect_row_outcome_receipt_terminal_state(receipt),
    Some("applied"),
  )
  assert_eq(peer.read("site_effect_response_bytes", cid).unwrap().body, b"")
  let original = peer
    .read(
      "site_effect_ledger_head",
      @effect.effect_ledger_entry_locator_cid(terminal),
    )
    .unwrap()
  assert_eq(original.revision, 1L)
  let repeated = work.settle_saved_row(limits).unwrap()
  assert_eq(
    @effect.effect_ledger_entry_cid(row.settle().unwrap().1),
    @effect.effect_ledger_entry_cid(terminal),
  )
  assert_eq(
    @effect.effect_ledger_entry_cid(repeated.1),
    @effect.effect_ledger_entry_cid(terminal),
  )
  assert_eq(
    peer
    .read(
      "site_effect_ledger_head",
      @effect.effect_ledger_entry_locator_cid(terminal),
    )
    .unwrap().revision,
    original.revision,
  )
  assert_true(row.send(access) is Err(ReconciliationRequired))
  assert_true(result.output.result_schema_wire() is Ok(_))
  assert_eq(consumer.usage().reserved_retention_bytes, before)
  // Failed cleanup probes retained the pending write, rather than starting
  // holder retirement. Original approval evidence remains admissible under
  // independently supplied current authority; it does not permit a resend.
  assert_true(
    work.admit_resolution(wire, authentication, reviewers, keys, () => true, at)
    is Ok(_),
  )
  // Row terminality discharges only this pending physical write. Overall Run
  // publication and formal Site release are not implied by these saved facts.
  ignore(client.close())
  database.close_checked().unwrap()
  peer.close_checked().unwrap()
  println(
    "native-approved-row: common receipt and original Ledger terminal saved without another send",
  )
}
