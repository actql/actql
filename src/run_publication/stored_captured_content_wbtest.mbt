///|
test "saved captured Content retains its original identity and requires current custody" {
  let binding = content_reference_test_binding()
  let limits = content_reference_test_limits()
  let original = prepare_captured_content_reference(
    binding, "application/pdf", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    0, limits,
  ).unwrap()
  let wire = captured_content_reference_wire(original)
  let restored = prepare_stored_captured_content_reference(
    wire, binding, limits,
  ).unwrap()
  // Independent canonical preimage vector, shared with fresh capture tests.
  assert_eq(
    captured_content_reference_identity(restored),
    "sha256:2dfff07c2e376252233bf4a15fa5c1277c255adc2ec6c946a6e70d9206c71716",
  )
  assert_eq(captured_content_reference_wire(restored), wire)
  assert_eq(
    captured_content_reference_storage(restored),
    (
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
    issue_captured_content_reference(restored, issuer, limits)
    is Err(Issuance(@admitted.IssuerRejected)),
  )
  stored.val = true
  allowed.val = false
  assert_true(
    issue_captured_content_reference(restored, issuer, limits)
    is Err(Issuance(@admitted.Unauthorized)),
  )
  allowed.val = true
  let checked = issue_captured_content_reference(restored, issuer, limits).unwrap()
  guard checked.value is @admitted.Reference(reference) else {
    fail("No reference")
  }
  assert_eq(@admitted.reference_wire(reference), wire)
  allowed.val = false
  assert_true(!@admitted.reference_available(reference))
}

///|
test "saved captured Content refuses relabeling and provenance conversion" {
  let binding = content_reference_test_binding()
  let limits = content_reference_test_limits()
  let wire = captured_content_reference_wire(
    prepare_captured_content_reference(
      binding, "application/pdf", "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      0, limits,
    ).unwrap(),
  )
  let foreign = "sha256:7777777777777777777777777777777777777777777777777777777777777777"
  for
    changed in [
      { ..binding, content_store_id: "another-store", },
      { ..binding, content_store_cid: foreign, },
      { ..binding, workspace_scope_cid: foreign, },
      { ..binding, effective_data_policy_cid: foreign, },
      { ..binding, availability_evidence_cid: foreign, },
      { ..binding, issuer_contract_cid: foreign, },
      { ..binding, capture_authority_cid: foreign, },
      { ..binding, data_classification: "public", },
      { ..binding, retention_class: "renewed", },
      { ..binding, expires_at: Some("2026-10-11T00:00:00.000Z"), },
    ] {
    assert_true(
      prepare_stored_captured_content_reference(wire, changed, limits)
      is Err(InvalidBinding("saved_reference")),
    )
  }
  assert_true(
    prepare_stored_generated_content_reference(wire, binding, limits)
    is Err(InvalidBinding("saved_reference")),
  )
  let generated = generated_content_reference_wire(
    prepare_generated_content_reference(
      content_reference_empty_encoder(),
      binding,
      limits,
    ).unwrap(),
  )
  assert_true(
    prepare_stored_captured_content_reference(generated, binding, limits)
    is Err(InvalidBinding("saved_reference")),
  )
  for
    changed in [
      wire.replace(old="\"size_bytes\":0", new="\"size_bytes\":0.5"),
      wire.replace(old="\"size_bytes\":0", new="\"size_bytes\":-1"),
      wire.replace(old="\"truncated\":false", new="\"truncated\":true"),
      wire.replace(old="\"metadata\":{", new="\"metadata\":{\"extra\":true,"),
      wire.replace(old="\"storage_scope\":\"workspace\",", new=""),
      wire.replace(
        old="2dfff07c2e376252233bf4a15fa5c1277c255adc2ec6c946a6e70d9206c71716",
        new="7dfff07c2e376252233bf4a15fa5c1277c255adc2ec6c946a6e70d9206c71716",
      ),
    ] {
    assert_true(
      prepare_stored_captured_content_reference(changed, binding, limits)
      is Err(_),
    )
  }
  assert_true(
    prepare_stored_captured_content_reference(wire, binding, {
      ..limits,
      max_bytes: 8,
    })
    is Err(Encoding),
  )
}
