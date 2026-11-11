// Generated independent two-row reordered final-reducer controls. No physical IO or authority is claimed.

///|
fn file_ordered_receipt_fixture() -> (
  @publication.EffectPreviewIdentity,
  EffectRecoveryBinding,
  EffectLedgerBasis,
  EffectLedgerEntry,
  EffectLedgerEntry,
) raise {
  let scope = prepare_logical_request_scope(
    "sha256:7777777777777777777777777777777777777777777777777777777777777777", "ordered-file-request",
    256,
  ).unwrap()
  let wire = "{\"authoring_context\":{\"annotations\":[],\"authoring_context_cid\":\"sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a\",\"program_definition_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-authoring-context/0.1\"},\"barrier_provenance_cids\":[],\"check_environment_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"effect_preview_cid\":\"sha256:852e6a4986a8522861a48db32e78de8cb704dcac25c89f3ad29c8fd6a56e6558\",\"effects\":[{\"approval\":\"required\",\"authority_scope_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"capability_evidence_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"changes\":[{\"after\":{\"state\":\"present\",\"value\":{\"id\":\"B\",\"value\":2}},\"before\":{\"state\":\"present\",\"value\":{\"id\":\"B\",\"value\":1}},\"intended_changes\":{\"state\":\"present\",\"value\":{\"value\":2}},\"row_idempotency_key\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"row_preview_cid\":\"sha256:0426447180fcebf4aa8c57983b23050b177e74be6eabf33d1bdf07408cab5a50\",\"target_guard\":{\"state\":\"version\",\"version_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"},\"target_row_identity\":\"B\"},{\"after\":{\"state\":\"present\",\"value\":{\"id\":\"A\",\"value\":2}},\"before\":{\"state\":\"present\",\"value\":{\"id\":\"A\",\"value\":1}},\"intended_changes\":{\"state\":\"present\",\"value\":{\"value\":2}},\"row_idempotency_key\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"row_preview_cid\":\"sha256:2bb1bd032e4791127080a468bbca5dc144371bcdfe39efe0bfc44132a8d7f7ac\",\"target_guard\":{\"state\":\"version\",\"version_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"},\"target_row_identity\":\"A\"}],\"count\":2,\"effect_id\":\"WriteOne\",\"effect_identity_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"effect_kind\":\"update\",\"effect_member_preview_cid\":\"sha256:cd630afef85de308b8afd88f9fe2bedb737f4115ac1481437882a7e00b067cf9\",\"executed\":false,\"mapping\":\"mapping:fixture\",\"max_items\":2,\"on_item_failure\":\"halt\",\"preview_strength\":\"full_diff\",\"required_permissions\":[\"write\"],\"resolved_mapping_contract_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"row_order\":[\"sha256:2bb1bd032e4791127080a468bbca5dc144371bcdfe39efe0bfc44132a8d7f7ac\",\"sha256:0426447180fcebf4aa8c57983b23050b177e74be6eabf33d1bdf07408cab5a50\"],\"source_binding_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"target\":\"Object\",\"write_footprint\":{\"kind\":\"exact_targets\",\"provider_boundary_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"provider_namespace\":\"fixture\",\"provider_object_identity_cids\":[\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\"],\"resource_identity_scheme_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"resource_kind\":\"file\"}}],\"encryption_required\":true,\"executed\":false,\"invocation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"model_derived\":false,\"model_invocation_evidence_cids\":[],\"model_response_artifact_cids\":[],\"model_task_contract_cids\":[],\"program_definition_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"program_semantics_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"retention_class\":\"authority-evidence\",\"run_identity_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"sensitivity\":\"private\",\"version\":\"actql-effect-preview/0.1\"}"
  let initial = @publication.admit_effect_preview_identity(
    wire, "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a", 20000,
    512, 32,
  ).unwrap()
  let raw_a = prepare_effect_dispatch_key(
    scope,
    @publication.effect_preview_semantic_identity(initial),
    "\"B\"",
    256,
    32,
    8,
  ).unwrap()
  let raw_b = prepare_effect_dispatch_key(
    scope,
    @publication.effect_preview_semantic_identity(initial),
    "\"A\"",
    256,
    32,
    8,
  ).unwrap()
  let completed = @publication.complete_effect_preview_dispatch_keys(
    wire,
    [[raw_a.cid, raw_b.cid]],
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a",
    20000,
    512,
    32,
  ).unwrap()
  let preview = admit_effect_preview_apply_identity(
    completed,
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a",
    scope,
    [[raw_a, raw_b]],
    20000,
    512,
    32,
  ).unwrap()
  assert_eq(
    @publication.effect_preview_ordered_row_identity(preview, 0, 0),
    Some(
      "sha256:2bb1bd032e4791127080a468bbca5dc144371bcdfe39efe0bfc44132a8d7f7ac",
    ),
  )
  let binding = prepare_effect_recovery_bindings(
      preview, scope, "file-program", "file-node", 2, 3,
    ).unwrap()[0][0]
  let basis = prepare_effect_ledger_basis(
    scope,
    binding.locator,
    binding.key,
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "sha256:cd630afef85de308b8afd88f9fe2bedb737f4115ac1481437882a7e00b067cf9",
    "sha256:2bb1bd032e4791127080a468bbca5dc144371bcdfe39efe0bfc44132a8d7f7ac",
    "sha256:3333333333333333333333333333333333333333333333333333333333333333",
    "sha256:5555555555555555555555555555555555555555555555555555555555555555",
    "unavailable",
    "sha256:8888888888888888888888888888888888888888888888888888888888888888",
    "sha256:9999999999999999999999999999999999999999999999999999999999999999",
  ).unwrap()
  let prepared = issue_prepared_effect_ledger_entry(basis, 20000, 512, 32).unwrap()
  let dispatch = issue_next_effect_ledger_entry(
    prepared,
    "dispatching",
    None,
    20000,
    512,
    32,
  ).unwrap()
  (preview, binding, basis, prepared, dispatch)
}

///|
test "file ordered final reducer refuses another raw row at this ordinal" {
  let (preview, binding, basis, prepared, dispatch) = file_ordered_receipt_fixture()
  let metadata = @publication.seal_publication_contract(
    "effect_local_operation_receipt",
    "{\"authorization_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"backend_kind\":\"json_file\",\"canonical_request_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"dispatch_entry_cid\":\"@DISPATCH@\",\"effect_member_preview_cid\":\"sha256:cd630afef85de308b8afd88f9fe2bedb737f4115ac1481437882a7e00b067cf9\",\"effect_preview_cid\":\"sha256:852e6a4986a8522861a48db32e78de8cb704dcac25c89f3ad29c8fd6a56e6558\",\"installation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"operation_kind\":\"update\",\"replacement_byte_count\":64,\"replacement_generation\":{\"device\":\"16777234\",\"inode\":\"18446744073709551615\",\"size\":\"64\"},\"replacement_physical_sha256\":\"e64f47a0258db63ce7b5f85121d4a4fd22679ec1fecc2c60bfde30d2a3eb3fdf\",\"replacement_status\":\"acknowledged\",\"resolution_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"row_preview_cid\":\"sha256:0426447180fcebf4aa8c57983b23050b177e74be6eabf33d1bdf07408cab5a50\",\"target_cid\":\"sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb\",\"target_version_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"typed_outcome\":{\"result\":{\"row\":\"raw-A\"},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:5d8bae1b063b707ffb023cf121ba35d2a33dc3f8bd301385925b26ee0d4439ad\",\"version\":\"actql-local-effect-operation-receipt/0.1\"}".replace_all(
      old="@DISPATCH@",
      new=dispatch.cid,
    ),
    20000,
    512,
    32,
  ).unwrap()
  let local_wire = @publication.publication_contract_json(metadata)
  let saved = @publication.admit_saved_effect_file_operation_receipt(
    local_wire,
    @utf8.encode(
      " {\"items\":[{\"Id\":3,\"e\\u0301\":\"raw\\r\\n\",\"é\":null}],\"keep\":true}\n",
    ),
    4096,
    20000,
    512,
    32,
  ).unwrap()
  let row_body = "{\"dispatch_entry_cid\":\"@DISPATCH@\",\"effect_member_preview_cid\":\"sha256:cd630afef85de308b8afd88f9fe2bedb737f4115ac1481437882a7e00b067cf9\",\"effect_preview_cid\":\"sha256:852e6a4986a8522861a48db32e78de8cb704dcac25c89f3ad29c8fd6a56e6558\",\"local_operation_receipt_cid\":\"@LOCAL@\",\"response_byte_count\":\"@LENGTH@\",\"response_kind\":\"local_operation\",\"response_physical_sha256\":\"@SHA@\",\"row_preview_cid\":\"sha256:0426447180fcebf4aa8c57983b23050b177e74be6eabf33d1bdf07408cab5a50\",\"typed_outcome\":{\"result\":{\"row\":\"raw-A\"},\"state\":\"applied\"},\"typed_outcome_cid\":\"sha256:5d8bae1b063b707ffb023cf121ba35d2a33dc3f8bd301385925b26ee0d4439ad\",\"version\":\"actql-effect-row-outcome-receipt/0.1\"}"
    .replace_all(old="@DISPATCH@", new=dispatch.cid)
    .replace_all(
      old="@LOCAL@",
      new=@publication.publication_contract_identity(metadata),
    )
    .replace_all(old="@SHA@", new=@sha.hex(@utf8.encode(local_wire)))
    .replace_all(
      old="\"@LENGTH@\"",
      new=@utf8.encode(local_wire).length().to_string(),
    )
  let row = @publication.seal_publication_contract(
    "effect_row_outcome_receipt", row_body, 20000, 512, 32,
  ).unwrap()
  let committed = issue_effect_row_receipt_terminal_entry_from_file(
    preview,
    0,
    0,
    binding.scope,
    binding.locator,
    binding.key,
    basis.canonical_request_cid,
    dispatch,
    [prepared, dispatch],
    dispatch.cid,
    saved,
    @publication.publication_contract_json(row),
    20000,
    512,
    32,
  )
  @debug.debug_inspect(
    committed.map(entry => effect_ledger_entry_state_code(entry)),
    content="Err(ForeignReceipt)",
  )
}

///|
test "file ordered final reducer settles only the matching ordered row" {
  let (preview, binding, basis, prepared, dispatch) = file_ordered_receipt_fixture()
  let evidence = @publication.admit_effect_file_replacement_evidence(
    @utf8.encode(
      " {\"items\":[{\"Id\":3,\"e\\u0301\":\"raw\\r\\n\",\"é\":null}],\"keep\":true}\n",
    ),
    "16777234",
    "18446744073709551615",
    64L,
    4096,
  ).unwrap()
  let operation = @publication.prepare_effect_file_operation(
    preview,
    0,
    0,
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "sha256:9c8b13889918a09b3b24766920adc033cdf3e17d8d5e58dfe4173793aa13efcb",
    basis.canonical_request_cid,
    dispatch.cid,
    "sha256:7777777777777777777777777777777777777777777777777777777777777777",
    "sha256:6666666666666666666666666666666666666666666666666666666666666666",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  ).unwrap()
  assert_eq(
    operation.row_preview_cid,
    "sha256:2bb1bd032e4791127080a468bbca5dc144371bcdfe39efe0bfc44132a8d7f7ac",
  )
  let saved = @publication.prepare_effect_file_operation_receipt(
    operation, evidence, "{\"result\":{\"Id\":3,\"é\":\"raw\\r\\n\",\"é\":null},\"state\":\"applied\"}",
    20000, 512, 32,
  ).unwrap()
  let row = @publication.issue_effect_row_outcome_receipt_from_file(
    preview,
    0,
    0,
    dispatch.cid,
    saved,
    20000,
    512,
    32,
  ).unwrap()
  let terminal = issue_effect_row_receipt_terminal_entry_from_file(
    preview,
    0,
    0,
    binding.scope,
    binding.locator,
    binding.key,
    basis.canonical_request_cid,
    dispatch,
    [prepared, dispatch],
    dispatch.cid,
    saved,
    @publication.publication_contract_json(row),
    20000,
    512,
    32,
  ).unwrap()
  assert_eq(effect_ledger_entry_state_code(terminal), 2)
  assert_eq(terminal.logical_item_locator_cid, binding.locator.cid)
  assert_true(
    issue_effect_row_receipt_terminal_entry_from_file(
      preview,
      0,
      1,
      binding.scope,
      binding.locator,
      binding.key,
      basis.canonical_request_cid,
      dispatch,
      [prepared, dispatch],
      dispatch.cid,
      saved,
      @publication.publication_contract_json(row),
      20000,
      512,
      32,
    )
    is Err(_),
  )
}
