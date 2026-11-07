///|
// Actual synthetic normalized failure input, not a product-derived expected value.
let nearest_failed_environment : String = "{\"command_contracts\":[],\"connector_capabilities\":[{\"capability_contract_cids\":[\"sha256:cdaab753fd3c01709fbd9ae32022a8462bc8200edf1e9c93d533a293989f8a3b\"],\"read_mode\":\"snapshot\",\"source_contract_cid\":\"sha256:b4015abcd0ef002cb5825df326b919e9ec9d20f5aa746c9029893deedad7777b\",\"source_ref\":\"connector://nearest_fixture/candidates#records\",\"source_view_contract_cid\":\"sha256:b4015abcd0ef002cb5825df326b919e9ec9d20f5aa746c9029893deedad7777b\"},{\"capability_contract_cids\":[\"sha256:cdaab753fd3c01709fbd9ae32022a8462bc8200edf1e9c93d533a293989f8a3b\"],\"read_mode\":\"snapshot\",\"source_contract_cid\":\"sha256:7a0eff89f9165ee7117c148fa649b501f0d20388a1ec39c52cf6b8597c73fa2b\",\"source_ref\":\"connector://nearest_fixture/queries#records\",\"source_view_contract_cid\":\"sha256:7a0eff89f9165ee7117c148fa649b501f0d20388a1ec39c52cf6b8597c73fa2b\"}],\"connector_catalogs\":[{\"catalog_cid\":\"sha256:922fff583592b8ac089766553b4ff66d3c4fba3f96673f20b4208696247579b2\",\"commands\":[],\"connector_id\":\"nearest_fixture\",\"connector_version\":\"nearest_fixture/0.1\",\"contracts\":[{\"body\":{\"fields\":{\"embedding\":{\"dimensions\":2,\"element_type\":\"f32\",\"nullable\":false,\"type\":\"vector\"},\"note\":{\"nullable\":true,\"type\":\"string\"},\"request_id\":{\"nullable\":false,\"type\":\"string\"}},\"version\":\"actql-relation-schema/0.1\"},\"cid\":\"sha256:10398d9c513b4a315b624bd5a73efe5dfcfb864d427eb69052ff0d8b6f61212c\",\"id\":\"nearest_fixture/queries/records/row\",\"kind\":\"carrier_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"nearest_fixture/0.1\"},{\"body\":{\"relation_keys\":{\"candidate_keys\":[[\"item_id\"]]}},\"cid\":\"sha256:25e9d7b4b5c97b807c32ad37482ac1f30a7a34bd983caa8f27d8db279085f858\",\"id\":\"nearest_fixture/candidates/records/facts\",\"kind\":\"carrier_facts\",\"schema\":\"actql.contract/0.1\",\"version\":\"nearest_fixture/0.1\"},{\"body\":{\"additional_properties\":false,\"fields\":{},\"nullable\":false,\"type\":\"object\"},\"cid\":\"sha256:3d56d5b099a4b9a1a4d9b8133a962cb54a5ec7c711418c7179332b018968165d\",\"id\":\"nearest_fixture/queries/records/request\",\"kind\":\"request_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"nearest_fixture/0.1\"},{\"body\":{\"fields\":{\"embedding\":{\"dimensions\":2,\"element_type\":\"f32\",\"nullable\":false,\"type\":\"vector\"},\"item_id\":{\"nullable\":false,\"type\":\"string\"},\"label\":{\"nullable\":false,\"type\":\"string\"}},\"version\":\"actql-relation-schema/0.1\"},\"cid\":\"sha256:7f4f0c0f4f011d8ca5039e3c8df7e52cd1a612a0478b126e160964135de2b9ec\",\"id\":\"nearest_fixture/candidates/records/row\",\"kind\":\"carrier_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"nearest_fixture/0.1\"},{\"body\":{\"relation_keys\":{\"candidate_keys\":[[\"request_id\"]]}},\"cid\":\"sha256:9ddece7324893957af2b888506eadad11b83c84eacce6e04a32d4488389ac444\",\"id\":\"nearest_fixture/queries/records/facts\",\"kind\":\"carrier_facts\",\"schema\":\"actql.contract/0.1\",\"version\":\"nearest_fixture/0.1\"},{\"body\":{\"additional_properties\":false,\"fields\":{},\"nullable\":false,\"type\":\"object\"},\"cid\":\"sha256:aef963b149bb822850067091fd60c66192df949c797e86762150e69a764e8323\",\"id\":\"nearest_fixture/candidates/records/request\",\"kind\":\"request_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"nearest_fixture/0.1\"},{\"body\":{\"classification\":\"unknown\",\"source_ref\":\"connector://nearest_fixture/candidates#records\",\"version\":\"actql-source-data-policy/0.1\"},\"cid\":\"sha256:c75c4b00ed8cd95917d4dcad95b7203043bea3475af37b76ca23f688e3f555a1\",\"id\":\"nearest_fixture/candidates/records/policy\",\"kind\":\"data_policy\",\"schema\":\"actql.contract/0.1\",\"version\":\"nearest_fixture/0.1\"},{\"body\":{\"classification\":\"unknown\",\"source_ref\":\"connector://nearest_fixture/queries#records\",\"version\":\"actql-source-data-policy/0.1\"},\"cid\":\"sha256:cdb45d757a87e18dc32e486c33846b4c9dcad63c7f3bebcf8b31ca9b145e44ed\",\"id\":\"nearest_fixture/queries/records/policy\",\"kind\":\"data_policy\",\"schema\":\"actql.contract/0.1\",\"version\":\"nearest_fixture/0.1\"},{\"body\":{\"carrier\":\"relation\",\"operations\":[\"projection\"],\"version\":\"actql-source-view-pushdown/0.1\"},\"cid\":\"sha256:d93e6b605286afa5090f92ff4ae8fed0808c8d9c7e523e202e60ef85fa3fa83e\",\"id\":\"nearest_fixture/queries/records/pushdown\",\"kind\":\"pushdown\",\"schema\":\"actql.contract/0.1\",\"version\":\"nearest_fixture/0.1\"},{\"body\":{\"carrier\":\"relation\",\"operations\":[\"projection\"],\"version\":\"actql-source-view-pushdown/0.1\"},\"cid\":\"sha256:db537ee4846eed2810a398c330b1ad2e8912acb6a8f8e9e9ed308f2dd6d0fbb9\",\"id\":\"nearest_fixture/candidates/records/pushdown\",\"kind\":\"pushdown\",\"schema\":\"actql.contract/0.1\",\"version\":\"nearest_fixture/0.1\"}],\"schema\":\"actql.connector_catalog/0.1\",\"source_views\":[{\"acquisition\":{\"authority\":\"read_content\",\"default_mode\":\"snapshot\",\"kind\":\"scan\",\"modes\":[{\"bounded\":true,\"mode\":\"snapshot\"}],\"request_schema\":{\"cid\":\"sha256:3d56d5b099a4b9a1a4d9b8133a962cb54a5ec7c711418c7179332b018968165d\",\"id\":\"nearest_fixture/queries/records/request\",\"version\":\"nearest_fixture/0.1\"}},\"connector_id\":\"nearest_fixture\",\"connector_version\":\"nearest_fixture/0.1\",\"contract_cid\":\"sha256:7a0eff89f9165ee7117c148fa649b501f0d20388a1ec39c52cf6b8597c73fa2b\",\"output\":{\"carrier\":\"relation\",\"data_policy\":{\"cid\":\"sha256:cdb45d757a87e18dc32e486c33846b4c9dcad63c7f3bebcf8b31ca9b145e44ed\",\"id\":\"nearest_fixture/queries/records/policy\",\"version\":\"nearest_fixture/0.1\"},\"facts\":{\"cid\":\"sha256:9ddece7324893957af2b888506eadad11b83c84eacce6e04a32d4488389ac444\",\"id\":\"nearest_fixture/queries/records/facts\",\"version\":\"nearest_fixture/0.1\"},\"schema\":{\"cid\":\"sha256:10398d9c513b4a315b624bd5a73efe5dfcfb864d427eb69052ff0d8b6f61212c\",\"id\":\"nearest_fixture/queries/records/row\",\"version\":\"nearest_fixture/0.1\"}},\"pushdown\":{\"contract\":{\"cid\":\"sha256:d93e6b605286afa5090f92ff4ae8fed0808c8d9c7e523e202e60ef85fa3fa83e\",\"id\":\"nearest_fixture/queries/records/pushdown\",\"version\":\"nearest_fixture/0.1\"},\"operations\":[\"projection\"]},\"request_processing\":{\"mutates_business_state\":false},\"resource_kind\":\"table\",\"schema\":\"actql.source_view/0.1\",\"view_id\":\"records\",\"view_version\":\"nearest_fixture/0.1\"},{\"acquisition\":{\"authority\":\"read_content\",\"default_mode\":\"snapshot\",\"kind\":\"scan\",\"modes\":[{\"bounded\":true,\"mode\":\"snapshot\"}],\"request_schema\":{\"cid\":\"sha256:aef963b149bb822850067091fd60c66192df949c797e86762150e69a764e8323\",\"id\":\"nearest_fixture/candidates/records/request\",\"version\":\"nearest_fixture/0.1\"}},\"connector_id\":\"nearest_fixture\",\"connector_version\":\"nearest_fixture/0.1\",\"contract_cid\":\"sha256:b4015abcd0ef002cb5825df326b919e9ec9d20f5aa746c9029893deedad7777b\",\"output\":{\"carrier\":\"relation\",\"data_policy\":{\"cid\":\"sha256:c75c4b00ed8cd95917d4dcad95b7203043bea3475af37b76ca23f688e3f555a1\",\"id\":\"nearest_fixture/candidates/records/policy\",\"version\":\"nearest_fixture/0.1\"},\"facts\":{\"cid\":\"sha256:25e9d7b4b5c97b807c32ad37482ac1f30a7a34bd983caa8f27d8db279085f858\",\"id\":\"nearest_fixture/candidates/records/facts\",\"version\":\"nearest_fixture/0.1\"},\"schema\":{\"cid\":\"sha256:7f4f0c0f4f011d8ca5039e3c8df7e52cd1a612a0478b126e160964135de2b9ec\",\"id\":\"nearest_fixture/candidates/records/row\",\"version\":\"nearest_fixture/0.1\"}},\"pushdown\":{\"contract\":{\"cid\":\"sha256:db537ee4846eed2810a398c330b1ad2e8912acb6a8f8e9e9ed308f2dd6d0fbb9\",\"id\":\"nearest_fixture/candidates/records/pushdown\",\"version\":\"nearest_fixture/0.1\"},\"operations\":[\"projection\"]},\"request_processing\":{\"mutates_business_state\":false},\"resource_kind\":\"table\",\"schema\":\"actql.source_view/0.1\",\"view_id\":\"records\",\"view_version\":\"nearest_fixture/0.1\"}]}],\"connector_manifest\":{\"connectors\":[{\"connector\":\"nearest_fixture\",\"connector_id\":\"nearest_fixture\",\"connector_version\":\"nearest_fixture/0.1\"}],\"version\":\"actql-connectors/0.1\"},\"contract_registry\":[{\"body\":{\"carrier\":\"relation\",\"operations\":[\"projection\"],\"version\":\"actql-source-view-pushdown/0.1\"},\"cid\":\"sha256:d93e6b605286afa5090f92ff4ae8fed0808c8d9c7e523e202e60ef85fa3fa83e\",\"id\":\"nearest_fixture/queries/records/pushdown\",\"kind\":\"pushdown\",\"schema\":\"actql.contract/0.1\",\"version\":\"nearest_fixture/0.1\"},{\"body\":{\"additional_properties\":false,\"fields\":{},\"nullable\":false,\"type\":\"object\"},\"cid\":\"sha256:3d56d5b099a4b9a1a4d9b8133a962cb54a5ec7c711418c7179332b018968165d\",\"id\":\"nearest_fixture/queries/records/request\",\"kind\":\"request_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"nearest_fixture/0.1\"},{\"body\":{\"relation_keys\":{\"candidate_keys\":[[\"item_id\"]]}},\"cid\":\"sha256:25e9d7b4b5c97b807c32ad37482ac1f30a7a34bd983caa8f27d8db279085f858\",\"id\":\"nearest_fixture/candidates/records/facts\",\"kind\":\"carrier_facts\",\"schema\":\"actql.contract/0.1\",\"version\":\"nearest_fixture/0.1\"},{\"body\":{\"fields\":{\"embedding\":{\"dimensions\":2,\"element_type\":\"f32\",\"nullable\":false,\"type\":\"vector\"},\"note\":{\"nullable\":true,\"type\":\"string\"},\"request_id\":{\"nullable\":false,\"type\":\"string\"}},\"version\":\"actql-relation-schema/0.1\"},\"cid\":\"sha256:10398d9c513b4a315b624bd5a73efe5dfcfb864d427eb69052ff0d8b6f61212c\",\"id\":\"nearest_fixture/queries/records/row\",\"kind\":\"carrier_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"nearest_fixture/0.1\"},{\"body\":{\"classification\":\"unknown\",\"source_ref\":\"connector://nearest_fixture/candidates#records\",\"version\":\"actql-source-data-policy/0.1\"},\"cid\":\"sha256:c75c4b00ed8cd95917d4dcad95b7203043bea3475af37b76ca23f688e3f555a1\",\"id\":\"nearest_fixture/candidates/records/policy\",\"kind\":\"data_policy\",\"schema\":\"actql.contract/0.1\",\"version\":\"nearest_fixture/0.1\"},{\"body\":{\"fields\":{\"embedding\":{\"dimensions\":2,\"element_type\":\"f32\",\"nullable\":false,\"type\":\"vector\"},\"item_id\":{\"nullable\":false,\"type\":\"string\"},\"label\":{\"nullable\":false,\"type\":\"string\"}},\"version\":\"actql-relation-schema/0.1\"},\"cid\":\"sha256:7f4f0c0f4f011d8ca5039e3c8df7e52cd1a612a0478b126e160964135de2b9ec\",\"id\":\"nearest_fixture/candidates/records/row\",\"kind\":\"carrier_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"nearest_fixture/0.1\"},{\"body\":{\"additional_properties\":false,\"fields\":{},\"nullable\":false,\"type\":\"object\"},\"cid\":\"sha256:aef963b149bb822850067091fd60c66192df949c797e86762150e69a764e8323\",\"id\":\"nearest_fixture/candidates/records/request\",\"kind\":\"request_schema\",\"schema\":\"actql.contract/0.1\",\"version\":\"nearest_fixture/0.1\"},{\"body\":{\"classification\":\"unknown\",\"source_ref\":\"connector://nearest_fixture/queries#records\",\"version\":\"actql-source-data-policy/0.1\"},\"cid\":\"sha256:cdb45d757a87e18dc32e486c33846b4c9dcad63c7f3bebcf8b31ca9b145e44ed\",\"id\":\"nearest_fixture/queries/records/policy\",\"kind\":\"data_policy\",\"schema\":\"actql.contract/0.1\",\"version\":\"nearest_fixture/0.1\"},{\"body\":{\"carrier\":\"relation\",\"operations\":[\"projection\"],\"version\":\"actql-source-view-pushdown/0.1\"},\"cid\":\"sha256:db537ee4846eed2810a398c330b1ad2e8912acb6a8f8e9e9ed308f2dd6d0fbb9\",\"id\":\"nearest_fixture/candidates/records/pushdown\",\"kind\":\"pushdown\",\"schema\":\"actql.contract/0.1\",\"version\":\"nearest_fixture/0.1\"},{\"body\":{\"relation_keys\":{\"candidate_keys\":[[\"request_id\"]]}},\"cid\":\"sha256:9ddece7324893957af2b888506eadad11b83c84eacce6e04a32d4488389ac444\",\"id\":\"nearest_fixture/queries/records/facts\",\"kind\":\"carrier_facts\",\"schema\":\"actql.contract/0.1\",\"version\":\"nearest_fixture/0.1\"}],\"evidence_bundle_cid\":\"sha256:ed5b4c7bac73a5a615474043ce88e0dd766deba32f8fca9110bb94e1ee37b72c\",\"host_policy_profile\":{\"capacity\":{\"max_aggregate_array_items\":1000,\"max_artifact_bytes\":1000,\"max_artifact_rows\":1000,\"max_effect_items\":1000,\"max_graph_input_edges\":1000,\"max_graph_input_nodes\":1000,\"max_graph_output_rows\":1000,\"max_graph_paths\":1000,\"max_infer_items\":1000,\"max_model_input_tokens_per_item\":1000,\"max_model_request_bytes_per_item\":1000,\"max_model_total_duration_ms\":1000,\"max_nested_value_bytes\":1000,\"max_nested_value_depth\":1000,\"max_relation_output_rows\":1000,\"max_temporal_matches_per_key\":1000,\"max_temporal_output_rows\":1000,\"version\":\"actql-capacity-host-policy/0.1\"}},\"mapping_contracts\":[],\"model_task_contracts\":[],\"schema_snapshots\":[{\"carrier_schema_contract_cid\":\"sha256:10398d9c513b4a315b624bd5a73efe5dfcfb864d427eb69052ff0d8b6f61212c\",\"data_classification\":\"unknown\",\"output_carrier\":\"relation\",\"read_mode\":\"snapshot\",\"source_contract_cid\":\"sha256:7a0eff89f9165ee7117c148fa649b501f0d20388a1ec39c52cf6b8597c73fa2b\",\"source_data_policy_cid\":\"sha256:cdb45d757a87e18dc32e486c33846b4c9dcad63c7f3bebcf8b31ca9b145e44ed\",\"source_ref\":\"connector://nearest_fixture/queries#records\",\"source_view_contract_cid\":\"sha256:7a0eff89f9165ee7117c148fa649b501f0d20388a1ec39c52cf6b8597c73fa2b\"},{\"carrier_schema_contract_cid\":\"sha256:7f4f0c0f4f011d8ca5039e3c8df7e52cd1a612a0478b126e160964135de2b9ec\",\"data_classification\":\"unknown\",\"output_carrier\":\"relation\",\"read_mode\":\"snapshot\",\"source_contract_cid\":\"sha256:b4015abcd0ef002cb5825df326b919e9ec9d20f5aa746c9029893deedad7777b\",\"source_data_policy_cid\":\"sha256:c75c4b00ed8cd95917d4dcad95b7203043bea3475af37b76ca23f688e3f555a1\",\"source_ref\":\"connector://nearest_fixture/candidates#records\",\"source_view_contract_cid\":\"sha256:b4015abcd0ef002cb5825df326b919e9ec9d20f5aa746c9029893deedad7777b\"}],\"source_views\":[{\"acquisition\":{\"authority\":\"read_content\",\"default_mode\":\"snapshot\",\"kind\":\"scan\",\"modes\":[{\"bounded\":true,\"mode\":\"snapshot\"}],\"request_schema\":{\"cid\":\"sha256:3d56d5b099a4b9a1a4d9b8133a962cb54a5ec7c711418c7179332b018968165d\",\"id\":\"nearest_fixture/queries/records/request\",\"version\":\"nearest_fixture/0.1\"}},\"connector_id\":\"nearest_fixture\",\"connector_version\":\"nearest_fixture/0.1\",\"contract_cid\":\"sha256:7a0eff89f9165ee7117c148fa649b501f0d20388a1ec39c52cf6b8597c73fa2b\",\"output\":{\"carrier\":\"relation\",\"data_policy\":{\"cid\":\"sha256:cdb45d757a87e18dc32e486c33846b4c9dcad63c7f3bebcf8b31ca9b145e44ed\",\"id\":\"nearest_fixture/queries/records/policy\",\"version\":\"nearest_fixture/0.1\"},\"facts\":{\"cid\":\"sha256:9ddece7324893957af2b888506eadad11b83c84eacce6e04a32d4488389ac444\",\"id\":\"nearest_fixture/queries/records/facts\",\"version\":\"nearest_fixture/0.1\"},\"schema\":{\"cid\":\"sha256:10398d9c513b4a315b624bd5a73efe5dfcfb864d427eb69052ff0d8b6f61212c\",\"id\":\"nearest_fixture/queries/records/row\",\"version\":\"nearest_fixture/0.1\"}},\"pushdown\":{\"contract\":{\"cid\":\"sha256:d93e6b605286afa5090f92ff4ae8fed0808c8d9c7e523e202e60ef85fa3fa83e\",\"id\":\"nearest_fixture/queries/records/pushdown\",\"version\":\"nearest_fixture/0.1\"},\"operations\":[\"projection\"]},\"request_processing\":{\"mutates_business_state\":false},\"resource_kind\":\"table\",\"schema\":\"actql.source_view/0.1\",\"view_id\":\"records\",\"view_version\":\"nearest_fixture/0.1\"},{\"acquisition\":{\"authority\":\"read_content\",\"default_mode\":\"snapshot\",\"kind\":\"scan\",\"modes\":[{\"bounded\":true,\"mode\":\"snapshot\"}],\"request_schema\":{\"cid\":\"sha256:aef963b149bb822850067091fd60c66192df949c797e86762150e69a764e8323\",\"id\":\"nearest_fixture/candidates/records/request\",\"version\":\"nearest_fixture/0.1\"}},\"connector_id\":\"nearest_fixture\",\"connector_version\":\"nearest_fixture/0.1\",\"contract_cid\":\"sha256:b4015abcd0ef002cb5825df326b919e9ec9d20f5aa746c9029893deedad7777b\",\"output\":{\"carrier\":\"relation\",\"data_policy\":{\"cid\":\"sha256:c75c4b00ed8cd95917d4dcad95b7203043bea3475af37b76ca23f688e3f555a1\",\"id\":\"nearest_fixture/candidates/records/policy\",\"version\":\"nearest_fixture/0.1\"},\"facts\":{\"cid\":\"sha256:25e9d7b4b5c97b807c32ad37482ac1f30a7a34bd983caa8f27d8db279085f858\",\"id\":\"nearest_fixture/candidates/records/facts\",\"version\":\"nearest_fixture/0.1\"},\"schema\":{\"cid\":\"sha256:7f4f0c0f4f011d8ca5039e3c8df7e52cd1a612a0478b126e160964135de2b9ec\",\"id\":\"nearest_fixture/candidates/records/row\",\"version\":\"nearest_fixture/0.1\"}},\"pushdown\":{\"contract\":{\"cid\":\"sha256:db537ee4846eed2810a398c330b1ad2e8912acb6a8f8e9e9ed308f2dd6d0fbb9\",\"id\":\"nearest_fixture/candidates/records/pushdown\",\"version\":\"nearest_fixture/0.1\"},\"operations\":[\"projection\"]},\"request_processing\":{\"mutates_business_state\":false},\"resource_kind\":\"table\",\"schema\":\"actql.source_view/0.1\",\"view_id\":\"records\",\"view_version\":\"nearest_fixture/0.1\"}],\"version\":\"actql-check-environment/0.1\"}"

///|
let nearest_failed_document : String = "{\"id\":\"adhoc.query\",\"results\":{\"answer\":{\"from\":{\"result\":\"rows\",\"stage\":\"main\"}}},\"stages\":[{\"id\":\"capture\",\"inputs\":{\"source_0\":{\"connector\":\"nearest_fixture\",\"resource\":\"queries\",\"view\":\"records\"}},\"results\":{\"source\":{\"fields\":[\"embedding\",\"note\",\"request_id\"],\"from\":\"aql_capture_0\"}},\"steps\":[{\"filter\":{\"literal\":true},\"from\":\"source_0\"},{\"as\":\"aql_capture_0\",\"select\":[\"embedding\",\"note\",\"request_id\"]}]},{\"id\":\"capture_1\",\"inputs\":{\"source_1\":{\"connector\":\"nearest_fixture\",\"resource\":\"candidates\",\"view\":\"records\"}},\"results\":{\"source\":{\"fields\":[\"embedding\",\"item_id\",\"label\"],\"from\":\"aql_capture_0\"}},\"steps\":[{\"filter\":{\"literal\":true},\"from\":\"source_1\"},{\"as\":\"aql_capture_0\",\"select\":[\"embedding\",\"item_id\",\"label\"]}]},{\"id\":\"main\",\"inputs\":{\"source_0\":{\"result\":{\"result\":\"source\",\"stage\":\"capture\"}},\"source_1\":{\"result\":{\"result\":\"source\",\"stage\":\"capture_1\"}}},\"results\":{\"rows\":{\"fields\":[\"note\",\"label\",\"neighbor\"],\"from\":\"aql_script_result\"}},\"steps\":[{\"as\":\"aql_nearest_queries_0_2\",\"from\":\"source_0\",\"select\":[\"embedding\",\"note\",\"request_id\"]},{\"as\":\"aql_nearest_candidates_0_3\",\"from\":\"source_1\",\"select\":[\"embedding\",\"item_id\",\"label\"]},{\"as\":\"aql_nearest_query_vectors_0_4\",\"from\":\"aql_nearest_queries_0_2\",\"to_vectors\":{\"id\":\"request_id\",\"vector\":\"embedding\"}},{\"as\":\"aql_nearest_candidate_vectors_0_5\",\"from\":\"aql_nearest_candidates_0_3\",\"to_vectors\":{\"id\":\"item_id\",\"vector\":\"embedding\"}},{\"from\":\"aql_nearest_candidate_vectors_0_5\",\"nearest\":{\"k\":2,\"metric\":\"dot\",\"queries\":\"aql_nearest_query_vectors_0_4\"}},{\"derive\":{\"aql_nearest_key_7\":{\"field\":\"query_id\"},\"aql_nearest_key_8\":{\"field\":\"candidate_id\"}}},{\"join\":{\"cardinality\":\"many_to_one\",\"kind\":\"inner\",\"on\":[{\"left\":\"aql_nearest_key_7\",\"right\":\"request_id\"}],\"select\":{\"aql_nearest_keep_9\":\"right.note\",\"aql_nearest_key_7\":\"left.aql_nearest_key_7\",\"aql_nearest_key_8\":\"left.aql_nearest_key_8\",\"candidate_id\":\"left.candidate_id\",\"query_id\":\"left.query_id\",\"rank\":\"left.rank\",\"score\":\"left.score\"},\"with\":\"aql_nearest_queries_0_2\"}},{\"join\":{\"cardinality\":\"many_to_one\",\"kind\":\"inner\",\"on\":[{\"left\":\"aql_nearest_key_8\",\"right\":\"item_id\"}],\"select\":{\"aql_nearest_keep_10\":\"right.label\",\"aql_nearest_keep_9\":\"left.aql_nearest_keep_9\",\"aql_nearest_key_7\":\"left.aql_nearest_key_7\",\"aql_nearest_key_8\":\"left.aql_nearest_key_8\",\"candidate_id\":\"left.candidate_id\",\"query_id\":\"left.query_id\",\"rank\":\"left.rank\",\"score\":\"left.score\"},\"with\":\"aql_nearest_candidates_0_3\"}},{\"derive\":{\"aql_nearest_result_11\":{\"object\":{\"candidate_key\":{\"object\":{\"item_id\":{\"field\":\"aql_nearest_key_8\"}}},\"query_key\":{\"object\":{\"request_id\":{\"field\":\"aql_nearest_key_7\"}}},\"rank\":{\"field\":\"rank\"},\"score\":{\"field\":\"score\"}}}}},{\"select\":[{\"note\":\"aql_nearest_keep_9\"},{\"label\":\"aql_nearest_keep_10\"},{\"neighbor\":\"aql_nearest_result_11\"}]},{\"derive\":{\"aql_pipe_sort_6\":{\"property\":{\"name\":\"rank\",\"value\":{\"field\":\"neighbor\"}}}}},{\"sort\":[{\"dir\":\"asc\",\"field\":\"aql_pipe_sort_6\",\"nulls\":\"first\"}]},{\"as\":\"aql_script_result\",\"select\":[\"note\",\"label\",\"neighbor\"]}]}],\"version\":\"actql/0.1\"}"

///|
test "original installed nearest Host capacity is derived from its checked tasks" {
  let source_contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let prepared = nearest_failed_prepared()
  let sequences = prepare_client_local_sequences(
    prepared,
    source_contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let count = @strategy.graph_task_count(
    @publication_host.prepared_client_graph(prepared),
  )
  assert_eq(count, 15)
  let (_, execution, measurement) = client_local_execution_limits(
    max_rows=@publication_host.prepared_client_values_max_rows(prepared),
  )
  let compute = []
  let mut total = 0L
  for task in 2..<count {
    compute.push(sequences[task])
    let capacity = @execution.generated_sequence_capacity(
      sequences[task],
      execution,
      measurement,
    ).unwrap()
    let retained = @execution.execution_capacity_retained_bytes(capacity)
    let executing = @execution.execution_capacity_execution_bytes(capacity)
    println(
      "NEAREST_CAPACITY task=\{task} retained=\{retained} execution=\{executing}",
    )
    total += retained
  }
  println("NEAREST_CAPACITY total_retained=\{total}")
  assert_true(
    client_local_sequence_capacity(
      compute,
      count,
      max_rows=@publication_host.prepared_client_values_max_rows(prepared),
    )
    is Some(_),
  )
}

///|
fn nearest_failed_prepared() -> @publication_host.PreparedClientProgram {
  let environment = @publication_host.admit_client_check_environment(
    nearest_failed_environment,
    "sha256:ed5b4c7bac73a5a615474043ce88e0dd766deba32f8fca9110bb94e1ee37b72c",
    { text_time: false, veca: true, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let prepared = @publication_host.prepare_effect_free_client_program(
    nearest_failed_document,
    Json,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  prepared
}

///|
test "original installed nearest captures retain their exact graph and Host owner" {
  nearest_failed_capture_fixture()
}

///|
test "original nearest one-short transfer allowance remains a typed refusal" {
  nearest_failed_capture_fixture(historical_budget=true)
}

///|
fn nearest_failed_capture_fixture(
  historical_budget? : Bool = false,
) -> Unit raise {
  let source_contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let prepared = nearest_failed_prepared()
  let declaration = @row_source_host.restore_relation_row_declaration(
    "nearest_fixture",
    "nearest_fixture",
    "nearest_fixture/0.1",
    "{\"views\":[{\"resource\":\"queries\",\"resource_kind\":\"table\",\"schema_wire\":\"{\\\"embedding\\\":{\\\"dimensions\\\":2,\\\"element_type\\\":\\\"f32\\\",\\\"nullable\\\":false,\\\"type\\\":\\\"vector\\\"},\\\"note\\\":{\\\"nullable\\\":true,\\\"type\\\":\\\"string\\\"},\\\"request_id\\\":{\\\"nullable\\\":false,\\\"type\\\":\\\"string\\\"}}\",\"schema_cid\":\"sha256:561dfd2407116f43ed07dbe940c571e4fea7779fa0e6dda1bf079d8f986c02a5\",\"facts_wire\":\"{\\\"relation_keys\\\":{\\\"candidate_keys\\\":[[\\\"request_id\\\"]]}}\"},{\"resource\":\"candidates\",\"resource_kind\":\"table\",\"schema_wire\":\"{\\\"embedding\\\":{\\\"dimensions\\\":2,\\\"element_type\\\":\\\"f32\\\",\\\"nullable\\\":false,\\\"type\\\":\\\"vector\\\"},\\\"item_id\\\":{\\\"nullable\\\":false,\\\"type\\\":\\\"string\\\"},\\\"label\\\":{\\\"nullable\\\":false,\\\"type\\\":\\\"string\\\"}}\",\"schema_cid\":\"sha256:c58169521c543e83af21aed505d1f304fef1496c5e427295f905f797d69a349b\",\"facts_wire\":\"{\\\"relation_keys\\\":{\\\"candidate_keys\\\":[[\\\"item_id\\\"]]}}\"}]}",
    None,
  ).unwrap()
  let acquisitions = Array::makei(2, task => {
    let requirement = prepare_local_query_requirement(
      prepared,
      task,
      0,
      source_contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
    ).unwrap()
    @row_source_host.prepare_row_acquisition(
      declaration, requirement, original_row_query_contract_fixture, original_row_evidence_contract_fixture,
    ).unwrap()
  })
  let capacities = acquisitions.map(acquisition => {
    installed_row_capture_capacity(acquisition).unwrap()
  })
  let ledger = prepare_multi_captured_local_installed_ledger(
    prepared,
    capacities,
    [4096L, 4096L],
    [4096L, 4096L],
    source_contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let graph = @publication_host.prepared_client_graph(prepared)
  assert_eq(@strategy.graph_task_count(graph), 15)
  assert_eq(@strategy.graph_captured_prefix(graph), 2)
  let ledger = if historical_budget {
    // Sixteen receiving ports minus two direct Carrier views and one already
    // captured cell-access input leave thirteen row-wire imports. A one-byte
    // short allowance must still refuse; all other dimensions match success.
    @resources.create_ledger({
      ..@resources.ledger_admission_limits(ledger),
      transfer_bytes: 13L * 1000000L - 1L,
    }).unwrap()
  } else {
    ledger
  }
  // Sixteen declared receiving ports, each with the existing one-million-byte
  // wire envelope, plus the two original 4096-byte acquisition allowances.
  assert_eq(
    @resources.ledger_admission_limits(ledger).transfer_bytes,
    if historical_budget {
      13L * 1000000L - 1L
    } else {
      16008192L
    },
  )
  let bodies = [
    "[{\"request_id\":\"q1\",\"embedding\":[1,0],\"note\":null}]", "[{\"item_id\":\"b\",\"embedding\":[0,1],\"label\":\"second\"},{\"item_id\":\"a\",\"embedding\":[1,0],\"label\":\"first\"}]",
  ]
  let runs = []
  let sources = []
  for task in 0..<2 {
    let run = @row_source_host.start_accounted_row_acquisition(
      acquisitions[task],
      "nearest-component-\{task}",
      _ => true,
      ledger,
      4096L,
      4096L,
    ).unwrap()
    runs.push(run)
    @row_source_host.begin_row_run(run, 4096, 3, 3).unwrap()
    let bytes = @utf8.encode(bodies[task])
    let charge = @row_source_host.charge_row_run_page(run, bytes).unwrap()
    @row_source_host.accept_charged_row_run_page(run, charge, bytes).unwrap()
    |> ignore
    @row_source_host.finish_row_run(run).unwrap()
    @row_source_host.begin_row_capture(run).unwrap()
    let mut complete = false
    for _ in 0..<10000 {
      if @row_source_host.advance_row_capture(run, 256).unwrap().0 {
        complete = true
        break
      }
    }
    assert_true(complete)
    let capture = @row_source_host.capture_row_run(run).unwrap()
    sources.push((task, @row_source_host.row_capture_source(capture).unwrap()))
  }
  let dag = match @strategy.open_multi_captured_dag(graph, sources, ledger) {
    Ok(run) => run
    Err(ForeignCapture) => fail("original installed nearest ForeignCapture")
    Err(UnsupportedGraph) => fail("original installed nearest UnsupportedGraph")
    Err(_) => fail("original installed nearest other graph opening refusal")
  }
  assert_eq(@strategy.graph_task_count(graph), 15)
  nearest_failed_offer_boundary(dag, prepared, historical_budget)
  @strategy.stop_captured_dag(dag)
  @strategy.refresh_captured_retention(dag)
  for run in runs {
    @row_source_host.close_accounted_row_run(run).unwrap()
  }
}

///|
fn nearest_failed_offer_boundary(
  run : @strategy.CapturedDAG,
  prepared : @publication_host.PreparedClientProgram,
  historical_budget : Bool,
) -> Unit raise {
  let source_contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let all = prepare_client_local_sequences(
    prepared,
    source_contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let compute = []
  for task in 2..<all.length() {
    compute.push(all[task])
  }
  let max_rows = @publication_host.prepared_client_values_max_rows(prepared)
  let (values, execution, measurement) = client_local_execution_limits(
    max_rows~,
  )
  let (_, retained, executing) = client_local_sequence_capacity(
    compute,
    all.length(),
    max_rows~,
  ).unwrap()
  // Exact existing selected Node VecA profile, not a new implementation limit.
  let provider = @nearest_provider.provider(
    {
      max_input_records: 100,
      max_records: 100,
      max_fields_per_record: 100,
      max_value_bytes: 10000,
      max_total_value_bytes: 100000,
      max_retained_value_bytes: 100000,
      max_value_nodes: 10000,
      max_value_depth: 100,
      max_contract_work: 10000,
      max_work: 100000,
      max_workspace_slots: 10000,
    },
    100000L,
    @execution.execution_capacity(retained, executing).unwrap(),
  )
  let capacity : @connector.FixedComputeCapacity = {
    contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
    max_rows,
    max_value_bytes: 10000,
    common_fragment: None,
  }
  let configuration : @local_driver.LocalComputeConfiguration = {
    sequences: compute,
    managed_providers: [provider],
    managed_capacity: capacity,
    execution,
    measurement,
    max_work: 100,
  }
  let bundle : @connector.CapabilityBundle[
    Unit,
    @local_driver.LocalComputeConfiguration,
    Unit,
  ] = {
    name: "local",
    acquisition: None,
    fixed_compute: Some((_, _) => configuration),
    effect: None,
  }
  let bundles = @connector.install_bundles([bundle], 1, 100).unwrap()
  let registry = @connector.installed_bundle_registry(bundles)
  let registration = @connector.capability_registration_at(registry, 0).unwrap()
  let installed = @local_driver.configure_local_compute(
    @host_driver.open_dispatch_driver(run),
    registry,
    registration,
    configuration,
  ).unwrap()
  @local_driver.configure_local_retained_inputs(
    installed,
    client_local_import_limits(capacity, values),
    Some(0L),
  ).unwrap()
  let slots = @local_driver.local_dispatch_work_slots()
  let schedule = @cost.prepare_rate_schedule(
    slots,
    [
      {
        work_slots: Array::makei(slots, i => i),
        fixed_ms: Some(1L),
        per_row_ms: Some(0L),
        per_wire_byte_ms: Some(0L),
        per_pair_ms: Some(0L),
      },
    ],
    100,
  ).unwrap()
  let estimates = @local_driver.prepare_local_estimate_module(
    installed,
    Array::make(compute.length(), schedule),
    1000,
  ).unwrap()
  @local_driver.install_local_dispatch_estimates(installed, estimates).unwrap()
  let offers = []
  for task in 2..<all.length() {
    let proposed = match
      @local_driver.estimate_local_installed_offers(installed, task, {
        rows: None,
        wire_bytes: None,
        pairs: None,
      }) {
      Ok(value) => value
      Err(_) => fail("original nearest offer estimation rejected task \{task}")
    }
    println("NEAREST_OFFERS task=\{task} count=\{proposed.length()}")
    if proposed.is_empty() {
      fail("original nearest task \{task} has no installed offer")
    }
    for offer in proposed {
      offers.push(offer)
    }
  }
  @strategy.configure_strategy_search(run, {
    max_offers: 100,
    max_strategies: 100,
    max_work: 10000,
    max_revisions: 100,
  }).unwrap()
  let choice = @strategy.prepare_strategy_choices(run, offers, registry, None).unwrap()
  let decision = @strategy.commit_strategy_choice(choice, None)
  let budget = @resources.ledger_admission_limits(
    @strategy.captured_dag_ledger(run),
  )
  println(
    "NEAREST_STRATEGY budget_retained=\{budget.retained_bytes} budget_execution=\{budget.execution_bytes} budget_transfer=\{budget.transfer_bytes}",
  )
  assert_eq(@strategy.strategy_report_count(run), 1)
  for index in 0..<@strategy.strategy_report_count(run) {
    let report = @strategy.strategy_report_at(run, index).unwrap()
    println(
      "NEAREST_STRATEGY retained=\{report.retained_bytes} execution=\{report.execution_bytes} transfer=\{report.transfer_bytes}",
    )
    if report.rejection is Some(@resources.RetentionLimit) {
      fail("original nearest strategy RetentionLimit")
    }
    if report.rejection is Some(@resources.ExecutionLimit) {
      fail("original nearest strategy ExecutionLimit")
    }
    // The two nearest Carrier views and the first ready captured cell-access
    // input retain their originals without opening row-wire importers.
    assert_eq(report.transfer_bytes, (16L - 2L - 1L) * 1000000L)
    if historical_budget {
      assert_true(report.rejection is Some(@resources.TransferLimit))
    } else {
      assert_true(report.rejection is None)
    }
  }
  if historical_budget {
    assert_true(decision is Ok(@strategy.NoFeasible))
  } else {
    assert_true(decision is Ok(@strategy.Selected(_)))
  }
}
