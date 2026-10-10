///|
fn effect_resume_poll_fixture() -> (RemoteEffectResumeDelivery, String) {
  let (report, auth, reviewers, wire, _) = effect_resume_fixture()
  let resolution = @checkpoint.admit_attested_effect_resolution(
      remote_effect_checkpoint_report_checkpoint(report),
      wire,
      auth,
      reviewers,
      review_limits(),
    ).unwrap().resolution
  let delivery = prepare_remote_effect_resume_delivery(
    report,
    resolution,
    { claimant: "original-coordinator", generation: 1L, },
    review_limits(),
  ).unwrap()
  // Independent fixture encoding in spec/fixtures/remote-effect-resume-vectors.json.
  (
    delivery, "{\"delivery_json\":\"{\\\"checkpoint_cid\\\":\\\"sha256:5f519ab12d76e539039de72a94b1b2f337654c8741ea17cee0266231a56ec10d\\\",\\\"claimant\\\":\\\"original-coordinator\\\",\\\"dispatch_request_cid\\\":\\\"sha256:3b5d3a0baae35a4c3ed4f9d3a9bbf3bab875cdb325db11b18ea8b5dd1af04f93\\\",\\\"generation\\\":\\\"1\\\",\\\"report_cid\\\":\\\"sha256:31bcdabc6df955bda9b2f862d7a8ef59554b566b19ca4a3406ba13a861d85996\\\",\\\"resolution_cid\\\":\\\"sha256:19e9389ed7f0a966255f0d76aaec9718d2fc82aa4c41e2b762af2626e88e4f19\\\",\\\"resolution_wire\\\":\\\"{\\\\\\\"approval_evidence\\\\\\\":{\\\\\\\"checkpoint_cid\\\\\\\":\\\\\\\"sha256:5f519ab12d76e539039de72a94b1b2f337654c8741ea17cee0266231a56ec10d\\\\\\\",\\\\\\\"compatibility_approval\\\\\\\":{\\\\\\\"approved_at\\\\\\\":\\\\\\\"2026-10-10T00:01:00.000Z\\\\\\\",\\\\\\\"approver\\\\\\\":\\\\\\\"alice\\\\\\\",\\\\\\\"attestation_cid\\\\\\\":\\\\\\\"sha256:58c346e2d95c3ea04430a14d5691a157244726df76a0250de4492bb89f463432\\\\\\\",\\\\\\\"authority_scope_cid\\\\\\\":\\\\\\\"sha256:5555555555555555555555555555555555555555555555555555555555555555\\\\\\\",\\\\\\\"claims\\\\\\\":[\\\\\\\"effect_scope_approved\\\\\\\"],\\\\\\\"effect_preview_cid\\\\\\\":\\\\\\\"sha256:3333333333333333333333333333333333333333333333333333333333333333\\\\\\\",\\\\\\\"proof\\\\\\\":{\\\\\\\"key_id\\\\\\\":\\\\\\\"reviewer-key\\\\\\\",\\\\\\\"scheme\\\\\\\":\\\\\\\"ed25519-v1\\\\\\\",\\\\\\\"signature\\\\\\\":\\\\\\\"c2lnbmF0dXJl\\\\\\\"},\\\\\\\"review_projection_cid\\\\\\\":\\\\\\\"sha256:4444444444444444444444444444444444444444444444444444444444444444\\\\\\\",\\\\\\\"version\\\\\\\":\\\\\\\"actql-approval-attestation/0.1\\\\\\\"},\\\\\\\"kind\\\\\\\":\\\\\\\"effect_set\\\\\\\",\\\\\\\"review_projection_cid\\\\\\\":\\\\\\\"sha256:4444444444444444444444444444444444444444444444444444444444444444\\\\\\\",\\\\\\\"version\\\\\\\":\\\\\\\"actql-checkpoint-approval-evidence/0.1\\\\\\\"},\\\\\\\"authorization_context_cid\\\\\\\":\\\\\\\"sha256:6666666666666666666666666666666666666666666666666666666666666666\\\\\\\",\\\\\\\"authorization_evidence\\\\\\\":{\\\\\\\"authority_context_cid\\\\\\\":\\\\\\\"sha256:6666666666666666666666666666666666666666666666666666666666666666\\\\\\\",\\\\\\\"checkpoint_cid\\\\\\\":\\\\\\\"sha256:5f519ab12d76e539039de72a94b1b2f337654c8741ea17cee0266231a56ec10d\\\\\\\",\\\\\\\"key_id\\\\\\\":\\\\\\\"reviewer-key\\\\\\\",\\\\\\\"resolution_cid\\\\\\\":\\\\\\\"sha256:19e9389ed7f0a966255f0d76aaec9718d2fc82aa4c41e2b762af2626e88e4f19\\\\\\\",\\\\\\\"version\\\\\\\":\\\\\\\"actql-checkpoint-resolution-authorization-evidence/0.1\\\\\\\"},\\\\\\\"authorization_evidence_cid\\\\\\\":\\\\\\\"sha256:f5a58b6577470b015c38a75a8d01297e8b96604a108298b7996269ec2edbc918\\\\\\\",\\\\\\\"host_attestation\\\\\\\":{\\\\\\\"host_key_id\\\\\\\":\\\\\\\"host-key\\\\\\\",\\\\\\\"scheme\\\\\\\":\\\\\\\"ed25519-v1\\\\\\\",\\\\\\\"signature\\\\\\\":\\\\\\\"aG9zdA==\\\\\\\"},\\\\\\\"requirements\\\\\\\":[\\\\\\\"effect_scope_approved\\\\\\\"],\\\\\\\"resolution\\\\\\\":{\\\\\\\"actor\\\\\\\":\\\\\\\"alice\\\\\\\",\\\\\\\"approval_evidence_cid\\\\\\\":\\\\\\\"sha256:0fbdaa8a8c8406c0d81643b6fa4d7beb13dff23badd14e50d2e67c8e51bd1a05\\\\\\\",\\\\\\\"checkpoint_cid\\\\\\\":\\\\\\\"sha256:5f519ab12d76e539039de72a94b1b2f337654c8741ea17cee0266231a56ec10d\\\\\\\",\\\\\\\"checkpoint_id\\\\\\\":\\\\\\\"review-1\\\\\\\",\\\\\\\"decided_at\\\\\\\":\\\\\\\"2026-10-10T00:01:00.000Z\\\\\\\",\\\\\\\"decision\\\\\\\":\\\\\\\"approved\\\\\\\",\\\\\\\"proof\\\\\\\":{\\\\\\\"key_id\\\\\\\":\\\\\\\"reviewer-key\\\\\\\",\\\\\\\"scheme\\\\\\\":\\\\\\\"ed25519-v1\\\\\\\",\\\\\\\"signature\\\\\\\":\\\\\\\"c2lnbmF0dXJl\\\\\\\"},\\\\\\\"required_artifact_cid\\\\\\\":\\\\\\\"sha256:3333333333333333333333333333333333333333333333333333333333333333\\\\\\\",\\\\\\\"resolution_cid\\\\\\\":\\\\\\\"sha256:19e9389ed7f0a966255f0d76aaec9718d2fc82aa4c41e2b762af2626e88e4f19\\\\\\\",\\\\\\\"resolution_id\\\\\\\":\\\\\\\"resolution-1\\\\\\\",\\\\\\\"review_projection_cid\\\\\\\":\\\\\\\"sha256:4444444444444444444444444444444444444444444444444444444444444444\\\\\\\",\\\\\\\"run_definition_cid\\\\\\\":\\\\\\\"sha256:0000000000000000000000000000000000000000000000000000000000000000\\\\\\\",\\\\\\\"run_id\\\\\\\":\\\\\\\"run-1\\\\\\\",\\\\\\\"version\\\\\\\":\\\\\\\"actql-checkpoint-resolution/0.1\\\\\\\"},\\\\\\\"verified_at\\\\\\\":\\\\\\\"2026-10-10T00:01:01.000Z\\\\\\\",\\\\\\\"verified_by_policy_cid\\\\\\\":\\\\\\\"sha256:7777777777777777777777777777777777777777777777777777777777777777\\\\\\\",\\\\\\\"verified_resolution_cid\\\\\\\":\\\\\\\"sha256:9b9a8d9d6fc76b0254d4708b1d71cb130ad4a9ba6bda2beca4bf26695482ab6b\\\\\\\",\\\\\\\"verified_reviewer_id\\\\\\\":\\\\\\\"alice\\\\\\\",\\\\\\\"version\\\\\\\":\\\\\\\"actql-verified-checkpoint-resolution/0.1\\\\\\\"}\\\",\\\"resume_intent_id\\\":\\\"sha256:14592585f30f30a822f36461bd2187dd8926f52ebea2e0a9e21f17b2924bbf73\\\",\\\"version\\\":\\\"actql-remote-effect-resume-delivery/0.1\\\"}\",\"dispatch_request_cid\":\"sha256:3b5d3a0baae35a4c3ed4f9d3a9bbf3bab875cdb325db11b18ea8b5dd1af04f93\",\"request_json\":\"{\\\"budget_cid\\\":\\\"sha256:3333333333333333333333333333333333333333333333333333333333333333\\\",\\\"connector_registration\\\":\\\"local\\\",\\\"connector_revision\\\":\\\"local/1\\\",\\\"coordinator_authority\\\":\\\"coordinator-a\\\",\\\"dispatch_id\\\":\\\"consumer-a\\\",\\\"evidence_issuer_capability_cid\\\":\\\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\\",\\\"grant_cid\\\":\\\"sha256:4444444444444444444444444444444444444444444444444444444444444444\\\",\\\"input_binding_cid\\\":\\\"sha256:1111111111111111111111111111111111111111111111111111111111111111\\\",\\\"obligations_cid\\\":\\\"sha256:2222222222222222222222222222222222222222222222222222222222222222\\\",\\\"run_definition_cid\\\":\\\"sha256:0000000000000000000000000000000000000000000000000000000000000000\\\",\\\"runtime_bundle_cid\\\":\\\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\\",\\\"site_generation\\\":1,\\\"site_key\\\":\\\"site-a\\\",\\\"strategy_revision\\\":\\\"strategy/1\\\",\\\"task_attempt\\\":1,\\\"task_key\\\":\\\"task-a\\\",\\\"version\\\":\\\"actql-remote-dispatch-request/0.1\\\"}\",\"version\":\"actql-remote-poll-effect-resume/0.1\"}",
  )
}

///|
test "Effect resume poll routes exact original dispatch without dispatch authority" {
  let (delivery, fixed) = effect_resume_poll_fixture()
  assert_eq(remote_poll_effect_resume_json(delivery), Ok(fixed))
  let operation = admit_remote_poll_operation_json(fixed).unwrap()
  assert_true(remote_poll_operation_is_effect_resume(operation))
  assert_false(remote_poll_operation_is_query(operation))
  assert_false(remote_poll_operation_is_output(operation))
  assert_false(remote_poll_operation_is_release(operation))
  assert_false(remote_poll_operation_is_cancel(operation))
  let routed = admit_remote_poll_effect_resume_json(fixed).unwrap()
  assert_eq(
    dispatch_request_identity(remote_poll_effect_resume_request(routed)),
    dispatch_request_identity(remote_effect_resume_delivery_dispatch(delivery)),
  )
  assert_eq(
    remote_poll_effect_resume_delivery_json(routed),
    remote_effect_resume_delivery_json(delivery),
  )
}

///|
test "Effect resume poll rejects dispatch substitution and noncanonical framing" {
  let (_, fixed) = effect_resume_poll_fixture()
  for
    body in [
      fixed + "\n",
      fixed.replace(
        old="{\"delivery_json\"",
        new="{\"extra\":\"value\",\"delivery_json\"",
      ),
      fixed.replace(
        old="sha256:3b5d3a0baae35a4c3ed4f9d3a9bbf3bab875cdb325db11b18ea8b5dd1af04f93",
        new="sha256:0000000000000000000000000000000000000000000000000000000000000000",
      ),
    ] {
    assert_true(
      admit_remote_poll_effect_resume_json(body) is Err(InvalidDispatch),
    )
  }
  assert_true(
    admit_remote_poll_effect_resume_json("x".repeat(1048577))
    is Err(InvalidDispatch),
  )
}

///|
test "Effect resume routing cannot replace original report admission or current claim" {
  let (_, fixed) = effect_resume_poll_fixture()
  let (report, auth, reviewers, _, _) = effect_resume_fixture()
  // A routing parser carries syntax; it cannot confer approval or adopt a
  // substituted Checkpoint. The receiving common Owner must still refuse.
  let changed = fixed.replace(
    old="sha256:5f519ab12d76e539039de72a94b1b2f337654c8741ea17cee0266231a56ec10d",
    new="sha256:0000000000000000000000000000000000000000000000000000000000000000",
  )
  let routed = admit_remote_poll_effect_resume_json(changed).unwrap()
  assert_true(
    admit_remote_effect_resume_delivery_json(
      remote_poll_effect_resume_delivery_json(routed),
      report,
      auth,
      reviewers,
      review_limits(),
    )
    is Err(InvalidDispatch),
  )
}
