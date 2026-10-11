// Generated from independent two-receipt preimages; do not edit.

///|
test "two receipt preimage 0" {
  let input = @json.parse("{\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"read_view\":\"view-1\",\"received_bytes\":43,\"received_fields\":[\"amount\",\"id\"],\"received_rows\":2,\"received_rows_cid\":\"sha256:f3d361fe4b7d5abb78027fd06b49ca9faca87ed483cd8979aa121096df4f8580\",\"requirement_cid\":\"sha256:24f6dcd372b8548bc010a2fbc7818db651c9cf138d61823c8334693a36167cc1\",\"role\":\"validation_scan\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-receipt/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:f8cc49b6b32f1a8f18ecc1e270ee53339d44bb77b52219bcbee650bf11674649")
}

///|
test "two receipt preimage 1" {
  let input = @json.parse("{\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"read_view\":\"view-1\",\"received_bytes\":10,\"received_fields\":[\"id\"],\"received_rows\":1,\"received_rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\",\"requirement_cid\":\"sha256:24f6dcd372b8548bc010a2fbc7818db651c9cf138d61823c8334693a36167cc1\",\"role\":\"native_result\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-receipt/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:d3a16db34d08d8f7d3ed51f3ce58c15fc243285fbdac9519900844af092aa2c3")
}

///|
test "two receipt preimage 2" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:d3a16db34d08d8f7d3ed51f3ce58c15fc243285fbdac9519900844af092aa2c3\",\"validation_scan_cid\":\"sha256:f8cc49b6b32f1a8f18ecc1e270ee53339d44bb77b52219bcbee650bf11674649\"},\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"read_view\":\"view-1\",\"requirement_cid\":\"sha256:24f6dcd372b8548bc010a2fbc7818db651c9cf138d61823c8334693a36167cc1\",\"role\":\"source_validation\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-two-receipt-evidence/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:a9ad247cb587e5b119d50182b147627d5a2bf1baaa5f4572ee2c2f1a88d89eab")
}

///|
test "two receipt preimage 3" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:d3a16db34d08d8f7d3ed51f3ce58c15fc243285fbdac9519900844af092aa2c3\",\"validation_scan_cid\":\"sha256:f8cc49b6b32f1a8f18ecc1e270ee53339d44bb77b52219bcbee650bf11674649\"},\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"read_view\":\"view-1\",\"requirement_cid\":\"sha256:24f6dcd372b8548bc010a2fbc7818db651c9cf138d61823c8334693a36167cc1\",\"role\":\"filter\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-two-receipt-evidence/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:54d58f96ef0dc2131cd0720dda5a874dafd169ca782c4caa74d10bc6c4ebba8b")
}

///|
test "two receipt preimage 4" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:d3a16db34d08d8f7d3ed51f3ce58c15fc243285fbdac9519900844af092aa2c3\",\"validation_scan_cid\":\"sha256:f8cc49b6b32f1a8f18ecc1e270ee53339d44bb77b52219bcbee650bf11674649\"},\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"read_view\":\"view-1\",\"requirement_cid\":\"sha256:24f6dcd372b8548bc010a2fbc7818db651c9cf138d61823c8334693a36167cc1\",\"role\":\"select\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-two-receipt-evidence/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:3517b9facc2562130cfea958a796e28e77bb34ad61a77788819885655d94c721")
}

///|
test "two receipt preimage 5" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:d3a16db34d08d8f7d3ed51f3ce58c15fc243285fbdac9519900844af092aa2c3\",\"validation_scan_cid\":\"sha256:f8cc49b6b32f1a8f18ecc1e270ee53339d44bb77b52219bcbee650bf11674649\"},\"coverage\":{\"complete\":true,\"filter_evidence_cid\":\"sha256:54d58f96ef0dc2131cd0720dda5a874dafd169ca782c4caa74d10bc6c4ebba8b\",\"scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"select_evidence_cid\":\"sha256:3517b9facc2562130cfea958a796e28e77bb34ad61a77788819885655d94c721\",\"source_validation_evidence_cid\":\"sha256:a9ad247cb587e5b119d50182b147627d5a2bf1baaa5f4572ee2c2f1a88d89eab\"},\"evidence_contract_cid\":\"sha256:7d9eec132b742aca27b78a801c6bea187a251b7423967950e285755c50e853d8\",\"execution\":{\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"read_view\":\"view-1\"},\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"owner\":{\"input\":\"records\",\"program_source_cid\":\"sha256:69dabafd2b636418fbb963ee6f55daaff2441ab0a2eb694e482e71d032c18cef\",\"stage\":\"first\"},\"parameter_values_cid\":\"sha256:ce3468bea3995136201f0f1242c8d388f927d5c1b751f60a6cccf6b539ef4897\",\"requirement_cid\":\"sha256:24f6dcd372b8548bc010a2fbc7818db651c9cf138d61823c8334693a36167cc1\",\"resolved_request_cid\":\"sha256:9e475b942ea0d73d63e2e4cdeffb72d0d145e5bbd3cdf4605d2acbca829cdde1\",\"retention\":\"process\",\"snapshot\":null,\"source_contract_cid\":\"sha256:7bcef77b0a1627fbd4687b96f276f348e3aa564575e3fb16dd2991c664a535d1\",\"source_ref\":\"connector://fixture/local-read#scan\",\"version\":\"actql-query-two-receipt-observation/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:d45df384875bcdf7be09ed6e2479c39c82d1347828fa52629fc07eb0ff48d344")
}
