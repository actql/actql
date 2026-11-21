// Generated from the independent query-acquisition fixtures; do not edit.

///|
test "query acquisition preimage 0" {
  let input = @json.parse("{\"filter\":{\"expression_cid\":\"sha256:11ee6436f22f4aac9ed90700d83925684aa80cdbdb30c186cd79ad45b31274b7\",\"occurrence\":\"/steps/0/filter\"},\"input_contract_cid\":\"sha256:7263e8377ceede3197740c6bee4949aaa96bc4852499dedd7b4b2c28a685d7b5\",\"logical_guards\":{\"max_rows\":2,\"max_value_bytes\":1000},\"output_contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"owner\":{\"input\":\"records\",\"program_source_cid\":\"sha256:3726e10de94d7b575f201bc775a429005523f0cbe37ef268318152bb50e8d062\",\"stage\":\"first\"},\"parameter_values_cid\":\"sha256:ce3468bea3995136201f0f1242c8d388f927d5c1b751f60a6cccf6b539ef4897\",\"request\":{\"tenant\":\"fixture\"},\"select\":{\"fields\":[{\"input\":\"id\",\"output\":\"id\"}],\"occurrence\":\"/steps/1/select\"},\"source_contract_cid\":\"sha256:b6dadf2beda041fc3f9cccc66cec826b777dd2adc13732f261e362c2aea341d2\",\"source_order_cid\":\"sha256:50fdab8a9d78cf61c8d9fb16bc8edc2282416ed4cbd0a907ea46faa11604544f\",\"source_ref\":\"connector://fixture/records#scan\",\"source_validation\":{\"fields\":[\"amount\",\"id\",\"status\"],\"scope\":\"selected_scan\"},\"version\":\"actql-query-acquisition/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:d51152a141185a7ab2c69d616b84fbbca0626e6725c559f35a3da7ba1add9fd2")
}

///|
test "query acquisition preimage 1" {
  let input = @json.parse("{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":23,\"received_fields\":[\"id\"],\"received_rows\":2,\"scope_cid\":\"sha256:36d8ff60de04963e5bf6cd6647b54c2fa456c584d1adc99363f3348c145d98e7\"},\"coverage\":{\"complete\":true,\"filter_evidence_cid\":\"sha256:d35244df3472bbd87d177115f088521f1b2cd4083e24c1d2e4d815826a9c0c0e\",\"scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"select_evidence_cid\":\"sha256:92f9681af56022bb31dcbebe62e887bd094574d4bf5bf16d1e06018baa53b6c7\",\"source_validation_evidence_cid\":\"sha256:1c8ad37d594cdec2517681afea839382b0c3673596660e721a7889e0bf244d63\"},\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"owner\":{\"input\":\"records\",\"program_source_cid\":\"sha256:3726e10de94d7b575f201bc775a429005523f0cbe37ef268318152bb50e8d062\",\"stage\":\"first\"},\"parameter_values_cid\":\"sha256:ce3468bea3995136201f0f1242c8d388f927d5c1b751f60a6cccf6b539ef4897\",\"requirement_cid\":\"sha256:d51152a141185a7ab2c69d616b84fbbca0626e6725c559f35a3da7ba1add9fd2\",\"resolved_request_cid\":\"sha256:9e475b942ea0d73d63e2e4cdeffb72d0d145e5bbd3cdf4605d2acbca829cdde1\",\"retention\":\"process\",\"snapshot\":{\"contract_cid\":\"sha256:b79f5ece34bfbbac75d18b3f91b44ede480e367a6b69cce5212798dbc4b3b0b3\",\"token_cid\":\"sha256:e44aec26748c4401b41f05d34db446622b4fb4a077771d46dc8b7504bcb652a1\"},\"source_contract_cid\":\"sha256:b6dadf2beda041fc3f9cccc66cec826b777dd2adc13732f261e362c2aea341d2\",\"source_ref\":\"connector://fixture/records#scan\",\"version\":\"actql-query-observation/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:b70ba95f214cd7014430d6c0311a4a1281df9d052b69f1fd189a785f887c96df")
}

///|
test "query acquisition preimage 2" {
  let input = @json.parse("{\"actual_access\":{\"provider_scope_cid\":null,\"received_bytes\":120,\"received_fields\":[\"amount\",\"id\",\"status\"],\"received_rows\":3,\"scope_cid\":\"sha256:a75ca4aa1dcbfa7f2ee7c548b561c9a9eb01b6a8b53cbff919a7293332282650\"},\"coverage\":{\"complete\":true,\"filter_evidence_cid\":\"sha256:d35244df3472bbd87d177115f088521f1b2cd4083e24c1d2e4d815826a9c0c0e\",\"scope_cid\":\"sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573\",\"select_evidence_cid\":\"sha256:92f9681af56022bb31dcbebe62e887bd094574d4bf5bf16d1e06018baa53b6c7\",\"source_validation_evidence_cid\":\"sha256:1c8ad37d594cdec2517681afea839382b0c3673596660e721a7889e0bf244d63\"},\"output\":{\"contract_cid\":\"sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b\",\"row_count\":2,\"rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\"},\"owner\":{\"input\":\"records\",\"program_source_cid\":\"sha256:3726e10de94d7b575f201bc775a429005523f0cbe37ef268318152bb50e8d062\",\"stage\":\"first\"},\"parameter_values_cid\":\"sha256:ce3468bea3995136201f0f1242c8d388f927d5c1b751f60a6cccf6b539ef4897\",\"requirement_cid\":\"sha256:d51152a141185a7ab2c69d616b84fbbca0626e6725c559f35a3da7ba1add9fd2\",\"resolved_request_cid\":\"sha256:9e475b942ea0d73d63e2e4cdeffb72d0d145e5bbd3cdf4605d2acbca829cdde1\",\"retention\":\"process\",\"snapshot\":{\"contract_cid\":\"sha256:b79f5ece34bfbbac75d18b3f91b44ede480e367a6b69cce5212798dbc4b3b0b3\",\"token_cid\":\"sha256:e44aec26748c4401b41f05d34db446622b4fb4a077771d46dc8b7504bcb652a1\"},\"source_contract_cid\":\"sha256:b6dadf2beda041fc3f9cccc66cec826b777dd2adc13732f261e362c2aea341d2\",\"source_ref\":\"connector://fixture/records#scan\",\"version\":\"actql-query-observation/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:2604c65405272c8ae1021e90769151d2b33aeced3338c22e90335b2eeabb0eb3")
}

///|
test "query acquisition preimage 3" {
  let input = @json.parse("{\"resolved_request_cid\":\"sha256:9e475b942ea0d73d63e2e4cdeffb72d0d145e5bbd3cdf4605d2acbca829cdde1\",\"source_contract_cid\":\"sha256:b6dadf2beda041fc3f9cccc66cec826b777dd2adc13732f261e362c2aea341d2\",\"source_ref\":\"connector://fixture/records#scan\",\"version\":\"actql-query-scan-scope/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573")
}

///|
test "query acquisition preimage 4" {
  let input = @json.parse("{\"received_fields\":[\"id\"],\"received_rows_cid\":\"sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a\",\"requirement_cid\":\"sha256:d51152a141185a7ab2c69d616b84fbbca0626e6725c559f35a3da7ba1add9fd2\",\"version\":\"actql-query-access-scope/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:36d8ff60de04963e5bf6cd6647b54c2fa456c584d1adc99363f3348c145d98e7")
}

///|
test "query acquisition preimage 5" {
  let input = @json.parse("{\"received_fields\":[\"amount\",\"id\",\"status\"],\"received_rows_cid\":\"sha256:410930adbff0caf978e1a8959e98f4cbee9a88bbbd58a0290ed66cdd5bbc52c9\",\"requirement_cid\":\"sha256:d51152a141185a7ab2c69d616b84fbbca0626e6725c559f35a3da7ba1add9fd2\",\"version\":\"actql-query-access-scope/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:a75ca4aa1dcbfa7f2ee7c548b561c9a9eb01b6a8b53cbff919a7293332282650")
}

///|
test "query acquisition preimage 6" {
  let input = @json.parse("{\"binding_references\":[],\"bindings\":{},\"expression_contract_cid\":\"sha256:6cd16dcf9c63afc1b6a882fe960b87e19156d7cdb0b2c48fc3133c66fb98291e\",\"local_body\":{\"effects\":{},\"inputs\":{\"records\":{\"connector\":\"fixture\",\"request\":{\"tenant\":\"fixture\"},\"resource\":\"records\",\"view\":\"scan\"}},\"results\":{\"out\":{\"fields\":[\"id\"],\"from\":\"selected\"}},\"steps\":[{\"filter\":{\"eq\":[{\"field\":\"status\"},{\"$param\":\"wanted\"}]}},{\"as\":\"selected\",\"select\":[\"id\"]}]},\"parameter_references\":[{\"name\":\"wanted\",\"path\":\"/steps/0/filter/eq/1\",\"type\":{\"type\":\"string\"}}],\"parameters\":{\"wanted\":{\"type\":\"string\"}},\"version\":\"actql-stage-semantics/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:ea172f17201b6dc2b02dbc19d6ebc70baae923e8c978b5494fcfe1e2a392a7f4")
}

///|
test "query acquisition preimage 7" {
  let input = @json.parse("{\"actql_version\":\"actql/0.1\",\"binding_references\":[],\"bindings\":{},\"expression_contract_cid\":\"sha256:6cd16dcf9c63afc1b6a882fe960b87e19156d7cdb0b2c48fc3133c66fb98291e\",\"parameter_references\":[{\"name\":\"wanted\",\"path\":\"/stages/0/steps/0/filter/eq/1\",\"type\":{\"type\":\"string\"}}],\"parameters\":{\"wanted\":{\"type\":\"string\"}},\"program_template\":{\"exports\":{\"out\":{\"from\":{\"result\":\"out\",\"stage\":\"first\"}}},\"stages\":[{\"after\":\"initial\",\"id\":\"first\",\"imports\":{},\"stage_semantics_cid\":\"sha256:ea172f17201b6dc2b02dbc19d6ebc70baae923e8c978b5494fcfe1e2a392a7f4\"}]},\"version\":\"actql-program-semantics/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:c80245d9139473be785c7c1f873e21050f0db650dac521df37dd5f1b12868195")
}

///|
test "query acquisition preimage 8" {
  let input = @json.parse("{\"id\":\"query.fixture\",\"program_semantics_cid\":\"sha256:c80245d9139473be785c7c1f873e21050f0db650dac521df37dd5f1b12868195\",\"version\":\"actql-program-definition/0.1\"}")
  let value = @canonical_json.from_json(input, 10000, 100, 100000)
  assert_eq(@canonical_json.cid_value(value, 100000, 10000, 100), "sha256:3726e10de94d7b575f201bc775a429005523f0cbe37ef268318152bb50e8d062")
}
