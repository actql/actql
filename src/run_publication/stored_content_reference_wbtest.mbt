///|
test "saved generated Content reference retains its identity without encoding again" {
  let binding = content_reference_test_binding()
  let limits = content_reference_test_limits()
  let original = prepare_generated_content_reference(
    content_reference_empty_encoder(),
    binding,
    limits,
  ).unwrap()
  let wire = generated_content_reference_wire(original)
  let saved = prepare_stored_generated_content_reference(wire, binding, limits).unwrap()
  assert_eq(stored_generated_content_reference_wire(saved), wire)
  assert_eq(
    stored_generated_content_reference_storage(saved),
    (
      "sha256:0d11df98e30db97f20f9154bccd2ed9141238afcbd09ac0dde74104dd8809df8",
      binding.content_store_cid,
      binding.workspace_scope_cid,
      "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      0,
    ),
  )
  let stored = Ref(false)
  let allowed = Ref(true)
  let issuer = @admitted.bind_reference_issuer(
    (_, observed) => stored.val && observed == wire,
    _ => allowed.val,
  )
  assert_true(
    issue_stored_generated_content_reference(saved, issuer, limits)
    is Err(Issuance(@admitted.IssuerRejected)),
  )
  stored.val = true
  allowed.val = false
  assert_true(
    issue_stored_generated_content_reference(saved, issuer, limits)
    is Err(Issuance(@admitted.Unauthorized)),
  )
  allowed.val = true
  let value = issue_stored_generated_content_reference(saved, issuer, limits).unwrap()
  guard value.value is @admitted.Reference(reference) else {
    fail("No reference")
  }
  assert_eq(@admitted.reference_wire(reference), wire)
  assert_true(@admitted.reference_available(reference))
  allowed.val = false
  assert_true(!@admitted.reference_available(reference))
}

///|
test "saved generated reference refuses binding changes and metadata repair" {
  let binding = content_reference_test_binding()
  let limits = content_reference_test_limits()
  let foreign = "sha256:7777777777777777777777777777777777777777777777777777777777777777"
  let wire = generated_content_reference_wire(
    prepare_generated_content_reference(
      content_reference_empty_encoder(),
      binding,
      limits,
    ).unwrap(),
  )
  for
    changed in [
      { ..binding, content_store_id: "another-store", },
      { ..binding, content_store_cid: foreign, },
      { ..binding, workspace_scope_cid: foreign, },
      { ..binding, effective_data_policy_cid: foreign, },
      { ..binding, availability_evidence_cid: foreign, },
      { ..binding, issuer_contract_cid: foreign, },
      { ..binding, capture_authority_cid: foreign, },
      { ..binding, retention_class: "renewed", },
      { ..binding, expires_at: Some("2026-10-11T00:00:00.000Z"), },
    ] {
    assert_true(
      prepare_stored_generated_content_reference(wire, changed, limits)
      is Err(InvalidBinding("saved_reference")),
    )
  }
  for
    changed in [
      wire.replace(old="\"size_bytes\":0", new="\"size_bytes\":0.5"),
      wire.replace(old="\"size_bytes\":0", new="\"size_bytes\":-1"),
      wire.replace(old="\"truncated\":false", new="\"truncated\":true"),
      wire.replace(
        old="\"issuer_kind\":\"content_derivation\"",
        new="\"issuer_kind\":\"connector_capture\"",
      ),
      wire.replace(old="\"metadata\":{", new="\"metadata\":{\"extra\":true,"),
      wire.replace(old="\"storage_scope\":\"workspace\",", new=""),
      wire.replace(
        old="0d11df98e30db97f20f9154bccd2ed9141238afcbd09ac0dde74104dd8809df8",
        new="7d11df98e30db97f20f9154bccd2ed9141238afcbd09ac0dde74104dd8809df8",
      ),
    ] {
    assert_true(
      prepare_stored_generated_content_reference(changed, binding, limits)
      is Err(_),
    )
  }
  assert_true(
    prepare_stored_generated_content_reference(wire, binding, {
      ..limits,
      max_bytes: 8,
    })
    is Err(Encoding),
  )
}
