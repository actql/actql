///|
// Authored two-row input from scripts/fixtures/effect-file-operation-vectors.mjs.
// Pure immutable-key projection only; no Host, Account, signer or IO is admitted.
test "Native retained application keys follow execution order without reissuing originals" {
  let (request, _, _, _) = journal_test_run(
    "key-projection", "key-projection-run",
  )
  let scope = @host.client_request_logical_scope(request)
  let wire = "{\"authoring_context\":{\"annotations\":[],\"authoring_context_cid\":\"sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a\",\"program_definition_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-authoring-context/0.1\"},\"barrier_provenance_cids\":[],\"check_environment_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"effect_preview_cid\":\"sha256:852e6a4986a8522861a48db32e78de8cb704dcac25c89f3ad29c8fd6a56e6558\",\"effects\":[{\"approval\":\"required\",\"authority_scope_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"capability_evidence_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"changes\":[{\"after\":{\"state\":\"present\",\"value\":{\"id\":\"B\",\"value\":2}},\"before\":{\"state\":\"present\",\"value\":{\"id\":\"B\",\"value\":1}},\"intended_changes\":{\"state\":\"present\",\"value\":{\"value\":2}},\"row_idempotency_key\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"row_preview_cid\":\"sha256:0426447180fcebf4aa8c57983b23050b177e74be6eabf33d1bdf07408cab5a50\",\"target_guard\":{\"state\":\"version\",\"version_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"target_row_identity\":\"B\"},{\"after\":{\"state\":\"present\",\"value\":{\"id\":\"A\",\"value\":2}},\"before\":{\"state\":\"present\",\"value\":{\"id\":\"A\",\"value\":1}},\"intended_changes\":{\"state\":\"present\",\"value\":{\"value\":2}},\"row_idempotency_key\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"row_preview_cid\":\"sha256:2bb1bd032e4791127080a468bbca5dc144371bcdfe39efe0bfc44132a8d7f7ac\",\"target_guard\":{\"state\":\"version\",\"version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"target_row_identity\":\"A\"}],\"count\":2,\"effect_id\":\"WriteOne\",\"effect_identity_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"effect_kind\":\"update\",\"effect_member_preview_cid\":\"sha256:cd630afef85de308b8afd88f9fe2bedb737f4115ac1481437882a7e00b067cf9\",\"executed\":false,\"mapping\":\"mapping:fixture\",\"max_items\":2,\"on_item_failure\":\"halt\",\"preview_strength\":\"full_diff\",\"required_permissions\":[\"write\"],\"resolved_mapping_contract_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"row_order\":[\"sha256:2bb1bd032e4791127080a468bbca5dc144371bcdfe39efe0bfc44132a8d7f7ac\",\"sha256:0426447180fcebf4aa8c57983b23050b177e74be6eabf33d1bdf07408cab5a50\"],\"source_binding_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"target\":\"Object\",\"write_footprint\":{\"kind\":\"exact_targets\",\"provider_boundary_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"provider_namespace\":\"fixture\",\"provider_object_identity_cids\":[\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\"],\"resource_identity_scheme_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"resource_kind\":\"file\"}}],\"encryption_required\":true,\"executed\":false,\"invocation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"model_derived\":false,\"model_invocation_evidence_cids\":[],\"model_response_artifact_cids\":[],\"model_task_contract_cids\":[],\"program_definition_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"program_semantics_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"retention_class\":\"authority-evidence\",\"run_identity_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"sensitivity\":\"private\",\"version\":\"actql-effect-preview/0.1\"}"
  let initial = @publication.admit_effect_preview_identity(
    wire, "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a", 20000,
    512, 32,
  ).unwrap()
  let raw_keys = ["\"B\"", "\"A\""].map(correlation => {
    @effect.prepare_effect_dispatch_key(
      scope,
      @publication.effect_preview_semantic_identity(initial),
      correlation,
      256,
      32,
      8,
    ).unwrap()
  })
  let completed = @publication.complete_effect_preview_dispatch_keys(
    wire,
    [raw_keys.map(key => key.cid)],
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a",
    20000,
    512,
    32,
  ).unwrap()
  let preview = @effect.admit_effect_preview_apply_identity(
    completed,
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a",
    scope,
    [raw_keys],
    20000,
    512,
    32,
  ).unwrap()
  let retained = @effect.recover_effect_preview_apply_keys(
    preview, scope, 1, 2, 1000, 256, 32, 8,
  ).unwrap()
  assert_eq(
    @publication.effect_preview_row_correlation_wire(preview, 0, 0),
    Some("\"B\""),
  )
  assert_eq(
    @publication.effect_preview_ordered_row_correlation_wire(preview, 0, 0),
    Some("\"A\""),
  )
  let first = retained_effect_ordered_row_key(preview, retained, 0, 0).unwrap()
  let second = retained_effect_ordered_row_key(preview, retained, 0, 1).unwrap()
  assert_true(physical_equal(first, retained[0][1]))
  assert_true(physical_equal(second, retained[0][0]))
  assert_true(
    physical_equal(
      retained_effect_ordered_row_key(preview, retained, 0, 0).unwrap(),
      first,
    ),
  )
  assert_true(retained_effect_ordered_row_key(preview, retained, 0, -1) is None)
  assert_true(retained_effect_ordered_row_key(preview, retained, 0, 2) is None)
  assert_true(retained_effect_ordered_row_key(preview, retained, 1, 0) is None)
  assert_true(retained_effect_ordered_row_key(preview, [], 0, 0) is None)
}
