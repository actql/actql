///|
test "Model media dependency generated schema matches the closed complete-byte profile" {
  // Canonical preimage and digest independently fixed using Node SHA-256,
  // not returned by the common sealer or the Model dependency reader.
  let body =
    #|{"payload":{"classifications":["internal"],"complete":true,"egress_scope_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","max_bytes":4096,"max_frames":null,"max_pages":4,"media_type":"application/pdf","regions":["fixture-region"],"transfer_method":"inline_bytes"},"version":"actql-model-media-input/0.1"}
  let value = parse_contract_wire(body, 4096, 128, 16).unwrap()
  // Dependency admission is not newly issued Run observation evidence.
  assert_true(
    validate_generated_protocol_shape(
      "model_media_input", value, false, 4096, 128, 16,
    ),
  )
  assert_eq(
    @json.cid_value(value, 4096, 128, 16),
    "sha256:ece55a0064625c262ee09ae48b8293377848469876c77b1c19718dab759280fe",
  )
  for
    invalid in [
      body.replace(old="\"max_frames\":null,", new=""),
      body.replace(old="\"complete\":true", new="\"complete\":false"),
      body.replace(old="\"max_bytes\":4096", new="\"max_bytes\":0"),
      body.replace(old="\"max_pages\":4", new="\"max_pages\":null"),
      body.replace(
        old="\"transfer_method\":\"inline_bytes\"",
        new="\"transfer_method\":\"arbitrary_url\"",
      ),
    ] {
    if invalid.contains("\"max_pages\":null") {
      // Explicitly not-applicable is part of the same nullable schema; absent
      // is not. Byte/page applicability is checked by the physical preflight.
      assert_true(
        validate_generated_protocol_shape(
          "model_media_input",
          parse_contract_wire(invalid, 4096, 128, 16).unwrap(),
          false,
          4096,
          128,
          16,
        ),
      )
    } else {
      assert_false(
        validate_generated_protocol_shape(
          "model_media_input",
          parse_contract_wire(invalid, 4096, 128, 16).unwrap(),
          false,
          4096,
          128,
          16,
        ),
      )
    }
  }
}
