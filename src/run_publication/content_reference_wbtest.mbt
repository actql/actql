///|
fn content_reference_test_binding() -> GeneratedContentBinding {
  {
    content_store_id: "fixture",
    content_store_cid: "sha256:1111111111111111111111111111111111111111111111111111111111111111",
    workspace_scope_cid: "sha256:2222222222222222222222222222222222222222222222222222222222222222",
    storage_scope: "workspace",
    retention_class: "fixture",
    expires_at: None,
    availability_evidence_cid: "sha256:3333333333333333333333333333333333333333333333333333333333333333",
    effective_data_policy_cid: "sha256:4444444444444444444444444444444444444444444444444444444444444444",
    data_classification: "internal",
    issuer_contract_cid: "sha256:5555555555555555555555555555555555555555555555555555555555555555",
    capture_authority_cid: "sha256:6666666666666666666666666666666666666666666666666666666666666666",
  }
}

///|
fn content_reference_test_limits() -> @admitted.ReferenceLimits {
  { max_bytes: 4096, max_nodes: 100, max_depth: 8, max_text_units: 4096, }
}

///|
fn content_reference_empty_encoder() -> ContentByteEncoder raise {
  let owner = content_test_encoder(
    content_test_profile(ContentJsonl, "{\"name\":\"empty.jsonl\"}"),
  )
  assert_eq(drain_content_test(owner, 1).0, "")
  let completion = finish_content_bytes(owner).unwrap()
  assert_eq(completion.size_bytes, 0)
  assert_eq(completion.row_count, 0)
  assert_eq(
    completion.content_cid,
    "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  owner
}

///|
test "Content reference candidate uses completed bytes and independent identities" {
  let owner = content_reference_empty_encoder()
  let candidate = prepare_generated_content_reference(
    owner,
    content_reference_test_binding(),
    content_reference_test_limits(),
  ).unwrap()
  // Independently canonicalized ASCII preimages and Node SHA-256, not product
  // output. Empty JSONL has the standard zero-byte content digest.
  assert_eq(
    generated_content_issuer_evidence_cid(candidate),
    "sha256:2a4d3820a33234b966fdcee9c32aab5049e9be58cd3abeea6253ab38cb57684f",
  )
  assert_eq(
    generated_content_reference_identity(candidate),
    "sha256:0d11df98e30db97f20f9154bccd2ed9141238afcbd09ac0dde74104dd8809df8",
  )
  let value = parse_contract_wire(
    generated_content_reference_wire(candidate),
    4096,
    100,
    8,
    data_keys=true,
  ).unwrap()
  let metadata = @json.object_field(value, "metadata").unwrap()
  assert_true(
    @json.object_field(metadata, "size_bytes") is Some(@json.Number(0)),
  )
  assert_true(
    @json.object_field(metadata, "truncated") is Some(@json.Bool(false)),
  )
  assert_true(
    @json.object_field(metadata, "media_type")
    is Some(@json.String("application/x-ndjson")),
  )
  assert_true(@json.object_field(metadata, "source_resource_ref") is None)
  let incomplete = content_test_encoder(
    content_test_profile(ContentJsonl, "{\"name\":\"empty.jsonl\"}"),
  )
  assert_true(
    prepare_generated_content_reference(
      incomplete,
      content_reference_test_binding(),
      content_reference_test_limits(),
    )
    is Err(GenerationIncomplete),
  )
}

///|
test "Content reference issuance requires exact Store evidence and current authority" {
  let candidate = prepare_generated_content_reference(
    content_reference_empty_encoder(),
    content_reference_test_binding(),
    content_reference_test_limits(),
  ).unwrap()
  let stored = Ref(false)
  let authorized = Ref(true)
  let expected = generated_content_reference_wire(candidate)
  let issuer = @admitted.bind_reference_issuer(
    (_, wire) => stored.val && wire == expected,
    _ => authorized.val,
  )
  assert_true(
    issue_generated_content_reference(
      candidate,
      issuer,
      content_reference_test_limits(),
    )
    is Err(Issuance(@admitted.IssuerRejected)),
  )
  stored.val = true
  authorized.val = false
  assert_true(
    issue_generated_content_reference(
      candidate,
      issuer,
      content_reference_test_limits(),
    )
    is Err(Issuance(@admitted.Unauthorized)),
  )
  authorized.val = true
  let issued = issue_generated_content_reference(
    candidate,
    issuer,
    content_reference_test_limits(),
  ).unwrap()
  let writer = @encode.writer(4096, 100, 8)
  @admitted.emit_checked_wire_value(issued, writer)
  assert_eq(@encode.finish(writer), expected)
  // A parsed candidate from the same bytes but another scope is not this
  // Store's issued occurrence. No byte CID-only authority fallback is allowed.
  let binding = content_reference_test_binding()
  let foreign = prepare_generated_content_reference(
    content_reference_empty_encoder(),
    { ..binding, content_store_id: "another-store", },
    content_reference_test_limits(),
  ).unwrap()
  assert_true(
    generated_content_reference_identity(foreign) !=
    generated_content_reference_identity(candidate),
  )
  assert_true(
    issue_generated_content_reference(
      foreign,
      issuer,
      content_reference_test_limits(),
    )
    is Err(Issuance(@admitted.IssuerRejected)),
  )
}

///|
test "Content reference binding rejects invalid fields and preserves data spelling" {
  let owner = content_reference_empty_encoder()
  let binding = content_reference_test_binding()
  for
    changed in [
      { ..binding, content_store_cid: "not-a-cid", },
      { ..binding, storage_scope: "other", },
      { ..binding, retention_class: "", },
      { ..binding, expires_at: Some("not-a-date"), },
    ] {
    assert_true(
      prepare_generated_content_reference(
        owner,
        changed,
        content_reference_test_limits(),
      )
      is Err(InvalidBinding(_)),
    )
  }
  let candidate = prepare_generated_content_reference(
    owner,
    { ..binding, content_store_id: "e\u{0301}", },
    content_reference_test_limits(),
  ).unwrap()
  let metadata = @json.object_field(
    parse_contract_wire(
      generated_content_reference_wire(candidate),
      4096,
      100,
      8,
      data_keys=true,
    ).unwrap(),
    "metadata",
  ).unwrap()
  assert_true(
    @json.object_field(metadata, "content_store_id")
    is Some(@json.String("e\u{0301}")),
  )
}

///|
test "Captured Content uses independent byte and issuer identities without envelope authority" {
  let limits = content_reference_test_limits()
  let candidate = prepare_captured_content_reference(
    content_reference_test_binding(),
    "application/pdf",
    "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    0,
    limits,
  ).unwrap()
  // Independent ASCII canonical preimages and Node SHA-256. This candidate
  // differs from derivation even when the byte digest and Store bindings agree.
  assert_eq(
    captured_content_reference_identity(candidate),
    "sha256:2dfff07c2e376252233bf4a15fa5c1277c255adc2ec6c946a6e70d9206c71716",
  )
  let wire = captured_content_reference_wire(candidate)
  let body = parse_contract_wire(wire, 4096, 100, 8, data_keys=true).unwrap()
  let metadata = @json.object_field(body, "metadata").unwrap()
  let evidence = @json.object_field(metadata, "issuer_evidence").unwrap()
  assert_eq(
    contract_string_from_value(evidence, "evidence_cid"),
    Some(
      "sha256:3262be0c7204cd24b97fc4e3a322a51916435887dde89dc873017202a7379771",
    ),
  )
  assert_eq(
    contract_string_from_value(evidence, "issuer_kind"),
    Some("connector_capture"),
  )
  let stored = Ref(false)
  let authorized = Ref(true)
  let issuer = @admitted.bind_reference_issuer(
    (_, observed) => stored.val && observed == wire,
    _ => authorized.val,
  )
  assert_true(
    issue_captured_content_reference(candidate, issuer, limits)
    is Err(Issuance(@admitted.IssuerRejected)),
  )
  stored.val = true
  authorized.val = false
  assert_true(
    issue_captured_content_reference(candidate, issuer, limits)
    is Err(Issuance(@admitted.Unauthorized)),
  )
  authorized.val = true
  let issued = issue_captured_content_reference(candidate, issuer, limits).unwrap()
  let writer = @encode.writer(4096, 100, 8)
  @admitted.emit_checked_wire_value(issued, writer)
  assert_eq(@encode.finish(writer), wire)
  assert_true(
    prepare_captured_content_reference(
      content_reference_test_binding(),
      "application/pdf",
      "not-a-cid",
      0,
      limits,
    )
    is Err(InvalidBinding("content_bytes")),
  )
  assert_true(
    prepare_captured_content_reference(
      content_reference_test_binding(),
      "application/pdf",
      "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      -1,
      limits,
    )
    is Err(InvalidBinding("content_bytes")),
  )
}
