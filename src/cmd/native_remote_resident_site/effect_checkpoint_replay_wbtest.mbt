///|
test "empty Effect report replay avoids unrelated dispatch reconstruction and keeps present corruption pending" {
  let (http, client, slot, _) = control_terminal_fixture(
    "empty-checkpoint-replay",
  )
  let (library, journal, request, path, _) = cleanup_test_open(
    "empty-checkpoint-replay",
  )
  journal.accept(request).unwrap() |> ignore
  let raw = library.open_database(path, 262144L).unwrap()
  let key = @remote.dispatch_request_attempt_identity(request).unwrap()
  let saved = raw.read("site_dispatch", key).unwrap()
  raw.compare_exchange("site_dispatch", key, saved.revision, b"{").unwrap()
  |> ignore
  assert_true(journal.require(request) is Err(Protocol(_)))
  assert_true(journal.has_effect_checkpoint_reports() is Ok(false))
  let cursor = Ref("previous-scheduling-hint")
  let next = Ref(0UL)
  let callbacks = Ref(0)
  let advance = (current, selected) => {
    advance_effect_checkpoint_replay(
      current,
      client,
      "https://127.0.0.1/unavailable",
      completed_output_test_delegation(selected),
      4,
      cursor,
      next,
      0UL,
      100,
      _ => callbacks.val += 1,
    )
  }
  assert_true(advance(journal, request) is Idle)
  assert_eq(cursor.val, "")
  assert_eq(next.val, 0UL)
  // No dispatch admission or mutation is inferred from absence of work. The
  // independent selected-record read still rejects its authored corruption.
  assert_true(journal.require(request) is Err(Protocol(_)))
  raw.close()
  assert_true(journal.close())
  assert_true(advance(journal, request) is Pending(_, "journal-recovery"))
  // A distinct valid original dispatch plus malformed report DATA must still
  // enter its complete report admission, never the empty-work shortcut.
  let (same_library, pending, pending_request, pending_path, _) = cleanup_test_open(
    "present-checkpoint-replay",
  )
  pending.accept(pending_request).unwrap() |> ignore
  let raw_pending = same_library.open_database(pending_path, 262144L).unwrap()
  raw_pending
  .insert(
    "site_effect_checkpoint_report",
    @remote.dispatch_request_identity(pending_request),
    b"{",
  )
  .unwrap()
  |> ignore
  assert_true(pending.has_effect_checkpoint_reports() is Ok(true))
  assert_true(pending.require(pending_request) is Ok(_))
  assert_true(advance(pending, pending_request) is Pending(_, "journal-report"))
  raw_pending.close()
  assert_true(pending.close())
  assert_eq(callbacks.val, 0)
  assert_true(client.response_limit() is Ok(64L))
  client.close_checked().unwrap()
  assert_true(slot.close())
  http.close_checked().unwrap()
}

///|
/// Authored protocol evidence with real SQLite and authenticated HTTPS. This
/// isolates the production control replay call, not Provider Preview, encrypted
/// continuation persistence, Cloud waiting, approval or Effect execution.
test "control restart replays only the original pending Effect report and saves its exact ACK" {
  // The authenticated HTTP harness supplies this finite peer. Ordinary Core
  // runs do not establish this delivery acceptance without that environment.
  guard @env.get_env_var("ACTQL_TEST_NATIVE_EFFECT_CHECKPOINT_URL")
    is Some(origin) else {
    if @env.get_env_var("ACTQL_REQUIRE_NATIVE_EFFECT_REPLAY_TESTS") is Some("1") {
      fail(
        "selected Effect replay acceptance requires its authenticated HTTPS peer",
      )
    }
    return
  }
  let required = name => @env.get_env_var(name).unwrap()
  let http = @http.load_library(required("ACTQL_TEST_NATIVE_HTTP_LIBRARY")).unwrap()
  let client = http
    .create_client(
      required("ACTQL_TEST_NATIVE_HTTP_CA"),
      required("ACTQL_TEST_NATIVE_HTTP_CERT"),
      required("ACTQL_TEST_NATIVE_HTTP_KEY"),
      262144L,
      2000,
      3000,
    )
    .unwrap()
  let (library, journal, request, path, site) = cleanup_test_open(
    "effect-control-replay",
  )
  let scope = @remote.dispatch_request_execution_scope(request)
  let record = journal.accept(request).unwrap().1
  let capability = @remote.register_remote_execution_capability(
    site,
    scope[2],
    scope[3],
    scope[4],
    scope[5],
    scope[6],
  ).unwrap()
  journal
  .commit_transition(
    @remote.prepare_begin_provisioning(record, capability).unwrap(),
  )
  .unwrap()
  journal
  .commit_transition(@remote.prepare_begin_remote_execution(record).unwrap())
  .unwrap()
  journal
  .commit_transition(@remote.prepare_confirm_native_settled(record).unwrap())
  .unwrap()
  let cursor : Ref[String] = Ref("")
  let next : Ref[UInt64] = Ref(0UL)
  let delegation = completed_output_test_delegation(request)
  let advance = (current, route, instant, point) => {
    cursor.val = ""
    advance_effect_checkpoint_replay(
      current,
      client,
      origin + route,
      delegation,
      4,
      cursor,
      next,
      instant,
      100,
      point,
    )
  }
  assert_true(advance(journal, "/accepted", 0UL, fn(_) {  }) is Idle)
  let c = (fill : String) => "sha256:" + fill.repeat(64)
  let artifact = @checkpoint.seal_checkpoint(
    {
      checkpoint_id: "control-review",
      continuation_state_cid: c("2"),
      subject: @checkpoint.RunUnit(
        run_id="original-run",
        unit_id="compute",
        run_definition_cid=@remote.dispatch_request_task_scope(request).0,
      ),
      phase: @checkpoint.Commit,
      kind: @checkpoint.EffectSet,
      required_artifact_cid: c("3"),
      review_projection_cid: c("4"),
      requirements: [@checkpoint.EffectScopeApproved],
      reason_code: "effect_review_required",
      human_summary: "Original review",
      created_at: "2026-10-10T00:00:00.000Z",
      expires_at: "2099-01-01T00:00:00.000Z",
    },
    resident_checkpoint_report_limits(),
  ).unwrap()
  let report = @remote.prepare_remote_effect_checkpoint_report(
    request,
    @checkpoint.confirm_checkpoint_persisted(artifact, artifact.wire).unwrap(),
    resident_checkpoint_report_limits(),
  ).unwrap()
  journal.retain_effect_checkpoint_report(report).unwrap()
  let original_wire = @remote.remote_effect_checkpoint_report_json(report)
  cursor.val = ""
  assert_true(
    advance_effect_checkpoint_replay(
      journal,
      client,
      origin + "/accepted",
      { ..delegation, site_key: "foreign-site", },
      4,
      cursor,
      next,
      0UL,
      100,
      fn(_) {  },
    )
    is Pending(_, "scope-mismatch"),
  )
  assert_eq(
    journal
    .effect_checkpoint_report(request, resident_checkpoint_report_limits())
    .unwrap().1,
    None,
  )
  // Retry is bounded by the same transient deadline. No HTTP request occurs
  // before it, even when a control pass revisits the original dispatch.
  assert_true(advance(journal, "/accepted", 99UL, fn(_) {  }) is Idle)
  // The same class deadline also covers another original dispatch, without
  // allocating a history key or reading/sending that dispatch before it is due.
  let (_, sibling, sibling_request, _, _) = cleanup_test_open(
    "effect-control-replay-sibling",
  )
  sibling.accept(sibling_request).unwrap() |> ignore
  let sibling_cursor : Ref[String] = Ref("")
  assert_true(
    advance_effect_checkpoint_replay(
      sibling,
      client,
      origin + "/accepted",
      delegation,
      4,
      sibling_cursor,
      next,
      99UL,
      100,
      fn(_) {  },
    )
    is Idle,
  )
  assert_eq(sibling_cursor.val, "")
  assert_eq(
    @remote.dispatch_record_revision(sibling.require(sibling_request).unwrap()),
    0,
  )
  assert_eq(sibling.start_claimant(sibling_request).unwrap(), None)
  sibling.close_checked().unwrap()
  assert_true(
    advance(journal, "/lost", 100UL, fn(_) {  }) is Pending(_, "transport"),
  )
  assert_true(advance(journal, "/accepted", 199UL, fn(_) {  }) is Idle)
  let lock = library.open_database(path, 262144L).unwrap()
  let lost_save = advance(journal, "/accepted", 200UL, step => {
    if step == "before-checkpoint-ack-save" {
      lock.begin_immediate().unwrap()
    }
  })
  assert_true(lost_save is Pending(_, "journal"))
  assert_eq(
    journal
    .effect_checkpoint_report(request, resident_checkpoint_report_limits())
    .unwrap().1,
    None,
  )
  lock.rollback().unwrap()
  let revision = @remote.dispatch_record_revision(
    journal.require(request).unwrap(),
  )
  assert_true(journal.close())
  let reopen = () => {
    let current_site = @site.create_site(
      scope[0],
      4,
      scope[2],
      4,
      4,
      1048576L,
      1048576L,
    ).unwrap()
    @journal.open_journal(
      library,
      path,
      262144L,
      @remote.create_site_dispatch_journal(
        current_site, "actql-remote-site/0.1",
      ).unwrap(),
    ).unwrap()
  }
  let restored = reopen()
  let restart_cursor : Ref[String] = Ref("")
  let replay = () => {
    restart_cursor.val = ""
    advance_effect_checkpoint_replay(
      restored,
      client,
      origin + "/accepted",
      delegation,
      4,
      restart_cursor,
      Ref(0UL),
      0UL,
      100,
      fn(_) {  },
    )
  }
  assert_true(
    replay() is Acknowledged(identity) &&
    identity == @remote.dispatch_request_identity(request),
  )
  assert_eq(
    @remote.remote_effect_checkpoint_report_json(
      restored
      .effect_checkpoint_report(request, resident_checkpoint_report_limits())
      .unwrap().0,
    ),
    original_wire,
  )
  assert_true(replay() is Idle)
  assert_eq(
    @remote.dispatch_record_revision(restored.require(request).unwrap()),
    revision,
  )
  assert_eq(restored.start_claimant(request).unwrap(), None)
  assert_false(
    @remote.remote_runtime_record_released(restored.require(request).unwrap()),
  )
  assert_true(restored.close())
  let again = reopen()
  assert_eq(
    again
    .effect_checkpoint_report(request, resident_checkpoint_report_limits())
    .unwrap().1,
    Some(@remote.RemoteEffectCheckpointReply::Accepted),
  )
  assert_true(
    advance_effect_checkpoint_replay(
      again,
      client,
      origin + "/accepted",
      delegation,
      4,
      Ref(""),
      Ref(0UL),
      0UL,
      100,
      fn(_) {  },
    )
    is Idle,
  )
  assert_true(again.close())
  let counts = client.post_json(origin + "/counts", b"{}").unwrap()
  assert_eq(
    @utf8.decode(counts.body),
    "{\"accepted\":2,\"bare\":0,\"foreign\":0,\"lost\":1}",
  )
  lock.close()
  assert_true(client.close())
}
