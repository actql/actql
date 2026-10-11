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
  let progress = @filesystem.open_root(
    retained_runtime_required_env("ACTQL_TEST_NATIVE_RETAINED_TASK_ROOT"),
  ).unwrap()
  let mark = (phase : String) => {
    progress.create_directory("effect-completion-" + phase).unwrap() |> ignore
  }
  mark("start")
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
  let direct_prepare = () => {
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
  let delivery = @remote.prepare_remote_effect_resume_delivery(
    report,
    resolution,
    observed.claim,
    limits.ledger,
  ).unwrap()
  let body = @remote.remote_effect_resume_delivery_json(delivery)
  let receive = body => {
    work.prepare_remote_approved_row(
      body,
      authentication,
      reviewers,
      keys,
      () => allowed.val,
      () => Some(current_resume.val),
      at,
      limits,
    )
  }
  let prepare = () => receive(body)
  allowed.val = false
  assert_true(direct_prepare() is Err(Resolution(_)))
  assert_true(prepare() is Err(AuthorityDenied))
  allowed.val = true
  current_resume.val = { ..observed, settlement_only: true, }
  assert_true(prepare() is Err(AuthorityDenied))
  current_resume.val = { ..observed, resume_intent_id: "foreign-intent", }
  assert_true(prepare() is Err(AuthorityDenied))
  current_resume.val = {
    ..observed,
    claim: { ..observed.claim, generation: generation + 1L, },
  }
  assert_true(prepare() is Err(AuthorityDenied))
  current_resume.val = {
    ..observed,
    claim: { ..observed.claim, claimant: "another-coordinator", },
  }
  assert_true(prepare() is Err(AuthorityDenied))
  current_resume.val = observed
  for
    field in [
      "report_cid", "dispatch_request_cid", "resolution_cid", "resume_intent_id",
    ] {
    let foreign = body.replace(
      old="\"" + field + "\":\"",
      new="\"" + field + "\":\"foreign-",
    )
    assert_true(receive(foreign) is Err(ForeignRequest))
  }
  assert_true(work.restore_row_custody(limits.ledger) is Ok(None))
  assert_true(
    work.observe_effect_custody(() => false, limits.ledger)
    is Err(EvidenceDenied),
  )
  let before_send_observation = work
    .observe_effect_custody(() => true, limits.ledger)
    .unwrap()
  assert_eq(
    before_send_observation.report_cid,
    @remote.remote_effect_checkpoint_report_identity(report),
  )
  assert_eq(before_send_observation.ledger_head_cid, None)
  assert_eq(before_send_observation.unknown_effects(), [])
  assert_false(before_send_observation.response_saved)
  let current_query = @remote.prepare_remote_effect_current_query(
    report,
    before_send_observation.effect_id,
    "native-current-before-send",
    limits.ledger,
  ).unwrap()
  assert_true(
    work.answer_effect_current(current_query, () => false, limits.ledger)
    is Err(EvidenceDenied),
  )
  if @env.get_env_var("ACTQL_TEST_EFFECT_CURRENT_FIXTURE_URL") is Some(url) {
    retained_holder_report_effect_current(
      work,
      current_query,
      url,
      limits.ledger,
      true,
    )
  }
  let before_reply = work
    .answer_effect_current(current_query, () => true, limits.ledger)
    .unwrap()
  assert_eq(
    @remote.remote_effect_current_reply_facts(
      @remote.admit_remote_effect_current_reply_json(
        current_query,
        @remote.remote_effect_current_reply_json(before_reply),
        limits.ledger,
      ).unwrap(),
    ),
    (None, 0, false),
  )
  let foreign_member_query = @remote.prepare_remote_effect_current_query(
    report,
    "foreign-effect-member",
    "native-current-foreign",
    limits.ledger,
  ).unwrap()
  assert_true(
    work.answer_effect_current(foreign_member_query, () => true, limits.ledger)
    is Err(Row(ForeignRequest)),
  )
  let observation_reads = Ref(0)
  assert_true(
    work.observe_effect_custody(
      () => {
        observation_reads.val += 1
        observation_reads.val == 1
      },
      limits.ledger,
    )
    is Err(EvidenceDenied),
  )
  assert_eq(observation_reads.val, 2)
  let row = prepare().unwrap()
  assert_true(physical_equal(row, prepare().unwrap()))
  // A cached delivered row cannot be borrowed through the older unfenced
  // preparation or silently rebound to a new current Coordinator lease.
  assert_true(direct_prepare() is Err(ForeignRequest))
  let next_claim = { ..observed.claim, generation: generation + 1L, }
  let next_delivery = @remote.prepare_remote_effect_resume_delivery(
    report,
    resolution,
    next_claim,
    limits.ledger,
  ).unwrap()
  current_resume.val = {
    ..observed,
    claim: next_claim,
    view: { ..observed.view, generation: next_claim.generation, },
  }
  assert_true(
    receive(@remote.remote_effect_resume_delivery_json(next_delivery))
    is Err(ForeignRequest),
  )
  assert_true(prepare() is Err(AuthorityDenied))
  current_resume.val = observed
  mark("missing-response-start")
  assert_true(
    work.complete_saved_effect(() => true, limits)
    is Err(Row(ReconciliationRequired)),
  )
  mark("missing-response-end")
  let request = row.request()
  let create = @catalog.single_write_request_kind(request)
    is @catalog.SingleCreate
  let response_status = if create { 201 } else { 204 }
  // Independently authored physical Provider response, not a receipt or a
  // synthesized successful Effect. The Catalog response Owner admits it.
  let response_body = if create {
    b"{\"id\":\"001000000000001AAA\",\"success\":true,\"errors\":[]}"
  } else {
    b""
  }
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
    operation: @catalog.single_write_request_grant_operation(request),
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
        verb: if create {
          @http.Post
        } else {
          @http.Patch
        },
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
  mark("physical-send-start")
  println("native-approved-row: sending original checked request")
  assert_true(row.send(access) is Err(Journal(Physical(_))))
  mark("physical-send-end")
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
  assert_eq(observed_use.status, Some(response_status))
  assert_true(row.send(access) is Err(ReconciliationRequired))
  peer.rollback().unwrap()
  println("native-approved-row: retrying original raw response custody")
  assert_eq(row.retry_response_custody().unwrap(), true)
  assert_eq(row.retry_response_custody().unwrap(), false)
  assert_eq(
    peer.read("site_effect_response_bytes", cid).unwrap().body,
    response_body,
  )
  // Current write permission is gone. Historical custody remains observable
  // and can settle its exact saved response without another approval or send.
  allowed.val = false
  current_resume.val = { ..observed, settlement_only: true, }
  let restored = work.restore_row_custody(limits.ledger).unwrap().unwrap()
  let pending_observation = work
    .observe_effect_custody(() => true, limits.ledger)
    .unwrap()
  assert_eq(
    pending_observation.ledger_head_cid,
    Some(@effect.effect_ledger_entry_cid(restored.head)),
  )
  assert_eq(pending_observation.unknown_effects(), [
    pending_observation.effect_id,
  ])
  let caller_copy = pending_observation.unknown_effects()
  caller_copy.clear()
  assert_eq(pending_observation.unknown_effects(), [
    pending_observation.effect_id,
  ])
  assert_true(pending_observation.response_saved)
  let pending_query = @remote.prepare_remote_effect_current_query(
    report,
    pending_observation.effect_id,
    "native-current-pending",
    limits.ledger,
  ).unwrap()
  if @env.get_env_var("ACTQL_TEST_EFFECT_CURRENT_FIXTURE_URL") is Some(url) {
    retained_holder_report_effect_current(
      work,
      pending_query,
      url,
      limits.ledger,
      false,
    )
  }
  let pending_reply = work
    .answer_effect_current(pending_query, () => true, limits.ledger)
    .unwrap()
  let pending_body = @remote.remote_effect_current_reply_json(pending_reply)
  assert_eq(
    @remote.remote_effect_current_reply_facts(
      @remote.admit_remote_effect_current_reply_json(
        pending_query,
        pending_body,
        limits.ledger,
      ).unwrap(),
    ),
    (pending_observation.ledger_head_cid, 3, true),
  )
  assert_eq(@effect.effect_ledger_entry_cid(restored.dispatching.unwrap()), cid)
  assert_eq(restored.response.unwrap().status_code, response_status)
  assert_eq(restored.response.unwrap().credential_use_cid, observed_use.use_cid)
  assert_eq(restored.response.unwrap().body, response_body)
  assert_true(direct_prepare() is Err(Resolution(_)))
  assert_true(prepare() is Err(AuthorityDenied))
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
  mark("terminal-failure-start")
  assert_true(
    work.complete_saved_effect(() => true, limits)
    is Err(Row(Journal(Physical(_)))),
  )
  mark("terminal-failure-end")
  // Custody is unconfirmed and the same peer still holds SQLite's write lock.
  // Cleanup must preserve the concrete Store failure and all reservations.
  assert_true(work.retry_cleanup() is Err(Journal(Physical(_))))
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
  mark("terminal-settlement-start")
  let (receipt, terminal) = work.settle_saved_row(limits).unwrap()
  mark("terminal-settlement-end")
  assert_eq(row.retry_response_custody().unwrap(), false)
  assert_true(terminal.state is @effect.Applied)
  let terminal_observation = work
    .observe_effect_custody(() => true, limits.ledger)
    .unwrap()
  assert_eq(
    terminal_observation.ledger_head_cid,
    Some(@effect.effect_ledger_entry_cid(terminal)),
  )
  assert_eq(terminal_observation.unknown_effects(), [])
  assert_true(terminal_observation.response_saved)
  let terminal_query = @remote.prepare_remote_effect_current_query(
    report,
    terminal_observation.effect_id,
    "native-current-terminal",
    limits.ledger,
  ).unwrap()
  assert_true(
    @remote.admit_remote_effect_current_reply_json(
      terminal_query,
      pending_body,
      limits.ledger,
    )
    is Err(InvalidDispatch),
  )
  if @env.get_env_var("ACTQL_TEST_EFFECT_CURRENT_FIXTURE_URL") is Some(url) {
    retained_holder_report_effect_current(
      work,
      terminal_query,
      url,
      limits.ledger,
      false,
    )
  }
  let terminal_reply = work
    .answer_effect_current(terminal_query, () => true, limits.ledger)
    .unwrap()
  assert_eq(
    @remote.remote_effect_current_reply_facts(
      @remote.admit_remote_effect_current_reply_json(
        terminal_query,
        @remote.remote_effect_current_reply_json(terminal_reply),
        limits.ledger,
      ).unwrap(),
    ),
    (terminal_observation.ledger_head_cid, 5, true),
  )
  assert_eq(
    @publication.effect_row_outcome_receipt_terminal_state(receipt),
    Some("applied"),
  )
  assert_eq(
    peer.read("site_effect_response_bytes", cid).unwrap().body,
    response_body,
  )
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
  assert_true(
    work.complete_saved_effect(() => false, limits) is Err(EvidenceDenied),
  )
  let evidence_reads = Ref(0)
  assert_true(
    work.complete_saved_effect(
      () => {
        evidence_reads.val += 1
        mark("early-revocation-" + evidence_reads.val.to_string())
        evidence_reads.val == 1
      },
      limits,
    )
    is Err(EvidenceDenied),
  )
  evidence_reads.val = 0
  assert_true(
    work.complete_saved_effect(
      () => {
        evidence_reads.val += 1
        mark("final-revocation-" + evidence_reads.val.to_string())
        evidence_reads.val < 3
      },
      limits,
    )
    is Err(EvidenceDenied),
  )
  assert_eq(evidence_reads.val, 3)
  mark("receipt-completion-start")
  evidence_reads.val = 0
  let completion = work
    .complete_saved_effect(
      () => {
        evidence_reads.val += 1
        mark("completion-authority-" + evidence_reads.val.to_string())
        true
      },
      limits,
    )
    .unwrap()
  mark("receipt-completion-end")
  assert_eq(
    @publication.publication_contract_json(completion.row_receipt),
    @publication.publication_contract_json(receipt),
  )
  assert_eq(
    @publication.publication_contract_name(completion.final_receipt),
    "run_receipt",
  )
  assert_true(
    @publication.publication_contract_identity(completion.final_receipt) !=
    @publication.publication_contract_identity(result.receipt),
  )
  assert_eq(
    @publication.effect_set_receipt_run_disposition(
      completion.preview,
      @publication.publication_contract_json(completion.set_receipt),
      [@publication.publication_contract_json(completion.member_receipt)],
      limits.ledger.max_wire_bytes,
      limits.ledger.max_nodes,
      limits.ledger.max_depth,
    ).unwrap(),
    0,
  )
  mark("repeated-receipts-start")
  let repeated_completion = work
    .complete_saved_effect(() => true, limits)
    .unwrap()
  mark("repeated-receipts-end")
  assert_eq(
    @publication.publication_contract_json(repeated_completion.final_receipt),
    @publication.publication_contract_json(completion.final_receipt),
  )
  assert_eq(
    @publication.publication_contract_json(repeated_completion.set_receipt),
    @publication.publication_contract_json(completion.set_receipt),
  )
  assert_eq(
    @publication.publication_contract_json(repeated_completion.member_receipt),
    @publication.publication_contract_json(completion.member_receipt),
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
  // The final receipt binds the original computation, capture and row evidence.
  // Publication commit and formal Site release remain distinct Owner operations.
  ignore(client.close())
  database.close_checked().unwrap()
  peer.close_checked().unwrap()
  println(
    "native-approved-row: common receipt and original Ledger terminal saved without another send",
  )
}

///|
/// The peer accepts transport bytes only. Original query/row/report admission
/// and Ledger facts are issued by the actual review Owner above.
fn retained_holder_report_effect_current(
  work : @effect_provider.NativeResidentEffectReview,
  query : @remote.RemoteEffectCurrentQuery,
  url : String,
  limits : @checkpoint.WireLimits,
  first : Bool,
) -> Unit raise {
  let required = name => @env.get_env_var(name).unwrap()
  let http = @http.load_library(required("ACTQL_TEST_NATIVE_HTTP_LIBRARY")).unwrap()
  let client = http
    .create_authenticated_client(
      required("ACTQL_TEST_NATIVE_HTTP_CA"),
      Bearer(required("ACTQL_TEST_NATIVE_HTTP_SECRET")),
      65536L,
      2000,
      5000,
    )
    .unwrap()
  defer assert_true(client.close())
  let body = @remote.remote_effect_current_query_json(query)
  if first {
    assert_true(
      work.report_effect_current(body, client, url, () => false, limits)
      is Err(EvidenceDenied),
    )
    let foreign = body.replace(
      old="\"report_cid\":\"",
      new="\"report_cid\":\"foreign-",
    )
    assert_true(
      work.report_effect_current(foreign, client, url, () => true, limits)
      is Err(Query(_)),
    )
    let report = @remote.remote_effect_current_query_report(query)
    let other = @remote.prepare_remote_effect_current_query(
      report, "foreign-effect-member", "native-current-foreign-transport", limits,
    ).unwrap()
    assert_true(
      work.report_effect_current(
        @remote.remote_effect_current_query_json(other),
        client,
        url,
        () => true,
        limits,
      )
      is Err(Observation(Row(ForeignRequest))),
    )
    // The first actual post is refused by the peer. It must not become an
    // Effect success or an automatic Provider retry.
    assert_true(
      work.report_effect_current(body, client, url, () => true, limits)
      is Err(Transport(HttpStatus(503))),
    )
  }
  let sent = work
    .report_effect_current(body, client, url, () => true, limits)
    .unwrap()
  let current = work.answer_effect_current(query, () => true, limits).unwrap()
  assert_eq(
    @remote.remote_effect_current_reply_json(sent),
    @remote.remote_effect_current_reply_json(current),
  )
  if first {
    let root = @filesystem.open_root(required("ACTQL_TEST_NATIVE_TARGET_ROOT")).unwrap()
    let authorized = () => {
      root.inspect_generation("current-evidence-revoked") is Ok(None)
    }
    assert_true(authorized())
    let revoked = @remote.prepare_remote_effect_current_query(
      @remote.remote_effect_current_query_report(query),
      @remote.remote_effect_current_query_effect_id(query),
      "native-current-revoked",
      limits,
    ).unwrap()
    // The actual peer retires the independent read permission during HTTP.
    // Transport may have accepted the old snapshot, but no current reply may
    // be returned to the caller after that revocation.
    assert_true(
      work.report_effect_current(
        @remote.remote_effect_current_query_json(revoked),
        client,
        url,
        authorized,
        limits,
      )
      is Err(EvidenceDenied),
    )
    assert_false(authorized())
  }
}
