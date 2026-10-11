// Generated from independent process-evidence preimages; do not edit.

///|
test "process evidence preimage 0" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":23,\"received_fields\":[\"id\"],\"received_rows\":2,\"scope_cid\":\"sha256:bc568a3a684ff5a76b09eebb38d86b779f100bea98f31dba8b69defc9b63fc67\"},\"attempt\":\"1\",\"issuer\":\"fixture-process\",\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"requirement_cid\":\"sha256:0a4714cf592fcab24f7cfea5f1d2385468cac4c43f045d267a22b984f32b4d18\",\"role\":\"source_validation\",\"scan_scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"snapshot\":null,\"version\":\"actql-query-process-evidence/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:93a69b96543e3cb646c4d7ef85b2050cd21b8aed6095c922f672db0055eab0ca",
  )
}

///|
test "process evidence preimage 1" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":23,\"received_fields\":[\"id\"],\"received_rows\":2,\"scope_cid\":\"sha256:bc568a3a684ff5a76b09eebb38d86b779f100bea98f31dba8b69defc9b63fc67\"},\"attempt\":\"1\",\"issuer\":\"fixture-process\",\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"requirement_cid\":\"sha256:0a4714cf592fcab24f7cfea5f1d2385468cac4c43f045d267a22b984f32b4d18\",\"role\":\"filter\",\"scan_scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"snapshot\":null,\"version\":\"actql-query-process-evidence/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:35b959c96acc80009fb2b6cc59bb14624ef1532a5bc80e25bf5daf0a9e447cac",
  )
}

///|
test "process evidence preimage 2" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":23,\"received_fields\":[\"id\"],\"received_rows\":2,\"scope_cid\":\"sha256:bc568a3a684ff5a76b09eebb38d86b779f100bea98f31dba8b69defc9b63fc67\"},\"attempt\":\"1\",\"issuer\":\"fixture-process\",\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"requirement_cid\":\"sha256:0a4714cf592fcab24f7cfea5f1d2385468cac4c43f045d267a22b984f32b4d18\",\"role\":\"select\",\"scan_scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"snapshot\":null,\"version\":\"actql-query-process-evidence/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:5959cfe8cec360b85ac4eb7db176947ee4f21b8567d6468e4becf739be7aff4f",
  )
}

///|
test "process evidence preimage 3" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":120,\"received_fields\":[\"amount\",\"id\",\"status\"],\"received_rows\":3,\"scope_cid\":\"sha256:89ec926c683c43f78c2690849f5ce425d59e4ec41452c4468819ada643ead004\"},\"attempt\":\"2\",\"issuer\":\"fixture-process\",\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"requirement_cid\":\"sha256:0a4714cf592fcab24f7cfea5f1d2385468cac4c43f045d267a22b984f32b4d18\",\"role\":\"source_validation\",\"scan_scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"snapshot\":null,\"version\":\"actql-query-process-evidence/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:c7b1f31d121bc926e6995a0a8d05ebd30c1f085db0685936262c75b22572b1e7",
  )
}

///|
test "process evidence preimage 4" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":120,\"received_fields\":[\"amount\",\"id\",\"status\"],\"received_rows\":3,\"scope_cid\":\"sha256:89ec926c683c43f78c2690849f5ce425d59e4ec41452c4468819ada643ead004\"},\"attempt\":\"2\",\"issuer\":\"fixture-process\",\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"requirement_cid\":\"sha256:0a4714cf592fcab24f7cfea5f1d2385468cac4c43f045d267a22b984f32b4d18\",\"role\":\"filter\",\"scan_scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"snapshot\":null,\"version\":\"actql-query-process-evidence/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:d9e0df0cb02456e3a93df5566ac844200fbd3edbe075bc646837535a0d4e1348",
  )
}

///|
test "process evidence preimage 5" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":120,\"received_fields\":[\"amount\",\"id\",\"status\"],\"received_rows\":3,\"scope_cid\":\"sha256:89ec926c683c43f78c2690849f5ce425d59e4ec41452c4468819ada643ead004\"},\"attempt\":\"2\",\"issuer\":\"fixture-process\",\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"requirement_cid\":\"sha256:0a4714cf592fcab24f7cfea5f1d2385468cac4c43f045d267a22b984f32b4d18\",\"role\":\"select\",\"scan_scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"snapshot\":null,\"version\":\"actql-query-process-evidence/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:cae33f8990de3baac1591223512a56616be5d243b16becb957887063509d0533",
  )
}
