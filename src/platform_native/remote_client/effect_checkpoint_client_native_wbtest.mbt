///|
test "native Effect review delivery preserves original report after HTTPS and ACK-save failures" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_EFFECT_CHECKPOINT_URL") is Some(origin) else { return }
  let required = name => @env.get_env_var(name).unwrap()
  let http = @http.load_library(required("ACTQL_TEST_NATIVE_HTTP_LIBRARY")).unwrap()
  let client = http.create_client(required("ACTQL_TEST_NATIVE_HTTP_CA"), required("ACTQL_TEST_NATIVE_HTTP_CERT"), required("ACTQL_TEST_NATIVE_HTTP_KEY"), 262144L, 2000, 3000).unwrap()
  let library = @sqlite.load_library(required("ACTQL_TEST_NATIVE_SQLITE_LIBRARY")).unwrap()
  let path = required("ACTQL_TEST_NATIVE_REMOTE_JOURNAL") + ".effect-review"
  let c = (fill : String) => "sha256:" + fill.repeat(64)
  let site = @site.create_site("native-site", 1, c("a"), 4, 4, 1048576L, 1048576L).unwrap()
  let open = () => @journal.open_journal(library, path, 262144L, @remote.create_site_dispatch_journal(site, "actql-remote-site/0.1").unwrap()).unwrap()
  let journal = open()
  let request = native_remote_request()
  let (_, record) = journal.accept(request).unwrap()
  let capability = @remote.register_remote_execution_capability(site, c("a"), "local", "local/1", "strategy/1", c("4")).unwrap()
  journal.commit_transition(@remote.prepare_begin_provisioning(record, capability).unwrap()).unwrap()
  journal.commit_transition(@remote.prepare_begin_remote_execution(record).unwrap()).unwrap()
  journal.commit_transition(@remote.prepare_confirm_native_settled(record).unwrap()).unwrap()
  let limits : @checkpoint.WireLimits = {max_wire_bytes: 262144, max_nodes: 4096, max_depth: 32}
  let artifact = @checkpoint.seal_checkpoint({
    checkpoint_id: "review-https", continuation_state_cid: c("2"),
    subject: @checkpoint.RunUnit(run_id="original-run", unit_id="compute", run_definition_cid=@remote.dispatch_request_task_scope(request).0),
    phase: @checkpoint.Commit, kind: @checkpoint.EffectSet,
    required_artifact_cid: c("3"), review_projection_cid: c("4"), requirements: [@checkpoint.EffectScopeApproved],
    reason_code: "effect_review_required", human_summary: "Review original write",
    created_at: "2026-10-10T00:00:00.000Z", expires_at: "2099-01-01T00:00:00.000Z",
  }, limits).unwrap()
  // Protocol-authored fixture. Physical Provider/Store readback has independent
  // Native acceptance; this test isolates the real HTTP and journal boundary.
  let report = @remote.prepare_remote_effect_checkpoint_report(request, @checkpoint.confirm_checkpoint_persisted(artifact, artifact.wire).unwrap(), limits).unwrap()
  // A missing original report is never reconstructed by the delivery adapter.
  assert_true(acknowledge_retained_effect_checkpoint(journal, client, origin + "/accepted", request, limits) is Err(Journal(_)))
  journal.retain_effect_checkpoint_report(report).unwrap()
  for route in ["bare", "foreign", "lost"] {
    assert_true(acknowledge_retained_effect_checkpoint(journal, client, origin + "/" + route, request, limits) is Err(_))
    assert_eq(journal.effect_checkpoint_report(request, limits).unwrap().1, None)
  }
  let lock = library.open_database(path, 262144L).unwrap()
  let lost = acknowledge_retained_effect_checkpoint(journal, client, origin + "/accepted", request, limits,
    checkpoint=step => { if step == "before-checkpoint-ack-save" { lock.begin_immediate().unwrap() } })
  assert_true(lost is Err(Journal(_)))
  assert_eq(journal.effect_checkpoint_report(request, limits).unwrap().1, None)
  lock.rollback().unwrap()
  assert_true(journal.close())
  let restored = open()
  assert_eq(@remote.remote_effect_checkpoint_report_json(restored.effect_checkpoint_report(request, limits).unwrap().0), @remote.remote_effect_checkpoint_report_json(report))
  assert_true(acknowledge_retained_effect_checkpoint(restored, client, origin + "/accepted", request, limits) is Ok(()))
  assert_true(acknowledge_retained_effect_checkpoint(restored, client, origin + "/accepted", request, limits) is Ok(()))
  let counts = client.post_json(origin + "/counts", b"{}").unwrap()
  assert_eq(@utf8.decode(counts.body), "{\"accepted\":2,\"bare\":1,\"foreign\":1,\"lost\":1}")
  assert_eq(restored.effect_checkpoint_report(request, limits).unwrap().1, Some(@remote.RemoteEffectCheckpointReply::Accepted))
  assert_eq(lock.read("site_effect_checkpoint_reply", @remote.dispatch_request_identity(request)).unwrap().revision, 0L)
  assert_true(restored.close())
  lock.close()
  assert_true(client.close())
}
