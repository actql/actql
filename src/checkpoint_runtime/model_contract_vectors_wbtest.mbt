///|
// Expected bodies/CIDs are copied from the independent contract corpus
// portability/corpus/model-invocation-scope.json, not product issuance.
// These have synthetic dependency references and prove wire identity only.
test "Model independent contract corpus remains admitted without rewriting identities" {
  {
    let value = @publication.seal_run_evidence_value(
      "model_provider_binding", "{\"configuration_cid\":\"sha256:75c49612c249b1399ff18ad510a39cfc03ec7900c1a3b04ac2817c51839db33d\",\"configuration_contract_cid\":\"sha256:600b139f6f19e15554b0987004b384b58a9bc6c1e08fe3228bbc63c678804bf2\",\"installation_revision_cid\":\"sha256:5efaaa99bf5823004d28451dfa6800c784abe35f59af4edc6d00e8e069838846\",\"provider_id\":\"models/fixture\",\"version\":\"actql-model-provider-binding/0.1\"}",
      262144, 4096, 32,
    ).unwrap()
    assert_eq(
      @publication.run_evidence_value_identity(value),
      "sha256:351728aba495e031d1618366e0681a679f68a360156272fa2fd50d2fe52e03ce",
    )
  }
  {
    let value = @publication.seal_run_evidence_value(
      "model_invocation_scope", "{\"authorization_context\":{\"account_id\":\"fixture-account\",\"boundary\":\"activation\",\"configuration_cid\":\"sha256:6900f0c0b682fa4cfb739262dd1e338f64dd549affea09e83f9a33351e8648d6\",\"connection\":\"models/fixture\",\"context_cid\":\"sha256:34f3f190fba96dbdc832b407409412b7d2dc0da5a4e6e6cb001dfff7a32ceaf8\",\"entry_id\":\"delegate-model\",\"operation\":\"infer\",\"principal\":\"fixture-principal\",\"resource\":\"sha256:ddd7f99f9434d917eb3fc8260ad0efd2246631a938f8fe5581ea29d6abba9863\"},\"inference_barrier_cid\":\"sha256:7797e0c349baf2ea0df4db83803599fd14bd0bb9e5bf26c537105b3ca154a23b\",\"input_artifact_cid\":\"sha256:491e83d2d595bea22a0416af21bfd97d8560b74acbe968636212d9026daf9215\",\"model_call_slot_cids\":[\"sha256:c073e9701df23e7dd86aabff3656cb2ee38fcbd249a5789fb3dae1be61fa634e\",\"sha256:bb24e5b7df44cef176992d8a3a738a945fddddc7e0ef5bdf3416a244d2595e31\",\"sha256:6267265659a2cc889a2a1c7e145c89b369b59df7cc554238a6d3ad44c59697fe\"],\"provider_binding_cid\":\"sha256:351728aba495e031d1618366e0681a679f68a360156272fa2fd50d2fe52e03ce\",\"run_definition_cid\":\"sha256:ae6fd23f993ecb1f0bddcd1d8f9bc658343426e82c0855d782a000203c68118d\",\"strategy_revision\":0,\"task_index\":2,\"version\":\"actql-model-invocation-scope/0.1\"}",
      262144, 4096, 32,
    ).unwrap()
    assert_eq(
      @publication.run_evidence_value_identity(value),
      "sha256:1882726121931825201f65beffcc6ed3ed14574bb30680f7cc3dca4aa27f44ad",
    )
  }
  {
    let value = @publication.seal_run_evidence_value(
      "run_review_projection", "{\"approval_claims\":[\"invocation_scope_approved\"],\"authoring_context_cid\":\"sha256:cf990635e185255e65c47c7a2dde0ab8257167493fc1f789f8a8233fd05aa288\",\"displayed_authoring_context\":[],\"displayed_scope\":{\"model_call_slot_cids\":[\"sha256:c073e9701df23e7dd86aabff3656cb2ee38fcbd249a5789fb3dae1be61fa634e\",\"sha256:bb24e5b7df44cef176992d8a3a738a945fddddc7e0ef5bdf3416a244d2595e31\",\"sha256:6267265659a2cc889a2a1c7e145c89b369b59df7cc554238a6d3ad44c59697fe\"],\"model_invocation_scope_cid\":\"sha256:1882726121931825201f65beffcc6ed3ed14574bb30680f7cc3dca4aa27f44ad\"},\"encryption_required\":true,\"execution_context_cid\":\"sha256:54d45990b023cad6ba2de6864f31fb152617f47e8b8a119b98b8b062f32a6cbf\",\"expires_at\":\"2026-10-04T01:00:00.000Z\",\"host_policy_cid\":\"sha256:428f63c1044e9899d9acedadf0339fac35139b8c5be1ea2da8d702cc8af66e34\",\"prepared_invocation_cid\":\"sha256:0a27cd8062281f315918bb5cf1706ebceea575eb0689fb2a6efd7f0e4e6df92e\",\"redaction_policy_cid\":\"sha256:e7cc76da9a14c14b88355a593896174fb37648c1878d8bba49d1aee4099ca80b\",\"retention_class\":\"approval-evidence\",\"sensitivity\":\"restricted\",\"version\":\"actql-run-review-projection/0.1\"}",
      262144, 4096, 32,
    ).unwrap()
    assert_eq(
      @publication.run_evidence_value_identity(value),
      "sha256:995841854018ffca5048146fdeaffb0cae985964e32fdf41db57183a1724372c",
    )
  }
  let value = @publication.seal_run_evidence_value(
    "model_dispatch_authority", "{\"account_configuration_cid\":\"sha256:6900f0c0b682fa4cfb739262dd1e338f64dd549affea09e83f9a33351e8648d6\",\"answering_authority\":\"fixture-reviewer\",\"basis\":\"host_permit\",\"connection\":\"models/fixture\",\"entry_id\":\"delegate-model\",\"execution_context_cid\":\"sha256:54d45990b023cad6ba2de6864f31fb152617f47e8b8a119b98b8b062f32a6cbf\",\"fixed_request_cid\":\"sha256:e79e07d1ea99f34a9e8549c0b7dcf403d964d05b8ef2e3c6b5522592ed206148\",\"host_policy_cid\":\"sha256:428f63c1044e9899d9acedadf0339fac35139b8c5be1ea2da8d702cc8af66e34\",\"model_task_cid\":\"sha256:ddd7f99f9434d917eb3fc8260ad0efd2246631a938f8fe5581ea29d6abba9863\",\"operation\":\"infer\",\"principal\":\"fixture-principal\",\"program_definition_cid\":\"sha256:2c6cba9e3bf727960faf974f4326beb1f99cc1a05f04e1e581d4342b4e6b5880\",\"resource\":\"sha256:ddd7f99f9434d917eb3fc8260ad0efd2246631a938f8fe5581ea29d6abba9863\",\"run_authorization_cid\":\"sha256:5c2535cee3ef88706dadf3c9ff1bd582120874c0bc9afd68e554467410b322ed\",\"run_definition_cid\":\"sha256:ae6fd23f993ecb1f0bddcd1d8f9bc658343426e82c0855d782a000203c68118d\",\"satisfied_claims\":[\"invocation_scope_approved\"],\"version\":\"actql-model-dispatch-authority/0.1\"}",
    262144, 4096, 32,
  ).unwrap()
  assert_eq(
    @publication.run_evidence_value_identity(value),
    "sha256:91b78c7cce29a1328b4c9bcc117065d7e76ebafdf3c782017f3c8dcf92d7eedc",
  )
}
