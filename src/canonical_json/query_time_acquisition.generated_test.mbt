// Generated from independent same-Run query-time preimages; do not edit.

///|
test "query-time acquisition preimage 0" {
  let input = @json.parse(
    "{\"filter\":{\"expression_cid\":\"sha256:11ee6436f22f4aac9ed90700d83925684aa80cdbdb30c186cd79ad45b31274b7\",\"occurrence\":\"/steps/0/filter\"},\"input_contract_cid\":\"sha256:7263e8377ceede3197740c6bee4949aaa96bc4852499dedd7b4b2c28a685d7b5\",\"logical_guards\":{\"max_rows\":2,\"max_value_bytes\":1000},\"output_contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"owner\":{\"input\":\"records\",\"program_source_cid\":\"sha256:444615f698dcc6ea53fa296c2edb70bbba62cd67befae8c1ed2be3daf3f3737f\",\"run_definition_cid\":\"sha256:8b1c4c522665303127f0f1f00c2c3fc6540e12edbfde6c1c09f8bd4e07fe75e5\",\"stage\":\"first\"},\"parameter_values_cid\":\"sha256:ce3468bea3995136201f0f1242c8d388f927d5c1b751f60a6cccf6b539ef4897\",\"request\":{\"tenant\":\"fixture\"},\"select\":{\"fields\":[{\"input\":\"id\",\"output\":\"id\"}],\"occurrence\":\"/steps/1/select\"},\"source_contract_cid\":\"sha256:b6dadf2beda041fc3f9cccc66cec826b777dd2adc13732f261e362c2aea341d2\",\"source_order_cid\":\"sha256:50fdab8a9d78cf61c8d9fb16bc8edc2282416ed4cbd0a907ea46faa11604544f\",\"source_ref\":\"connector://fixture/records#scan\",\"source_validation\":{\"fields\":[\"amount\",\"id\",\"status\"],\"scope\":\"selected_scan\"},\"version\":\"actql-query-acquisition/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:9f130824c424089ca095981d79434addb9b4048df997210b9fd301717ff8eeba",
  )
}

///|
test "query-time acquisition preimage 1" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":120,\"received_fields\":[\"amount\",\"id\",\"status\"],\"received_rows\":3,\"scope_cid\":\"sha256:e6090cf70d76728e0bf25dff26df27d86eab1fb1438ca91eb1dd568868e12199\"},\"coverage\":{\"complete\":true,\"filter_evidence_cid\":\"sha256:d35244df3472bbd87d177115f088521f1b2cd4083e24c1d2e4d815826a9c0c0e\",\"scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"select_evidence_cid\":\"sha256:92f9681af56022bb31dcbebe62e887bd094574d4bf5bf16d1e06018baa53b6c7\",\"source_validation_evidence_cid\":\"sha256:1c8ad37d594cdec2517681afea839382b0c3673596660e721a7889e0bf244d63\"},\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"owner\":{\"input\":\"records\",\"program_source_cid\":\"sha256:444615f698dcc6ea53fa296c2edb70bbba62cd67befae8c1ed2be3daf3f3737f\",\"run_definition_cid\":\"sha256:8b1c4c522665303127f0f1f00c2c3fc6540e12edbfde6c1c09f8bd4e07fe75e5\",\"stage\":\"first\"},\"parameter_values_cid\":\"sha256:ce3468bea3995136201f0f1242c8d388f927d5c1b751f60a6cccf6b539ef4897\",\"requirement_cid\":\"sha256:9f130824c424089ca095981d79434addb9b4048df997210b9fd301717ff8eeba\",\"resolved_request_cid\":\"sha256:9e475b942ea0d73d63e2e4cdeffb72d0d145e5bbd3cdf4605d2acbca829cdde1\",\"retention\":\"process\",\"snapshot\":{\"contract_cid\":\"sha256:b79f5ece34bfbbac75d18b3f91b44ede480e367a6b69cce5212798dbc4b3b0b3\",\"token_cid\":\"sha256:e44aec26748c4401b41f05d34db446622b4fb4a077771d46dc8b7504bcb652a1\"},\"source_contract_cid\":\"sha256:b6dadf2beda041fc3f9cccc66cec826b777dd2adc13732f261e362c2aea341d2\",\"source_ref\":\"connector://fixture/records#scan\",\"version\":\"actql-query-observation/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:fcf6cc51637e7e0fa9e870a7083abb7ac3f95244be3741b0951699819daa2017",
  )
}

///|
test "query-time acquisition preimage 2" {
  let input = @json.parse(
    "{\"filter\":{\"expression_cid\":\"sha256:11ee6436f22f4aac9ed90700d83925684aa80cdbdb30c186cd79ad45b31274b7\",\"occurrence\":\"/steps/0/filter\"},\"input_contract_cid\":\"sha256:7263e8377ceede3197740c6bee4949aaa96bc4852499dedd7b4b2c28a685d7b5\",\"logical_guards\":{\"max_rows\":2,\"max_value_bytes\":1000},\"output_contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"owner\":{\"input\":\"records\",\"program_source_cid\":\"sha256:444615f698dcc6ea53fa296c2edb70bbba62cd67befae8c1ed2be3daf3f3737f\",\"run_definition_cid\":\"sha256:b0e2a6e1efd560cb11876b36f0cff2d1129202f02b2bfaa39c004dee19941518\",\"stage\":\"first\"},\"parameter_values_cid\":\"sha256:ce3468bea3995136201f0f1242c8d388f927d5c1b751f60a6cccf6b539ef4897\",\"request\":{\"tenant\":\"fixture\"},\"select\":{\"fields\":[{\"input\":\"id\",\"output\":\"id\"}],\"occurrence\":\"/steps/1/select\"},\"source_contract_cid\":\"sha256:b6dadf2beda041fc3f9cccc66cec826b777dd2adc13732f261e362c2aea341d2\",\"source_order_cid\":\"sha256:50fdab8a9d78cf61c8d9fb16bc8edc2282416ed4cbd0a907ea46faa11604544f\",\"source_ref\":\"connector://fixture/records#scan\",\"source_validation\":{\"fields\":[\"amount\",\"id\",\"status\"],\"scope\":\"selected_scan\"},\"version\":\"actql-query-acquisition/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:49f8d6f8567c311daaa6d5e602038546047ad489201e3736a1d12b3f2a4c3951",
  )
}

///|
test "query-time acquisition preimage 3" {
  let input = @json.parse(
    "{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":120,\"received_fields\":[\"amount\",\"id\",\"status\"],\"received_rows\":3,\"scope_cid\":\"sha256:7232b3717c1a8e69a5b76deb89fb1b173a5af75b92588eaaad2916e7fc2fcfdf\"},\"coverage\":{\"complete\":true,\"filter_evidence_cid\":\"sha256:d35244df3472bbd87d177115f088521f1b2cd4083e24c1d2e4d815826a9c0c0e\",\"scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"select_evidence_cid\":\"sha256:92f9681af56022bb31dcbebe62e887bd094574d4bf5bf16d1e06018baa53b6c7\",\"source_validation_evidence_cid\":\"sha256:1c8ad37d594cdec2517681afea839382b0c3673596660e721a7889e0bf244d63\"},\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"owner\":{\"input\":\"records\",\"program_source_cid\":\"sha256:444615f698dcc6ea53fa296c2edb70bbba62cd67befae8c1ed2be3daf3f3737f\",\"run_definition_cid\":\"sha256:b0e2a6e1efd560cb11876b36f0cff2d1129202f02b2bfaa39c004dee19941518\",\"stage\":\"first\"},\"parameter_values_cid\":\"sha256:ce3468bea3995136201f0f1242c8d388f927d5c1b751f60a6cccf6b539ef4897\",\"requirement_cid\":\"sha256:49f8d6f8567c311daaa6d5e602038546047ad489201e3736a1d12b3f2a4c3951\",\"resolved_request_cid\":\"sha256:9e475b942ea0d73d63e2e4cdeffb72d0d145e5bbd3cdf4605d2acbca829cdde1\",\"retention\":\"process\",\"snapshot\":{\"contract_cid\":\"sha256:b79f5ece34bfbbac75d18b3f91b44ede480e367a6b69cce5212798dbc4b3b0b3\",\"token_cid\":\"sha256:e44aec26748c4401b41f05d34db446622b4fb4a077771d46dc8b7504bcb652a1\"},\"source_contract_cid\":\"sha256:b6dadf2beda041fc3f9cccc66cec826b777dd2adc13732f261e362c2aea341d2\",\"source_ref\":\"connector://fixture/records#scan\",\"version\":\"actql-query-observation/0.1\"}",
  )
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(
    @canonical_json.cid_value(value, 100000, 10000, 100),
    "sha256:c039657e29b4f567e5dec6be41894b4290b2e03bd6a3023aebe7039a1e8a8f58",
  )
}
