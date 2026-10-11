// Generated from independent two-receipt preimages; do not edit.

///|
test "two receipt preimage 0" {
  let input = @json.parse("{\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"read_view\":\"view-1\",\"received_bytes\":43,\"received_fields\":[\"amount\",\"id\"],\"received_rows\":2,\"received_rows_cid\":\"sha256:f3d361fe4b7d5abb78027fd06b49ca9faca87ed483cd8979aa121096df4f8580\",\"requirement_cid\":\"sha256:2a0814aef26b5c56d4581bdf1b3e88b53cc2fafef37e4476c41612a9f3829df9\",\"role\":\"validation_scan\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-receipt/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:9b662f03c2b4aedc9bfcb9bff03ce037028c8d74951f7da59dc0d6f7f3248896")
}

///|
test "two receipt preimage 1" {
  let input = @json.parse("{\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"read_view\":\"view-1\",\"received_bytes\":10,\"received_fields\":[\"id\"],\"received_rows\":1,\"received_rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\",\"requirement_cid\":\"sha256:2a0814aef26b5c56d4581bdf1b3e88b53cc2fafef37e4476c41612a9f3829df9\",\"role\":\"native_result\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-receipt/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:2389dc78a44483783b513c3d3a7a059bbb5261ad06c5bf99a2bf5ff526d75a5b")
}

///|
test "two receipt preimage 2" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:2389dc78a44483783b513c3d3a7a059bbb5261ad06c5bf99a2bf5ff526d75a5b\",\"validation_scan_cid\":\"sha256:9b662f03c2b4aedc9bfcb9bff03ce037028c8d74951f7da59dc0d6f7f3248896\"},\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"read_view\":\"view-1\",\"requirement_cid\":\"sha256:2a0814aef26b5c56d4581bdf1b3e88b53cc2fafef37e4476c41612a9f3829df9\",\"role\":\"source_validation\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-two-receipt-evidence/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:46cc7b0de282acf744e1a03a97041524e59349029aa1db796d02b90eb2a12d62")
}

///|
test "two receipt preimage 3" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:2389dc78a44483783b513c3d3a7a059bbb5261ad06c5bf99a2bf5ff526d75a5b\",\"validation_scan_cid\":\"sha256:9b662f03c2b4aedc9bfcb9bff03ce037028c8d74951f7da59dc0d6f7f3248896\"},\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"read_view\":\"view-1\",\"requirement_cid\":\"sha256:2a0814aef26b5c56d4581bdf1b3e88b53cc2fafef37e4476c41612a9f3829df9\",\"role\":\"filter\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-two-receipt-evidence/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:da0f962f2ef918530f68854fbd29dcfbef7fffba9f54e66477022a407cde56ab")
}

///|
test "two receipt preimage 4" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:2389dc78a44483783b513c3d3a7a059bbb5261ad06c5bf99a2bf5ff526d75a5b\",\"validation_scan_cid\":\"sha256:9b662f03c2b4aedc9bfcb9bff03ce037028c8d74951f7da59dc0d6f7f3248896\"},\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"read_view\":\"view-1\",\"requirement_cid\":\"sha256:2a0814aef26b5c56d4581bdf1b3e88b53cc2fafef37e4476c41612a9f3829df9\",\"role\":\"select\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-two-receipt-evidence/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:089890dba2874d7b093bd6feccc787c1813756dd88f90a0c2d23051f79101251")
}

///|
test "two receipt preimage 5" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:2389dc78a44483783b513c3d3a7a059bbb5261ad06c5bf99a2bf5ff526d75a5b\",\"validation_scan_cid\":\"sha256:9b662f03c2b4aedc9bfcb9bff03ce037028c8d74951f7da59dc0d6f7f3248896\"},\"coverage\":{\"complete\":true,\"filter_evidence_cid\":\"sha256:da0f962f2ef918530f68854fbd29dcfbef7fffba9f54e66477022a407cde56ab\",\"scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"select_evidence_cid\":\"sha256:089890dba2874d7b093bd6feccc787c1813756dd88f90a0c2d23051f79101251\",\"source_validation_evidence_cid\":\"sha256:46cc7b0de282acf744e1a03a97041524e59349029aa1db796d02b90eb2a12d62\"},\"evidence_contract_cid\":\"sha256:7d9eec132b742aca27b78a801c6bea187a251b7423967950e285755c50e853d8\",\"execution\":{\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"read_view\":\"view-1\"},\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"owner\":{\"input\":\"records\",\"program_source_cid\":\"sha256:66a703f9967c17cbb545d9a833cbf3e8d5b5077380a50b1a8c20600dc0849a30\",\"stage\":\"first\"},\"parameter_values_cid\":\"sha256:ce3468bea3995136201f0f1242c8d388f927d5c1b751f60a6cccf6b539ef4897\",\"requirement_cid\":\"sha256:2a0814aef26b5c56d4581bdf1b3e88b53cc2fafef37e4476c41612a9f3829df9\",\"resolved_request_cid\":\"sha256:9e475b942ea0d73d63e2e4cdeffb72d0d145e5bbd3cdf4605d2acbca829cdde1\",\"retention\":\"process\",\"snapshot\":null,\"source_contract_cid\":\"sha256:7bcef77b0a1627fbd4687b96f276f348e3aa564575e3fb16dd2991c664a535d1\",\"source_ref\":\"connector://fixture/local-read#scan\",\"version\":\"actql-query-two-receipt-observation/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:f85ce5d881b8692de8f79c734e44f9cec471961b334facc0fe6ceeb149e2e2c7")
}
