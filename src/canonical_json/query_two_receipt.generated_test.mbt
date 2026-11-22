// Generated from independent two-receipt preimages; do not edit.

///|
test "two receipt preimage 0" {
  let input = @json.parse("{\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"read_view\":\"view-1\",\"received_bytes\":43,\"received_fields\":[\"amount\",\"id\"],\"received_rows\":2,\"received_rows_cid\":\"sha256:f3d361fe4b7d5abb78027fd06b49ca9faca87ed483cd8979aa121096df4f8580\",\"requirement_cid\":\"sha256:131d475f60c13fe4615bdfae1050c3b266e9a1049d9b57df6d338cafce6bb9ac\",\"role\":\"validation_scan\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-receipt/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:375c7e9ea9d25aac585eb62aa9255af71d3099267284452cff6f1ce9c4db4895")
}

///|
test "two receipt preimage 1" {
  let input = @json.parse("{\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"read_view\":\"view-1\",\"received_bytes\":10,\"received_fields\":[\"id\"],\"received_rows\":1,\"received_rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\",\"requirement_cid\":\"sha256:131d475f60c13fe4615bdfae1050c3b266e9a1049d9b57df6d338cafce6bb9ac\",\"role\":\"native_result\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-receipt/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:eeed97d2f9c30b85497a996bef382d709450e50f13e713e55521b29345d4e9f4")
}

///|
test "two receipt preimage 2" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:eeed97d2f9c30b85497a996bef382d709450e50f13e713e55521b29345d4e9f4\",\"validation_scan_cid\":\"sha256:375c7e9ea9d25aac585eb62aa9255af71d3099267284452cff6f1ce9c4db4895\"},\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"read_view\":\"view-1\",\"requirement_cid\":\"sha256:131d475f60c13fe4615bdfae1050c3b266e9a1049d9b57df6d338cafce6bb9ac\",\"role\":\"source_validation\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-two-receipt-evidence/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:4c5d07f4c48cf66bf7e103ebcf9d14559a38b617c81f3c16756d15517533c6d9")
}

///|
test "two receipt preimage 3" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:eeed97d2f9c30b85497a996bef382d709450e50f13e713e55521b29345d4e9f4\",\"validation_scan_cid\":\"sha256:375c7e9ea9d25aac585eb62aa9255af71d3099267284452cff6f1ce9c4db4895\"},\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"read_view\":\"view-1\",\"requirement_cid\":\"sha256:131d475f60c13fe4615bdfae1050c3b266e9a1049d9b57df6d338cafce6bb9ac\",\"role\":\"filter\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-two-receipt-evidence/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:9b6ab85d3b5d806afc2310bd8980451435bc65dac3d0ef87a3b0a0b07080beb9")
}

///|
test "two receipt preimage 4" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:eeed97d2f9c30b85497a996bef382d709450e50f13e713e55521b29345d4e9f4\",\"validation_scan_cid\":\"sha256:375c7e9ea9d25aac585eb62aa9255af71d3099267284452cff6f1ce9c4db4895\"},\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"read_view\":\"view-1\",\"requirement_cid\":\"sha256:131d475f60c13fe4615bdfae1050c3b266e9a1049d9b57df6d338cafce6bb9ac\",\"role\":\"select\",\"scan_scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"snapshot\":null,\"version\":\"actql-query-two-receipt-evidence/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:720dd09911b0d42702ab73cdeec689614f982fb39c86fae28d72f501f8ec6f4a")
}

///|
test "two receipt preimage 5" {
  let input = @json.parse("{\"accesses\":{\"native_result_cid\":\"sha256:eeed97d2f9c30b85497a996bef382d709450e50f13e713e55521b29345d4e9f4\",\"validation_scan_cid\":\"sha256:375c7e9ea9d25aac585eb62aa9255af71d3099267284452cff6f1ce9c4db4895\"},\"coverage\":{\"complete\":true,\"filter_evidence_cid\":\"sha256:9b6ab85d3b5d806afc2310bd8980451435bc65dac3d0ef87a3b0a0b07080beb9\",\"scope_cid\":\"sha256:3befbdbe52d3d74d31f986dfce133ed29b71e3691ea871d5b47171e57c2b4b1b\",\"select_evidence_cid\":\"sha256:720dd09911b0d42702ab73cdeec689614f982fb39c86fae28d72f501f8ec6f4a\",\"source_validation_evidence_cid\":\"sha256:4c5d07f4c48cf66bf7e103ebcf9d14559a38b617c81f3c16756d15517533c6d9\"},\"evidence_contract_cid\":\"sha256:359725157c8d5d9b883eaf58bdf1772c6864b5c6a1845470d6e183bc8aaf2807\",\"execution\":{\"attempt\":\"1\",\"issuer\":\"fixture-two-receipt\",\"read_view\":\"view-1\"},\"output\":{\"contract_cid\":\"sha256:1397f3486d94d87d6affa84e5258a36a23def0f068df837fa8aa746839d2c513\",\"row_count\":1,\"rows_cid\":\"sha256:280631f7b642776726d9874a54438209a4416c7fcfcb399bdfbb210e73560d64\"},\"owner\":{\"input\":\"records\",\"program_source_cid\":\"sha256:c85f8ab606d240bb88b836501fd0e18956ee4b7e6ba07b0a7a011381189d4213\",\"stage\":\"first\"},\"parameter_values_cid\":\"sha256:ce3468bea3995136201f0f1242c8d388f927d5c1b751f60a6cccf6b539ef4897\",\"requirement_cid\":\"sha256:131d475f60c13fe4615bdfae1050c3b266e9a1049d9b57df6d338cafce6bb9ac\",\"resolved_request_cid\":\"sha256:9e475b942ea0d73d63e2e4cdeffb72d0d145e5bbd3cdf4605d2acbca829cdde1\",\"retention\":\"process\",\"snapshot\":null,\"source_contract_cid\":\"sha256:7bcef77b0a1627fbd4687b96f276f348e3aa564575e3fb16dd2991c664a535d1\",\"source_ref\":\"connector://fixture/local-read#scan\",\"version\":\"actql-query-two-receipt-observation/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:41a447f05584013534fdfc1b53dd9373661d4427b4a96f632ee15a2d3f89b5dd")
}
