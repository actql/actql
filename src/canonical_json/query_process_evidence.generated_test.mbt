// Generated from independent process-evidence preimages; do not edit.

///|
test "process evidence preimage 0" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":23,\"received_fields\":[\"id\"],\"received_rows\":2,\"scope_cid\":\"sha256:d9bb66dac4816aa4fd88454d2018ec2df50c8213d851204e56f7af02b2895a6b\"},\"attempt\":\"1\",\"issuer\":\"fixture-process\",\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"requirement_cid\":\"sha256:102d99098d4146d607436ce7e071c8a1997192c0ee437807103087da11b002b2\",\"role\":\"source_validation\",\"scan_scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"snapshot\":null,\"version\":\"actql-query-process-evidence/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:b774cda5a0fedac74edad7ce402d66c277040f7d5b5f90b31e572a5faf888975",
  )
}

///|
test "process evidence preimage 1" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":23,\"received_fields\":[\"id\"],\"received_rows\":2,\"scope_cid\":\"sha256:d9bb66dac4816aa4fd88454d2018ec2df50c8213d851204e56f7af02b2895a6b\"},\"attempt\":\"1\",\"issuer\":\"fixture-process\",\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"requirement_cid\":\"sha256:102d99098d4146d607436ce7e071c8a1997192c0ee437807103087da11b002b2\",\"role\":\"filter\",\"scan_scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"snapshot\":null,\"version\":\"actql-query-process-evidence/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:1a31d57485e8c9b6195b7552fc13c505dc777664c2e7633eb61c60ea08276ac1",
  )
}

///|
test "process evidence preimage 2" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":23,\"received_fields\":[\"id\"],\"received_rows\":2,\"scope_cid\":\"sha256:d9bb66dac4816aa4fd88454d2018ec2df50c8213d851204e56f7af02b2895a6b\"},\"attempt\":\"1\",\"issuer\":\"fixture-process\",\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"requirement_cid\":\"sha256:102d99098d4146d607436ce7e071c8a1997192c0ee437807103087da11b002b2\",\"role\":\"select\",\"scan_scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"snapshot\":null,\"version\":\"actql-query-process-evidence/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:b505044a1c7e2623d43756e5775e6121ba4c9166ec1581c1b25c0d19b48c11b6",
  )
}

///|
test "process evidence preimage 3" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":120,\"received_fields\":[\"amount\",\"id\",\"status\"],\"received_rows\":3,\"scope_cid\":\"sha256:273be1ed56492328b3c4c1e9657e40a8639f9b834dbd6c1b539fc84370b9fac6\"},\"attempt\":\"2\",\"issuer\":\"fixture-process\",\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"requirement_cid\":\"sha256:102d99098d4146d607436ce7e071c8a1997192c0ee437807103087da11b002b2\",\"role\":\"source_validation\",\"scan_scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"snapshot\":null,\"version\":\"actql-query-process-evidence/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:51d18eec930a195b565562447354de98928d8b82c826988927c3e9046384928d",
  )
}

///|
test "process evidence preimage 4" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":120,\"received_fields\":[\"amount\",\"id\",\"status\"],\"received_rows\":3,\"scope_cid\":\"sha256:273be1ed56492328b3c4c1e9657e40a8639f9b834dbd6c1b539fc84370b9fac6\"},\"attempt\":\"2\",\"issuer\":\"fixture-process\",\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"requirement_cid\":\"sha256:102d99098d4146d607436ce7e071c8a1997192c0ee437807103087da11b002b2\",\"role\":\"filter\",\"scan_scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"snapshot\":null,\"version\":\"actql-query-process-evidence/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:650368b05011e8347148fab46232e1ffd4adb8e3163de064e32198fcceaab3d2",
  )
}

///|
test "process evidence preimage 5" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":120,\"received_fields\":[\"amount\",\"id\",\"status\"],\"received_rows\":3,\"scope_cid\":\"sha256:273be1ed56492328b3c4c1e9657e40a8639f9b834dbd6c1b539fc84370b9fac6\"},\"attempt\":\"2\",\"issuer\":\"fixture-process\",\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"requirement_cid\":\"sha256:102d99098d4146d607436ce7e071c8a1997192c0ee437807103087da11b002b2\",\"role\":\"select\",\"scan_scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"snapshot\":null,\"version\":\"actql-query-process-evidence/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:37b05d28d73314902e4075c3fac12aa85a2a6dd53f584b9749840fee758b73cf",
  )
}
