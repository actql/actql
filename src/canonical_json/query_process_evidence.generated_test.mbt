// Generated from independent process-evidence preimages; do not edit.

///|
test "process evidence preimage 0" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":23,\"received_fields\":[\"id\"],\"received_rows\":2,\"scope_cid\":\"sha256:6c91b8aaeb9589f617e662ca65b0980119df1ef8e3d9262167525c630060720a\"},\"attempt\":\"1\",\"issuer\":\"fixture-process\",\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"requirement_cid\":\"sha256:c864602898da6da1836fa4c8c21e1be258a17571cdf0ff1156b0ec4fec8b998e\",\"role\":\"source_validation\",\"scan_scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"snapshot\":null,\"version\":\"actql-query-process-evidence/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:3e16142044d8707bf0eb69de4c54211fafa35534e1119bf289936e48aecd9fca",
  )
}

///|
test "process evidence preimage 1" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":23,\"received_fields\":[\"id\"],\"received_rows\":2,\"scope_cid\":\"sha256:6c91b8aaeb9589f617e662ca65b0980119df1ef8e3d9262167525c630060720a\"},\"attempt\":\"1\",\"issuer\":\"fixture-process\",\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"requirement_cid\":\"sha256:c864602898da6da1836fa4c8c21e1be258a17571cdf0ff1156b0ec4fec8b998e\",\"role\":\"filter\",\"scan_scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"snapshot\":null,\"version\":\"actql-query-process-evidence/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:b82742a2c5a8141d61266551636717b03aaec440566f8932c5b6e4349af96df4",
  )
}

///|
test "process evidence preimage 2" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":23,\"received_fields\":[\"id\"],\"received_rows\":2,\"scope_cid\":\"sha256:6c91b8aaeb9589f617e662ca65b0980119df1ef8e3d9262167525c630060720a\"},\"attempt\":\"1\",\"issuer\":\"fixture-process\",\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"requirement_cid\":\"sha256:c864602898da6da1836fa4c8c21e1be258a17571cdf0ff1156b0ec4fec8b998e\",\"role\":\"select\",\"scan_scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"snapshot\":null,\"version\":\"actql-query-process-evidence/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:a09da4a5cf37ae377ebd06d4a8e8457947459d0dcd886c8254b0a9c79962afbd",
  )
}

///|
test "process evidence preimage 3" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":120,\"received_fields\":[\"amount\",\"id\",\"status\"],\"received_rows\":3,\"scope_cid\":\"sha256:50c2811c7fd858f1c43398c92c8f1c2f8853abfd38b5ce579e31c198634df8d1\"},\"attempt\":\"2\",\"issuer\":\"fixture-process\",\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"requirement_cid\":\"sha256:c864602898da6da1836fa4c8c21e1be258a17571cdf0ff1156b0ec4fec8b998e\",\"role\":\"source_validation\",\"scan_scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"snapshot\":null,\"version\":\"actql-query-process-evidence/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:fb647374ef5bc2cdf69594b5a9510c64dd70ef9c8a2ae9b9ad9fc768e9966e8b",
  )
}

///|
test "process evidence preimage 4" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":120,\"received_fields\":[\"amount\",\"id\",\"status\"],\"received_rows\":3,\"scope_cid\":\"sha256:50c2811c7fd858f1c43398c92c8f1c2f8853abfd38b5ce579e31c198634df8d1\"},\"attempt\":\"2\",\"issuer\":\"fixture-process\",\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"requirement_cid\":\"sha256:c864602898da6da1836fa4c8c21e1be258a17571cdf0ff1156b0ec4fec8b998e\",\"role\":\"filter\",\"scan_scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"snapshot\":null,\"version\":\"actql-query-process-evidence/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:0363c170246c66a6ec9d63337458bf1ae358e231063fa64ce1d6475037c9db92",
  )
}

///|
test "process evidence preimage 5" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":120,\"received_fields\":[\"amount\",\"id\",\"status\"],\"received_rows\":3,\"scope_cid\":\"sha256:50c2811c7fd858f1c43398c92c8f1c2f8853abfd38b5ce579e31c198634df8d1\"},\"attempt\":\"2\",\"issuer\":\"fixture-process\",\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"requirement_cid\":\"sha256:c864602898da6da1836fa4c8c21e1be258a17571cdf0ff1156b0ec4fec8b998e\",\"role\":\"select\",\"scan_scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"snapshot\":null,\"version\":\"actql-query-process-evidence/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:3f0a61d80e76f704503dccabc0c219fb16a2814a315e82cd2ab6741c15683bb8",
  )
}
