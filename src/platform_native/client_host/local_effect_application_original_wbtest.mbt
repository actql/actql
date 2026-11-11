///|
test "Native saved file request measures the same original canonical subtrees before text construction" {
  let before = @canonical.from_json(
    { "id": "e\u0301", "Name": "日😀" },
    64,
    8,
    4096,
    data_keys=true,
  )
  let target = @canonical.from_json("row", 64, 8, 4096, data_keys=true)
  let value = @canonical.from_json(
    { "NextStep": "a\n\"\\b", "metadata": [1, 2] },
    64,
    8,
    4096,
    data_keys=true,
  )
  let measure = @encode.measuring_writer(4096, 64, 8)
  emit_native_local_effect_update_request(
    measure, "binding", "mapping", target, value, before, "version",
  )
  let (bytes, nodes, depth) = @encode.finish_measurement_usage(measure)
  let wire = native_local_effect_update_request_wire(
    "binding", "mapping", target, value, before, "version", 4096, 64, 8,
  ).unwrap()
  assert_eq(
    wire, "{\"before\":{\"Name\":\"日😀\",\"id\":\"e\u0301\"},\"binding\":\"binding\",\"mapping\":\"mapping\",\"target\":\"row\",\"value\":{\"NextStep\":\"a\\n\\\"\\\\b\",\"metadata\":[1,2]},\"version\":\"version\"}",
  )
  assert_eq(bytes, @utf8.encode(wire).length())
  assert_eq(nodes, 13)
  assert_eq(depth, 3)
  assert_true(bytes < 4096)
  assert_true(
    native_local_effect_update_request_wire(
      "binding",
      "mapping",
      target,
      value,
      before,
      "version",
      bytes - 1,
      64,
      8,
    )
    is Err(_),
  )
}

///|
// Authored two-row input from scripts/fixtures/effect-file-operation-vectors.mjs.
// Pure immutable-key projection only; no Host, Account, signer or IO is admitted.
fn native_application_projection_fixture() -> (
  @scope.LogicalRequestScope,
  @publication.EffectPreviewIdentity,
  Array[Array[@effect.EffectDispatchKey]],
) {
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
  (scope, preview, retained)
}

///|
test "Native retained application keys follow execution order without reissuing originals" {
  let (_, preview, retained) = native_application_projection_fixture()
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

///|
test "Native application row basis retains original key and ordered membership" {
  let (scope, preview, keys) = native_application_projection_fixture()
  let request = "sha256:" + "c".repeat(64)
  let retention = "sha256:" + "d".repeat(64)
  let unit = "sha256:" + "e".repeat(64)
  let invocation = "sha256:" + "f".repeat(64)
  let first_key = retained_effect_ordered_row_key(preview, keys, 0, 0).unwrap()
  let (locator, key, basis) = retained_effect_application_row_basis(
    preview, scope, first_key, "ProgramOriginal", "UnitOriginal", unit, invocation,
    0, 0, request, retention, 64,
  ).unwrap()
  assert_true(physical_equal(key, first_key))
  assert_eq(locator.program_id, "ProgramOriginal")
  assert_eq(locator.node_id, "UnitOriginal")
  assert_eq(locator.effect_id, "WriteOne")
  assert_eq(locator.item_correlation_wire, "\"A\"")
  assert_eq(basis.logical_item_locator_cid, locator.cid)
  assert_eq(basis.dispatch_key_cid, first_key.cid)
  assert_eq(basis.unit_definition_cid, unit)
  assert_eq(
    basis.original_membership_cid,
    @publication.effect_preview_member_identity(preview, 0).unwrap(),
  )
  assert_eq(
    basis.intent_fingerprint_cid,
    @publication.effect_preview_ordered_row_identity(preview, 0, 0).unwrap(),
  )
  assert_eq(basis.canonical_request_cid, request)
  assert_eq(basis.retention_contract_cid, retention)
  assert_eq(basis.capability, "unavailable")
  assert_eq(
    basis.reservation_evidence_cid,
    @publication.effect_preview_member_capability_evidence_cid(preview, 0).unwrap(),
  )
  // Independent literal preimage, calculated outside the product encoder.
  assert_eq(
    basis.recovery_contract_cid,
    "sha256:8d268a8219c27f2d3c6eec3e91c1df28a0db9eb10bb134017f026123cce379c0",
  )
  let second_key = retained_effect_ordered_row_key(preview, keys, 0, 1).unwrap()
  assert_true(
    retained_effect_application_row_basis(
      preview, scope, second_key, "ProgramOriginal", "UnitOriginal", unit, invocation,
      0, 0, request, retention, 64,
    )
    is Err(_),
  )
  assert_true(
    retained_effect_application_row_basis(
      preview, scope, first_key, "ProgramOriginal", "UnitOriginal", unit, invocation,
      0, 2, request, retention, 64,
    )
    is Err(_),
  )
  let (second_locator, same_second_key, second_basis) = retained_effect_application_row_basis(
    preview, scope, second_key, "ProgramOriginal", "UnitOriginal", unit, invocation,
    0, 1, request, retention, 64,
  ).unwrap()
  assert_true(physical_equal(same_second_key, second_key))
  assert_eq(second_locator.item_correlation_wire, "\"B\"")
  assert_true(second_locator.cid != locator.cid)
  assert_true(
    second_basis.intent_fingerprint_cid != basis.intent_fingerprint_cid,
  )
  assert_eq(second_basis.recovery_contract_cid, basis.recovery_contract_cid)
  assert_true(
    retained_effect_application_row_basis(
      preview, scope, first_key, "ProgramOriginal", "UnitOriginal", unit, invocation,
      0, 0, "invalid-request-cid", retention, 64,
    )
    is Err(_),
  )
}
