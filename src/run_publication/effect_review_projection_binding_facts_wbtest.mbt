///|
fn review_binding_facts_fixture() -> RunEvidenceValue {
  seal_run_evidence_value(
    "review_projection", "{\"version\":\"actql-review-projection/0.1\",\"effect_preview_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"authoring_context_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"authority_scope_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"approval_claims\":[\"effect_scope_approved\"],\"redaction_policy_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"sensitivity\":\"restricted\",\"retention_class\":\"approval-evidence\",\"encryption_required\":true,\"displayed_scope\":{\"effects\":[]},\"displayed_permissions\":[],\"displayed_rows\":[],\"displayed_authoring_context\":[]}",
    65536, 4096, 32,
  ).unwrap()
}

///|
test "Review binding facts retain the admitted original and isolate returned claims" {
  let review = review_binding_facts_fixture()
  let before = run_evidence_value_json(review)
  let (preview, authoring, authority, claims) = effect_review_projection_binding_facts(
    review,
  ).unwrap()
  assert_eq(
    preview, "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  assert_eq(
    authoring, "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  )
  assert_eq(
    authority, "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
  )
  assert_eq(claims, ["effect_scope_approved"])
  claims.push("partial_application_accepted")
  let (_, _, _, again) = effect_review_projection_binding_facts(review).unwrap()
  assert_eq(again, ["effect_scope_approved"])
  assert_eq(run_evidence_value_json(review), before)
}

///|
test "Review binding facts do not reinterpret a different admitted evidence family" {
  let authoring = seal_run_evidence_value(
    "authoring_context", "{\"version\":\"actql-authoring-context/0.1\",\"program_definition_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"annotations\":[]}",
    65536, 4096, 32,
  ).unwrap()
  assert_true(effect_review_projection_binding_facts(authoring) is None)
}
