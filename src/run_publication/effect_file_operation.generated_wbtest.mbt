// Generated from independent original file-operation preimages, never product output.

///|
test "file operation original binds exact physical bytes and generation" {
  let original = admit_effect_preview_identity(
    "{\"authoring_context\":{\"annotations\":[],\"authoring_context_cid\":\"sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a\",\"program_definition_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-authoring-context/0.1\"},\"barrier_provenance_cids\":[],\"check_environment_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"effects\":[{\"approval\":\"required\",\"authority_scope_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"capability_evidence_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"changes\":[{\"after\":{\"state\":\"present\",\"value\":{\"Name\":\"After\"}},\"before\":{\"state\":\"present\",\"value\":{\"Name\":\"Before\"}},\"intended_changes\":{\"state\":\"present\",\"value\":{\"Name\":\"After\"}},\"row_idempotency_key\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_guard\":{\"state\":\"version\",\"version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"target_row_identity\":\"001000000000001\"}],\"count\":1,\"effect_id\":\"WriteOne\",\"effect_identity_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"effect_kind\":\"update\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"executed\":false,\"mapping\":\"mapping:fixture\",\"max_items\":1,\"on_item_failure\":\"halt\",\"preview_strength\":\"full_diff\",\"required_permissions\":[\"write\"],\"resolved_mapping_contract_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"row_order\":[\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\"],\"source_binding_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"target\":\"Object\",\"write_footprint\":{\"kind\":\"exact_targets\",\"provider_boundary_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"provider_namespace\":\"fixture\",\"provider_object_identity_cids\":[\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\"],\"resource_identity_scheme_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"resource_kind\":\"file\"}}],\"encryption_required\":true,\"executed\":false,\"invocation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"model_derived\":false,\"model_invocation_evidence_cids\":[],\"model_response_artifact_cids\":[],\"model_task_contract_cids\":[],\"program_definition_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"program_semantics_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"retention_class\":\"authority-evidence\",\"run_identity_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"sensitivity\":\"private\",\"version\":\"actql-effect-preview/0.1\"}",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a",
    20000, 2000, 32,
  ).unwrap()
  let operation = prepare_effect_file_operation(
    original, 0, 0, "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb", "sha256:3333333333333333333333333333333333333333333333333333333333333333",
    "sha256:4444444444444444444444444444444444444444444444444444444444444444", "sha256:7777777777777777777777777777777777777777777777777777777777777777",
    "sha256:6666666666666666666666666666666666666666666666666666666666666666", "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  ).unwrap()
  let evidence = admit_effect_file_replacement_evidence(
    @utf8.encode(
      " {\"items\":[{\"Id\":3,\"e\\u0301\":\"raw\\r\\n\",\"é\":null}],\"keep\":true}\n",
    ),
    "16777234",
    "18446744073709551615",
    64L,
    4096,
  ).unwrap()
  assert_eq(
    effect_file_target_cid(
      "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "/original/é", "accounts.json", "connector://mock/accounts", "\"001000000000001\"",
      20000, 2000, 32,
    ).unwrap(),
    "sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb",
  )
  let response = prepare_effect_file_operation_receipt(
    operation, evidence, "{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_eq(
    effect_file_operation_receipt_wire(response),
    "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"backend_kind\":\"json_file\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:ae05fde44750b3abaabeb0d6b7aab96fa19a2f457fd8e19d2e15aad85796e1f1\",\"replacement_byte_count\":64,\"replacement_generation\":{\"device\":\"16777234\",\"inode\":\"18446744073709551615\",\"size\":\"64\"},\"replacement_physical_sha256\":\"e64f47a0258db63ce7b5f85121d4a4fd22679ec1fecc2c60bfde30d2a3eb3fdf\",\"replacement_status\":\"acknowledged\",\"resolution_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
  )
  assert_eq(
    effect_file_operation_receipt_cid(response),
    "sha256:ae05fde44750b3abaabeb0d6b7aab96fa19a2f457fd8e19d2e15aad85796e1f1",
  )
  let admitted = admit_effect_file_operation_receipt(
    operation, evidence, "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"backend_kind\":\"json_file\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:ae05fde44750b3abaabeb0d6b7aab96fa19a2f457fd8e19d2e15aad85796e1f1\",\"replacement_byte_count\":64,\"replacement_generation\":{\"device\":\"16777234\",\"inode\":\"18446744073709551615\",\"size\":\"64\"},\"replacement_physical_sha256\":\"e64f47a0258db63ce7b5f85121d4a4fd22679ec1fecc2c60bfde30d2a3eb3fdf\",\"replacement_status\":\"acknowledged\",\"resolution_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  let row = issue_effect_row_outcome_receipt_from_file(
    original, 0, 0, "sha256:4444444444444444444444444444444444444444444444444444444444444444",
    admitted, 20000, 2000, 32,
  ).unwrap()
  assert_eq(
    publication_contract_json(row),
    "{\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"local_operation_receipt_cid\":\"sha256:ae05fde44750b3abaabeb0d6b7aab96fa19a2f457fd8e19d2e15aad85796e1f1\",\"receipt_cid\":\"sha256:004209abe4483c96be86096710fd8b3c9b99d862dc3a3820efd7778ff5a576f3\",\"response_byte_count\":1570,\"response_kind\":\"local_operation\",\"response_physical_sha256\":\"b4362e4610fd192a9590f9e18cbc838a0d3101fd6722ee37fc82979d3cff1a8b\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-effect-row-outcome-receipt/0.1\"}",
  )
  assert_eq(
    publication_contract_identity(row),
    "sha256:004209abe4483c96be86096710fd8b3c9b99d862dc3a3820efd7778ff5a576f3",
  )
  assert_true(
    admit_effect_row_outcome_receipt_from_file(
      original, 0, 0, "sha256:4444444444444444444444444444444444444444444444444444444444444444",
      admitted, "{\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"local_operation_receipt_cid\":\"sha256:ae05fde44750b3abaabeb0d6b7aab96fa19a2f457fd8e19d2e15aad85796e1f1\",\"receipt_cid\":\"sha256:004209abe4483c96be86096710fd8b3c9b99d862dc3a3820efd7778ff5a576f3\",\"response_byte_count\":1570,\"response_kind\":\"local_operation\",\"response_physical_sha256\":\"b4362e4610fd192a9590f9e18cbc838a0d3101fd6722ee37fc82979d3cff1a8b\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-effect-row-outcome-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Ok(_),
  )
}

///|
test "file operation original refuses foreign uncertain and HTTP evidence" {
  let original = admit_effect_preview_identity(
    "{\"authoring_context\":{\"annotations\":[],\"authoring_context_cid\":\"sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a\",\"program_definition_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-authoring-context/0.1\"},\"barrier_provenance_cids\":[],\"check_environment_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"effects\":[{\"approval\":\"required\",\"authority_scope_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"capability_evidence_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"changes\":[{\"after\":{\"state\":\"present\",\"value\":{\"Name\":\"After\"}},\"before\":{\"state\":\"present\",\"value\":{\"Name\":\"Before\"}},\"intended_changes\":{\"state\":\"present\",\"value\":{\"Name\":\"After\"}},\"row_idempotency_key\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_guard\":{\"state\":\"version\",\"version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"target_row_identity\":\"001000000000001\"}],\"count\":1,\"effect_id\":\"WriteOne\",\"effect_identity_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"effect_kind\":\"update\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"executed\":false,\"mapping\":\"mapping:fixture\",\"max_items\":1,\"on_item_failure\":\"halt\",\"preview_strength\":\"full_diff\",\"required_permissions\":[\"write\"],\"resolved_mapping_contract_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"row_order\":[\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\"],\"source_binding_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"target\":\"Object\",\"write_footprint\":{\"kind\":\"exact_targets\",\"provider_boundary_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"provider_namespace\":\"fixture\",\"provider_object_identity_cids\":[\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\"],\"resource_identity_scheme_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"resource_kind\":\"file\"}}],\"encryption_required\":true,\"executed\":false,\"invocation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"model_derived\":false,\"model_invocation_evidence_cids\":[],\"model_response_artifact_cids\":[],\"model_task_contract_cids\":[],\"program_definition_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"program_semantics_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"retention_class\":\"authority-evidence\",\"run_identity_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"sensitivity\":\"private\",\"version\":\"actql-effect-preview/0.1\"}",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a",
    20000, 2000, 32,
  ).unwrap()
  let operation = prepare_effect_file_operation(
    original, 0, 0, "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb", "sha256:3333333333333333333333333333333333333333333333333333333333333333",
    "sha256:4444444444444444444444444444444444444444444444444444444444444444", "sha256:7777777777777777777777777777777777777777777777777777777777777777",
    "sha256:6666666666666666666666666666666666666666666666666666666666666666", "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  ).unwrap()
  let evidence = admit_effect_file_replacement_evidence(
    @utf8.encode(
      " {\"items\":[{\"Id\":3,\"e\\u0301\":\"raw\\r\\n\",\"é\":null}],\"keep\":true}\n",
    ),
    "16777234",
    "18446744073709551615",
    64L,
    4096,
  ).unwrap()
  // foreign effect_preview_cid
  assert_true(
    admit_effect_file_operation_receipt(
      operation, evidence, "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"backend_kind\":\"json_file\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"installation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:7741f11300e4591b8ca6099c9f5dc1e0cb2e8a4a176500906a02ba543f76f8fa\",\"replacement_byte_count\":64,\"replacement_generation\":{\"device\":\"16777234\",\"inode\":\"18446744073709551615\",\"size\":\"64\"},\"replacement_physical_sha256\":\"e64f47a0258db63ce7b5f85121d4a4fd22679ec1fecc2c60bfde30d2a3eb3fdf\",\"replacement_status\":\"acknowledged\",\"resolution_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // foreign effect_member_preview_cid
  assert_true(
    admit_effect_file_operation_receipt(
      operation, evidence, "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"backend_kind\":\"json_file\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:1f3035ba37d959ec1c0ad8b295c5a4382c3723553c2d1afb6374c63246824533\",\"replacement_byte_count\":64,\"replacement_generation\":{\"device\":\"16777234\",\"inode\":\"18446744073709551615\",\"size\":\"64\"},\"replacement_physical_sha256\":\"e64f47a0258db63ce7b5f85121d4a4fd22679ec1fecc2c60bfde30d2a3eb3fdf\",\"replacement_status\":\"acknowledged\",\"resolution_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // foreign row_preview_cid
  assert_true(
    admit_effect_file_operation_receipt(
      operation, evidence, "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"backend_kind\":\"json_file\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:1922ba1cd99061169e6cf68b85fd7006414fce27d2a003769595309a3d1e45c7\",\"replacement_byte_count\":64,\"replacement_generation\":{\"device\":\"16777234\",\"inode\":\"18446744073709551615\",\"size\":\"64\"},\"replacement_physical_sha256\":\"e64f47a0258db63ce7b5f85121d4a4fd22679ec1fecc2c60bfde30d2a3eb3fdf\",\"replacement_status\":\"acknowledged\",\"resolution_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"row_preview_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"target_cid\":\"sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // foreign installation_cid
  assert_true(
    admit_effect_file_operation_receipt(
      operation, evidence, "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"backend_kind\":\"json_file\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:d050ffe0e88744550618f5b08f38aa6397c46d7f34e8a196e0372d548d8981fb\",\"replacement_byte_count\":64,\"replacement_generation\":{\"device\":\"16777234\",\"inode\":\"18446744073709551615\",\"size\":\"64\"},\"replacement_physical_sha256\":\"e64f47a0258db63ce7b5f85121d4a4fd22679ec1fecc2c60bfde30d2a3eb3fdf\",\"replacement_status\":\"acknowledged\",\"resolution_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // foreign target_cid
  assert_true(
    admit_effect_file_operation_receipt(
      operation, evidence, "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"backend_kind\":\"json_file\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:b4880abc27ed5c8da1929fc57d2c2c8bd41627d4cc5a2a669ab30f51b33b3c1e\",\"replacement_byte_count\":64,\"replacement_generation\":{\"device\":\"16777234\",\"inode\":\"18446744073709551615\",\"size\":\"64\"},\"replacement_physical_sha256\":\"e64f47a0258db63ce7b5f85121d4a4fd22679ec1fecc2c60bfde30d2a3eb3fdf\",\"replacement_status\":\"acknowledged\",\"resolution_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // foreign canonical_request_cid
  assert_true(
    admit_effect_file_operation_receipt(
      operation, evidence, "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"backend_kind\":\"json_file\",\"canonical_request_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:5e961e9707aff0d82c03ea5aeac083773eff5a0a7ddccbb16cb6b5abe561edbd\",\"replacement_byte_count\":64,\"replacement_generation\":{\"device\":\"16777234\",\"inode\":\"18446744073709551615\",\"size\":\"64\"},\"replacement_physical_sha256\":\"e64f47a0258db63ce7b5f85121d4a4fd22679ec1fecc2c60bfde30d2a3eb3fdf\",\"replacement_status\":\"acknowledged\",\"resolution_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // foreign dispatch_entry_cid
  assert_true(
    admit_effect_file_operation_receipt(
      operation, evidence, "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"backend_kind\":\"json_file\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"dispatch_entry_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:09f6333a11d41777f6b81e41a05582a6ce0459635d196af40a3615ed5909d9b9\",\"replacement_byte_count\":64,\"replacement_generation\":{\"device\":\"16777234\",\"inode\":\"18446744073709551615\",\"size\":\"64\"},\"replacement_physical_sha256\":\"e64f47a0258db63ce7b5f85121d4a4fd22679ec1fecc2c60bfde30d2a3eb3fdf\",\"replacement_status\":\"acknowledged\",\"resolution_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // foreign authorization_context_cid
  assert_true(
    admit_effect_file_operation_receipt(
      operation, evidence, "{\"authorization_context_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"backend_kind\":\"json_file\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:4790d8c85366f9050e945b845f9e89d53a75a657d19338c4531db7cdf5f5ccc5\",\"replacement_byte_count\":64,\"replacement_generation\":{\"device\":\"16777234\",\"inode\":\"18446744073709551615\",\"size\":\"64\"},\"replacement_physical_sha256\":\"e64f47a0258db63ce7b5f85121d4a4fd22679ec1fecc2c60bfde30d2a3eb3fdf\",\"replacement_status\":\"acknowledged\",\"resolution_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // foreign resolution_cid
  assert_true(
    admit_effect_file_operation_receipt(
      operation, evidence, "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"backend_kind\":\"json_file\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:4361db9c0fdbf4e7ed3d07d2450f9ea739cf5d03a06def29363f43a67d9b844a\",\"replacement_byte_count\":64,\"replacement_generation\":{\"device\":\"16777234\",\"inode\":\"18446744073709551615\",\"size\":\"64\"},\"replacement_physical_sha256\":\"e64f47a0258db63ce7b5f85121d4a4fd22679ec1fecc2c60bfde30d2a3eb3fdf\",\"replacement_status\":\"acknowledged\",\"resolution_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // foreign target_version_cid
  assert_true(
    admit_effect_file_operation_receipt(
      operation, evidence, "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"backend_kind\":\"json_file\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:af3ef31baf2e42575807a6551fa2a183057e2ab290ee774113d40a70d1dfdd12\",\"replacement_byte_count\":64,\"replacement_generation\":{\"device\":\"16777234\",\"inode\":\"18446744073709551615\",\"size\":\"64\"},\"replacement_physical_sha256\":\"e64f47a0258db63ce7b5f85121d4a4fd22679ec1fecc2c60bfde30d2a3eb3fdf\",\"replacement_status\":\"acknowledged\",\"resolution_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb\",\"target_version_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // missing authorization_context_cid
  assert_true(
    admit_effect_file_operation_receipt(
      operation, evidence, "{\"backend_kind\":\"json_file\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:0fc17b39ea30f209ea6502b3f40bd61bdbad763c76364ba3eff634b4448b3119\",\"replacement_byte_count\":64,\"replacement_generation\":{\"device\":\"16777234\",\"inode\":\"18446744073709551615\",\"size\":\"64\"},\"replacement_physical_sha256\":\"e64f47a0258db63ce7b5f85121d4a4fd22679ec1fecc2c60bfde30d2a3eb3fdf\",\"replacement_status\":\"acknowledged\",\"resolution_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // missing resolution_cid
  assert_true(
    admit_effect_file_operation_receipt(
      operation, evidence, "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"backend_kind\":\"json_file\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:be7754682ab4d57b55ccf9fd165ab533b990c1a1fe278e41b39f0040f210c2c7\",\"replacement_byte_count\":64,\"replacement_generation\":{\"device\":\"16777234\",\"inode\":\"18446744073709551615\",\"size\":\"64\"},\"replacement_physical_sha256\":\"e64f47a0258db63ce7b5f85121d4a4fd22679ec1fecc2c60bfde30d2a3eb3fdf\",\"replacement_status\":\"acknowledged\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // missing replacement_generation
  assert_true(
    admit_effect_file_operation_receipt(
      operation, evidence, "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"backend_kind\":\"json_file\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:76bbff3e8e95a8031ff17e4ec24086889e5932320511cbaa03eedd326a51c98b\",\"replacement_byte_count\":64,\"replacement_physical_sha256\":\"e64f47a0258db63ce7b5f85121d4a4fd22679ec1fecc2c60bfde30d2a3eb3fdf\",\"replacement_status\":\"acknowledged\",\"resolution_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // uncertain replacement
  assert_true(
    admit_effect_file_operation_receipt(
      operation, evidence, "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"backend_kind\":\"json_file\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:621ab001ed15ec909a77c56e3f2201bded46e3cc4c9af12d7547480c26c18210\",\"replacement_byte_count\":64,\"replacement_generation\":{\"device\":\"16777234\",\"inode\":\"18446744073709551615\",\"size\":\"64\"},\"replacement_physical_sha256\":\"e64f47a0258db63ce7b5f85121d4a4fd22679ec1fecc2c60bfde30d2a3eb3fdf\",\"replacement_status\":\"unknown\",\"resolution_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // SQLite atomic substitution
  assert_true(
    admit_effect_file_operation_receipt(
      operation, evidence, "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"backend_kind\":\"sqlite\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"commit_status\":\"committed\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:f3b57b412e5163b6b30b1465dd6d2f86ee6328d10f340bd5b28f73898ac0ce81\",\"replacement_byte_count\":64,\"replacement_generation\":{\"device\":\"16777234\",\"inode\":\"18446744073709551615\",\"size\":\"64\"},\"replacement_physical_sha256\":\"e64f47a0258db63ce7b5f85121d4a4fd22679ec1fecc2c60bfde30d2a3eb3fdf\",\"replacement_status\":\"acknowledged\",\"resolution_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // HTTP substitution
  assert_true(
    admit_effect_file_operation_receipt(
      operation, evidence, "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"backend_kind\":\"json_file\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"credential_use_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"http_status_code\":200,\"installation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:b476f23bbe6b9cbf184463ffc09a6b3d3b5910271a885db40a0ebe6aca118eab\",\"replacement_byte_count\":64,\"replacement_generation\":{\"device\":\"16777234\",\"inode\":\"18446744073709551615\",\"size\":\"64\"},\"replacement_physical_sha256\":\"e64f47a0258db63ce7b5f85121d4a4fd22679ec1fecc2c60bfde30d2a3eb3fdf\",\"replacement_status\":\"acknowledged\",\"resolution_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // foreign physical digest
  assert_true(
    admit_effect_file_operation_receipt(
      operation, evidence, "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"backend_kind\":\"json_file\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:6a754554d0473a3680d10f040c14c0bfcd1baafb7cbcee67cbf22326b52733df\",\"replacement_byte_count\":64,\"replacement_generation\":{\"device\":\"16777234\",\"inode\":\"18446744073709551615\",\"size\":\"64\"},\"replacement_physical_sha256\":\"0000000000000000000000000000000000000000000000000000000000000000\",\"replacement_status\":\"acknowledged\",\"resolution_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // foreign byte count
  assert_true(
    admit_effect_file_operation_receipt(
      operation, evidence, "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"backend_kind\":\"json_file\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:822ca65ab4bf920e9a6723457db1f2758b13b7713123d207a3974db35bbd8b0f\",\"replacement_byte_count\":65,\"replacement_generation\":{\"device\":\"16777234\",\"inode\":\"18446744073709551615\",\"size\":\"64\"},\"replacement_physical_sha256\":\"e64f47a0258db63ce7b5f85121d4a4fd22679ec1fecc2c60bfde30d2a3eb3fdf\",\"replacement_status\":\"acknowledged\",\"resolution_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // foreign generation
  assert_true(
    admit_effect_file_operation_receipt(
      operation, evidence, "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"backend_kind\":\"json_file\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:b72862b7aab34cf3864b67f6fb28c30761da5f7e2929cf28ae7af9060b67e61a\",\"replacement_byte_count\":64,\"replacement_generation\":{\"device\":\"16777234\",\"inode\":\"7\",\"size\":\"64\"},\"replacement_physical_sha256\":\"e64f47a0258db63ce7b5f85121d4a4fd22679ec1fecc2c60bfde30d2a3eb3fdf\",\"replacement_status\":\"acknowledged\",\"resolution_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // noncanonical generation
  assert_true(
    admit_effect_file_operation_receipt(
      operation, evidence, "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"backend_kind\":\"json_file\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:378464bc09289fe51966b015e07ab2c2ca00c73d07035b3e2524fefa321bab9e\",\"replacement_byte_count\":64,\"replacement_generation\":{\"device\":\"01\",\"inode\":\"18446744073709551615\",\"size\":\"64\"},\"replacement_physical_sha256\":\"e64f47a0258db63ce7b5f85121d4a4fd22679ec1fecc2c60bfde30d2a3eb3fdf\",\"replacement_status\":\"acknowledged\",\"resolution_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // generation trailing newline
  assert_true(
    admit_effect_file_operation_receipt(
      operation, evidence, "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"backend_kind\":\"json_file\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:8570204605d1c2be6e1814fe67e6c0a602dd7d67c2f1dc56ce184974fe4c82c7\",\"replacement_byte_count\":64,\"replacement_generation\":{\"device\":\"1\\n\",\"inode\":\"18446744073709551615\",\"size\":\"64\"},\"replacement_physical_sha256\":\"e64f47a0258db63ce7b5f85121d4a4fd22679ec1fecc2c60bfde30d2a3eb3fdf\",\"replacement_status\":\"acknowledged\",\"resolution_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // generation overflow
  assert_true(
    admit_effect_file_operation_receipt(
      operation, evidence, "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"backend_kind\":\"json_file\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:9817261e0b236fb4ff9f0d6c592405f2293f540897757b8ea1d9fb6f3873b01e\",\"replacement_byte_count\":64,\"replacement_generation\":{\"device\":\"16777234\",\"inode\":\"18446744073709551616\",\"size\":\"64\"},\"replacement_physical_sha256\":\"e64f47a0258db63ce7b5f85121d4a4fd22679ec1fecc2c60bfde30d2a3eb3fdf\",\"replacement_status\":\"acknowledged\",\"resolution_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // unobserved outcome
  assert_true(
    admit_effect_file_operation_receipt(
      operation, evidence, "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"backend_kind\":\"json_file\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:004653aa55190e27c44bfc2699c7be70be8687b4cc9bfd98dab97aee357d10f3\",\"replacement_byte_count\":64,\"replacement_generation\":{\"device\":\"16777234\",\"inode\":\"18446744073709551615\",\"size\":\"64\"},\"replacement_physical_sha256\":\"e64f47a0258db63ce7b5f85121d4a4fd22679ec1fecc2c60bfde30d2a3eb3fdf\",\"replacement_status\":\"acknowledged\",\"resolution_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"state\":\"unknown\"},\"typed_outcome_cid\":\"sha256:ddf4274a393f4610550c660e8a06f971530b3e11813047f0ec5ba1e99bd50969\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  // false typed identity
  assert_true(
    admit_effect_file_operation_receipt(
      operation, evidence, "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"backend_kind\":\"json_file\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"dispatch_entry_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"installation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"operation_kind\":\"update\",\"receipt_cid\":\"sha256:f4e9c3cf9f22c6ca42ec5025afd40900978cbef0131290efb1bf5339970d63b4\",\"replacement_byte_count\":64,\"replacement_generation\":{\"device\":\"16777234\",\"inode\":\"18446744073709551615\",\"size\":\"64\"},\"replacement_physical_sha256\":\"e64f47a0258db63ce7b5f85121d4a4fd22679ec1fecc2c60bfde30d2a3eb3fdf\",\"replacement_status\":\"acknowledged\",\"resolution_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_cid\":\"sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb\",\"target_version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"typed_outcome\":{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:0000000000000000000000000000000000000000000000000000000000000000\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
}

///|
test "file operation evidence refuses noncanonical generation sizes and unobserved outcomes" {
  let original = admit_effect_preview_identity(
    "{\"authoring_context\":{\"annotations\":[],\"authoring_context_cid\":\"sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a\",\"program_definition_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-authoring-context/0.1\"},\"barrier_provenance_cids\":[],\"check_environment_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"effect_preview_cid\":\"sha256:3a14d7c0b9f2621348576dce89999b1603d11cd68555242a0b7c5fd9be5f0968\",\"effects\":[{\"approval\":\"required\",\"authority_scope_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"capability_evidence_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"changes\":[{\"after\":{\"state\":\"present\",\"value\":{\"Name\":\"After\"}},\"before\":{\"state\":\"present\",\"value\":{\"Name\":\"Before\"}},\"intended_changes\":{\"state\":\"present\",\"value\":{\"Name\":\"After\"}},\"row_idempotency_key\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"row_preview_cid\":\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\",\"target_guard\":{\"state\":\"version\",\"version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"target_row_identity\":\"001000000000001\"}],\"count\":1,\"effect_id\":\"WriteOne\",\"effect_identity_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"effect_kind\":\"update\",\"effect_member_preview_cid\":\"sha256:6d695f925df3fb3e7def1c1b31318d37f50b0a7189de0b5b78eb2901d80b8584\",\"executed\":false,\"mapping\":\"mapping:fixture\",\"max_items\":1,\"on_item_failure\":\"halt\",\"preview_strength\":\"full_diff\",\"required_permissions\":[\"write\"],\"resolved_mapping_contract_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"row_order\":[\"sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8\"],\"source_binding_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"target\":\"Object\",\"write_footprint\":{\"kind\":\"exact_targets\",\"provider_boundary_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"provider_namespace\":\"fixture\",\"provider_object_identity_cids\":[\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\"],\"resource_identity_scheme_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"resource_kind\":\"file\"}}],\"encryption_required\":true,\"executed\":false,\"invocation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"model_derived\":false,\"model_invocation_evidence_cids\":[],\"model_response_artifact_cids\":[],\"model_task_contract_cids\":[],\"program_definition_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"program_semantics_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"retention_class\":\"authority-evidence\",\"run_identity_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"sensitivity\":\"private\",\"version\":\"actql-effect-preview/0.1\"}",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a",
    20000, 2000, 32,
  ).unwrap()
  let operation = prepare_effect_file_operation(
    original, 0, 0, "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb", "sha256:3333333333333333333333333333333333333333333333333333333333333333",
    "sha256:4444444444444444444444444444444444444444444444444444444444444444", "sha256:7777777777777777777777777777777777777777777777777777777777777777",
    "sha256:6666666666666666666666666666666666666666666666666666666666666666", "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  ).unwrap()
  let evidence = admit_effect_file_replacement_evidence(
    @utf8.encode(
      " {\"items\":[{\"Id\":3,\"e\\u0301\":\"raw\\r\\n\",\"é\":null}],\"keep\":true}\n",
    ),
    "16777234",
    "18446744073709551615",
    64L,
    4096,
  ).unwrap()
  assert_true(
    admit_effect_file_replacement_evidence(
      @utf8.encode(
        " {\"items\":[{\"Id\":3,\"e\\u0301\":\"raw\\r\\n\",\"é\":null}],\"keep\":true}\n",
      ),
      "",
      "18446744073709551615",
      64L,
      4096,
    )
    is Err(_),
  )
  assert_true(
    admit_effect_file_replacement_evidence(
      @utf8.encode(
        " {\"items\":[{\"Id\":3,\"e\\u0301\":\"raw\\r\\n\",\"é\":null}],\"keep\":true}\n",
      ),
      "01",
      "18446744073709551615",
      64L,
      4096,
    )
    is Err(_),
  )
  assert_true(
    admit_effect_file_replacement_evidence(
      @utf8.encode(
        " {\"items\":[{\"Id\":3,\"e\\u0301\":\"raw\\r\\n\",\"é\":null}],\"keep\":true}\n",
      ),
      "-1",
      "18446744073709551615",
      64L,
      4096,
    )
    is Err(_),
  )
  assert_true(
    admit_effect_file_replacement_evidence(
      @utf8.encode(
        " {\"items\":[{\"Id\":3,\"e\\u0301\":\"raw\\r\\n\",\"é\":null}],\"keep\":true}\n",
      ),
      "1\n",
      "18446744073709551615",
      64L,
      4096,
    )
    is Err(_),
  )
  assert_true(
    admit_effect_file_replacement_evidence(
      @utf8.encode(
        " {\"items\":[{\"Id\":3,\"e\\u0301\":\"raw\\r\\n\",\"é\":null}],\"keep\":true}\n",
      ),
      "18446744073709551616",
      "18446744073709551615",
      64L,
      4096,
    )
    is Err(_),
  )
  assert_true(
    admit_effect_file_replacement_evidence(
      @utf8.encode(
        " {\"items\":[{\"Id\":3,\"e\\u0301\":\"raw\\r\\n\",\"é\":null}],\"keep\":true}\n",
      ),
      "16777234",
      "18446744073709551615",
      0L,
      4096,
    )
    is Err(_),
  )
  assert_true(
    admit_effect_file_replacement_evidence(
      @utf8.encode(
        " {\"items\":[{\"Id\":3,\"e\\u0301\":\"raw\\r\\n\",\"é\":null}],\"keep\":true}\n",
      ),
      "16777234",
      "18446744073709551615",
      64L,
      1,
    )
    is Err(_),
  )
  assert_true(
    prepare_effect_file_operation_receipt(
      operation, evidence, "{\"state\":\"unknown\"}", 20000, 2000, 32,
    )
    is Err(_),
  )
  assert_true(
    prepare_effect_file_operation_receipt(
      operation, evidence, "{\"action\":\"updated\",\"result\":{},\"state\":\"applied\"}",
      20000, 2000, 32,
    )
    is Err(_),
  )
  let response = prepare_effect_file_operation_receipt(
    operation, evidence, "{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"}",
    20000, 2000, 32,
  ).unwrap()
  assert_true(
    issue_effect_row_outcome_receipt_from_file(
      original, 0, 0, "sha256:0000000000000000000000000000000000000000000000000000000000000000",
      response, 20000, 2000, 32,
    )
    is Err(_),
  )
}
