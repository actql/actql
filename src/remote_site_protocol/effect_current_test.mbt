///|
test "Effect current query rejects stale challenge and substituted original scope" {
  let (report, _, _, _, _) = effect_resume_fixture()
  let limits = { ..review_limits(), max_wire_bytes: 65536, }
  let query = prepare_remote_effect_current_query(
    report, "write-1", "query-original", limits,
  ).unwrap()
  let wire = remote_effect_current_query_json(query)
  assert_eq(
    remote_effect_current_query_identity(query),
    "sha256:91d733911e2832e78dba7b3c727943ca1e1cee0081a2cf2005f909d6411e64fb",
  )
  assert_eq(
    wire, "{\"checkpoint_cid\":\"sha256:5f519ab12d76e539039de72a94b1b2f337654c8741ea17cee0266231a56ec10d\",\"dispatch_request_cid\":\"sha256:3b5d3a0baae35a4c3ed4f9d3a9bbf3bab875cdb325db11b18ea8b5dd1af04f93\",\"effect_id\":\"write-1\",\"query_id\":\"query-original\",\"report_cid\":\"sha256:31bcdabc6df955bda9b2f862d7a8ef59554b566b19ca4a3406ba13a861d85996\",\"version\":\"actql-remote-effect-current-query/0.1\"}",
  )
  assert_eq(
    remote_effect_current_query_json(
      admit_remote_effect_current_query_json(wire, report, limits).unwrap(),
    ),
    wire,
  )
  let reply = prepare_remote_effect_current_reply(query, None, 0, false, limits).unwrap()
  let body = remote_effect_current_reply_json(reply)
  assert_eq(
    remote_effect_current_reply_identity(reply),
    "sha256:9f41aae53431191530f1fb11e9aaf30405b436f1e09a6d6ad175eda4dc97680f",
  )
  assert_eq(
    body, "{\"checkpoint_cid\":\"sha256:5f519ab12d76e539039de72a94b1b2f337654c8741ea17cee0266231a56ec10d\",\"dispatch_request_cid\":\"sha256:3b5d3a0baae35a4c3ed4f9d3a9bbf3bab875cdb325db11b18ea8b5dd1af04f93\",\"effect_id\":\"write-1\",\"ledger_head_cid\":\"\",\"query_cid\":\"sha256:91d733911e2832e78dba7b3c727943ca1e1cee0081a2cf2005f909d6411e64fb\",\"query_id\":\"query-original\",\"recovery_action\":0,\"report_cid\":\"sha256:31bcdabc6df955bda9b2f862d7a8ef59554b566b19ca4a3406ba13a861d85996\",\"response_saved\":false,\"version\":\"actql-remote-effect-current-reply/0.1\"}",
  )
  assert_eq(
    remote_effect_current_reply_facts(
      admit_remote_effect_current_reply_json(query, body, limits).unwrap(),
    ),
    (None, 0, false),
  )
  let fresh = prepare_remote_effect_current_query(
    report, "write-1", "query-fresh", limits,
  ).unwrap()
  assert_true(
    admit_remote_effect_current_reply_json(fresh, body, limits)
    is Err(InvalidDispatch),
  )
  for
    field in [
      "checkpoint_cid", "dispatch_request_cid", "effect_id", "query_id", "query_cid",
      "report_cid",
    ] {
    assert_true(
      admit_remote_effect_current_reply_json(
        query,
        body.replace(
          old="\"" + field + "\":\"",
          new="\"" + field + "\":\"foreign-",
        ),
        limits,
      )
      is Err(InvalidDispatch),
    )
  }
  assert_true(
    admit_remote_effect_current_query_json(wire + " ", report, limits)
    is Err(InvalidDispatch),
  )
  assert_true(
    admit_remote_effect_current_reply_json(query, body + " ", limits)
    is Err(InvalidDispatch),
  )
}

///|
test "Effect current framing retains pending response and rejects impossible custody shapes" {
  let (report, _, _, _, _) = effect_resume_fixture()
  let limits = { ..review_limits(), max_wire_bytes: 65536, }
  let query = prepare_remote_effect_current_query(
    report, "write-1", "query-original", limits,
  ).unwrap()
  let head = Some("sha256:" + "a".repeat(64))
  for action in [1, 3, 4, 5, 6, 7] {
    let saved = action != 1
    let reply = prepare_remote_effect_current_reply(
      query, head, action, saved, limits,
    ).unwrap()
    assert_eq(
      remote_effect_current_reply_facts(
        admit_remote_effect_current_reply_json(
          query,
          remote_effect_current_reply_json(reply),
          limits,
        ).unwrap(),
      ),
      (head, action, saved),
    )
  }
  for action in [2, 8, 9] {
    assert_true(
      prepare_remote_effect_current_reply(query, head, action, false, limits)
      is Err(InvalidDispatch),
    )
  }
  assert_true(
    prepare_remote_effect_current_reply(query, None, 3, true, limits)
    is Err(InvalidDispatch),
  )
  assert_true(
    prepare_remote_effect_current_reply(query, head, 0, false, limits)
    is Err(InvalidDispatch),
  )
  assert_true(
    prepare_remote_effect_current_reply(query, head, 1, true, limits)
    is Err(InvalidDispatch),
  )
  assert_true(
    prepare_remote_effect_current_query(report, "write-1", "", limits)
    is Err(InvalidDispatch),
  )
  assert_true(
    prepare_remote_effect_current_query(
      report,
      "write-1",
      "é".repeat(129),
      limits,
    )
    is Err(InvalidDispatch),
  )
  for
    bound in [
      { ..limits, max_wire_bytes: 1, },
      { ..limits, max_nodes: 1, },
      { ..limits, max_depth: 0, },
      { ..limits, max_wire_bytes: 65537, },
    ] {
    assert_true(
      prepare_remote_effect_current_query(
        report, "write-1", "query-original", bound,
      )
      is Err(InvalidDispatch),
    )
    assert_true(
      prepare_remote_effect_current_reply(query, head, 3, true, bound)
      is Err(InvalidDispatch),
    )
    assert_true(
      admit_remote_effect_current_query_json(
        remote_effect_current_query_json(query),
        report,
        bound,
      )
      is Err(InvalidDispatch),
    )
  }
}
