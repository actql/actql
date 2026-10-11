// Generated from independent two-receipt preimages; do not edit.

///|
test "two receipt preimage 0" {
  let input = @json.parse("{\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"read_view\":\"view-1\",\"received_bytes\":43,\"received_fields\":[\"amount\",\"id\"],\"received_rows\":2,\"received_rows_cid\":\"sha256:f3d361fe4b7d5abb78027fd06b49ca9faca87ed483cd8979aa121096df4f8580\",\"requirement_cid\":\"sha256:100cf36b04bd9280148cf8d36c4a39c2fd2288caf4230629e973712cc9599331\",\"role\":\"validation_scan\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-receipt/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:fd589a0748ca4d2f6c2bb26e67df63b1bdf7335f551769481a0545ff0a88767a")
}

///|
test "two receipt preimage 1" {
  let input = @json.parse("{\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"read_view\":\"view-1\",\"received_bytes\":10,\"received_fields\":[\"id\"],\"received_rows\":1,\"received_rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\",\"requirement_cid\":\"sha256:100cf36b04bd9280148cf8d36c4a39c2fd2288caf4230629e973712cc9599331\",\"role\":\"native_result\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-receipt/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:2191bcb6d4e297fa257904e5e6711b73d3beb81c82078931f88e417227c43ea8")
}

///|
test "two receipt preimage 2" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:2191bcb6d4e297fa257904e5e6711b73d3beb81c82078931f88e417227c43ea8\",\"validation_scan_cid\":\"sha256:fd589a0748ca4d2f6c2bb26e67df63b1bdf7335f551769481a0545ff0a88767a\"},\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"read_view\":\"view-1\",\"requirement_cid\":\"sha256:100cf36b04bd9280148cf8d36c4a39c2fd2288caf4230629e973712cc9599331\",\"role\":\"source_validation\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-two-receipt-evidence/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:5e78292aeba9a58787a7a1ffe8aa78ebde9c5ca8d119d0fb4f4977d708e866aa")
}

///|
test "two receipt preimage 3" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:2191bcb6d4e297fa257904e5e6711b73d3beb81c82078931f88e417227c43ea8\",\"validation_scan_cid\":\"sha256:fd589a0748ca4d2f6c2bb26e67df63b1bdf7335f551769481a0545ff0a88767a\"},\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"read_view\":\"view-1\",\"requirement_cid\":\"sha256:100cf36b04bd9280148cf8d36c4a39c2fd2288caf4230629e973712cc9599331\",\"role\":\"filter\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-two-receipt-evidence/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:661b0cfc28d62c1c0f8722a205cf84202b84b55ec052fbe319770ea7d15026c6")
}

///|
test "two receipt preimage 4" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:2191bcb6d4e297fa257904e5e6711b73d3beb81c82078931f88e417227c43ea8\",\"validation_scan_cid\":\"sha256:fd589a0748ca4d2f6c2bb26e67df63b1bdf7335f551769481a0545ff0a88767a\"},\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"read_view\":\"view-1\",\"requirement_cid\":\"sha256:100cf36b04bd9280148cf8d36c4a39c2fd2288caf4230629e973712cc9599331\",\"role\":\"select\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-two-receipt-evidence/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:2b3afcca1c15e3720d10d91e800a647609be6f305c2d905cb4f5cd96e2329ddc")
}

///|
test "two receipt preimage 5" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:2191bcb6d4e297fa257904e5e6711b73d3beb81c82078931f88e417227c43ea8\",\"validation_scan_cid\":\"sha256:fd589a0748ca4d2f6c2bb26e67df63b1bdf7335f551769481a0545ff0a88767a\"},\"coverage\":{\"complete\":true,\"filter_evidence_cid\":\"sha256:661b0cfc28d62c1c0f8722a205cf84202b84b55ec052fbe319770ea7d15026c6\",\"scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"select_evidence_cid\":\"sha256:2b3afcca1c15e3720d10d91e800a647609be6f305c2d905cb4f5cd96e2329ddc\",\"source_validation_evidence_cid\":\"sha256:5e78292aeba9a58787a7a1ffe8aa78ebde9c5ca8d119d0fb4f4977d708e866aa\"},\"evidence_contract_cid\":\"sha256:7d9eec132b742aca27b78a801c6bea187a251b7423967950e285755c50e853d8\",\"execution\":{\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"read_view\":\"view-1\"},\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"owner\":{\"input\":\"records\",\"program_source_cid\":\"sha256:0a6f0f12c849d7248479ece309c38b2e5145522338ee82a4bdccb358e8c4f95e\",\"stage\":\"first\"},\"parameter_values_cid\":\"sha256:ce3468bea3995136201f0f1242c8d388f927d5c1b751f60a6cccf6b539ef4897\",\"requirement_cid\":\"sha256:100cf36b04bd9280148cf8d36c4a39c2fd2288caf4230629e973712cc9599331\",\"resolved_request_cid\":\"sha256:9e475b942ea0d73d63e2e4cdeffb72d0d145e5bbd3cdf4605d2acbca829cdde1\",\"retention\":\"process\",\"snapshot\":null,\"source_contract_cid\":\"sha256:7bcef77b0a1627fbd4687b96f276f348e3aa564575e3fb16dd2991c664a535d1\",\"source_ref\":\"connector://fixture/local-read#scan\",\"version\":\"actql-query-two-receipt-observation/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:974697f177c1ed3f7a98ed297899943285c4af4bdac7a7f18f3362f84f77016c")
}
