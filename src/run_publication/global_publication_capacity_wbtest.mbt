///|
test "receipt shared emitter preserves persisted pre-refactor canonical wire and identity" {
  let wire = "{\"aoa_ir_version\":\"aoa-pipeline:0.1\",\"aoa_logical_cid\":\"sha256:ece2c8af56332f35cdf01e6a8253a6ff7dd0e0600c540fd8210b4dfffb2c1db9\",\"artifact_derivation_evidence_cids\":[\"sha256:8d26967c6558384ffba36e9063f8099d3b3ea63393f1750aa096f8268e98748e\"],\"barrier_attempt_receipt_cids\":[],\"bindings\":[],\"check_environment_cid\":\"sha256:eb8e7c5c88992c22583dacdb6d6a43a1bb5c9e0bfdc9ef1956dafbe6ebbd0d4a\",\"compiled_plan_cid\":\"sha256:ad73eb40b0082a55e35395c48af4ceb7c69a4d19c1faf43290ab0ef20e964967\",\"compiler_version\":\"actql-moonbit-0.0.1\",\"cross_source_consistency\":\"no_external_sources\",\"external_observation_evidence\":[],\"invocation_cid\":\"sha256:0809db692571ca1e7fa73c04add20a68d5f07df67b661ca5fbb069eaaa26046f\",\"normalization_journal_cid\":\"sha256:fb626f1daace6be17858cc65092be9fa3620b1fe1e4025df4eebc44c4f068862\",\"observation_set\":{\"capture_completed_at\":null,\"capture_started_at\":null,\"captured_input_artifact_cids\":[],\"consistency\":\"no_external_sources\",\"data_policy_cid\":\"sha256:41f57b048c92be9aca49527b69f129a2b2e6ddebb494c5fd498b9a4ebb70f6f1\",\"invocation_template_cid\":\"sha256:c9c38d39effa943592c73f1d05b0ba27711b06ab32447bdce49c562f839d82ca\",\"observation_set_cid\":\"sha256:16879a85ed8bcf9c8c7778c3e56afc20760a9279362e9efce91bc8d9407654de\",\"replayability\":{\"availability_evidence_cids\":[],\"materialized\":false},\"source_evidence_cids\":[],\"version\":\"actql-observation-set/0.1\"},\"observation_set_cid\":\"sha256:16879a85ed8bcf9c8c7778c3e56afc20760a9279362e9efce91bc8d9407654de\",\"prepared_invocation\":{\"compiled_plan_cid\":\"sha256:ad73eb40b0082a55e35395c48af4ceb7c69a4d19c1faf43290ab0ef20e964967\",\"execution_context_cid\":\"sha256:797647a21b1663f0463942e9876f5055b9622d16dc0b3cd684c21c385d8386f9\",\"expires_at\":\"2026-10-25T03:49:58.644Z\",\"host_policy_cid\":\"sha256:2a787ad72e33a9c5f5932f7678ee43f2e9778408ca42055cd121244688ffca9f\",\"invocation_template_cid\":\"sha256:c9c38d39effa943592c73f1d05b0ba27711b06ab32447bdce49c562f839d82ca\",\"policy_decision\":\"allow\",\"prepared_invocation_cid\":\"sha256:6bf913cdaf2e1e77de05ffdfe4a6c0ceedbd7e8c5432c0f94da39919287d65ab\",\"version\":\"actql-prepared-invocation/0.1\"},\"program_definition_cid\":\"sha256:7e52bc59289e0acc36e6444e3c7376a843827564b90ee0978b559a863db4f314\",\"program_semantics_cid\":\"sha256:7c664053212b3dd07d9c7b90931f9d4207079b592c3c9196916e5dc353d5a411\",\"receipt_identity_cid\":\"sha256:38ef8e61618877809d768319f242541d271b7ad69bf0e7b6cbd0479a2c6eff55\",\"result_artifacts\":{\"r0\":{\"actual_completeness\":\"complete\",\"actual_row_count\":1,\"effective_data_policy_cid\":\"sha256:41f57b048c92be9aca49527b69f129a2b2e6ddebb494c5fd498b9a4ebb70f6f1\",\"effective_retention_policy_cid\":\"sha256:e76b11419f23e615949d848ffa3b55f0b6e50aad38c28de337fee9b08029aa54\",\"invocation_cid\":\"sha256:0809db692571ca1e7fa73c04add20a68d5f07df67b661ca5fbb069eaaa26046f\",\"logical_result_cid\":\"sha256:537d1ecf4f3090820792a12473d114f7ac3ad72dda879c8e90f6c23753faf2e9\",\"ordering_evidence_cid\":\"sha256:513b99431a8bfcdebf0b0485aea64965d53af7c792e2744e85f332b1026e4347\",\"provenance_evidence_cids\":[\"sha256:8d26967c6558384ffba36e9063f8099d3b3ea63393f1750aa096f8268e98748e\"],\"result_artifact_cid\":\"sha256:06fbdc9e1089c01bb2251083143aa9e9480e3e8d2bd4fed4df8450edb8950690\",\"result_definition_cid\":\"sha256:26da9f4830c56a8002ff857696ca8403911b360c3b3e925826328fea22acfe02\",\"result_schema_cid\":\"sha256:d06123b726fa93d892fd927f82aaf759104e28ede96016fcc7336f1bcc7583ea\",\"version\":\"actql-result-artifact/0.1\"}},\"result_manifest\":{\"invocation_cid\":\"sha256:0809db692571ca1e7fa73c04add20a68d5f07df67b661ca5fbb069eaaa26046f\",\"result_manifest_cid\":\"sha256:c04014af6f79579f547b99098fd8a2340bf3d80079603635fc0ca8c5ecb10b22\",\"results\":{\"r0\":{\"actual_completeness\":\"complete\",\"actual_row_count\":1,\"effective_data_policy_cid\":\"sha256:41f57b048c92be9aca49527b69f129a2b2e6ddebb494c5fd498b9a4ebb70f6f1\",\"effective_retention_policy_cid\":\"sha256:e76b11419f23e615949d848ffa3b55f0b6e50aad38c28de337fee9b08029aa54\",\"invocation_cid\":\"sha256:0809db692571ca1e7fa73c04add20a68d5f07df67b661ca5fbb069eaaa26046f\",\"logical_result_cid\":\"sha256:537d1ecf4f3090820792a12473d114f7ac3ad72dda879c8e90f6c23753faf2e9\",\"ordering_evidence_cid\":\"sha256:513b99431a8bfcdebf0b0485aea64965d53af7c792e2744e85f332b1026e4347\",\"provenance_evidence_cids\":[\"sha256:8d26967c6558384ffba36e9063f8099d3b3ea63393f1750aa096f8268e98748e\"],\"result_artifact_cid\":\"sha256:06fbdc9e1089c01bb2251083143aa9e9480e3e8d2bd4fed4df8450edb8950690\",\"result_definition_cid\":\"sha256:26da9f4830c56a8002ff857696ca8403911b360c3b3e925826328fea22acfe02\",\"result_schema_cid\":\"sha256:d06123b726fa93d892fd927f82aaf759104e28ede96016fcc7336f1bcc7583ea\",\"version\":\"actql-result-artifact/0.1\"}},\"run_definition_cid\":\"sha256:aad54414df2ed7a34791533f8fd55434487f88a4846456f38eb800faa92d1e92\",\"version\":\"actql-result-manifest/0.1\"},\"result_manifest_cid\":\"sha256:c04014af6f79579f547b99098fd8a2340bf3d80079603635fc0ca8c5ecb10b22\",\"run_authorization\":{\"decision\":\"allowed\",\"execution_context_cid\":\"sha256:797647a21b1663f0463942e9876f5055b9622d16dc0b3cd684c21c385d8386f9\",\"host_policy_cid\":\"sha256:2a787ad72e33a9c5f5932f7678ee43f2e9778408ca42055cd121244688ffca9f\",\"prepared_invocation_cid\":\"sha256:6bf913cdaf2e1e77de05ffdfe4a6c0ceedbd7e8c5432c0f94da39919287d65ab\",\"run_authorization_cid\":\"sha256:6539132c4049afda827b174fcad9ed1d8ac2cc016a77f3f94c59b6985eb8ca46\",\"version\":\"actql-run-authorization/0.1\"},\"source_evidence\":[],\"source_evidence_cids\":[],\"version\":\"actql-run-receipt/0.1\"}"
  let original = admit_publication_contract(
    "run_receipt", wire, 1000000, 100000, 100,
  ).unwrap()
  let value = original.value
  let text = (name : String) => contract_string(original, name).unwrap()
  let field = (name : String) => @json.object_field(value, name).unwrap()
  let derivations = evidence_string_array(
    field("artifact_derivation_evidence_cids"),
  ).unwrap()
  let barriers = evidence_string_array(field("barrier_attempt_receipt_cids")).unwrap()
  let sources = evidence_string_array(field("source_evidence_cids")).unwrap()
  // The captured pre-refactor ordinary fixture has no external evidence or bindings.
  let writer = @encode.writer(1000000, 100000, 100)
  emit_effect_free_run_receipt_body(
    text("aoa_ir_version"),
    text("aoa_logical_cid"),
    derivations.length(),
    index => derivations[index],
    barriers,
    [],
    text("check_environment_cid"),
    text("compiled_plan_cid"),
    text("compiler_version"),
    text("cross_source_consistency"),
    [],
    [],
    sources,
    text("invocation_cid"),
    text("normalization_journal_cid"),
    field("observation_set"),
    text("observation_set_cid"),
    field("prepared_invocation"),
    text("program_definition_cid"),
    text("program_semantics_cid"),
    Some(field("result_artifacts")),
    Some(field("result_manifest")),
    text("result_manifest_cid"),
    field("run_authorization"),
    [],
    writer,
  )
  let actual = finish_publication_body(
    "run_receipt", writer, 1000000, 100000, 100,
  ).unwrap()
  assert_eq(actual.wire, original.wire)
  assert_eq(actual.identity, original.identity)
}
