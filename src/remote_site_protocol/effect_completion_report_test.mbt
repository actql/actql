///|
// Deliberately opaque authored transport DATA, not a valid Completion chain.
// Exact whitespace and inner escapes survive; the existing receiver owns the
// separate complete semantic admission and durable confirmation.
let completion_test_wire = " {\"kind\":\"opaque-completion\",\"text\":\"\\u0061\",\"items\":[1,1]}\n"

///|
fn completion_delivery_fixture() -> RemoteEffectResumeDelivery {
  let (report, auth, reviewers, verified_wire, _) = effect_resume_fixture()
  let resolution = @checkpoint.admit_attested_effect_resolution(
      remote_effect_checkpoint_report_checkpoint(report),
      verified_wire,
      auth,
      reviewers,
      review_limits(),
    ).unwrap().resolution
  prepare_remote_effect_resume_delivery(
    report,
    resolution,
    { claimant: "original-coordinator", generation: 1L, },
    review_limits(),
  ).unwrap()
}

///|
test "Effect completion report retains exact full opaque bytes and original delivery" {
  let delivery = completion_delivery_fixture()
  let report = prepare_remote_effect_completion_report(
    delivery,
    completion_test_wire,
    review_limits(),
  ).unwrap()
  // Independently computed from the existing fixed resume fixture plus the
  // authored carrier, not captured from product emission.
  let expected = "{\"checkpoint_cid\":\"sha256:5f519ab12d76e539039de72a94b1b2f337654c8741ea17cee0266231a56ec10d\",\"checkpoint_report_cid\":\"sha256:31bcdabc6df955bda9b2f862d7a8ef59554b566b19ca4a3406ba13a861d85996\",\"claimant\":\"original-coordinator\",\"completion_cid\":\"sha256:5c2042a172201ef6c3023dc4934f2d92a36c7af5be5fabab5e1e0e98aa889b03\",\"completion_wire\":\" {\\\"kind\\\":\\\"opaque-completion\\\",\\\"text\\\":\\\"\\\\u0061\\\",\\\"items\\\":[1,1]}\\n\",\"dispatch_request_cid\":\"sha256:3b5d3a0baae35a4c3ed4f9d3a9bbf3bab875cdb325db11b18ea8b5dd1af04f93\",\"generation\":\"1\",\"resolution_cid\":\"sha256:19e9389ed7f0a966255f0d76aaec9718d2fc82aa4c41e2b762af2626e88e4f19\",\"resume_intent_id\":\"sha256:14592585f30f30a822f36461bd2187dd8926f52ebea2e0a9e21f17b2924bbf73\",\"verified_resolution_cid\":\"sha256:9b9a8d9d6fc76b0254d4708b1d71cb130ad4a9ba6bda2beca4bf26695482ab6b\",\"version\":\"actql-remote-effect-completion-report/0.1\"}"
  assert_eq(remote_effect_completion_report_json(report), expected)
  assert_eq(
    remote_effect_completion_report_identity(report),
    "sha256:452bbaa85d9c1f87c252546025db8a1b54564d66e0b2afb433b048aebc4ff4f9",
  )
  assert_eq(
    remote_effect_completion_report_completion_identity(report),
    "sha256:5c2042a172201ef6c3023dc4934f2d92a36c7af5be5fabab5e1e0e98aa889b03",
  )
  assert_eq(
    remote_effect_completion_report_completion_wire(report),
    completion_test_wire,
  )
  assert_true(
    physical_equal(remote_effect_completion_report_delivery(report), delivery),
  )
  let admitted = admit_remote_effect_completion_report_json(
    expected,
    delivery,
    review_limits(),
  ).unwrap()
  assert_eq(
    remote_effect_completion_report_completion_wire(admitted),
    completion_test_wire,
  )
  assert_true(
    physical_equal(remote_effect_completion_report_delivery(admitted), delivery),
  )
}

///|
test "Effect completion report refuses changed delivery binding carrier or canonical envelope" {
  let delivery = completion_delivery_fixture()
  let report = prepare_remote_effect_completion_report(
    delivery,
    completion_test_wire,
    review_limits(),
  ).unwrap()
  let body = remote_effect_completion_report_json(report)
  for
    name in [
      "checkpoint_cid", "checkpoint_report_cid", "claimant", "completion_cid", "dispatch_request_cid",
      "generation", "resolution_cid", "resume_intent_id", "verified_resolution_cid",
      "version",
    ] {
    let changed = body.replace(
      old="\"" + name + "\":\"",
      new="\"" + name + "\":\"foreign-",
    )
    assert_true(
      admit_remote_effect_completion_report_json(
        changed,
        delivery,
        review_limits(),
      )
      is Err(InvalidDispatch),
    )
  }
  for
    changed in [
      body + "\n",
      body.replace(old="opaque-completion", new="other-completion"),
      body.replace(old="\"generation\":\"1\"", new="\"generation\":\"01\""),
      body.replace(
        old="{\"checkpoint_cid\"",
        new="{\"extra\":\"data\",\"checkpoint_cid\"",
      ),
      body.replace(
        old="\"generation\":\"1\"",
        new="\"generation\":\"1\",\"generation\":\"1\"",
      ),
    ] {
    assert_true(
      admit_remote_effect_completion_report_json(
        changed,
        delivery,
        review_limits(),
      )
      is Err(InvalidDispatch),
    )
  }
  let (review, _, _, _, _) = effect_resume_fixture()
  let claims : Array[@checkpoint.ResumeClaim] = [
    { claimant: "another-coordinator", generation: 1L, },
    { claimant: "original-coordinator", generation: 2L, },
  ]
  for claim in claims {
    let other = prepare_remote_effect_resume_delivery(
      review,
      remote_effect_resume_delivery_resolution(delivery),
      claim,
      review_limits(),
    ).unwrap()
    assert_true(
      admit_remote_effect_completion_report_json(body, other, review_limits())
      is Err(InvalidDispatch),
    )
  }
}

///|
test "Effect completion report and reply preserve exact UTF8 framing and syntax bounds" {
  let delivery = completion_delivery_fixture()
  assert_true(
    admit_remote_effect_completion_report_json("x".repeat(65), delivery, {
      ..review_limits(),
      max_wire_bytes: 64,
    })
    is Err(InvalidDispatch),
  )
  assert_true(
    prepare_remote_effect_completion_report(delivery, "", review_limits())
    is Err(InvalidDispatch),
  )
  // A byte-valid carrier can still overflow after outer quoting and binding.
  assert_true(
    prepare_remote_effect_completion_report(delivery, "x".repeat(32), {
      ..review_limits(),
      max_wire_bytes: 32,
    })
    is Err(InvalidDispatch),
  )
  assert_true(
    prepare_remote_effect_completion_report(delivery, "東京".repeat(32), {
      ..review_limits(),
      max_wire_bytes: 64,
    })
    is Err(InvalidDispatch),
  )
  let report = prepare_remote_effect_completion_report(
    delivery,
    "東京\n",
    review_limits(),
  ).unwrap()
  let body = remote_effect_completion_report_json(report)
  let exact = {
    ..review_limits(),
    max_wire_bytes: @utf8.encode(body).length(),
  }
  assert_true(
    prepare_remote_effect_completion_report(delivery, "東京\n", exact)
    is Ok(_),
  )
  let short = { ..exact, max_wire_bytes: exact.max_wire_bytes - 1, }
  assert_true(
    prepare_remote_effect_completion_report(delivery, "東京\n", short)
    is Err(InvalidDispatch),
  )
  assert_true(
    admit_remote_effect_completion_report_json(body, delivery, short)
    is Err(InvalidDispatch),
  )
  for
    invalid in [
      { ..review_limits(), max_wire_bytes: 0, },
      { ..review_limits(), max_nodes: 1, },
      { ..review_limits(), max_depth: 0, },
    ] {
    assert_true(
      prepare_remote_effect_completion_report(
        delivery, completion_test_wire, invalid,
      )
      is Err(InvalidDispatch),
    )
    assert_true(
      admit_remote_effect_completion_report_json(body, delivery, invalid)
      is Err(InvalidDispatch),
    )
    assert_true(
      remote_effect_completion_reply_json(report, Accepted, invalid)
      is Err(InvalidDispatch),
    )
  }
  let reply = remote_effect_completion_reply_json(
    report,
    Accepted,
    review_limits(),
  ).unwrap()
  let exact_reply = {
    ..review_limits(),
    max_wire_bytes: @utf8.encode(reply).length(),
  }
  assert_true(
    admit_remote_effect_completion_reply_json("x".repeat(65), report, {
      ..review_limits(),
      max_wire_bytes: 64,
    })
    is Err(InvalidDispatch),
  )
  assert_eq(
    remote_effect_completion_reply_json(report, Accepted, exact_reply),
    Ok(reply),
  )
  assert_true(
    remote_effect_completion_reply_json(report, Accepted, {
      ..exact_reply,
      max_wire_bytes: exact_reply.max_wire_bytes - 1,
    })
    is Err(InvalidDispatch),
  )
}

///|
test "Effect completion persistence reply binds the original report and closed outcomes" {
  let report = prepare_remote_effect_completion_report(
    completion_delivery_fixture(),
    completion_test_wire,
    review_limits(),
  ).unwrap()
  let accepted = remote_effect_completion_reply_json(
    report,
    Accepted,
    review_limits(),
  ).unwrap()
  assert_eq(
    accepted, "{\"checkpoint_cid\":\"sha256:5f519ab12d76e539039de72a94b1b2f337654c8741ea17cee0266231a56ec10d\",\"claimant\":\"original-coordinator\",\"completion_cid\":\"sha256:5c2042a172201ef6c3023dc4934f2d92a36c7af5be5fabab5e1e0e98aa889b03\",\"dispatch_request_cid\":\"sha256:3b5d3a0baae35a4c3ed4f9d3a9bbf3bab875cdb325db11b18ea8b5dd1af04f93\",\"generation\":\"1\",\"outcome\":\"accepted\",\"reason\":\"\",\"report_cid\":\"sha256:452bbaa85d9c1f87c252546025db8a1b54564d66e0b2afb433b048aebc4ff4f9\",\"resume_intent_id\":\"sha256:14592585f30f30a822f36461bd2187dd8926f52ebea2e0a9e21f17b2924bbf73\",\"version\":\"actql-remote-effect-completion-reply/0.1\"}",
  )
  assert_eq(
    admit_remote_effect_completion_reply_json(accepted, report, review_limits()),
    Ok(Accepted),
  )
  for reason in ["authorization_denied", "scope_mismatch", "report_conflict"] {
    let reply = remote_effect_completion_reply_json(
      report,
      Refused(reason),
      review_limits(),
    ).unwrap()
    assert_eq(
      admit_remote_effect_completion_reply_json(reply, report, review_limits()),
      Ok(Refused(reason)),
    )
  }
  // Uncertain persistence has no wire acknowledgement or implicit retry.
  for reason in ["", "save_unknown", "cleanup_complete"] {
    assert_true(
      remote_effect_completion_reply_json(
        report,
        Refused(reason),
        review_limits(),
      )
      is Err(InvalidDispatch),
    )
  }
}

///|
test "Effect completion persistence reply refuses foreign report claim and checkpoint ACK" {
  let delivery = completion_delivery_fixture()
  let report = prepare_remote_effect_completion_report(
    delivery,
    completion_test_wire,
    review_limits(),
  ).unwrap()
  let reply = remote_effect_completion_reply_json(
    report,
    Accepted,
    review_limits(),
  ).unwrap()
  for
    name in [
      "checkpoint_cid", "claimant", "completion_cid", "dispatch_request_cid", "generation",
      "report_cid", "resume_intent_id", "version",
    ] {
    assert_true(
      admit_remote_effect_completion_reply_json(
        reply.replace(
          old="\"" + name + "\":\"",
          new="\"" + name + "\":\"foreign-",
        ),
        report,
        review_limits(),
      )
      is Err(InvalidDispatch),
    )
  }
  let other = prepare_remote_effect_completion_report(
    delivery,
    "different complete bytes",
    review_limits(),
  ).unwrap()
  assert_true(
    admit_remote_effect_completion_reply_json(reply, other, review_limits())
    is Err(InvalidDispatch),
  )
  let (review, _, _, _, _) = effect_resume_fixture()
  for
    changed in [
      reply + "\n",
      reply.replace(
        old="\"outcome\":\"accepted\"",
        new="\"outcome\":\"unknown\"",
      ),
      reply.replace(old="\"reason\":\"\"", new="\"reason\":\"save_unknown\""),
      reply.replace(
        old="\"generation\":\"1\"",
        new="\"generation\":\"1\",\"generation\":\"1\"",
      ),
      remote_effect_checkpoint_reply_json(review, Accepted).unwrap(),
    ] {
    assert_true(
      admit_remote_effect_completion_reply_json(
        changed,
        report,
        review_limits(),
      )
      is Err(InvalidDispatch),
    )
  }
}
