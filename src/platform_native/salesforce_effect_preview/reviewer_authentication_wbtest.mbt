///|
/// Copied from the independent checkpoint-resolution-signatures corpus.
/// This test seam does not execute Native cryptography or admit an approval.
fn reviewer_authentication_test_wire() -> String {
  "{\"version\":\"actql-checkpoint-resolution/0.1\",\"resolution_id\":\"resolution_01\",\"checkpoint_id\":\"checkpoint_run_01_effect_commit\",\"checkpoint_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"run_id\":\"run_01\",\"run_definition_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"decision\":\"rejected\",\"actor\":\"release-approver\",\"decided_at\":\"2026-09-25T00:00:00.000Z\",\"required_artifact_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"review_projection_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"proof\":{\"scheme\":\"ed25519-v1\",\"key_id\":\"release-approver-2026\",\"signature\":\"u2GRgUDJiDrrjYPJiC1z1VVL0JgnG9s9da2xfZlnkrnp034TjxpT9+M+dhhcID03Wa3SpFs+ghI48FICfSr9BQ==\"},\"resolution_cid\":\"sha256:87396910af30eb9f314ff792ef4711502b02f7a38dae5c5e05ca693a74411d01\"}"
}

///|
fn reviewer_authentication_test_selection() -> NativeEffectReviewerSelection {
  {
    principal_id: "original-http-principal",
    checkpoint_cid: "sha256:" + "1".repeat(64),
  }
}

///|
fn reviewer_authentication_test_registration() -> NativeEffectReviewerRegistration {
  {
    selection: reviewer_authentication_test_selection(),
    key_id: "release-approver-2026",
    reviewer_id: "release-approver",
    public_key_pem: "independently-installed-test-key",
    approval_authority_scope_cid: "sha256:" + "5".repeat(64),
    authority_context_cid: "sha256:" + "6".repeat(64),
    policy_cid: "sha256:" + "7".repeat(64),
  }
}

///|
fn reviewer_authentication_test_limits() -> @checkpoint.WireLimits {
  { max_wire_bytes: 65536, max_nodes: 4096, max_depth: 32, }
}

///|
test "Reviewer authentication verifies the common preimage with independent original principal" {
  let registered = reviewer_authentication_test_registration()
  let mut reads = 0
  let mut verifies = 0
  let (result, _) = authenticate_native_reviewer_with(
    registered.selection,
    reviewer_authentication_test_wire(),
    () => true,
    (selected, key) => {
      assert_eq(selected, registered.selection) catch {
        _ => abort("selection changed")
      }
      assert_eq(key, registered.key_id) catch {
        _ => abort("key changed")
      }
      reads += 1
      Some(registered)
    },
    (key, bytes, signature) => {
      verifies += 1
      assert_eq(key, registered.public_key_pem) catch {
        _ => abort("installed key changed")
      }
      assert_eq(
        @utf8.decode(bytes),
        "sha256:6a19960b235f700f5a88bcb26f324ad21e7e48d279f15160444fe687f6013dd1",
      ) catch {
        _ => abort("preimage changed")
      }
      assert_eq(
        signature, "u2GRgUDJiDrrjYPJiC1z1VVL0JgnG9s9da2xfZlnkrnp034TjxpT9-M-dhhcID03Wa3SpFs-ghI48FICfSr9BQ",
      ) catch {
        _ => abort("signature encoding changed")
      }
      Ok(true)
    },
    reviewer_authentication_test_limits(),
  ).unwrap()
  assert_eq(result.reviewer_id, "release-approver")
  assert_eq(result.authority_context_cid, registered.authority_context_cid)
  assert_eq(
    result.expected_authority_scope_cid,
    registered.approval_authority_scope_cid,
  )
  assert_eq(result.policy_cid, registered.policy_cid)
  assert_eq(reads, 2)
  assert_eq(verifies, 1)
}

///|
test "Reviewer authentication rejects foreign principal checkpoint signer and invalid current scope before crypto" {
  let registered = reviewer_authentication_test_registration()
  let mut verifies = 0
  for
    changed in [
      {
        ..registered,
        selection: {
          ..registered.selection,
          principal_id: "another-http-principal",
        },
      },
      {
        ..registered,
        selection: {
          ..registered.selection,
          checkpoint_cid: "sha256:" + "2".repeat(64),
        },
      },
      { ..registered, key_id: "another-key", },
      { ..registered, reviewer_id: "another-reviewer", },
      { ..registered, approval_authority_scope_cid: "not-a-cid", },
      { ..registered, authority_context_cid: "not-a-cid", },
      { ..registered, policy_cid: "not-a-cid", },
      { ..registered, public_key_pem: "", },
      { ..registered, public_key_pem: "x".repeat(4097), },
    ] {
    assert_true(
      authenticate_native_reviewer_with(
        registered.selection,
        reviewer_authentication_test_wire(),
        () => true,
        (_, _) => Some(changed),
        (_, _, _) => {
          verifies += 1
          Ok(true)
        },
        reviewer_authentication_test_limits(),
      )
      is Err(AuthorityDenied),
    )
  }
  assert_eq(verifies, 0)
}

///|
test "Reviewer authentication refuses malformed duplicate foreign and oversized candidate framing" {
  let registered = reviewer_authentication_test_registration()
  let mut reads = 0
  let mut verifies = 0
  let wire = reviewer_authentication_test_wire()
  for
    changed in [
      "{broken",
      wire.replace_all(old="ed25519-v1", new="other"),
      wire.replace_all(old="release-approver-2026", new="bad key"),
      wire.replace_all(old="release-approver\"", new="bad actor\""),
      wire.replace_all(
        old=registered.selection.checkpoint_cid,
        new="sha256:" + "2".repeat(64),
      ),
      wire.replace_all(old="u2GRgUDJiDrr", new="?2GRgUDJiDrr"),
      wire.replace_all(
        old="\"scheme\":",
        new="\"key_id\":\"duplicate\",\"scheme\":",
      ),
      wire.replace_all(old="\"scheme\":", new="\"extra\":true,\"scheme\":"),
      wire + " ".repeat(65536),
    ] {
    assert_true(
      authenticate_native_reviewer_with(
        registered.selection,
        changed,
        () => true,
        (_, _) => {
          reads += 1
          Some(registered)
        },
        (_, _, _) => {
          verifies += 1
          Ok(true)
        },
        reviewer_authentication_test_limits(),
      )
      is Err(AttestationRejected),
    )
  }
  assert_eq(reads, 0)
  assert_eq(verifies, 0)
}

///|
test "Reviewer authentication retains rejection and physical verification errors" {
  let registered = reviewer_authentication_test_registration()
  assert_true(
    authenticate_native_reviewer_with(
      registered.selection,
      reviewer_authentication_test_wire(),
      () => true,
      (_, _) => Some(registered),
      (_, _, _) => Ok(false),
      reviewer_authentication_test_limits(),
    )
    is Err(AttestationRejected),
  )
  assert_true(
    authenticate_native_reviewer_with(
      registered.selection,
      reviewer_authentication_test_wire(),
      () => true,
      (_, _) => Some(registered),
      (_, _, _) => Err(@signature.UnsupportedTarget),
      reviewer_authentication_test_limits(),
    )
    is Err(Signature(@signature.UnsupportedTarget)),
  )
}

///|
test "Reviewer authentication rechecks current registration and Site after verification" {
  let registered = reviewer_authentication_test_registration()
  for
    after in [
      None,
      Some({ ..registered, public_key_pem: "rotated-key", }),
      Some({
        ..registered,
        selection: {
          ..registered.selection,
          principal_id: "another-principal",
        },
      }),
      Some({ ..registered, authority_context_cid: "sha256:" + "8".repeat(64), }),
      Some({ ..registered, policy_cid: "sha256:" + "8".repeat(64), }),
      Some({
        ..registered,
        approval_authority_scope_cid: "sha256:" + "8".repeat(64),
      }),
    ] {
    let mut verified = false
    assert_true(
      authenticate_native_reviewer_with(
        registered.selection,
        reviewer_authentication_test_wire(),
        () => true,
        (_, _) => if verified { after } else { Some(registered) },
        (_, _, _) => {
          verified = true
          Ok(true)
        },
        reviewer_authentication_test_limits(),
      )
      is Err(AuthorityDenied),
    )
  }
  let mut current = true
  assert_true(
    authenticate_native_reviewer_with(
      registered.selection,
      reviewer_authentication_test_wire(),
      () => current,
      (_, _) => Some(registered),
      (_, _, _) => {
        current = false
        Ok(true)
      },
      reviewer_authentication_test_limits(),
    )
    is Err(AuthorityDenied),
  )
  let mut calls = 0
  assert_true(
    authenticate_native_reviewer_with(
      registered.selection,
      reviewer_authentication_test_wire(),
      () => false,
      (_, _) => {
        calls += 1
        Some(registered)
      },
      (_, _, _) => {
        calls += 1
        Ok(true)
      },
      reviewer_authentication_test_limits(),
    )
    is Err(AuthorityDenied),
  )
  assert_eq(calls, 0)
}

///|
test "Reviewer framing preserves Resolution values and delegates its signed preimage to the common Owner" {
  let wire = reviewer_authentication_test_wire()
  let wrapper = "{\"resolution\":" + wire + "}"
  let extracted = native_reviewer_resolution_wire(
    wrapper,
    reviewer_authentication_test_limits(),
  ).unwrap()
  assert_eq(
    @checkpoint.resolution_proof_preimage(
      extracted,
      reviewer_authentication_test_limits(),
    ).unwrap(),
    "sha256:6a19960b235f700f5a88bcb26f324ad21e7e48d279f15160444fe687f6013dd1",
  )
  for
    changed in [
      "{}",
      "{broken",
      wrapper.replace_all(
        old="\"actor\":",
        new="\"actor\":\"duplicate\",\"actor\":",
      ),
      wrapper + " ".repeat(65536),
    ] {
    assert_true(
      native_reviewer_resolution_wire(
        changed,
        reviewer_authentication_test_limits(),
      )
      is None,
    )
  }
}

///|
test "Reviewer delivery framing cannot substitute a trusted authentication or omit the exact common envelope admission" {
  let limits = reviewer_authentication_test_limits()
  let writer = @encode.writer(
    limits.max_wire_bytes,
    limits.max_nodes,
    limits.max_depth,
  )
  @encode.begin_object(writer)
  for
    (key, value) in [
      ("checkpoint_cid", "original-checkpoint"),
      ("claimant", "original-coordinator"),
      ("dispatch_request_cid", "original-dispatch"),
      ("generation", "1"),
      ("report_cid", "original-report"),
      ("resolution_cid", "original-resolution"),
      ("resolution_wire", "candidate-only"),
      ("resume_intent_id", "original-intent"),
      ("version", "actql-remote-effect-resume-delivery/0.1"),
    ] {
    @encode.key(writer, key)
    @encode.string_value(writer, value)
  }
  @encode.end_object(writer)
  let body = @encode.finish(writer)
  // Extraction grants nothing; original report admission rejects these labels.
  assert_eq(native_reviewer_delivery_wire(body, limits), Some("candidate-only"))
  for
    changed in [
      body.replace_all(
        old="actql-remote-effect-resume-delivery/0.1",
        new="another-version",
      ),
      body.replace_all(
        old="\"claimant\":",
        new="\"principal_id\":\"signer-is-not-principal\",\"claimant\":",
      ),
      body.replace_all(
        old="\"resolution_wire\":",
        new="\"resolution_wire\":\"duplicate\",\"resolution_wire\":",
      ),
      body.replace_all(
        old="\"resolution_wire\":\"candidate-only\"",
        new="\"resolution_wire\":null",
      ),
      body + " ".repeat(65536),
    ] {
    assert_true(native_reviewer_delivery_wire(changed, limits) is None)
  }
}
