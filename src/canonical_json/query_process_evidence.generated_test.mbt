// Generated from independent process-evidence preimages; do not edit.

///|
test "process evidence preimage 0" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":23,\"received_fields\":[\"id\"],\"received_rows\":2,\"scope_cid\":\"sha256:a0444b106a6e402c65f2c8d337b107d5356824b164b218dfb713c84b67efb21d\"},\"attempt\":\"1\",\"issuer\":\"fixture-process\",\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"requirement_cid\":\"sha256:2721dd2b75b22dba5d59b1f81f9594d8d2493308e7ba890bdd49e7e4b980b835\",\"role\":\"source_validation\",\"scan_scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"snapshot\":null,\"version\":\"actql-query-process-evidence/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:0ac6f30b70c81f5da98168698421429dda1d7c51bcba7a057f0a02257d969329",
  )
}

///|
test "process evidence preimage 1" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":23,\"received_fields\":[\"id\"],\"received_rows\":2,\"scope_cid\":\"sha256:a0444b106a6e402c65f2c8d337b107d5356824b164b218dfb713c84b67efb21d\"},\"attempt\":\"1\",\"issuer\":\"fixture-process\",\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"requirement_cid\":\"sha256:2721dd2b75b22dba5d59b1f81f9594d8d2493308e7ba890bdd49e7e4b980b835\",\"role\":\"filter\",\"scan_scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"snapshot\":null,\"version\":\"actql-query-process-evidence/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:18a73f47882072bd1cb700a53d47c76795941b3416a47dc99c0788b8125b2750",
  )
}

///|
test "process evidence preimage 2" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":23,\"received_fields\":[\"id\"],\"received_rows\":2,\"scope_cid\":\"sha256:a0444b106a6e402c65f2c8d337b107d5356824b164b218dfb713c84b67efb21d\"},\"attempt\":\"1\",\"issuer\":\"fixture-process\",\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"requirement_cid\":\"sha256:2721dd2b75b22dba5d59b1f81f9594d8d2493308e7ba890bdd49e7e4b980b835\",\"role\":\"select\",\"scan_scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"snapshot\":null,\"version\":\"actql-query-process-evidence/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:c3dfea4ea0d592715f04d50d106f8de7fc70d6b7e4672b7f8ef9959aee4ad7fe",
  )
}

///|
test "process evidence preimage 3" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":120,\"received_fields\":[\"amount\",\"id\",\"status\"],\"received_rows\":3,\"scope_cid\":\"sha256:c405adf54d82c6781da6c60986f6ddda8b387965838feb07a3cbf5f59ba9ada6\"},\"attempt\":\"2\",\"issuer\":\"fixture-process\",\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"requirement_cid\":\"sha256:2721dd2b75b22dba5d59b1f81f9594d8d2493308e7ba890bdd49e7e4b980b835\",\"role\":\"source_validation\",\"scan_scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"snapshot\":null,\"version\":\"actql-query-process-evidence/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:721863b9df04589f55af9fdda6d7c6e9d0bb8201c36d0da2db760e729a81986d",
  )
}

///|
test "process evidence preimage 4" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":120,\"received_fields\":[\"amount\",\"id\",\"status\"],\"received_rows\":3,\"scope_cid\":\"sha256:c405adf54d82c6781da6c60986f6ddda8b387965838feb07a3cbf5f59ba9ada6\"},\"attempt\":\"2\",\"issuer\":\"fixture-process\",\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"requirement_cid\":\"sha256:2721dd2b75b22dba5d59b1f81f9594d8d2493308e7ba890bdd49e7e4b980b835\",\"role\":\"filter\",\"scan_scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"snapshot\":null,\"version\":\"actql-query-process-evidence/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:0d80f0ca2b281a630554eab6cb8d13a8b9012bb59d1690e542395e5db51d95b0",
  )
}

///|
test "process evidence preimage 5" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":120,\"received_fields\":[\"amount\",\"id\",\"status\"],\"received_rows\":3,\"scope_cid\":\"sha256:c405adf54d82c6781da6c60986f6ddda8b387965838feb07a3cbf5f59ba9ada6\"},\"attempt\":\"2\",\"issuer\":\"fixture-process\",\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"requirement_cid\":\"sha256:2721dd2b75b22dba5d59b1f81f9594d8d2493308e7ba890bdd49e7e4b980b835\",\"role\":\"select\",\"scan_scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"snapshot\":null,\"version\":\"actql-query-process-evidence/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:541fc183ae91a020a9e6d6f222cde24c46ad309755203023e28aa20b92bd4134",
  )
}
