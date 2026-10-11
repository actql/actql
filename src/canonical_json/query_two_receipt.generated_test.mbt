// Generated from independent two-receipt preimages; do not edit.

///|
test "two receipt preimage 0" {
  let input = @json.parse("{\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"read_view\":\"view-1\",\"received_bytes\":43,\"received_fields\":[\"amount\",\"id\"],\"received_rows\":2,\"received_rows_cid\":\"sha256:f3d361fe4b7d5abb78027fd06b49ca9faca87ed483cd8979aa121096df4f8580\",\"requirement_cid\":\"sha256:aa26bb5bb5c80c3b4e2ecf396639b9f09e7e0db0bfbc9db6ed2e20aa4d777792\",\"role\":\"validation_scan\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-receipt/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:87a72e4312b9db27cc7232787a690e6fc469a06155f1f9c476d908657dc7524c")
}

///|
test "two receipt preimage 1" {
  let input = @json.parse("{\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"read_view\":\"view-1\",\"received_bytes\":10,\"received_fields\":[\"id\"],\"received_rows\":1,\"received_rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\",\"requirement_cid\":\"sha256:aa26bb5bb5c80c3b4e2ecf396639b9f09e7e0db0bfbc9db6ed2e20aa4d777792\",\"role\":\"native_result\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-receipt/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:c295394242c75c57ed6fae542f2cfda45faa38c3ab02a5728a577f569f167102")
}

///|
test "two receipt preimage 2" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:c295394242c75c57ed6fae542f2cfda45faa38c3ab02a5728a577f569f167102\",\"validation_scan_cid\":\"sha256:87a72e4312b9db27cc7232787a690e6fc469a06155f1f9c476d908657dc7524c\"},\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"read_view\":\"view-1\",\"requirement_cid\":\"sha256:aa26bb5bb5c80c3b4e2ecf396639b9f09e7e0db0bfbc9db6ed2e20aa4d777792\",\"role\":\"source_validation\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-two-receipt-evidence/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:2cdf3e7a3c54c2a591c19230f1cde6704d62e2767bac556ccee9d03cc9e896d0")
}

///|
test "two receipt preimage 3" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:c295394242c75c57ed6fae542f2cfda45faa38c3ab02a5728a577f569f167102\",\"validation_scan_cid\":\"sha256:87a72e4312b9db27cc7232787a690e6fc469a06155f1f9c476d908657dc7524c\"},\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"read_view\":\"view-1\",\"requirement_cid\":\"sha256:aa26bb5bb5c80c3b4e2ecf396639b9f09e7e0db0bfbc9db6ed2e20aa4d777792\",\"role\":\"filter\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-two-receipt-evidence/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:540e547658797e4961888ff62aa1ed5432f898e8ce008c3d2e12e8369135bac2")
}

///|
test "two receipt preimage 4" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:c295394242c75c57ed6fae542f2cfda45faa38c3ab02a5728a577f569f167102\",\"validation_scan_cid\":\"sha256:87a72e4312b9db27cc7232787a690e6fc469a06155f1f9c476d908657dc7524c\"},\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"read_view\":\"view-1\",\"requirement_cid\":\"sha256:aa26bb5bb5c80c3b4e2ecf396639b9f09e7e0db0bfbc9db6ed2e20aa4d777792\",\"role\":\"select\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-two-receipt-evidence/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:11bbe75c0f440743888c711ff6b51cd3039dc47dc8ec1641ccde215c7e017a94")
}

///|
test "two receipt preimage 5" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:c295394242c75c57ed6fae542f2cfda45faa38c3ab02a5728a577f569f167102\",\"validation_scan_cid\":\"sha256:87a72e4312b9db27cc7232787a690e6fc469a06155f1f9c476d908657dc7524c\"},\"coverage\":{\"complete\":true,\"filter_evidence_cid\":\"sha256:540e547658797e4961888ff62aa1ed5432f898e8ce008c3d2e12e8369135bac2\",\"scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"select_evidence_cid\":\"sha256:11bbe75c0f440743888c711ff6b51cd3039dc47dc8ec1641ccde215c7e017a94\",\"source_validation_evidence_cid\":\"sha256:2cdf3e7a3c54c2a591c19230f1cde6704d62e2767bac556ccee9d03cc9e896d0\"},\"evidence_contract_cid\":\"sha256:7d9eec132b742aca27b78a801c6bea187a251b7423967950e285755c50e853d8\",\"execution\":{\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"read_view\":\"view-1\"},\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"owner\":{\"input\":\"records\",\"program_source_cid\":\"sha256:b9e78abe6f41369a0003bac8b1b8296c6188976367d7ba9af70b4c11be4ccf21\",\"stage\":\"first\"},\"parameter_values_cid\":\"sha256:ce3468bea3995136201f0f1242c8d388f927d5c1b751f60a6cccf6b539ef4897\",\"requirement_cid\":\"sha256:aa26bb5bb5c80c3b4e2ecf396639b9f09e7e0db0bfbc9db6ed2e20aa4d777792\",\"resolved_request_cid\":\"sha256:9e475b942ea0d73d63e2e4cdeffb72d0d145e5bbd3cdf4605d2acbca829cdde1\",\"retention\":\"process\",\"snapshot\":null,\"source_contract_cid\":\"sha256:7bcef77b0a1627fbd4687b96f276f348e3aa564575e3fb16dd2991c664a535d1\",\"source_ref\":\"connector://fixture/local-read#scan\",\"version\":\"actql-query-two-receipt-observation/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:067e46edbf76bbdabd5f255c24c8c5bc98e247f1a22e92cddc92ead2c1891dcc")
}
