///|
fn risk_test_wire_with_auth(
  preview_cid : String,
  claims : String,
  authentication_cid : String,
) -> String {
  let a = preview_footprint_test_cid("a")
  let body = "{\"version\":\"actql-effect-risk-acceptance/0.1\"," +
    "\"issuer_kind\":\"policy\",\"issuer_evidence_cid\":\"" +
    a +
    "\",\"policy_cid\":\"" +
    a +
    "\",\"decision\":\"allow\",\"effect_preview_cid\":\"" +
    preview_cid +
    "\",\"review_projection_cid\":\"" +
    a +
    "\",\"authority_scope_cid\":\"" +
    a +
    "\",\"validity_evidence_cid\":\"" +
    a +
    "\",\"claims\":" +
    claims +
    ",\"authentication_evidence_cid\":\"" +
    authentication_cid +
    "\"}"
  let parsed = @source.parse_json(body, {
    max_input_bytes: 8192,
    max_nodes: 256,
    max_depth: 12,
  }).unwrap()
  let value = @json.from_source(parsed, 256, 12, 8192) catch {
    _ => abort("Expected risk body")
  }
  let cid = @json.cid_value(value, 8192, 256, 12) catch {
    _ => abort("Expected risk CID")
  }
  preview_apply_test_canonical(
    body.replace_all(
      old="\"version\":",
      new="\"self_cid\":\"" + cid + "\",\"version\":",
    ),
  )
}

///|
fn risk_test_wire(preview_cid : String, claims : String) -> String {
  risk_test_wire_with_auth(preview_cid, claims, preview_footprint_test_cid("a"))
}

///|
test "risk detached-authentication payload excludes only auth and self references" {
  let a = preview_footprint_test_cid("a")
  let b = preview_footprint_test_cid("b")
  let c = preview_footprint_test_cid("c")
  let first = admit_effect_risk_acceptance_body(
    risk_test_wire_with_auth(b, "[\"effect_scope_approved\"]", a),
    8192,
    256,
    12,
  ).unwrap()
  assert_eq(
    effect_risk_acceptance_unsigned_payload_cid(first),
    "sha256:07beb07c409c4a23fba09591f3d9aac3ef9db518b2c6bdc3f0b02c807b98b18d",
  )
  let changed_auth = admit_effect_risk_acceptance_body(
    risk_test_wire_with_auth(b, "[\"effect_scope_approved\"]", c),
    8192,
    256,
    12,
  ).unwrap()
  assert_eq(
    effect_risk_acceptance_unsigned_payload_cid(changed_auth),
    effect_risk_acceptance_unsigned_payload_cid(first),
  )
  assert_true(changed_auth.cid != first.cid)
  let changed_preview = admit_effect_risk_acceptance_body(
    risk_test_wire_with_auth(c, "[\"effect_scope_approved\"]", a),
    8192,
    256,
    12,
  ).unwrap()
  assert_true(
    effect_risk_acceptance_unsigned_payload_cid(changed_preview) !=
    effect_risk_acceptance_unsigned_payload_cid(first),
  )
}

///|
test "risk acceptance binds canonical body and exact private Preview" {
  let a = preview_footprint_test_cid("a")
  let authoring = "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a"
  let scope = prepare_logical_request_scope(a, "risk-request", 32).unwrap()
  let (preview_wire, _) = preview_apply_test_wire(scope, "halt")
  let preview = @publication.admit_effect_preview_identity(
    preview_wire, a, authoring, 8192, 256, 12,
  ).unwrap()
  let risk_wire = risk_test_wire(
    @publication.effect_preview_semantic_identity(preview),
    "[\"effect_scope_approved\"]",
  )
  let risk = admit_effect_risk_acceptance_body(risk_wire, 8192, 256, 12).unwrap()
  assert_true(
    check_effect_risk_acceptance_body(
      preview, risk, a, a, a, a, a, a, "policy", "allow",
    )
    is Ok(_),
  )
  assert_true(
    check_effect_risk_acceptance_body(
      preview,
      risk,
      preview_footprint_test_cid("b"),
      a,
      a,
      a,
      a,
      a,
      "policy",
      "allow",
    )
    is Err(ForeignReviewProjection),
  )
  assert_true(
    check_effect_risk_acceptance_body(
      preview, risk, a, a, a, a, a, a, "human", "allow",
    )
    is Err(ForeignIssuerKind),
  )
  assert_true(
    check_effect_risk_acceptance_body(
      preview, risk, a, a, a, a, a, a, "policy", "approved",
    )
    is Err(ForeignDecision),
  )
  assert_true(
    admit_effect_risk_acceptance_body(
      risk_wire.replace_all(
        old="\"decision\":\"allow\"",
        new="\"decision\":\"approved\"",
      ),
      8192,
      256,
      12,
    )
    is Err(InvalidIdentity),
  )
  assert_true(
    admit_effect_risk_acceptance_body(
      risk_test_wire(
        @publication.effect_preview_semantic_identity(preview),
        "[\"effect_scope_approved\",\"effect_scope_approved\"]",
      ),
      8192,
      256,
      12,
    )
    is Err(InvalidShape),
  )
}
