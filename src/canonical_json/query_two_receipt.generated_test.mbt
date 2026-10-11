// Generated from independent two-receipt preimages; do not edit.

///|
test "two receipt preimage 0" {
  let input = @json.parse("{\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"read_view\":\"view-1\",\"received_bytes\":43,\"received_fields\":[\"amount\",\"id\"],\"received_rows\":2,\"received_rows_cid\":\"sha256:f3d361fe4b7d5abb78027fd06b49ca9faca87ed483cd8979aa121096df4f8580\",\"requirement_cid\":\"sha256:b3c5b20cf67df37a6541b65ab700a00d58c5a64fbe72f335945170360a37f409\",\"role\":\"validation_scan\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-receipt/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:0c1d4d6fee84728b551804026b4f0f95cef0a2133b2f9ac86e56df50b780f72d")
}

///|
test "two receipt preimage 1" {
  let input = @json.parse("{\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"read_view\":\"view-1\",\"received_bytes\":10,\"received_fields\":[\"id\"],\"received_rows\":1,\"received_rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\",\"requirement_cid\":\"sha256:b3c5b20cf67df37a6541b65ab700a00d58c5a64fbe72f335945170360a37f409\",\"role\":\"native_result\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-receipt/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:48c7e17281e9d9105655748fa644f1eb88efb5f4ea8d865ee598b919527fdccc")
}

///|
test "two receipt preimage 2" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:48c7e17281e9d9105655748fa644f1eb88efb5f4ea8d865ee598b919527fdccc\",\"validation_scan_cid\":\"sha256:0c1d4d6fee84728b551804026b4f0f95cef0a2133b2f9ac86e56df50b780f72d\"},\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"read_view\":\"view-1\",\"requirement_cid\":\"sha256:b3c5b20cf67df37a6541b65ab700a00d58c5a64fbe72f335945170360a37f409\",\"role\":\"source_validation\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-two-receipt-evidence/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:fd539725a58effa7d6c6442588ea9feaf0852bc2ddc864b368670f08bc7ed39d")
}

///|
test "two receipt preimage 3" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:48c7e17281e9d9105655748fa644f1eb88efb5f4ea8d865ee598b919527fdccc\",\"validation_scan_cid\":\"sha256:0c1d4d6fee84728b551804026b4f0f95cef0a2133b2f9ac86e56df50b780f72d\"},\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"read_view\":\"view-1\",\"requirement_cid\":\"sha256:b3c5b20cf67df37a6541b65ab700a00d58c5a64fbe72f335945170360a37f409\",\"role\":\"filter\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-two-receipt-evidence/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:f54d9487874b094fab79f0ae439f1eb5d03957a0ecb413a1553e56fde676067b")
}

///|
test "two receipt preimage 4" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:48c7e17281e9d9105655748fa644f1eb88efb5f4ea8d865ee598b919527fdccc\",\"validation_scan_cid\":\"sha256:0c1d4d6fee84728b551804026b4f0f95cef0a2133b2f9ac86e56df50b780f72d\"},\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"read_view\":\"view-1\",\"requirement_cid\":\"sha256:b3c5b20cf67df37a6541b65ab700a00d58c5a64fbe72f335945170360a37f409\",\"role\":\"select\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-two-receipt-evidence/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:78dc84371aee24687ff5ca759da09038000aaf397dd0db29d2cbba9c7483882c")
}

///|
test "two receipt preimage 5" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:48c7e17281e9d9105655748fa644f1eb88efb5f4ea8d865ee598b919527fdccc\",\"validation_scan_cid\":\"sha256:0c1d4d6fee84728b551804026b4f0f95cef0a2133b2f9ac86e56df50b780f72d\"},\"coverage\":{\"complete\":true,\"filter_evidence_cid\":\"sha256:f54d9487874b094fab79f0ae439f1eb5d03957a0ecb413a1553e56fde676067b\",\"scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"select_evidence_cid\":\"sha256:78dc84371aee24687ff5ca759da09038000aaf397dd0db29d2cbba9c7483882c\",\"source_validation_evidence_cid\":\"sha256:fd539725a58effa7d6c6442588ea9feaf0852bc2ddc864b368670f08bc7ed39d\"},\"evidence_contract_cid\":\"sha256:7d9eec132b742aca27b78a801c6bea187a251b7423967950e285755c50e853d8\",\"execution\":{\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"read_view\":\"view-1\"},\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"owner\":{\"input\":\"records\",\"program_source_cid\":\"sha256:6e625cc897a8cac95f584c5c7d2a620d966251f6741070fcddc50cc8449042cd\",\"stage\":\"first\"},\"parameter_values_cid\":\"sha256:ce3468bea3995136201f0f1242c8d388f927d5c1b751f60a6cccf6b539ef4897\",\"requirement_cid\":\"sha256:b3c5b20cf67df37a6541b65ab700a00d58c5a64fbe72f335945170360a37f409\",\"resolved_request_cid\":\"sha256:9e475b942ea0d73d63e2e4cdeffb72d0d145e5bbd3cdf4605d2acbca829cdde1\",\"retention\":\"process\",\"snapshot\":null,\"source_contract_cid\":\"sha256:7bcef77b0a1627fbd4687b96f276f348e3aa564575e3fb16dd2991c664a535d1\",\"source_ref\":\"connector://fixture/local-read#scan\",\"version\":\"actql-query-two-receipt-observation/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:bcee33fee3922b326d2a3f5fcf770c3f6d5b45e8258fbfdfa7201e1923ff5ee3")
}
