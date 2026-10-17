// Generated from independent two-receipt preimages; do not edit.

///|
test "two receipt preimage 0" {
  let input = @json.parse("{\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"read_view\":\"view-1\",\"received_bytes\":43,\"received_fields\":[\"amount\",\"id\"],\"received_rows\":2,\"received_rows_cid\":\"sha256:f3d361fe4b7d5abb78027fd06b49ca9faca87ed483cd8979aa121096df4f8580\",\"requirement_cid\":\"sha256:678cb081e046fc9acb8fa855e96ef66c42d60855a949a0367c1fedc7cfdaed49\",\"role\":\"validation_scan\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-receipt/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:edac5972455217173c0d97bd2420278ead3c37111ef65705905c6e99c26e8722")
}

///|
test "two receipt preimage 1" {
  let input = @json.parse("{\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"read_view\":\"view-1\",\"received_bytes\":10,\"received_fields\":[\"id\"],\"received_rows\":1,\"received_rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\",\"requirement_cid\":\"sha256:678cb081e046fc9acb8fa855e96ef66c42d60855a949a0367c1fedc7cfdaed49\",\"role\":\"native_result\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-receipt/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:49c4dee7513de1cbd6fbb6dbf2cd7db7ffc2fbf2f07b56373e4a4b2e967d471f")
}

///|
test "two receipt preimage 2" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:49c4dee7513de1cbd6fbb6dbf2cd7db7ffc2fbf2f07b56373e4a4b2e967d471f\",\"validation_scan_cid\":\"sha256:edac5972455217173c0d97bd2420278ead3c37111ef65705905c6e99c26e8722\"},\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"read_view\":\"view-1\",\"requirement_cid\":\"sha256:678cb081e046fc9acb8fa855e96ef66c42d60855a949a0367c1fedc7cfdaed49\",\"role\":\"source_validation\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-two-receipt-evidence/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:bc93a94c720b863637bbcab16cd39d4eba4af16f9f9e5b37a5a26f7319e2e25b")
}

///|
test "two receipt preimage 3" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:49c4dee7513de1cbd6fbb6dbf2cd7db7ffc2fbf2f07b56373e4a4b2e967d471f\",\"validation_scan_cid\":\"sha256:edac5972455217173c0d97bd2420278ead3c37111ef65705905c6e99c26e8722\"},\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"read_view\":\"view-1\",\"requirement_cid\":\"sha256:678cb081e046fc9acb8fa855e96ef66c42d60855a949a0367c1fedc7cfdaed49\",\"role\":\"filter\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-two-receipt-evidence/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:78c93010aaa3157c620a9403aa94ab448a9339878ade12ccdabf197733abe405")
}

///|
test "two receipt preimage 4" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:49c4dee7513de1cbd6fbb6dbf2cd7db7ffc2fbf2f07b56373e4a4b2e967d471f\",\"validation_scan_cid\":\"sha256:edac5972455217173c0d97bd2420278ead3c37111ef65705905c6e99c26e8722\"},\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"read_view\":\"view-1\",\"requirement_cid\":\"sha256:678cb081e046fc9acb8fa855e96ef66c42d60855a949a0367c1fedc7cfdaed49\",\"role\":\"select\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-two-receipt-evidence/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:56516e3334ae16300f450bd8c9b2c4cb0958cfcf3a4577049fefc62e8be6a3e2")
}

///|
test "two receipt preimage 5" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:49c4dee7513de1cbd6fbb6dbf2cd7db7ffc2fbf2f07b56373e4a4b2e967d471f\",\"validation_scan_cid\":\"sha256:edac5972455217173c0d97bd2420278ead3c37111ef65705905c6e99c26e8722\"},\"coverage\":{\"complete\":true,\"filter_evidence_cid\":\"sha256:78c93010aaa3157c620a9403aa94ab448a9339878ade12ccdabf197733abe405\",\"scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"select_evidence_cid\":\"sha256:56516e3334ae16300f450bd8c9b2c4cb0958cfcf3a4577049fefc62e8be6a3e2\",\"source_validation_evidence_cid\":\"sha256:bc93a94c720b863637bbcab16cd39d4eba4af16f9f9e5b37a5a26f7319e2e25b\"},\"evidence_contract_cid\":\"sha256:db7ce19477afd82a8488a9f64fd75697c850eaaccdc738995483cc138a06361a\",\"execution\":{\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"read_view\":\"view-1\"},\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"owner\":{\"input\":\"records\",\"program_source_cid\":\"sha256:08119b4990d8d7e26062c9ff0bae80f03ec5cc471ca9a3b7a32205a22c9e07cf\",\"stage\":\"first\"},\"parameter_values_cid\":\"sha256:ce3468bea3995136201f0f1242c8d388f927d5c1b751f60a6cccf6b539ef4897\",\"requirement_cid\":\"sha256:678cb081e046fc9acb8fa855e96ef66c42d60855a949a0367c1fedc7cfdaed49\",\"resolved_request_cid\":\"sha256:9e475b942ea0d73d63e2e4cdeffb72d0d145e5bbd3cdf4605d2acbca829cdde1\",\"retention\":\"process\",\"snapshot\":null,\"source_contract_cid\":\"sha256:7bcef77b0a1627fbd4687b96f276f348e3aa564575e3fb16dd2991c664a535d1\",\"source_ref\":\"connector://fixture/local-read#scan\",\"version\":\"actql-query-two-receipt-observation/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:fc6a47160b88ff7fedd1553eb7498c1e01a6fa4316d3648ffd2745b42d135777")
}
