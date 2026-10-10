///|
fn review_checkpoint(
  dispatch : DispatchRequest,
) -> @checkpoint.SealedCheckpoint {
  @checkpoint.seal_checkpoint(
    {
      checkpoint_id: "review-1",
      continuation_state_cid: cid(
        "2222222222222222222222222222222222222222222222222222222222222222",
      ),
      subject: @checkpoint.RunUnit(
        run_id="run-1",
        unit_id="compute",
        run_definition_cid=dispatch_request_task_scope(dispatch).0,
      ),
      phase: @checkpoint.Commit,
      kind: @checkpoint.EffectSet,
      required_artifact_cid: cid(
        "3333333333333333333333333333333333333333333333333333333333333333",
      ),
      review_projection_cid: cid(
        "4444444444444444444444444444444444444444444444444444444444444444",
      ),
      requirements: [@checkpoint.EffectScopeApproved],
      reason_code: "effect_review_required",
      human_summary: "Review the original write",
      created_at: "2026-10-10T00:00:00.000Z",
      expires_at: "2099-01-01T00:00:00.000Z",
    },
    review_limits(),
  ).unwrap()
}

///|
fn review_limits() -> @checkpoint.WireLimits {
  { max_wire_bytes: 262144, max_nodes: 4096, max_depth: 32, }
}

///|
test "Effect review report and ACK preserve exact original dispatch and Checkpoint" {
  let original = request(
    "consumer-a",
    1,
    1,
    cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
  )
  let checkpoint = review_checkpoint(original)
  let persisted = @checkpoint.confirm_checkpoint_persisted(
    checkpoint,
    checkpoint.wire,
  ).unwrap()
  let report = prepare_remote_effect_checkpoint_report(
    original,
    persisted,
    review_limits(),
  ).unwrap()
  assert_eq(
    remote_effect_checkpoint_report_identity(report),
    "sha256:31bcdabc6df955bda9b2f862d7a8ef59554b566b19ca4a3406ba13a861d85996",
  )
  let body = remote_effect_checkpoint_report_json(report)
  let admitted = admit_remote_effect_checkpoint_report_json(
    body,
    original,
    review_limits(),
  ).unwrap()
  assert_eq(
    remote_effect_checkpoint_report_identity(admitted),
    remote_effect_checkpoint_report_identity(report),
  )
  assert_eq(remote_effect_checkpoint_report_checkpoint(admitted), checkpoint)
  assert_eq(remote_effect_checkpoint_report_json(admitted), body)
  for
    dispatch in [
      request(
        "consumer-b",
        1,
        1,
        cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
      ),
      request(
        "consumer-a",
        2,
        1,
        cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
      ),
      request(
        "consumer-a",
        1,
        2,
        cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
      ),
    ] {
    assert_true(
      admit_remote_effect_checkpoint_report_json(
        body,
        dispatch,
        review_limits(),
      )
      is Err(InvalidDispatch),
    )
  }
  for
    wire in [
      body + "\n",
      body.replace(
        old="actql-remote-effect-checkpoint-report/0.1",
        new="actql-remote-output-result/0.1",
      ),
    ] {
    assert_true(
      admit_remote_effect_checkpoint_report_json(
        wire,
        original,
        review_limits(),
      )
      is Err(InvalidDispatch),
    )
  }
  let reply = remote_effect_checkpoint_reply_json(report, Accepted).unwrap()
  assert_eq(
    admit_remote_effect_checkpoint_reply_json(reply, admitted),
    Ok(Accepted),
  )
  let other = prepare_remote_effect_checkpoint_report(
    request(
      "consumer-b",
      1,
      1,
      cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
    ),
    persisted,
    review_limits(),
  ).unwrap()
  assert_eq(
    admit_remote_effect_checkpoint_reply_json(reply, other),
    Err(InvalidDispatch),
  )
  assert_eq(
    admit_remote_effect_checkpoint_reply_json(reply + "\n", report),
    Err(InvalidDispatch),
  )
  assert_eq(
    remote_effect_checkpoint_reply_json(report, Refused("private-error")),
    Err(InvalidDispatch),
  )
  let refusal = remote_effect_checkpoint_reply_json(
    report,
    Refused("report_conflict"),
  ).unwrap()
  assert_eq(
    admit_remote_effect_checkpoint_reply_json(refusal, report),
    Ok(Refused("report_conflict")),
  )
}

///|
test "Effect report rejects foreign Run, wrong review kind and oversized envelope" {
  let original = request(
    "consumer-a",
    1,
    1,
    cid("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
  )
  let checkpoint = review_checkpoint(original)
  let prepare = checkpoint => {
    prepare_remote_effect_checkpoint_report(
      original,
      @checkpoint.confirm_checkpoint_persisted(checkpoint, checkpoint.wire).unwrap(),
      review_limits(),
    )
  }
  let changed = @checkpoint.seal_checkpoint(
    {
      ..checkpoint.checkpoint,
      subject: @checkpoint.RunUnit(
        run_id="run-1",
        unit_id="compute",
        run_definition_cid=cid(
          "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        ),
      ),
    },
    review_limits(),
  ).unwrap()
  assert_eq(prepare(changed) is Err(InvalidDispatch), true)
  let wrong = @checkpoint.seal_checkpoint(
    {
      ..checkpoint.checkpoint,
      subject: @checkpoint.PrepareAttempt(prepare_attempt_id="prepare-1"),
      phase: @checkpoint.Preflight,
      kind: @checkpoint.RunScope,
      requirements: [@checkpoint.InvocationScopeApproved],
    },
    review_limits(),
  ).unwrap()
  assert_true(prepare(wrong) is Err(InvalidDispatch))
  let report = prepare(checkpoint).unwrap()
  let checkpoint_size = @utf8.encode(checkpoint.wire).length()
  let limits = { ..review_limits(), max_wire_bytes: checkpoint_size, }
  assert_true(
    prepare_remote_effect_checkpoint_report(
      original,
      @checkpoint.confirm_checkpoint_persisted(checkpoint, checkpoint.wire).unwrap(),
      limits,
    )
    is Err(InvalidDispatch),
  )
  assert_true(
    admit_remote_effect_checkpoint_report_json(
      remote_effect_checkpoint_report_json(report),
      original,
      limits,
    )
    is Err(InvalidDispatch),
  )
}
