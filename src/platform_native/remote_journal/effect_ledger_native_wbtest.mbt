///|
fn native_effect_ledger_fixture() -> (
  @request_scope.LogicalRequestScope,
  @effect.LogicalItemLocator,
  @effect.EffectDispatchKey,
  @effect.EffectLedgerBasis,
) {
  let c = (value : String) => "sha256:" + value.repeat(64)
  let scope = @effect.prepare_logical_request_scope(
    c("a"),
    "effect-request",
    64,
  ).unwrap()
  // Protocol-authored row: this exercises real common entries and SQLite,
  // not a genuine Native Preview/approval or a complete public Run.
  let key = @effect.prepare_effect_dispatch_key(
    scope,
    c("3"),
    "\"row-1\"",
    64,
    16,
    4,
  ).unwrap()
  let locator = @effect.prepare_logical_item_locator(
    scope, "program-1", "effect-1", "WriteOne", "{\"id\":1}", 64, 128, 16, 4,
  ).unwrap()
  let basis = @effect.prepare_effect_ledger_basis(
    scope,
    locator,
    key,
    c("b"),
    c("c"),
    c("d"),
    c("e"),
    c("f"),
    "unavailable",
    c("0"),
    c("1"),
  ).unwrap()
  (scope, locator, key, basis)
}

///|
fn native_effect_ledger_limits() -> @checkpoint.WireLimits {
  { max_wire_bytes: 4096, max_nodes: 128, max_depth: 8, }
}

///|
fn native_effect_ledger_open(
  name : String,
) -> (@sqlite.Library, String, Journal) {
  let library = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).unwrap()
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT").unwrap()
  let path = root +
    "/effect-ledger-" +
    name +
    "-" +
    @env.now().to_string() +
    ".sqlite3"
  (
    library,
    path,
    open_journal(library, path, 262144L, test_control(test_site())).unwrap(),
  )
}

///|
fn native_effect_ledger_ready(
  journal : Journal,
  request : @remote.DispatchRequest,
) -> Unit {
  let (_, record) = journal.accept(request).unwrap()
  journal
  .commit_transition(
    @remote.prepare_begin_provisioning(record, test_capability(test_site())).unwrap(),
  )
  .unwrap()
  journal
  .commit_transition(@remote.prepare_begin_remote_execution(record).unwrap())
  .unwrap()
  journal
  .commit_transition(@remote.prepare_confirm_native_settled(record).unwrap())
  .unwrap()
  journal
  .retain_effect_checkpoint_report(
    checkpoint_report_fixture(request, "original-review"),
  )
  .unwrap()
}

///|
test "native Effect Ledger claim uncertainty never permits a second dispatch" {
  let (library, path, journal) = native_effect_ledger_open("claim")
  let request = test_request("effect-ledger-claim")
  native_effect_ledger_ready(journal, request)
  let (scope, locator, key, basis) = native_effect_ledger_fixture()
  let claim = () => {
    journal.claim_effect_ledger_dispatch(
      request,
      scope,
      locator,
      key,
      basis,
      native_effect_ledger_limits(),
      checkpoint_report_limits(),
    )
  }
  test_fail_cancel_commit(journal.database, 1)
  assert_true(claim() is Err(Physical(_)))
  assert_true(
    journal.database.read(
      "site_effect_ledger_head",
      @effect.logical_item_locator_cid(locator),
    )
    is Err(@sqlite.NotFound),
  )
  // Commit succeeded but its reply was lost: no send permission is returned.
  test_fail_cancel_commit_reply(journal.database, 1)
  assert_true(claim() is Err(Physical(_)))
  let (won, dispatching) = claim().unwrap()
  assert_false(won)
  assert_eq(
    @effect.effect_row_recovery_action_from_entry(
      locator,
      basis.intent_fingerprint_cid,
      key,
      basis.canonical_request_cid,
      Some(dispatching),
      false,
    ),
    3,
  )
  let head = journal.database
    .read("site_effect_ledger_head", @effect.logical_item_locator_cid(locator))
    .unwrap()
  assert_eq(head.revision, 0L)
  assert_true(
    journal.effect_ledger_response(request, dispatching).unwrap() is None,
  )
  assert_true(
    journal.claim_effect_ledger_dispatch(
      request,
      scope,
      locator,
      key,
      @effect.prepare_effect_ledger_basis(
        scope,
        locator,
        key,
        basis.unit_definition_cid,
        basis.original_membership_cid,
        basis.intent_fingerprint_cid,
        "sha256:" + "9".repeat(64),
        basis.recovery_contract_cid,
        basis.capability,
        basis.reservation_evidence_cid,
        basis.retention_contract_cid,
      ).unwrap(),
      native_effect_ledger_limits(),
      checkpoint_report_limits(),
    )
    is Err(StateCollision),
  )
  assert_eq(
    journal.database
    .read("site_effect_ledger_head", @effect.logical_item_locator_cid(locator))
    .unwrap().body,
    head.body,
  )
  let other = open_journal(library, path, 262144L, test_control(test_site())).unwrap()
  assert_false(
    other
    .claim_effect_ledger_dispatch(
      request,
      scope,
      locator,
      key,
      basis,
      native_effect_ledger_limits(),
      checkpoint_report_limits(),
    )
    .unwrap().0,
  )
  assert_true(other.close())
  assert_true(journal.close())
  let reopened = open_journal(library, path, 262144L, test_control(test_site())).unwrap()
  let replay = reopened
    .claim_effect_ledger_dispatch(
      request,
      scope,
      locator,
      key,
      basis,
      native_effect_ledger_limits(),
      checkpoint_report_limits(),
    )
    .unwrap()
  assert_false(replay.0)
  assert_eq(
    @effect.effect_ledger_entry_cid(replay.1),
    @effect.effect_ledger_entry_cid(dispatching),
  )
  assert_true(reopened.close())
}

///|
test "native Effect Ledger saves raw response before interpretation and preserves it across retry and reopen" {
  let (library, path, journal) = native_effect_ledger_open("raw")
  let request = test_request("effect-ledger-response")
  native_effect_ledger_ready(journal, request)
  let (scope, locator, key, basis) = native_effect_ledger_fixture()
  let (won, dispatching) = journal
    .claim_effect_ledger_dispatch(
      request,
      scope,
      locator,
      key,
      basis,
      native_effect_ledger_limits(),
      checkpoint_report_limits(),
    )
    .unwrap()
  assert_true(won)
  assert_false(
    journal
    .claim_effect_ledger_dispatch(
      request,
      scope,
      locator,
      key,
      basis,
      native_effect_ledger_limits(),
      checkpoint_report_limits(),
    )
    .unwrap().0,
  )
  let response : NativeEffectSavedResponse = {
    credential_use_cid: "sha256:" + "7".repeat(64),
    status_code: 409,
    body: b"\x00\xffe\xcc\x81\r\n",
  }
  let save = (value : NativeEffectSavedResponse) => {
    journal.record_effect_ledger_response(
      request,
      dispatching,
      scope,
      locator,
      key,
      basis.canonical_request_cid,
      value,
    )
  }
  test_fail_cancel_commit(journal.database, 1)
  assert_true(save(response) is Err(Physical(_)))
  assert_true(
    journal.effect_ledger_response(request, dispatching).unwrap() is None,
  )
  // Sending may have preceded cancellation. Raw response custody is still due.
  journal.request_cancellation(request).unwrap() |> ignore
  test_fail_cancel_commit_reply(journal.database, 1)
  assert_true(save(response) is Err(Physical(_)))
  save(response).unwrap()
  assert_true(save({ ..response, body: b"other", }) is Err(StateCollision))
  assert_true(save({ ..response, status_code: 200, }) is Err(StateCollision))
  assert_true(
    save({ ..response, credential_use_cid: "sha256:" + "8".repeat(64), })
    is Err(StateCollision),
  )
  let stored = journal
    .effect_ledger_response(request, dispatching)
    .unwrap()
    .unwrap()
  assert_eq(stored.body, response.body)
  assert_eq(stored.status_code, 409)
  let cid = @effect.effect_ledger_entry_cid(dispatching)
  assert_eq(
    journal.database.read("site_effect_response_bytes", cid).unwrap().revision,
    0L,
  )
  assert_eq(
    journal.database.read("site_effect_response_meta", cid).unwrap().revision,
    0L,
  )
  assert_true(journal.close())
  let control = test_control(test_site())
  let twin = open_journal(library, path, 262144L, control).unwrap()
  assert_eq(
    twin.effect_ledger_response(request, dispatching).unwrap().unwrap().body,
    response.body,
  )
  // Test-only physical corruption must not become a saved Provider success.
  twin.database
  .compare_exchange("site_effect_response_bytes", cid, 0L, b"corrupted")
  .unwrap()
  |> ignore
  assert_true(
    twin.effect_ledger_response(request, dispatching) is Err(StateCollision),
  )
  assert_true(twin.close())
}

///|
test "native Effect Ledger refuses missing review foreign dispatch and stale Site binding" {
  let (_, _, journal) = native_effect_ledger_open("binding")
  let request = test_request("effect-ledger-binding")
  let (scope, locator, key, basis) = native_effect_ledger_fixture()
  assert_true(
    journal.claim_effect_ledger_dispatch(
      request,
      scope,
      locator,
      key,
      basis,
      native_effect_ledger_limits(),
      checkpoint_report_limits(),
    )
    is Err(MissingDispatch),
  )
  native_effect_ledger_ready(journal, request)
  let (won, dispatching) = journal
    .claim_effect_ledger_dispatch(
      request,
      scope,
      locator,
      key,
      basis,
      native_effect_ledger_limits(),
      checkpoint_report_limits(),
    )
    .unwrap()
  assert_true(won)
  let foreign = test_request_for(
    "another-effect-dispatch",
    8,
    4,
    "sha256:" + "a".repeat(64),
  )
  native_effect_ledger_ready(journal, foreign)
  assert_true(
    journal.claim_effect_ledger_dispatch(
      foreign,
      scope,
      locator,
      key,
      basis,
      native_effect_ledger_limits(),
      checkpoint_report_limits(),
    )
    is Err(StateCollision),
  )
  assert_true(
    journal.effect_ledger_response(foreign, dispatching) is Err(StateCollision),
  )
  // Cancellation before claim cannot be bypassed by an already-saved review.
  journal.request_cancellation(foreign).unwrap() |> ignore
  assert_true(
    journal.claim_effect_ledger_dispatch(
      foreign,
      scope,
      locator,
      key,
      basis,
      native_effect_ledger_limits(),
      checkpoint_report_limits(),
    )
    is Err(StateCollision),
  )
  let response : NativeEffectSavedResponse = {
    credential_use_cid: "sha256:" + "7".repeat(64),
    status_code: 200,
    body: b"ok",
  }
  assert_true(
    journal.record_effect_ledger_response(
      foreign,
      dispatching,
      scope,
      locator,
      key,
      basis.canonical_request_cid,
      response,
    )
    is Err(StateCollision),
  )
  // Changing only the durable current Site identity invalidates mutation;
  // historical custody remains readable and no old binding becomes current.
  journal.database
  .compare_exchange(
    "site_metadata", "binding", 0L, b"different-site-generation",
  )
  .unwrap()
  |> ignore
  assert_true(
    journal.record_effect_ledger_response(
      request,
      dispatching,
      scope,
      locator,
      key,
      basis.canonical_request_cid,
      response,
    )
    is Err(StaleSiteBinding),
  )
  assert_true(
    journal.claim_effect_ledger_dispatch(
      request,
      scope,
      locator,
      key,
      basis,
      native_effect_ledger_limits(),
      checkpoint_report_limits(),
    )
    is Err(StaleSiteBinding),
  )
  assert_true(
    journal.effect_ledger_response(request, dispatching).unwrap() is None,
  )
  assert_true(journal.close())
}

///|
test "native Effect Ledger custody reconstruction reads original claims without dispatching" {
  let (library, path, journal) = native_effect_ledger_open("restore")
  let request = test_request("effect-ledger-restore")
  native_effect_ledger_ready(journal, request)
  let (scope, locator, key, basis) = native_effect_ledger_fixture()
  let read = (owner : Journal) => {
    owner.effect_ledger_custody(
      request,
      scope,
      locator,
      key,
      basis,
      native_effect_ledger_limits(),
      checkpoint_report_limits(),
    )
  }
  assert_true(read(journal).unwrap() is None)
  assert_true(
    journal.database.read(
      "site_effect_ledger_binding",
      @effect.logical_item_locator_cid(locator),
    )
    is Err(@sqlite.NotFound),
  )
  // An uncertain read-only commit returns no custody fact and creates no claim.
  test_fail_cancel_commit_reply(journal.database, 1)
  assert_true(read(journal) is Err(Physical(_)))
  assert_true(read(journal).unwrap() is None)
  let (won, dispatching) = journal
    .claim_effect_ledger_dispatch(
      request,
      scope,
      locator,
      key,
      basis,
      native_effect_ledger_limits(),
      checkpoint_report_limits(),
    )
    .unwrap()
  assert_true(won)
  let original = journal.database
    .read("site_effect_ledger_head", @effect.logical_item_locator_cid(locator))
    .unwrap()
  assert_true(journal.close())
  let reopened = open_journal(library, path, 262144L, test_control(test_site())).unwrap()
  let before = read(reopened).unwrap().unwrap()
  assert_eq(
    @effect.effect_ledger_entry_cid(before.dispatching.unwrap()),
    @effect.effect_ledger_entry_cid(dispatching),
  )
  assert_true(before.response is None)
  assert_eq(
    @effect.effect_row_recovery_action_from_entry(
      locator,
      basis.intent_fingerprint_cid,
      key,
      basis.canonical_request_cid,
      Some(before.head),
      false,
    ),
    3,
  )
  let response : NativeEffectSavedResponse = {
    credential_use_cid: "sha256:" + "7".repeat(64),
    status_code: 409,
    body: b"original raw refusal",
  }
  reopened
  .record_effect_ledger_response(
    request,
    dispatching,
    scope,
    locator,
    key,
    basis.canonical_request_cid,
    response,
  )
  .unwrap()
  assert_true(reopened.close())
  let restored = open_journal(library, path, 262144L, test_control(test_site())).unwrap()
  let custody = read(restored).unwrap().unwrap()
  assert_eq(
    custody.response.unwrap().credential_use_cid,
    response.credential_use_cid,
  )
  assert_eq(custody.response.unwrap().status_code, response.status_code)
  assert_eq(custody.response.unwrap().body, response.body)
  let repeated = read(restored).unwrap().unwrap()
  assert_eq(
    @effect.effect_ledger_entry_cid(repeated.head),
    @effect.effect_ledger_entry_cid(custody.head),
  )
  let after = restored.database
    .read("site_effect_ledger_head", @effect.logical_item_locator_cid(locator))
    .unwrap()
  assert_eq(after.revision, original.revision)
  assert_eq(after.body, original.body)
  let foreign = test_request_for(
    "another-effect-ledger-restore", 8, 4,
    test_cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
  )
  native_effect_ledger_ready(restored, foreign)
  assert_true(
    restored.effect_ledger_custody(
      foreign,
      scope,
      locator,
      key,
      basis,
      native_effect_ledger_limits(),
      checkpoint_report_limits(),
    )
    is Err(StateCollision),
  )
  let different = @effect.prepare_effect_ledger_basis(
    scope,
    locator,
    key,
    "sha256:" + "9".repeat(64),
    basis.original_membership_cid,
    basis.intent_fingerprint_cid,
    basis.canonical_request_cid,
    basis.recovery_contract_cid,
    basis.capability,
    basis.reservation_evidence_cid,
    basis.retention_contract_cid,
  ).unwrap()
  assert_true(
    restored.effect_ledger_custody(
      request,
      scope,
      locator,
      key,
      different,
      native_effect_ledger_limits(),
      checkpoint_report_limits(),
    )
    is Err(StateCollision),
  )
  restored.request_cancellation(request).unwrap() |> ignore
  // Cancellation/generation changes retain historical evidence, not permission
  // to send or mutate under the old Site binding.
  restored.database
  .compare_exchange(
    "site_metadata", "binding", 0L, b"different-site-generation",
  )
  .unwrap()
  |> ignore
  assert_eq(
    read(restored).unwrap().unwrap().response.unwrap().body,
    response.body,
  )
  assert_true(
    restored.claim_effect_ledger_dispatch(
      request,
      scope,
      locator,
      key,
      basis,
      native_effect_ledger_limits(),
      checkpoint_report_limits(),
    )
    is Err(StaleSiteBinding),
  )
  // A head without its immutable chain is not absence or a completed row.
  let bad = @utf8.encode("corrupt historical entry")
  restored.database
  .compare_exchange(
    "site_effect_ledger_entry",
    @effect.effect_ledger_entry_cid(dispatching),
    0L,
    bad,
  )
  .unwrap()
  |> ignore
  assert_true(read(restored) is Err(StateCollision))
  assert_true(restored.close())
}
