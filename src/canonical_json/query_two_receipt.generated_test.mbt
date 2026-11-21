// Generated from independent two-receipt preimages; do not edit.

///|
test "two receipt preimage 0" {
  let input = @json.parse("{\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"read_view\":\"view-1\",\"received_bytes\":43,\"received_fields\":[\"amount\",\"id\"],\"received_rows\":2,\"received_rows_cid\":\"sha256:f3d361fe4b7d5abb78027fd06b49ca9faca87ed483cd8979aa121096df4f8580\",\"requirement_cid\":\"sha256:8f2173615ddfe6d43d974e340398d189d0621e5f46e903890ce6c1716be652c5\",\"role\":\"validation_scan\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-receipt/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:cbb1298de957ce5a9b19cdd31f4eefd7b5b0c2c6bd0597398348822d981328b4")
}

///|
test "two receipt preimage 1" {
  let input = @json.parse("{\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"read_view\":\"view-1\",\"received_bytes\":10,\"received_fields\":[\"id\"],\"received_rows\":1,\"received_rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\",\"requirement_cid\":\"sha256:8f2173615ddfe6d43d974e340398d189d0621e5f46e903890ce6c1716be652c5\",\"role\":\"native_result\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-receipt/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:e901b1b43bb73ca47b9cfcd0e17843a1fc2abfd410294cf6d48d43fc9b0555e5")
}

///|
test "two receipt preimage 2" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:e901b1b43bb73ca47b9cfcd0e17843a1fc2abfd410294cf6d48d43fc9b0555e5\",\"validation_scan_cid\":\"sha256:cbb1298de957ce5a9b19cdd31f4eefd7b5b0c2c6bd0597398348822d981328b4\"},\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"read_view\":\"view-1\",\"requirement_cid\":\"sha256:8f2173615ddfe6d43d974e340398d189d0621e5f46e903890ce6c1716be652c5\",\"role\":\"source_validation\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-two-receipt-evidence/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:ec8f844a864fe426771d2e9d3f083fc71acae671966ee3916e0aae67f720e79a")
}

///|
test "two receipt preimage 3" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:e901b1b43bb73ca47b9cfcd0e17843a1fc2abfd410294cf6d48d43fc9b0555e5\",\"validation_scan_cid\":\"sha256:cbb1298de957ce5a9b19cdd31f4eefd7b5b0c2c6bd0597398348822d981328b4\"},\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"read_view\":\"view-1\",\"requirement_cid\":\"sha256:8f2173615ddfe6d43d974e340398d189d0621e5f46e903890ce6c1716be652c5\",\"role\":\"filter\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-two-receipt-evidence/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:c323e9641605c6e42e4ebe38e4384f1c7604aa50b9ec22915b915aa085ecf31b")
}

///|
test "two receipt preimage 4" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:e901b1b43bb73ca47b9cfcd0e17843a1fc2abfd410294cf6d48d43fc9b0555e5\",\"validation_scan_cid\":\"sha256:cbb1298de957ce5a9b19cdd31f4eefd7b5b0c2c6bd0597398348822d981328b4\"},\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"read_view\":\"view-1\",\"requirement_cid\":\"sha256:8f2173615ddfe6d43d974e340398d189d0621e5f46e903890ce6c1716be652c5\",\"role\":\"select\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-two-receipt-evidence/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:559bae6ac70f54372b936824b5a691ddafd683ad5a5d2faff9a5dc7dd2735cec")
}

///|
test "two receipt preimage 5" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:e901b1b43bb73ca47b9cfcd0e17843a1fc2abfd410294cf6d48d43fc9b0555e5\",\"validation_scan_cid\":\"sha256:cbb1298de957ce5a9b19cdd31f4eefd7b5b0c2c6bd0597398348822d981328b4\"},\"coverage\":{\"complete\":true,\"filter_evidence_cid\":\"sha256:c323e9641605c6e42e4ebe38e4384f1c7604aa50b9ec22915b915aa085ecf31b\",\"scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"select_evidence_cid\":\"sha256:559bae6ac70f54372b936824b5a691ddafd683ad5a5d2faff9a5dc7dd2735cec\",\"source_validation_evidence_cid\":\"sha256:ec8f844a864fe426771d2e9d3f083fc71acae671966ee3916e0aae67f720e79a\"},\"evidence_contract_cid\":\"sha256:dcf4b1e2c8a078d96f9160a75a9f8279047e7448ea39b3b882588e18b9ab0929\",\"execution\":{\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"read_view\":\"view-1\"},\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"owner\":{\"input\":\"records\",\"program_source_cid\":\"sha256:19b740b62184a82f44e3b22b7b3dca2f91e79d53e7da17ad9a7f4d6abc2f7061\",\"stage\":\"first\"},\"parameter_values_cid\":\"sha256:ce3468bea3995136201f0f1242c8d388f927d5c1b751f60a6cccf6b539ef4897\",\"requirement_cid\":\"sha256:8f2173615ddfe6d43d974e340398d189d0621e5f46e903890ce6c1716be652c5\",\"resolved_request_cid\":\"sha256:9e475b942ea0d73d63e2e4cdeffb72d0d145e5bbd3cdf4605d2acbca829cdde1\",\"retention\":\"process\",\"snapshot\":null,\"source_contract_cid\":\"sha256:7bcef77b0a1627fbd4687b96f276f348e3aa564575e3fb16dd2991c664a535d1\",\"source_ref\":\"connector://fixture/local-read#scan\",\"version\":\"actql-query-two-receipt-observation/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:8c4d4789cc535b499b5cc48a4c83d9a725319d5d823d18e5c692ff55dea903ed")
}
