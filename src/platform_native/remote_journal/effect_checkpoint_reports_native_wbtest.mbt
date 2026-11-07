///|
fn checkpoint_report_limits() -> @checkpoint.WireLimits {
  { max_wire_bytes: 262144, max_nodes: 4096, max_depth: 32, }
}

///|
fn checkpoint_report_fixture(
  request : @remote.DispatchRequest,
  id : String,
) -> @remote.RemoteEffectCheckpointReport {
  let c = (fill : String) => "sha256:" + fill.repeat(64)
  let artifact = @checkpoint.seal_checkpoint(
    {
      checkpoint_id: id,
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
      human_summary: "Review original Effect",
      created_at: "2026-10-10T00:00:00.000Z",
      expires_at: "2099-01-01T00:00:00.000Z",
    },
    checkpoint_report_limits(),
  ).unwrap()
  // Protocol-authored fixture only. Genuine Native paired Store evidence is
  // exercised separately by the resident Provider/Checkpoint custody case.
  let persisted = @checkpoint.confirm_checkpoint_persisted(
    artifact,
    artifact.wire,
  ).unwrap()
  @remote.prepare_remote_effect_checkpoint_report(
    request,
    persisted,
    checkpoint_report_limits(),
  ).unwrap()
}

///|
test "native Effect checkpoint journal retains original report and exact ACK across reopen and failed commits" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")
    is Some(library_path) else {
    fail("actual SQLite is required")
  }
  guard @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT") is Some(root) else {
    fail("owned SQLite root is required")
  }
  let library = @sqlite.load_library(library_path).unwrap()
  let path = root + "/effect-report-" + @env.now().to_string() + ".sqlite3"
  let open = () => {
    open_journal(library, path, 262144L, test_control(test_site())).unwrap()
  }
  let journal = open()
  assert_true(journal.has_effect_checkpoint_reports() is Ok(false))
  let request = test_request("effect-checkpoint-report")
  let report = checkpoint_report_fixture(request, "review-1")
  assert_true(
    journal.retain_effect_checkpoint_report(report) is Err(MissingDispatch),
  )
  let (_, record) = journal.accept(request).unwrap()
  assert_true(
    journal.retain_effect_checkpoint_report(report) is Err(StateCollision),
  )
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
  // Cancellation before first retention cannot manufacture a waiting review.
  let cancelled_request = test_request_for(
    "cancelled-review",
    8,
    4,
    test_cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
  )
  journal.request_cancellation(cancelled_request).unwrap() |> ignore
  assert_true(
    journal.retain_effect_checkpoint_report(
      checkpoint_report_fixture(cancelled_request, "cancelled-review"),
    )
    is Err(StateCollision),
  )
  let lock = library.open_database(path, 262144L).unwrap()
  lock.begin_immediate().unwrap()
  assert_true(journal.retain_effect_checkpoint_report(report) is Err(_))
  assert_true(
    journal.effect_checkpoint_report(request, checkpoint_report_limits())
    is Err(Physical(@sqlite.NotFound)),
  )
  lock.rollback().unwrap()
  assert_true(journal.has_effect_checkpoint_reports() is Ok(false))
  journal.retain_effect_checkpoint_report(report).unwrap()
  assert_true(journal.has_effect_checkpoint_reports() is Ok(true))
  journal.retain_effect_checkpoint_report(report).unwrap()
  let wire = @remote.remote_effect_checkpoint_report_json(report)
  assert_true(
    journal.retain_effect_checkpoint_report(
      checkpoint_report_fixture(request, "different-review"),
    )
    is Err(StateCollision),
  )
  assert_true(journal.close())
  let restored = open()
  assert_true(restored.has_effect_checkpoint_reports() is Ok(true))
  let (original, pending) = restored
    .effect_checkpoint_report(request, checkpoint_report_limits())
    .unwrap()
  assert_eq(@remote.remote_effect_checkpoint_report_json(original), wire)
  assert_eq(pending, None)
  let ack = @remote.remote_effect_checkpoint_reply_json(report, Accepted).unwrap()
  let wrong = @remote.remote_effect_checkpoint_reply_json(
    checkpoint_report_fixture(request, "different-review"),
    Accepted,
  ).unwrap()
  assert_true(
    restored.record_effect_checkpoint_reply(
      request,
      wrong,
      checkpoint_report_limits(),
    )
    is Err(Protocol(_)),
  )
  lock.begin_immediate().unwrap()
  assert_true(
    restored.record_effect_checkpoint_reply(
      request,
      ack,
      checkpoint_report_limits(),
    )
    is Err(_),
  )
  assert_eq(
    restored
    .effect_checkpoint_report(request, checkpoint_report_limits())
    .unwrap().1,
    None,
  )
  lock.rollback().unwrap()
  restored
  .record_effect_checkpoint_reply(request, ack, checkpoint_report_limits())
  .unwrap()
  restored
  .record_effect_checkpoint_reply(request, ack, checkpoint_report_limits())
  .unwrap()
  let saved = lock
    .read(
      "site_effect_checkpoint_reply",
      @remote.dispatch_request_identity(request),
    )
    .unwrap()
  assert_eq(saved.revision, 0L)
  assert_true(
    restored.record_effect_checkpoint_reply(
      request,
      @remote.remote_effect_checkpoint_reply_json(
        report,
        Refused("report_conflict"),
      ).unwrap(),
      checkpoint_report_limits(),
    )
    is Err(StateCollision),
  )
  assert_true(restored.close())
  assert_true(restored.has_effect_checkpoint_reports() is Err(Closed))
  let again = open()
  assert_true(again.has_effect_checkpoint_reports() is Ok(true))
  assert_eq(
    again.effect_checkpoint_report(request, checkpoint_report_limits()).unwrap().1,
    Some(@remote.RemoteEffectCheckpointReply::Accepted),
  )
  let next_site = @site.create_site(
    "native-site",
    5,
    test_cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
    4,
    4,
    1048576L,
    1048576L,
  ).unwrap()
  again.restart(next_site).unwrap() |> ignore
  let restarted = open_journal(library, path, 262144L, test_control(next_site)).unwrap()
  assert_true(restarted.retain_effect_checkpoint_report(report) is Err(_))
  assert_true(again.retain_effect_checkpoint_report(report) is Err(_))
  assert_true(restarted.close())
  assert_true(again.close())
  assert_eq(
    lock
    .read(
      "site_effect_checkpoint_report",
      @remote.dispatch_request_identity(request),
    )
    .unwrap().body,
    @utf8.encode(wire),
  )
  assert_eq(
    lock
    .read(
      "site_effect_checkpoint_reply",
      @remote.dispatch_request_identity(request),
    )
    .unwrap().body,
    saved.body,
  )
  lock.close()
}
