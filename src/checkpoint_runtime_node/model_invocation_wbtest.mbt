///|
fn model_test_ok(text : String) -> Json raise {
  let value = parse(text).unwrap()
  assert_true(
    value is Object(map) && map.get("ok") == Some(Json::boolean(true)),
  )
  value
}

///|
fn model_test_refuses(text : String) -> Unit raise {
  let value = parse(text).unwrap()
  assert_true(
    value is Object(map) && map.get("ok") == Some(Json::boolean(false)),
  )
}

///|
test "Model ABI returns pure bounded originals without opaque custody or retry facts" {
  let original = model_test_ok(
    model_original_run_admit(model_fixture_wire("original_run")),
  )
  assert_eq(text_member(original, "runId"), Some("run-model"))
  let call_set = model_test_ok(
    model_call_set_admit(model_fixture_wire("call_set_request")),
  )
  assert_eq(
    text_member(call_set, "scopeCid"),
    Some(
      "sha256:3cabfeb57f5e1b83d060f416630bf5c18026be8e23867c4b2ee7a33fcf7ba08b",
    ),
  )
  assert_eq(
    text_member(call_set, "preparedInvocationCid"),
    text_member(original, "preparedInvocationCid"),
  )
  guard call_set is Object(fields) else { abort("Expected object") }
  assert_true(!fields.contains("fixedInputCustody"))
  assert_true(!fields.contains("retryBinding"))
  guard fields.get("slots") is Some(Array(slots)) else {
    abort("Expected slots")
  }
  assert_eq(slots.length(), 2)
  guard slots[0] is Object(slot) else { abort("Expected slot") }
  assert_true(!slot.contains("maxAttempts"))
  model_test_refuses(model_call_set_admit("{}"))
  model_test_refuses(model_call_set_admit("[".repeat(1048577)))
}

///|
test "Model ABI rejects missing inventory and substituted PreparedInvocation original" {
  guard parse(model_fixture_wire("call_set_request")) is Some(Object(fields)) else {
    abort("Expected object")
  }
  fields.remove("slotWires")
  model_test_refuses(model_call_set_admit(Json::object(fields).stringify()))
  fields["slotWires"] = Json::array([])
  model_test_refuses(model_call_set_admit(Json::object(fields).stringify()))
  guard parse(model_fixture_wire("call_set_request")) is Some(Object(changed)) else {
    abort("Expected object")
  }
  changed["preparedInvocationWire"] = Json::string(
    model_fixture_wire("model_invocation_scope"),
  )
  model_test_refuses(model_call_set_admit(Json::object(changed).stringify()))
}

///|
test "Model ABI attempt checks exact scope slot authority and one-based index" {
  let request = model_fixture_wire("call_set_request")
  let attempt = model_fixture_wire("model_call_attempt")
  let authority = model_fixture_wire("model_dispatch_authority")
  let checked = model_test_ok(
    model_call_attempt_admit(request, 0, attempt, authority, 1.0),
  )
  assert_eq(number_member(checked, "attemptIndex"), Some(1.0))
  model_test_refuses(
    model_call_attempt_admit(request, 1, attempt, authority, 1.0),
  )
  model_test_refuses(
    model_call_attempt_admit(request, 0, attempt, authority, 0.0),
  )
  model_test_refuses(
    model_call_attempt_admit(request, 0, attempt, authority, 1.5),
  )
}

///|
test "Model ABI resolution and immediate paths use the same original binding" {
  let request = model_fixture_wire("call_set_request")
  let checkpoint = model_fixture_wire("checkpoint")
  let resolution = model_fixture_wire("resolution")
  let evidence = model_fixture_wire("approval_evidence")
  let auth = model_fixture_wire("authentication")
  let reviewers = model_fixture_wire("authorities")
  let at = "2026-09-25T12:00:01.000Z"
  model_test_refuses(
    resolution_admit(checkpoint, resolution, evidence, auth, reviewers, at),
  )
  let admitted = model_test_ok(
    model_resolution_admit(
      request, checkpoint, resolution, evidence, auth, reviewers, at,
    ),
  )
  let decided = model_test_ok(
    model_resolution_decide(
      request, checkpoint, resolution, evidence, auth, reviewers, at, "host-key",
      "aG9zdA==", "open", "", "[]",
    ),
  )
  assert_eq(text_member(decided, "action"), Some("commit"))
  assert_eq(
    text_member(decided, "resolution_cid"),
    text_member(admitted, "resolution_cid"),
  )
  guard parse(checkpoint) is Some(Object(fields)) else {
    abort("Expected object")
  }
  fields.remove("checkpoint_cid")
  let body = Json::object(fields).stringify()
  let immediate = model_test_ok(
    model_resolution_admit_immediate(
      request, body, resolution, evidence, auth, reviewers, at,
    ),
  )
  assert_eq(
    text_member(immediate, "attestation_preimage"),
    text_member(admitted, "attestation_preimage"),
  )
  let answered = model_test_ok(
    model_resolution_seal_immediate(
      request, body, resolution, evidence, auth, reviewers, at, "host-key", "aG9zdA==",
    ),
  )
  assert_eq(
    text_member(answered, "verified_resolution_wire"),
    text_member(decided, "verified_resolution_wire"),
  )
}

///|
fn model_test_verified(prefix : String, immediate : Bool) -> String raise {
  let request = model_fixture_wire(prefix + "call_set_request")
  let checkpoint = model_fixture_wire(prefix + "checkpoint")
  let resolution = model_fixture_wire(prefix + "resolution")
  let evidence = model_fixture_wire(prefix + "approval_evidence")
  let auth = model_fixture_wire(prefix + "authentication")
  let reviewers = model_fixture_wire("authorities")
  let at = "2026-09-25T12:00:01.000Z"
  let answer = if immediate {
    guard parse(checkpoint) is Some(Object(body)) else {
      abort("Expected checkpoint")
    }
    body.remove("checkpoint_cid")
    model_resolution_seal_immediate(
      request,
      Json::object(body).stringify(),
      resolution,
      evidence,
      auth,
      reviewers,
      at,
      "host-key",
      "aG9zdA==",
    )
  } else {
    model_resolution_decide(
      request, checkpoint, resolution, evidence, auth, reviewers, at, "host-key",
      "aG9zdA==", "open", "", "[]",
    )
  }
  text_member(model_test_ok(answer), "verified_resolution_wire").unwrap()
}

///|
test "Model live grant checks minimum review and Run expiry for deferred and immediate originals" {
  for prefix in ["", "review_early_", "run_early_"] {
    let request = model_fixture_wire(prefix + "call_set_request")
    let checkpoint = model_fixture_wire(prefix + "checkpoint")
    let expiry = if prefix == "" {
      "2026-09-26T12:00:00.000Z"
    } else {
      "2026-09-26T11:30:00.000Z"
    }
    for immediate in [false, true] {
      let verified = model_test_verified(prefix, immediate)
      let live = if immediate {
        model_immediate_invocation_grant_at
      } else {
        model_invocation_grant_at
      }
      let answer = model_test_ok(
        live(request, checkpoint, verified, "2026-09-26T11:29:59.999Z"),
      )
      let handle = model_invocation_grant_handle(
        request, checkpoint, verified, "2026-09-26T11:29:59.999Z",
        immediate,
      ).unwrap()
      assert_eq(
        @checkpoint.model_invocation_grant_expires_at(handle),
        expiry,
      )
      assert_eq(
        @checkpoint.model_invocation_grant_checkpoint_cid(handle),
        text_member(answer, "checkpointCid").unwrap(),
      )
      assert_eq(text_member(answer, "expiresAt"), Some(expiry))
      assert_eq(text_member(answer, "runId"), Some("run-model"))
      assert_eq(
        text_member(answer, "preparedInvocationCid"),
        text_member(
          model_test_ok(model_call_set_admit(request)),
          "preparedInvocationCid",
        ),
      )
      guard answer is Object(fields) else { abort("Expected grant") }
      assert_eq(fields.get("current"), Some(Json::boolean(true)))
      assert_true(!fields.contains("resume_intent_id"))
      let approval_only = model_test_ok(
        resumed_approval_at(verified, "2026-09-26T11:30:00.000Z"),
      )
      guard approval_only is Object(approval_fields) else {
        abort("Expected approval")
      }
      assert_eq(approval_fields.get("current"), Some(Json::boolean(true)))
      for
        at in [
          expiry, "2026-09-26T12:00:00.001Z", "2026-09-25T12:00:00.999Z", "invalid",
        ] {
        model_test_refuses(live(request, checkpoint, verified, at))
        assert_true(
          model_invocation_grant_handle(
            request, checkpoint, verified, at, immediate,
          ) is Err(_),
        )
      }
      // Immutable custody/original observation stays legal after live expiry.
      ignore(model_test_ok(model_call_set_admit(request)))
    }
  }
}

///|
test "Model live grant rejects substituted committed identity and corrupted wrappers" {
  let request = model_fixture_wire("call_set_request")
  let checkpoint = model_fixture_wire("checkpoint")
  let verified = model_test_verified("", false)
  let other = model_test_verified("review_early_", false)
  let at = "2026-09-25T12:00:01.000Z"
  for live in [model_invocation_grant_at, model_immediate_invocation_grant_at] {
    for
      wire in [
        verified + " ",
        verified.replace(old="alice", new="mallory"),
        other,
        "{}",
      ] {
      model_test_refuses(live(request, checkpoint, wire, at))
    }
    model_test_refuses(
      live(request, model_fixture_wire("review_early_checkpoint"), verified, at),
    )
    model_test_refuses(live(request, checkpoint + " ", verified, at))
    model_test_refuses(live("{}", checkpoint, verified, at))
    let granted = model_test_ok(live(request, checkpoint, verified, at))
    let wrapper = parse(verified).unwrap()
    let resolution = model_field(wrapper, "resolution") catch {
      _ => abort("Expected resolution")
    }
    assert_eq(
      text_member(granted, "resolutionCid"),
      text_member(resolution, "resolution_cid"),
    )
    assert_eq(
      text_member(granted, "verifiedResolutionCid"),
      text_member(wrapper, "verified_resolution_cid"),
    )
    assert_eq(
      text_member(granted, "checkpointCid"),
      text_member(resolution, "checkpoint_cid"),
    )
  }
}
