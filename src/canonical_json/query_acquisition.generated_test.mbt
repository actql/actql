// Generated from the independent query-acquisition fixtures; do not edit.

///|
test "query acquisition preimage 0" {
  let input = @json.parse("{\"filter\":{\"expression_cid\":\"sha256:11ee6436f22f4aac9ed90700d83925684aa80cdbdb30c186cd79ad45b31274b7\",\"occurrence\":\"/steps/0/filter\"},\"input_contract_cid\":\"sha256:7263e8377ceede3197740c6bee4949aaa96bc4852499dedd7b4b2c28a685d7b5\",\"logical_guards\":{\"max_rows\":2,\"max_value_bytes\":1000},\"output_contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"owner\":{\"input\":\"records\",\"program_source_cid\":\"sha256:8d3ac1658e2019460abb47f8200be8dac90933b719bc14b9e7985fa61014bf9f\",\"stage\":\"first\"},\"parameter_values_cid\":\"sha256:ce3468bea3995136201f0f1242c8d388f927d5c1b751f60a6cccf6b539ef4897\",\"request\":{\"tenant\":\"fixture\"},\"select\":{\"fields\":[{\"input\":\"id\",\"output\":\"id\"}],\"occurrence\":\"/steps/1/select\"},\"source_contract_cid\":\"sha256:b6dadf2beda041fc3f9cccc66cec826b777dd2adc13732f261e362c2aea341d2\",\"source_order_cid\":\"sha256:50fdab8a9d78cf61c8d9fb16bc8edc2282416ed4cbd0a907ea46faa11604544f\",\"source_ref\":\"connector://fixture/records#scan\",\"source_validation\":{\"fields\":[\"amount\",\"id\",\"status\"],\"scope\":\"selected_scan\"},\"version\":\"actql-query-acquisition/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:cef8da5b7bd461dcd67ae5fcf4dd0e3551a908ca1e9567dca769448876d3c0fd")
}

///|
test "query acquisition preimage 1" {
  let input = @json.parse("{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":23,\"received_fields\":[\"id\"],\"received_rows\":2,\"scope_cid\":\"sha256:e28b8a76d0c3180be3d44c3a9fdfe27a887a2ed986ab3e69737823f65a6c9158\"},\"coverage\":{\"complete\":true,\"filter_evidence_cid\":\"sha256:d35244df3472bbd87d177115f088521f1b2cd4083e24c1d2e4d815826a9c0c0e\",\"scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"select_evidence_cid\":\"sha256:92f9681af56022bb31dcbebe62e887bd094574d4bf5bf16d1e06018baa53b6c7\",\"source_validation_evidence_cid\":\"sha256:1c8ad37d594cdec2517681afea839382b0c3673596660e721a7889e0bf244d63\"},\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"owner\":{\"input\":\"records\",\"program_source_cid\":\"sha256:8d3ac1658e2019460abb47f8200be8dac90933b719bc14b9e7985fa61014bf9f\",\"stage\":\"first\"},\"parameter_values_cid\":\"sha256:ce3468bea3995136201f0f1242c8d388f927d5c1b751f60a6cccf6b539ef4897\",\"requirement_cid\":\"sha256:cef8da5b7bd461dcd67ae5fcf4dd0e3551a908ca1e9567dca769448876d3c0fd\",\"resolved_request_cid\":\"sha256:9e475b942ea0d73d63e2e4cdeffb72d0d145e5bbd3cdf4605d2acbca829cdde1\",\"retention\":\"process\",\"snapshot\":{\"contract_cid\":\"sha256:b79f5ece34bfbbac75d18b3f91b44ede480e367a6b69cce5212798dbc4b3b0b3\",\"token_cid\":\"sha256:e44aec26748c4401b41f05d34db446622b4fb4a077771d46dc8b7504bcb652a1\"},\"source_contract_cid\":\"sha256:b6dadf2beda041fc3f9cccc66cec826b777dd2adc13732f261e362c2aea341d2\",\"source_ref\":\"connector://fixture/records#scan\",\"version\":\"actql-query-observation/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:9e82d5cbfca0eda2eb5b41d16c5c98f21ffeec94bf0ca9aff58ec4070dc6ec2f")
}

///|
test "query acquisition preimage 2" {
  let input = @json.parse("{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":120,\"received_fields\":[\"amount\",\"id\",\"status\"],\"received_rows\":3,\"scope_cid\":\"sha256:40a8d2ce0b820cce7df2e6a61522c2d8ce6b038d27a0b61fd868a51bc1777ae4\"},\"coverage\":{\"complete\":true,\"filter_evidence_cid\":\"sha256:d35244df3472bbd87d177115f088521f1b2cd4083e24c1d2e4d815826a9c0c0e\",\"scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"select_evidence_cid\":\"sha256:92f9681af56022bb31dcbebe62e887bd094574d4bf5bf16d1e06018baa53b6c7\",\"source_validation_evidence_cid\":\"sha256:1c8ad37d594cdec2517681afea839382b0c3673596660e721a7889e0bf244d63\"},\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"owner\":{\"input\":\"records\",\"program_source_cid\":\"sha256:8d3ac1658e2019460abb47f8200be8dac90933b719bc14b9e7985fa61014bf9f\",\"stage\":\"first\"},\"parameter_values_cid\":\"sha256:ce3468bea3995136201f0f1242c8d388f927d5c1b751f60a6cccf6b539ef4897\",\"requirement_cid\":\"sha256:cef8da5b7bd461dcd67ae5fcf4dd0e3551a908ca1e9567dca769448876d3c0fd\",\"resolved_request_cid\":\"sha256:9e475b942ea0d73d63e2e4cdeffb72d0d145e5bbd3cdf4605d2acbca829cdde1\",\"retention\":\"process\",\"snapshot\":{\"contract_cid\":\"sha256:b79f5ece34bfbbac75d18b3f91b44ede480e367a6b69cce5212798dbc4b3b0b3\",\"token_cid\":\"sha256:e44aec26748c4401b41f05d34db446622b4fb4a077771d46dc8b7504bcb652a1\"},\"source_contract_cid\":\"sha256:b6dadf2beda041fc3f9cccc66cec826b777dd2adc13732f261e362c2aea341d2\",\"source_ref\":\"connector://fixture/records#scan\",\"version\":\"actql-query-observation/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:d3768b8812611bc3cea8d344fd82d2f1146a158c903559d24a760da30b3a5701")
}

///|
test "query acquisition preimage 3" {
  let input = @json.parse("{\"resolved_request_cid\":\"sha256:9e475b942ea0d73d63e2e4cdeffb72d0d145e5bbd3cdf4605d2acbca829cdde1\",\"source_contract_cid\":\"sha256:b6dadf2beda041fc3f9cccc66cec826b777dd2adc13732f261e362c2aea341d2\",\"source_ref\":\"connector://fixture/records#scan\",\"version\":\"actql-query-scan-scope/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573")
}

///|
test "query acquisition preimage 4" {
  let input = @json.parse("{\"received_fields\":[\"id\"],\"received_rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\",\"requirement_cid\":\"sha256:cef8da5b7bd461dcd67ae5fcf4dd0e3551a908ca1e9567dca769448876d3c0fd\",\"version\":\"actql-query-access-scope/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:e28b8a76d0c3180be3d44c3a9fdfe27a887a2ed986ab3e69737823f65a6c9158")
}

///|
test "query acquisition preimage 5" {
  let input = @json.parse("{\"received_fields\":[\"amount\",\"id\",\"status\"],\"received_rows_cid\":\"sha256:410930adbff0caf978e1a8959e98f4cbee9a88bbbd58a0290ed66cdd5bbc52c9\",\"requirement_cid\":\"sha256:cef8da5b7bd461dcd67ae5fcf4dd0e3551a908ca1e9567dca769448876d3c0fd\",\"version\":\"actql-query-access-scope/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:40a8d2ce0b820cce7df2e6a61522c2d8ce6b038d27a0b61fd868a51bc1777ae4")
}

///|
test "query acquisition preimage 6" {
  let input = @json.parse("{\"binding_references\":[],\"bindings\":{},\"expression_contract_cid\":\"sha256:14a39a0812d6bb5a7a6a4a78c1431c5d6bf14407645b883da1f0acb3627e9068\",\"local_body\":{\"effects\":{},\"inputs\":{\"records\":{\"connector\":\"fixture\",\"request\":{\"tenant\":\"fixture\"},\"resource\":\"records\",\"view\":\"scan\"}},\"results\":{\"out\":{\"fields\":[\"id\"],\"from\":\"selected\"}},\"steps\":[{\"filter\":{\"eq\":[{\"field\":\"status\"},{\"$param\":\"wanted\"}]}},{\"as\":\"selected\",\"select\":[\"id\"]}]},\"parameter_references\":[{\"name\":\"wanted\",\"path\":\"/steps/0/filter/eq/1\",\"type\":{\"type\":\"string\"}}],\"parameters\":{\"wanted\":{\"type\":\"string\"}},\"version\":\"actql-stage-semantics/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:bfa95b5733842a59ad88be9c0170da2013e006ffed8f810413a1026087346785")
}

///|
test "query acquisition preimage 7" {
  let input = @json.parse("{\"actql_version\":\"actql/0.1\",\"binding_references\":[],\"bindings\":{},\"expression_contract_cid\":\"sha256:14a39a0812d6bb5a7a6a4a78c1431c5d6bf14407645b883da1f0acb3627e9068\",\"parameter_references\":[{\"name\":\"wanted\",\"path\":\"/stages/0/steps/0/filter/eq/1\",\"type\":{\"type\":\"string\"}}],\"parameters\":{\"wanted\":{\"type\":\"string\"}},\"program_template\":{\"exports\":{\"out\":{\"from\":{\"result\":\"out\",\"stage\":\"first\"}}},\"stages\":[{\"after\":\"initial\",\"id\":\"first\",\"imports\":{},\"stage_semantics_cid\":\"sha256:bfa95b5733842a59ad88be9c0170da2013e006ffed8f810413a1026087346785\"}]},\"version\":\"actql-program-semantics/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:faa25bdc510f5106f4cd2853a8e61f1f6605e35b73085fdcaa40f3555012a277")
}

///|
test "query acquisition preimage 8" {
  let input = @json.parse("{\"id\":\"query.fixture\",\"program_semantics_cid\":\"sha256:faa25bdc510f5106f4cd2853a8e61f1f6605e35b73085fdcaa40f3555012a277\",\"version\":\"actql-program-definition/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:8d3ac1658e2019460abb47f8200be8dac90933b719bc14b9e7985fa61014bf9f")
}
