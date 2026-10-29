// Generated from independent local-operation transaction receipt preimages.

///|
test "local operation original: committed update" {
  let original = admit_effect_preview_identity(
    "{\"authoring_context\":{\"annotations\":[],\"authoring_context_cid\":\"sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a\",\"program_definition_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-authoring-context/0.1\"},\"barrier_provenance_cids\":[],\"check_environment_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"effects\":[{\"approval\":\"required\",\"authority_scope_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"capability_evidence_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"changes\":[{\"after\":{\"state\":\"present\",\"value\":{\"Name\":\"After\"}},\"before\":{\"state\":\"present\",\"value\":{\"Name\":\"Before\"}},\"intended_changes\":{\"state\":\"present\",\"value\":{\"Name\":\"After\"}},\"row_idempotency_key\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_guard\":{\"state\":\"version\",\"version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"target_row_identity\":\"001000000000001\"}],\"count\":1,\"effect_id\":\"WriteOne\",\"effect_identity_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"effect_kind\":\"update\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"executed\":false,\"mapping\":\"mapping:fixture\",\"max_items\":1,\"on_item_failure\":\"halt\",\"preview_strength\":\"full_diff\",\"required_permissions\":[\"write\"],\"resolved_mapping_contract_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"row_order\":[\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\"],\"source_binding_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"target\":\"Object\",\"write_footprint\":{\"kind\":\"exact_targets\",\"provider_boundary_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"provider_namespace\":\"fixture\",\"provider_object_identity_cids\":[\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\"],\"resource_identity_scheme_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"resource_kind\":\"file\"}}],\"encryption_required\":true,\"executed\":false,\"invocation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"model_derived\":false,\"model_invocation_evidence_cids\":[],\"model_response_artifact_cids\":[],\"model_task_contract_cids\":[],\"program_definition_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"program_semantics_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"retention_class\":\"authority-evidence\",\"run_identity_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"sensitivity\":\"private\",\"version\":\"actql-effect-preview/0.1\"}",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a",
    20000, 2000, 32,
  ).unwrap()
  let operation = prepare_effect_local_operation(
    original, 0, 0, "sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875",
    "sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410", "sha256:3333333333333333333333333333333333333333333333333333333333333333",
    "sha256:4444444444444444444444444444444444444444444444444444444444444444", "sha256:5555555555555555555555555555555555555555555555555555555555555555",
    "sha256:6666666666666666666666666666666666666666666666666666666666666666", "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  ).unwrap()
  let response = prepare_effect_local_operation_receipt(
    operation,
    Applied(
      "sha256:9999999999999999999999999999999999999999999999999999999999999999",
    ),
    "{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"}",
    20000,
    2000,
    32,
  ).unwrap()
  assert_eq(
    effect_local_operation_receipt_wire(response),
    "{\"approval_use_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"authorization_use_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"backend_kind\":\"sqlite\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"commit_status\":\"committed\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875\",\"observed_version_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:6a15bf1bb1067842019b3949c090d3d517d836fe69ae70449a6898e2d59d90db\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
  )
  assert_eq(
    effect_local_operation_receipt_cid(response),
    "sha256:6a15bf1bb1067842019b3949c090d3d517d836fe69ae70449a6898e2d59d90db",
  )
  let admitted = admit_effect_local_operation_receipt(
    operation, "{\"approval_use_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"authorization_use_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"backend_kind\":\"sqlite\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"commit_status\":\"committed\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875\",\"observed_version_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:6a15bf1bb1067842019b3949c090d3d517d836fe69ae70449a6898e2d59d90db\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let row = issue_effect_row_outcome_receipt_from_local(
    original, 0, 0, "sha256:4444444444444444444444444444444444444444444444444444444444444444",
    admitted, 20000, 2000, 32,
  ).unwrap()
  assert_eq(
    publication_contract_json(row),
    "{\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"local_operation_receipt_cid\":\"sha256:6a15bf1bb1067842019b3949c090d3d517d836fe69ae70449a6898e2d59d90db\",\"receipt_cid\":\"sha256:d48eab82606665bc1618d2408a5f4c37acbbec42ae43ff8d8ce50c47c24ba395\",\"response_byte_count\":1439,\"response_kind\":\"local_operation\",\"response_physical_sha256\":\"9c2812b6b34637b7cf2c0324b8bf9ad70541cf28c7ffdf16752d68f0932dcb9b\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-effect-row-outcome-receipt/0.1\"}",
  )
  assert_eq(
    publication_contract_identity(row),
    "sha256:d48eab82606665bc1618d2408a5f4c37acbbec42ae43ff8d8ce50c47c24ba395",
  )
  assert_true(
    admit_effect_row_outcome_receipt_from_local(
      original, 0, 0, "sha256:4444444444444444444444444444444444444444444444444444444444444444",
      admitted, "{\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"local_operation_receipt_cid\":\"sha256:6a15bf1bb1067842019b3949c090d3d517d836fe69ae70449a6898e2d59d90db\",\"receipt_cid\":\"sha256:d48eab82606665bc1618d2408a5f4c37acbbec42ae43ff8d8ce50c47c24ba395\",\"response_byte_count\":1439,\"response_kind\":\"local_operation\",\"response_physical_sha256\":\"9c2812b6b34637b7cf2c0324b8bf9ad70541cf28c7ffdf16752d68f0932dcb9b\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-effect-row-outcome-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "local operation original: version conflict" {
  let original = admit_effect_preview_identity(
    "{\"authoring_context\":{\"annotations\":[],\"authoring_context_cid\":\"sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a\",\"program_definition_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-authoring-context/0.1\"},\"barrier_provenance_cids\":[],\"check_environment_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"effects\":[{\"approval\":\"required\",\"authority_scope_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"capability_evidence_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"changes\":[{\"after\":{\"state\":\"present\",\"value\":{\"Name\":\"After\"}},\"before\":{\"state\":\"present\",\"value\":{\"Name\":\"Before\"}},\"intended_changes\":{\"state\":\"present\",\"value\":{\"Name\":\"After\"}},\"row_idempotency_key\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_guard\":{\"state\":\"version\",\"version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"target_row_identity\":\"001000000000001\"}],\"count\":1,\"effect_id\":\"WriteOne\",\"effect_identity_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"effect_kind\":\"update\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"executed\":false,\"mapping\":\"mapping:fixture\",\"max_items\":1,\"on_item_failure\":\"halt\",\"preview_strength\":\"full_diff\",\"required_permissions\":[\"write\"],\"resolved_mapping_contract_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"row_order\":[\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\"],\"source_binding_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"target\":\"Object\",\"write_footprint\":{\"kind\":\"exact_targets\",\"provider_boundary_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"provider_namespace\":\"fixture\",\"provider_object_identity_cids\":[\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\"],\"resource_identity_scheme_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"resource_kind\":\"file\"}}],\"encryption_required\":true,\"executed\":false,\"invocation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"model_derived\":false,\"model_invocation_evidence_cids\":[],\"model_response_artifact_cids\":[],\"model_task_contract_cids\":[],\"program_definition_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"program_semantics_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"retention_class\":\"authority-evidence\",\"run_identity_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"sensitivity\":\"private\",\"version\":\"actql-effect-preview/0.1\"}",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a",
    20000, 2000, 32,
  ).unwrap()
  let operation = prepare_effect_local_operation(
    original, 0, 0, "sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875",
    "sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410", "sha256:3333333333333333333333333333333333333333333333333333333333333333",
    "sha256:4444444444444444444444444444444444444444444444444444444444444444", "sha256:5555555555555555555555555555555555555555555555555555555555555555",
    "sha256:6666666666666666666666666666666666666666666666666666666666666666", "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  ).unwrap()
  let response = prepare_effect_local_operation_receipt(
    operation,
    Conflict(
      Some(
        "sha256:8888888888888888888888888888888888888888888888888888888888888888",
      ),
    ),
    "{\"error\":{\"code\":\"conflict\",\"message\":\"Target changed\"},\"state\":\"failed\"}",
    20000,
    2000,
    32,
  ).unwrap()
  assert_eq(
    effect_local_operation_receipt_wire(response),
    "{\"approval_use_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"authorization_use_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"backend_kind\":\"sqlite\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"commit_status\":\"conflict\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875\",\"observed_version_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:8f2a48ea8f36dcf452f7cb8d9ff8d824c96f2e408db5d31504d6be0d4319577e\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"error\":{\"code\":\"conflict\",\"message\":\"Target changed\"},\"state\":\"failed\"},\"typed_outcome_cid\":\"sha256:a1cd1e396927e468a822b340b90ceea91b7b78f69b7a790b80461f1d35abe8ac\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
  )
  assert_eq(
    effect_local_operation_receipt_cid(response),
    "sha256:8f2a48ea8f36dcf452f7cb8d9ff8d824c96f2e408db5d31504d6be0d4319577e",
  )
  let admitted = admit_effect_local_operation_receipt(
    operation, "{\"approval_use_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"authorization_use_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"backend_kind\":\"sqlite\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"commit_status\":\"conflict\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875\",\"observed_version_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:8f2a48ea8f36dcf452f7cb8d9ff8d824c96f2e408db5d31504d6be0d4319577e\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"error\":{\"code\":\"conflict\",\"message\":\"Target changed\"},\"state\":\"failed\"},\"typed_outcome_cid\":\"sha256:a1cd1e396927e468a822b340b90ceea91b7b78f69b7a790b80461f1d35abe8ac\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let row = issue_effect_row_outcome_receipt_from_local(
    original, 0, 0, "sha256:4444444444444444444444444444444444444444444444444444444444444444",
    admitted, 20000, 2000, 32,
  ).unwrap()
  assert_eq(
    publication_contract_json(row),
    "{\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"local_operation_receipt_cid\":\"sha256:8f2a48ea8f36dcf452f7cb8d9ff8d824c96f2e408db5d31504d6be0d4319577e\",\"receipt_cid\":\"sha256:ad71b010b2b3021d5812f3997537fd4e89bca0c1beb82562e583110485634107\",\"response_byte_count\":1448,\"response_kind\":\"local_operation\",\"response_physical_sha256\":\"4ef82870bb0febbbb49ad128f37d770e74725faa588f79dea36df61a489f075b\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"typed_outcome\":{\"error\":{\"code\":\"conflict\",\"message\":\"Target changed\"},\"state\":\"failed\"},\"typed_outcome_cid\":\"sha256:a1cd1e396927e468a822b340b90ceea91b7b78f69b7a790b80461f1d35abe8ac\",\"version\":\"actql-effect-row-outcome-receipt/0.1\"}",
  )
  assert_eq(
    publication_contract_identity(row),
    "sha256:ad71b010b2b3021d5812f3997537fd4e89bca0c1beb82562e583110485634107",
  )
  assert_true(
    admit_effect_row_outcome_receipt_from_local(
      original, 0, 0, "sha256:4444444444444444444444444444444444444444444444444444444444444444",
      admitted, "{\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"local_operation_receipt_cid\":\"sha256:8f2a48ea8f36dcf452f7cb8d9ff8d824c96f2e408db5d31504d6be0d4319577e\",\"receipt_cid\":\"sha256:ad71b010b2b3021d5812f3997537fd4e89bca0c1beb82562e583110485634107\",\"response_byte_count\":1448,\"response_kind\":\"local_operation\",\"response_physical_sha256\":\"4ef82870bb0febbbb49ad128f37d770e74725faa588f79dea36df61a489f075b\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"typed_outcome\":{\"error\":{\"code\":\"conflict\",\"message\":\"Target changed\"},\"state\":\"failed\"},\"typed_outcome_cid\":\"sha256:a1cd1e396927e468a822b340b90ceea91b7b78f69b7a790b80461f1d35abe8ac\",\"version\":\"actql-effect-row-outcome-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "local operation original: absent target conflict" {
  let original = admit_effect_preview_identity(
    "{\"authoring_context\":{\"annotations\":[],\"authoring_context_cid\":\"sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a\",\"program_definition_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-authoring-context/0.1\"},\"barrier_provenance_cids\":[],\"check_environment_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"effects\":[{\"approval\":\"required\",\"authority_scope_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"capability_evidence_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"changes\":[{\"after\":{\"state\":\"present\",\"value\":{\"Name\":\"After\"}},\"before\":{\"state\":\"present\",\"value\":{\"Name\":\"Before\"}},\"intended_changes\":{\"state\":\"present\",\"value\":{\"Name\":\"After\"}},\"row_idempotency_key\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_guard\":{\"state\":\"version\",\"version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"target_row_identity\":\"001000000000001\"}],\"count\":1,\"effect_id\":\"WriteOne\",\"effect_identity_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"effect_kind\":\"update\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"executed\":false,\"mapping\":\"mapping:fixture\",\"max_items\":1,\"on_item_failure\":\"halt\",\"preview_strength\":\"full_diff\",\"required_permissions\":[\"write\"],\"resolved_mapping_contract_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"row_order\":[\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\"],\"source_binding_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"target\":\"Object\",\"write_footprint\":{\"kind\":\"exact_targets\",\"provider_boundary_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"provider_namespace\":\"fixture\",\"provider_object_identity_cids\":[\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\"],\"resource_identity_scheme_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"resource_kind\":\"file\"}}],\"encryption_required\":true,\"executed\":false,\"invocation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"model_derived\":false,\"model_invocation_evidence_cids\":[],\"model_response_artifact_cids\":[],\"model_task_contract_cids\":[],\"program_definition_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"program_semantics_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"retention_class\":\"authority-evidence\",\"run_identity_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"sensitivity\":\"private\",\"version\":\"actql-effect-preview/0.1\"}",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a",
    20000, 2000, 32,
  ).unwrap()
  let operation = prepare_effect_local_operation(
    original, 0, 0, "sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875",
    "sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410", "sha256:3333333333333333333333333333333333333333333333333333333333333333",
    "sha256:4444444444444444444444444444444444444444444444444444444444444444", "sha256:5555555555555555555555555555555555555555555555555555555555555555",
    "sha256:6666666666666666666666666666666666666666666666666666666666666666", "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  ).unwrap()
  let response = prepare_effect_local_operation_receipt(
    operation,
    Conflict(None),
    "{\"error\":{\"code\":\"conflict\",\"message\":\"Target absent\"},\"state\":\"failed\"}",
    20000,
    2000,
    32,
  ).unwrap()
  assert_eq(
    effect_local_operation_receipt_wire(response),
    "{\"approval_use_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"authorization_use_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"backend_kind\":\"sqlite\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"commit_status\":\"conflict\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875\",\"observed_version_cid\":null,\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:456c4689e173635fadcd606b91ef8f80dc7b0378626e41173450eb67c2505a03\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"error\":{\"code\":\"conflict\",\"message\":\"Target absent\"},\"state\":\"failed\"},\"typed_outcome_cid\":\"sha256:11600fee4711ede914a88c1058fd3117b431d63fdadca97e48bb80355ea61119\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
  )
  assert_eq(
    effect_local_operation_receipt_cid(response),
    "sha256:456c4689e173635fadcd606b91ef8f80dc7b0378626e41173450eb67c2505a03",
  )
  let admitted = admit_effect_local_operation_receipt(
    operation, "{\"approval_use_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"authorization_use_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"backend_kind\":\"sqlite\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"commit_status\":\"conflict\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875\",\"observed_version_cid\":null,\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:456c4689e173635fadcd606b91ef8f80dc7b0378626e41173450eb67c2505a03\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"error\":{\"code\":\"conflict\",\"message\":\"Target absent\"},\"state\":\"failed\"},\"typed_outcome_cid\":\"sha256:11600fee4711ede914a88c1058fd3117b431d63fdadca97e48bb80355ea61119\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let row = issue_effect_row_outcome_receipt_from_local(
    original, 0, 0, "sha256:4444444444444444444444444444444444444444444444444444444444444444",
    admitted, 20000, 2000, 32,
  ).unwrap()
  assert_eq(
    publication_contract_json(row),
    "{\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"local_operation_receipt_cid\":\"sha256:456c4689e173635fadcd606b91ef8f80dc7b0378626e41173450eb67c2505a03\",\"receipt_cid\":\"sha256:820f5182641a258d89eb743942ad7fb897c39e0c6fdee444bb4c68594d3b4080\",\"response_byte_count\":1378,\"response_kind\":\"local_operation\",\"response_physical_sha256\":\"84e9c50b70816f7ba5159f18c092080dac41abd90cac0ee721141534cc2d1e25\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"typed_outcome\":{\"error\":{\"code\":\"conflict\",\"message\":\"Target absent\"},\"state\":\"failed\"},\"typed_outcome_cid\":\"sha256:11600fee4711ede914a88c1058fd3117b431d63fdadca97e48bb80355ea61119\",\"version\":\"actql-effect-row-outcome-receipt/0.1\"}",
  )
  assert_eq(
    publication_contract_identity(row),
    "sha256:820f5182641a258d89eb743942ad7fb897c39e0c6fdee444bb4c68594d3b4080",
  )
  assert_true(
    admit_effect_row_outcome_receipt_from_local(
      original, 0, 0, "sha256:4444444444444444444444444444444444444444444444444444444444444444",
      admitted, "{\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"local_operation_receipt_cid\":\"sha256:456c4689e173635fadcd606b91ef8f80dc7b0378626e41173450eb67c2505a03\",\"receipt_cid\":\"sha256:820f5182641a258d89eb743942ad7fb897c39e0c6fdee444bb4c68594d3b4080\",\"response_byte_count\":1378,\"response_kind\":\"local_operation\",\"response_physical_sha256\":\"84e9c50b70816f7ba5159f18c092080dac41abd90cac0ee721141534cc2d1e25\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"typed_outcome\":{\"error\":{\"code\":\"conflict\",\"message\":\"Target absent\"},\"state\":\"failed\"},\"typed_outcome_cid\":\"sha256:11600fee4711ede914a88c1058fd3117b431d63fdadca97e48bb80355ea61119\",\"version\":\"actql-effect-row-outcome-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "local operation original refuses foreign and missing saved bindings" {
  let original = admit_effect_preview_identity(
    "{\"authoring_context\":{\"annotations\":[],\"authoring_context_cid\":\"sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a\",\"program_definition_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-authoring-context/0.1\"},\"barrier_provenance_cids\":[],\"check_environment_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"effects\":[{\"approval\":\"required\",\"authority_scope_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"capability_evidence_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"changes\":[{\"after\":{\"state\":\"present\",\"value\":{\"Name\":\"After\"}},\"before\":{\"state\":\"present\",\"value\":{\"Name\":\"Before\"}},\"intended_changes\":{\"state\":\"present\",\"value\":{\"Name\":\"After\"}},\"row_idempotency_key\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_guard\":{\"state\":\"version\",\"version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"target_row_identity\":\"001000000000001\"}],\"count\":1,\"effect_id\":\"WriteOne\",\"effect_identity_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"effect_kind\":\"update\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"executed\":false,\"mapping\":\"mapping:fixture\",\"max_items\":1,\"on_item_failure\":\"halt\",\"preview_strength\":\"full_diff\",\"required_permissions\":[\"write\"],\"resolved_mapping_contract_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"row_order\":[\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\"],\"source_binding_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"target\":\"Object\",\"write_footprint\":{\"kind\":\"exact_targets\",\"provider_boundary_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"provider_namespace\":\"fixture\",\"provider_object_identity_cids\":[\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\"],\"resource_identity_scheme_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"resource_kind\":\"file\"}}],\"encryption_required\":true,\"executed\":false,\"invocation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"model_derived\":false,\"model_invocation_evidence_cids\":[],\"model_response_artifact_cids\":[],\"model_task_contract_cids\":[],\"program_definition_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"program_semantics_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"retention_class\":\"authority-evidence\",\"run_identity_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"sensitivity\":\"private\",\"version\":\"actql-effect-preview/0.1\"}",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a",
    20000, 2000, 32,
  ).unwrap()
  let operation = prepare_effect_local_operation(
    original, 0, 0, "sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875",
    "sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410", "sha256:3333333333333333333333333333333333333333333333333333333333333333",
    "sha256:4444444444444444444444444444444444444444444444444444444444444444", "sha256:5555555555555555555555555555555555555555555555555555555555555555",
    "sha256:6666666666666666666666666666666666666666666666666666666666666666", "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  ).unwrap()
  // foreign effect_preview_cid
  assert_true(
    admit_effect_local_operation_receipt(
      operation, "{\"approval_use_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"authorization_use_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"backend_kind\":\"sqlite\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"commit_status\":\"committed\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"installation_cid\":\"sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875\",\"observed_version_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:0c0b9efaf406320032df8f123afbb2a4ace81f1b9bdaea0cf476572640df427b\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // foreign effect_member_preview_cid
  assert_true(
    admit_effect_local_operation_receipt(
      operation, "{\"approval_use_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"authorization_use_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"backend_kind\":\"sqlite\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"commit_status\":\"committed\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875\",\"observed_version_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:de5785ca9bffcadd9517f52fbe1739dc68c865705d1a98e2e56949c402865e21\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // foreign row_preview_cid
  assert_true(
    admit_effect_local_operation_receipt(
      operation, "{\"approval_use_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"authorization_use_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"backend_kind\":\"sqlite\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"commit_status\":\"committed\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875\",\"observed_version_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:c115ff4c73cf3dd2287dd015e5b23f6e7af95769a5403a27aaeca3c028bfd933\",\"row_preview_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"target_cid\":\"sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // foreign backend_kind
  assert_true(
    admit_effect_local_operation_receipt(
      operation, "{\"approval_use_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"authorization_use_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"backend_kind\":\"http\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"commit_status\":\"committed\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875\",\"observed_version_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:da2a42680415a45d5273f9b2b12b9a5305e15d3422fc1ec21a38d97001e8a3ab\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // foreign installation_cid
  assert_true(
    admit_effect_local_operation_receipt(
      operation, "{\"approval_use_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"authorization_use_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"backend_kind\":\"sqlite\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"commit_status\":\"committed\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"observed_version_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:be6a262bb1968c151ab793bd87fb7e9229e95b75dc0300ef8061287fd4345f5a\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // foreign target_cid
  assert_true(
    admit_effect_local_operation_receipt(
      operation, "{\"approval_use_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"authorization_use_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"backend_kind\":\"sqlite\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"commit_status\":\"committed\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875\",\"observed_version_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:670ce50bea4fb782134b473a063f7a343193c28138df3bb8de79cb1b4804c38a\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // foreign canonical_request_cid
  assert_true(
    admit_effect_local_operation_receipt(
      operation, "{\"approval_use_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"authorization_use_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"backend_kind\":\"sqlite\",\"canonical_request_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"commit_status\":\"committed\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875\",\"observed_version_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:da5a28cc66b0148da01ad9206f99b39f017de2fdcfc02d7e3bfabe723b87db4a\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // foreign dispatch_entry_cid
  assert_true(
    admit_effect_local_operation_receipt(
      operation, "{\"approval_use_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"authorization_use_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"backend_kind\":\"sqlite\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"commit_status\":\"committed\",\"dispatch_entry_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875\",\"observed_version_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:3b81bf34303bf25575e94115f2ec25634f493cf71c315d5e9f8d7bcccd74949c\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // foreign authorization_use_cid
  assert_true(
    admit_effect_local_operation_receipt(
      operation, "{\"approval_use_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"authorization_use_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"backend_kind\":\"sqlite\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"commit_status\":\"committed\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875\",\"observed_version_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:8775105872b0a7e2bfe68f46b34db3fe3ce27a01af88c5942ed3ea6352e4ba56\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // foreign approval_use_cid
  assert_true(
    admit_effect_local_operation_receipt(
      operation, "{\"approval_use_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"authorization_use_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"backend_kind\":\"sqlite\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"commit_status\":\"committed\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875\",\"observed_version_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:3fb69afbcacab202fb43309f3127aeb2697669ec40d92bf1b02b7e86dc3c5095\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // foreign target_version_cid
  assert_true(
    admit_effect_local_operation_receipt(
      operation, "{\"approval_use_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"authorization_use_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"backend_kind\":\"sqlite\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"commit_status\":\"committed\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875\",\"observed_version_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:0aa6d0ec261f57d3c7c03a966af9364016fbecca2f10bdafe5b03003506dc28b\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410\",\"target_version_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // missing authorization_use_cid
  assert_true(
    admit_effect_local_operation_receipt(
      operation, "{\"approval_use_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"backend_kind\":\"sqlite\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"commit_status\":\"committed\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875\",\"observed_version_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:1bcc4bceddfd7d7152a553f24f9f7ced1014f16fd085c2050a24afa93b19ef87\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // missing approval_use_cid
  assert_true(
    admit_effect_local_operation_receipt(
      operation, "{\"authorization_use_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"backend_kind\":\"sqlite\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"commit_status\":\"committed\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875\",\"observed_version_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:246ab8552c83413e99c410aa12388ec233d40a542756f7f44aa4a84d9f3fcf33\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // missing dispatch_entry_cid
  assert_true(
    admit_effect_local_operation_receipt(
      operation, "{\"approval_use_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"authorization_use_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"backend_kind\":\"sqlite\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"commit_status\":\"committed\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875\",\"observed_version_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:dec1b5788cbed397689364ea0f49fa8b74c9e145be2fe2e553ea8e9ea0abed49\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // HTTP substitution
  assert_true(
    admit_effect_local_operation_receipt(
      operation, "{\"approval_use_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"authorization_use_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"backend_kind\":\"sqlite\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"commit_status\":\"committed\",\"credential_use_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"http_status_code\":200,\"installation_cid\":\"sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875\",\"observed_version_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:45b0172126533c17c5afb5447e38148b41dc16cb2bc9c696bdc0517b7472e8f6\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // uncertain COMMIT
  assert_true(
    admit_effect_local_operation_receipt(
      operation, "{\"approval_use_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"authorization_use_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"backend_kind\":\"sqlite\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"commit_status\":\"unknown\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875\",\"observed_version_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:0046f178000eb3c52a6e4b5c6475d2a8f5149a41ff8bdedf5a00aae2085ac637\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // false outcome CID
  assert_true(
    admit_effect_local_operation_receipt(
      operation, "{\"approval_use_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"authorization_use_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"backend_kind\":\"sqlite\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"commit_status\":\"committed\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875\",\"observed_version_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:ea9c78f4089f2447d8f05db8d59212db238b72a52bba35f4a4f30f520bace4f3\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // applied without version
  assert_true(
    admit_effect_local_operation_receipt(
      operation, "{\"approval_use_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"authorization_use_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"backend_kind\":\"sqlite\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"commit_status\":\"committed\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875\",\"observed_version_cid\":null,\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:a76c150ed3db9053e2b434fee8ff6a721253462ebfb3ec282ecd66be149f9d9c\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // unmatched conflict
  assert_true(
    admit_effect_local_operation_receipt(
      operation, "{\"approval_use_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"authorization_use_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"backend_kind\":\"sqlite\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"commit_status\":\"committed\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875\",\"observed_version_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:2949dec0cf6c76ea0b16cfe067975ce09622f82ce220f779f0331c11226457bc\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"error\":{\"code\":\"denied\",\"message\":\"Not a conflict\"},\"state\":\"failed\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
}

///|
test "local operation original preserves exact installation and target bytes" {
  assert_eq(
    effect_local_installation_cid(
      "{\"installation\":\"local-original\",\"mapping\":\"mapping:accounts\",\"note\":\"e\\u0301\",\"primary_identity\":\"Id\"}",
      20000, 2000, 32,
    ).unwrap(),
    "sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875",
  )
  assert_eq(
    effect_local_target_cid(
      "sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875",
      "connector://mock/accounts", "\"001000000000001\"", 20000, 2000, 32,
    ).unwrap(),
    "sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410",
  )
  assert_true(
    effect_local_installation_cid(
      "{\"installation\":\"local-original\",\"mapping\":\"mapping:accounts\",\"note\":\"e\\u0301\",\"primary_identity\":\"Id\"}",
      1, 2000, 32,
    )
    is Err(_),
  )
  assert_true(
    effect_local_target_cid(
      "sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875",
      "connector://mock/accounts", "\"001000000000001\"", 1, 2000, 32,
    )
    is Err(_),
  )
  assert_true(
    effect_local_target_cid(
      "sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875",
      "connector://mock/accounts", " \"001000000000001\"", 20000, 2000, 32,
    )
    is Err(_),
  )
}

///|
test "local operation original refuses wrong row version and nonterminal evidence" {
  let original = admit_effect_preview_identity(
    "{\"authoring_context\":{\"annotations\":[],\"authoring_context_cid\":\"sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a\",\"program_definition_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-authoring-context/0.1\"},\"barrier_provenance_cids\":[],\"check_environment_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"effects\":[{\"approval\":\"required\",\"authority_scope_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"capability_evidence_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"changes\":[{\"after\":{\"state\":\"present\",\"value\":{\"Name\":\"After\"}},\"before\":{\"state\":\"present\",\"value\":{\"Name\":\"Before\"}},\"intended_changes\":{\"state\":\"present\",\"value\":{\"Name\":\"After\"}},\"row_idempotency_key\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_guard\":{\"state\":\"version\",\"version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"target_row_identity\":\"001000000000001\"}],\"count\":1,\"effect_id\":\"WriteOne\",\"effect_identity_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"effect_kind\":\"update\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"executed\":false,\"mapping\":\"mapping:fixture\",\"max_items\":1,\"on_item_failure\":\"halt\",\"preview_strength\":\"full_diff\",\"required_permissions\":[\"write\"],\"resolved_mapping_contract_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"row_order\":[\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\"],\"source_binding_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"target\":\"Object\",\"write_footprint\":{\"kind\":\"exact_targets\",\"provider_boundary_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"provider_namespace\":\"fixture\",\"provider_object_identity_cids\":[\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\"],\"resource_identity_scheme_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"resource_kind\":\"file\"}}],\"encryption_required\":true,\"executed\":false,\"invocation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"model_derived\":false,\"model_invocation_evidence_cids\":[],\"model_response_artifact_cids\":[],\"model_task_contract_cids\":[],\"program_definition_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"program_semantics_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"retention_class\":\"authority-evidence\",\"run_identity_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"sensitivity\":\"private\",\"version\":\"actql-effect-preview/0.1\"}",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a",
    20000, 2000, 32,
  ).unwrap()
  let operation = prepare_effect_local_operation(
    original, 0, 0, "sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875",
    "sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410", "sha256:3333333333333333333333333333333333333333333333333333333333333333",
    "sha256:4444444444444444444444444444444444444444444444444444444444444444", "sha256:5555555555555555555555555555555555555555555555555555555555555555",
    "sha256:6666666666666666666666666666666666666666666666666666666666666666", "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  ).unwrap()
  assert_true(
    prepare_effect_local_operation(
      original, 0, 0, "sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875",
      "sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410",
      "sha256:3333333333333333333333333333333333333333333333333333333333333333",
      "sha256:4444444444444444444444444444444444444444444444444444444444444444",
      "sha256:5555555555555555555555555555555555555555555555555555555555555555",
      "sha256:6666666666666666666666666666666666666666666666666666666666666666",
      "sha256:0000000000000000000000000000000000000000000000000000000000000000",
    )
    is Err(ForeignRow),
  )
  assert_true(
    prepare_effect_local_operation_receipt(
      operation,
      Applied(
        "sha256:9999999999999999999999999999999999999999999999999999999999999999",
      ),
      "{\"state\":\"applied\",\"result\":{},\"action\":\"updated\"}",
      20000,
      2000,
      32,
    )
    is Err(_),
  )
  assert_true(
    prepare_effect_local_operation_receipt(
      operation,
      Conflict(None),
      "{\"state\":\"unknown\"}",
      20000,
      2000,
      32,
    )
    is Err(_),
  )
  assert_true(
    prepare_effect_local_operation_receipt(
      operation,
      Applied(
        "sha256:9999999999999999999999999999999999999999999999999999999999999999",
      ),
      "{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"}",
      1,
      2000,
      32,
    )
    is Err(_),
  )
  let response = admit_effect_local_operation_receipt(
    operation, "{\"approval_use_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"authorization_use_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"backend_kind\":\"sqlite\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"commit_status\":\"committed\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:b985757358c184882cb4bf831494364855698603b65d9034b6f1b963d62f1875\",\"observed_version_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:6a15bf1bb1067842019b3949c090d3d517d836fe69ae70449a6898e2d59d90db\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:c1fd7c538748bfa3ba62d189003d0514a12b3c025bd3a214bb030297397a0410\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_true(
    issue_effect_row_outcome_receipt_from_local(
      original, 0, 0, "sha256:0000000000000000000000000000000000000000000000000000000000000000",
      response, 20000, 2000, 32,
    )
    is Err(_),
  )
  assert_true(
    admit_effect_row_outcome_receipt_from_local(
      original, 0, 0, "sha256:4444444444444444444444444444444444444444444444444444444444444444",
      response, "{\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"local_operation_receipt_cid\":\"sha256:8f2a48ea8f36dcf452f7cb8d9ff8d824c96f2e408db5d31504d6be0d4319577e\",\"receipt_cid\":\"sha256:ad71b010b2b3021d5812f3997537fd4e89bca0c1beb82562e583110485634107\",\"response_byte_count\":1448,\"response_kind\":\"local_operation\",\"response_physical_sha256\":\"4ef82870bb0febbbb49ad128f37d770e74725faa588f79dea36df61a489f075b\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"typed_outcome\":{\"error\":{\"code\":\"conflict\",\"message\":\"Target changed\"},\"state\":\"failed\"},\"typed_outcome_cid\":\"sha256:a1cd1e396927e468a822b340b90ceea91b7b78f69b7a790b80461f1d35abe8ac\",\"version\":\"actql-effect-row-outcome-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
}
