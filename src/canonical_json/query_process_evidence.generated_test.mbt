// Generated from independent process-evidence preimages; do not edit.

///|
test "process evidence preimage 0" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":23,\"received_fields\":[\"id\"],\"received_rows\":2,\"scope_cid\":\"sha256:a2e7fa3557321dd59ba46bb095aad9ad4cb26c7d462d86900430a63d1dc6202c\"},\"attempt\":\"1\",\"issuer\":\"fixture-process\",\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"requirement_cid\":\"sha256:5c64b1e646e06ea11c3f71139b2d1651922592f605ccbded52f5e8369ee74a40\",\"role\":\"source_validation\",\"scan_scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"snapshot\":null,\"version\":\"actql-query-process-evidence/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:e9e818643376e7ba5c7624947d8c0ae7a6efb923ae65484a6971deea0c84d0a8",
  )
}

///|
test "process evidence preimage 1" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":23,\"received_fields\":[\"id\"],\"received_rows\":2,\"scope_cid\":\"sha256:a2e7fa3557321dd59ba46bb095aad9ad4cb26c7d462d86900430a63d1dc6202c\"},\"attempt\":\"1\",\"issuer\":\"fixture-process\",\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"requirement_cid\":\"sha256:5c64b1e646e06ea11c3f71139b2d1651922592f605ccbded52f5e8369ee74a40\",\"role\":\"filter\",\"scan_scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"snapshot\":null,\"version\":\"actql-query-process-evidence/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:35883ce84369c66e2e16afba6ac6cbcf4c28985a8f030dbc3e81c24094f520de",
  )
}

///|
test "process evidence preimage 2" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":23,\"received_fields\":[\"id\"],\"received_rows\":2,\"scope_cid\":\"sha256:a2e7fa3557321dd59ba46bb095aad9ad4cb26c7d462d86900430a63d1dc6202c\"},\"attempt\":\"1\",\"issuer\":\"fixture-process\",\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"requirement_cid\":\"sha256:5c64b1e646e06ea11c3f71139b2d1651922592f605ccbded52f5e8369ee74a40\",\"role\":\"select\",\"scan_scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"snapshot\":null,\"version\":\"actql-query-process-evidence/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:878d180656a52ebac7ed1d662ba7c3f28fed8028785f010539a5cbec6ac9cce7",
  )
}

///|
test "process evidence preimage 3" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":120,\"received_fields\":[\"amount\",\"id\",\"status\"],\"received_rows\":3,\"scope_cid\":\"sha256:4cf5358ccea68087440858aa7ec7e2b65a53419ad98e96ae774c36918a4f503b\"},\"attempt\":\"2\",\"issuer\":\"fixture-process\",\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"requirement_cid\":\"sha256:5c64b1e646e06ea11c3f71139b2d1651922592f605ccbded52f5e8369ee74a40\",\"role\":\"source_validation\",\"scan_scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"snapshot\":null,\"version\":\"actql-query-process-evidence/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:53a575cfc0c9b27a2afdbd0ee72b679c2169c9789ac7d29e0cf70db2b89baf84",
  )
}

///|
test "process evidence preimage 4" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":120,\"received_fields\":[\"amount\",\"id\",\"status\"],\"received_rows\":3,\"scope_cid\":\"sha256:4cf5358ccea68087440858aa7ec7e2b65a53419ad98e96ae774c36918a4f503b\"},\"attempt\":\"2\",\"issuer\":\"fixture-process\",\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"requirement_cid\":\"sha256:5c64b1e646e06ea11c3f71139b2d1651922592f605ccbded52f5e8369ee74a40\",\"role\":\"filter\",\"scan_scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"snapshot\":null,\"version\":\"actql-query-process-evidence/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:c88419f4358c15de6631cb74da71c0df5885bb2ce97d5cec0a3832773714a10d",
  )
}

///|
test "process evidence preimage 5" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":120,\"received_fields\":[\"amount\",\"id\",\"status\"],\"received_rows\":3,\"scope_cid\":\"sha256:4cf5358ccea68087440858aa7ec7e2b65a53419ad98e96ae774c36918a4f503b\"},\"attempt\":\"2\",\"issuer\":\"fixture-process\",\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"requirement_cid\":\"sha256:5c64b1e646e06ea11c3f71139b2d1651922592f605ccbded52f5e8369ee74a40\",\"role\":\"select\",\"scan_scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"snapshot\":null,\"version\":\"actql-query-process-evidence/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:ed91924a621a01ce3783a01c60fad113d475dca300353102c5b7e941834f6d6f",
  )
}
