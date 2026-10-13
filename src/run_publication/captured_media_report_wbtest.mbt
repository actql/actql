///|
// Independently fixed canonical preimages and SHA-256. No product encoder,
// captured bytes, ReferenceIssuer or provider response produced these values.
test "captured MIME retains exact report in independent issuer and Ref identities" {
  let cases = [
    ("application/pdf", "application/pdf", "sha256:f7d077c12bd2d83b134036e19f2fc17ab8290f80257e0dd08f3873aba1e52317", "sha256:48897d51c27c2e3379072119b778536557890fda8bfade70017f9274cbb2ea36"),
    ("Application/PDF", "application/pdf", "sha256:8860ddb8251b67b6468860e3782aca76ec2e6b38ae399cf7805eafc3e07f9779", "sha256:26f153b4995a934a29f85b0883b245ca36850ced43eb4b30922e3a90b8c46fa4"),
    ("Text/Plain;Label=\"é\"", "text/plain;label=\"é\"", "sha256:27dc2b5382f7e529e22ae187a84196056f5d680b2e9cc02f7d14f071a71a303e", "sha256:8c31c107d791ed13001d3e295e363b0e832fbd92a67e6522257efedb4c2a7a32"),
    ("Text/Plain;Label=\"é\"", "text/plain;label=\"é\"", "sha256:ff6753e45da15c206ba98a6511269e5698b12ff96a2d57d8efd404da9c277401", "sha256:8816a4d58bc5f68c8052aa9ece6611e6170615676e75083d5493219d251581f9"),
  ]
  for (reported, media, issuer_cid, ref_cid) in cases {
    let candidate = prepare_captured_content_reference(
      content_reference_test_binding(), reported,
      "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      0, content_reference_test_limits(),
    ).unwrap()
    assert_eq(captured_content_reference_media_type(candidate), media)
    assert_eq(captured_content_reference_identity(candidate), ref_cid)
    let body = parse_contract_wire(captured_content_reference_wire(candidate), 4096, 100, 8, data_keys=true).unwrap()
    let evidence = @json.object_field(@json.object_field(body, "metadata").unwrap(), "issuer_evidence").unwrap()
    assert_eq(contract_string_from_value(evidence, "reported_media_type"), Some(reported))
    assert_eq(contract_string_from_value(evidence, "evidence_cid"), Some(issuer_cid))
  }
}

///|
test "saved captured MIME reconstructs original report and refuses missing or changed evidence" {
  let limits = content_reference_test_limits()
  let binding = content_reference_test_binding()
  let original_wire = "{\"$actql_ref\":\"content\",\"content_ref_cid\":\"sha256:26f153b4995a934a29f85b0883b245ca36850ced43eb4b30922e3a90b8c46fa4\",\"media_type\":\"application/pdf\",\"metadata\":{\"availability_evidence_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"capture_authority\":\"read_content\",\"content_cid\":\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\",\"content_store_id\":\"fixture\",\"data_classification\":\"internal\",\"effective_data_policy_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"issuer_evidence\":{\"capture_authority_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"content_cid\":\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\",\"content_store_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"effective_data_policy_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"evidence_cid\":\"sha256:8860ddb8251b67b6468860e3782aca76ec2e6b38ae399cf7805eafc3e07f9779\",\"issuer_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"issuer_kind\":\"connector_capture\",\"reported_media_type\":\"Application/PDF\",\"version\":\"actql-content-issuer-evidence/0.1\",\"workspace_scope_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\"},\"media_type\":\"application/pdf\",\"retention_class\":\"fixture\",\"size_bytes\":0,\"storage_scope\":\"workspace\",\"truncated\":false},\"version\":\"actql-content-ref/0.1\"}"
  let candidate = prepare_captured_content_reference(
    binding, "Application/PDF",
    "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    0, limits,
  ).unwrap()
  assert_eq(captured_content_reference_wire(candidate), original_wire)
  let saved = prepare_stored_captured_content_reference(original_wire, binding, limits).unwrap()
  assert_eq(captured_content_reference_wire(saved), original_wire)
  assert_eq(captured_content_reference_media_type(saved), "application/pdf")
  for changed in [
    original_wire.replace(old="\\\"reported_media_type\\\":\\\"Application/PDF\\\",", new=""),
    original_wire.replace(old="Application/PDF", new="application/pdf"),
    original_wire.replace(old="Application/PDF", new="text/plain"),
    original_wire.replace(old="Application/PDF", new="broken MIME"),
  ] {
    assert_true(prepare_stored_captured_content_reference(changed, binding, limits) is Err(_))
  }
  let retired_wire = "{\"$actql_ref\":\"content\",\"content_ref_cid\":\"sha256:2dfff07c2e376252233bf4a15fa5c1277c255adc2ec6c946a6e70d9206c71716\",\"media_type\":\"application/pdf\",\"metadata\":{\"availability_evidence_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"capture_authority\":\"read_content\",\"content_cid\":\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\",\"content_store_id\":\"fixture\",\"data_classification\":\"internal\",\"effective_data_policy_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"issuer_evidence\":{\"capture_authority_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"content_cid\":\"sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\",\"content_store_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"effective_data_policy_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"evidence_cid\":\"sha256:3262be0c7204cd24b97fc4e3a322a51916435887dde89dc873017202a7379771\",\"issuer_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"issuer_kind\":\"connector_capture\",\"version\":\"actql-content-issuer-evidence/0.1\",\"workspace_scope_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\"},\"media_type\":\"application/pdf\",\"retention_class\":\"fixture\",\"size_bytes\":0,\"storage_scope\":\"workspace\",\"truncated\":false},\"version\":\"actql-content-ref/0.1\"}"
  assert_true(prepare_stored_captured_content_reference(retired_wire, binding, limits) is Err(InvalidBinding("reported_media_type")))
  assert_true(prepare_captured_content_reference(binding, "broken MIME",
    "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", 0, limits) is Err(InvalidBinding("reported_media_type")))
}
