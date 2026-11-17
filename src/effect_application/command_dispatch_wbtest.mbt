///|
// Fixtures and expected row/set/dispatch CIDs were independently authored
// with Python SHA-256 over the specified canonical 0.1 preimages.
fn command_dispatch_fixture(
  multi : Bool,
) -> (String, @publication.EffectPreviewIdentity) {
  let wire = if multi {
    "{\"authoring_context\":{\"annotations\":[],\"authoring_context_cid\":\"sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a\",\"program_definition_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-authoring-context/0.1\"},\"barrier_provenance_cids\":[],\"check_environment_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"effect_preview_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"effects\":[{\"authority_scope_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"capability_evidence_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"changes\":[{\"after\":{\"state\":\"not_applicable\"},\"before\":{\"state\":\"not_applicable\"},\"intended_changes\":{\"state\":\"present\",\"value\":{\"body\":\"value-0\",\"path\":\"dependency-00.txt\"}},\"row_idempotency_key\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"row_preview_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"target_guard\":{\"state\":\"not_applicable\"},\"target_row_identity\":{\"$actql_ref\":\"resource\",\"authority_scope_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"boundary_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"identity_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"provider_identity_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"provider_namespace\":\"fixture\",\"resource_kind\":\"file\",\"version\":\"actql-resource-ref/0.1\"}},{\"after\":{\"state\":\"not_applicable\"},\"before\":{\"state\":\"not_applicable\"},\"intended_changes\":{\"state\":\"present\",\"value\":{\"body\":\"value-1\",\"path\":\"dependency-01.txt\"}},\"row_idempotency_key\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"row_preview_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"target_guard\":{\"state\":\"not_applicable\"},\"target_row_identity\":{\"$actql_ref\":\"resource\",\"authority_scope_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"boundary_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"identity_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"provider_identity_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"provider_namespace\":\"fixture\",\"resource_kind\":\"file\",\"version\":\"actql-resource-ref/0.1\"}}],\"contract\":\"command:fixture\",\"count\":2,\"effect_id\":\"write\",\"effect_identity_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"effect_kind\":\"command\",\"effect_member_preview_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"executed\":false,\"max_items\":2,\"on_item_failure\":\"halt\",\"preview_strength\":\"full_diff\",\"required_permissions\":[\"write\"],\"resolved_command_contract_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"row_order\":[\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"sha256:3333333333333333333333333333333333333333333333333333333333333333\"],\"source_binding_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"target\":\"file\",\"write_footprint\":{\"kind\":\"collection\",\"provider_boundary_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"provider_namespace\":\"fixture\",\"provider_object_identity_cids\":[],\"resource_identity_scheme_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"resource_kind\":\"file\"}}],\"encryption_required\":true,\"executed\":false,\"invocation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"model_derived\":false,\"model_invocation_evidence_cids\":[],\"model_response_artifact_cids\":[],\"model_task_contract_cids\":[],\"program_definition_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"program_semantics_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"retention_class\":\"authority-evidence\",\"run_identity_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"sensitivity\":\"private\",\"version\":\"actql-effect-preview/0.1\"}"
  } else {
    "{\"authoring_context\":{\"annotations\":[],\"authoring_context_cid\":\"sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a\",\"program_definition_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"version\":\"actql-authoring-context/0.1\"},\"barrier_provenance_cids\":[],\"check_environment_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"compiled_plan_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"effect_preview_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"effects\":[{\"authority_scope_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"capability_evidence_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"changes\":[{\"after\":{\"state\":\"not_applicable\"},\"before\":{\"state\":\"not_applicable\"},\"intended_changes\":{\"state\":\"present\",\"value\":{\"body\":\"value-0\",\"path\":\"dependency-00.txt\"}},\"row_idempotency_key\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"row_preview_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"target_guard\":{\"state\":\"not_applicable\"},\"target_row_identity\":{\"$actql_ref\":\"resource\",\"authority_scope_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"boundary_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"identity_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"provider_identity_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"provider_namespace\":\"fixture\",\"resource_kind\":\"file\",\"version\":\"actql-resource-ref/0.1\"}}],\"contract\":\"command:fixture\",\"count\":1,\"effect_id\":\"write\",\"effect_identity_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"effect_kind\":\"command\",\"effect_member_preview_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"executed\":false,\"max_items\":2,\"on_item_failure\":\"halt\",\"preview_strength\":\"full_diff\",\"required_permissions\":[\"write\"],\"resolved_command_contract_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"row_order\":[\"sha256:2222222222222222222222222222222222222222222222222222222222222222\"],\"source_binding_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"target\":\"file\",\"write_footprint\":{\"kind\":\"collection\",\"provider_boundary_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"provider_namespace\":\"fixture\",\"provider_object_identity_cids\":[],\"resource_identity_scheme_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"resource_kind\":\"file\"}}],\"encryption_required\":true,\"executed\":false,\"invocation_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"model_derived\":false,\"model_invocation_evidence_cids\":[],\"model_response_artifact_cids\":[],\"model_task_contract_cids\":[],\"program_definition_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"program_semantics_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"retention_class\":\"authority-evidence\",\"run_identity_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"sensitivity\":\"private\",\"version\":\"actql-effect-preview/0.1\"}"
  }
  @publication.author_effect_preview_semantic_wire(
    wire,
    preview_footprint_test_cid("a"),
    "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a",
    16384,
    1024,
    16,
  ).unwrap()
}

///|
test "multirow Command binds distinct full arguments without changing its collection target" {
  let (semantic, identity) = command_dispatch_fixture(true)
  let scope = prepare_logical_request_scope(
    preview_footprint_test_cid("a"),
    "command-request",
    32,
  ).unwrap()
  assert_eq(
    @publication.effect_preview_semantic_identity(identity),
    "sha256:4ecfbc3a5591220f53f98f74b1117b6c17f087423d952b988957b4b1eec70b92",
  )
  let keys = []
  for row in 0..<2 {
    let key = prepare_effect_preview_row_dispatch_key(
      identity, scope, 0, row, 4096, 64, 8,
    ).unwrap()
    keys.push(key)
    assert_eq(
      effect_dispatch_key_correlation_wire(key),
      "\"" +
      @publication.effect_preview_row_identity(identity, 0, row).unwrap() +
      "\"",
    )
  }
  assert_eq(
    effect_dispatch_key_cid(keys[0]),
    "sha256:dc0d50581a1d87e7e43954f4479bfa1f93de3bf4a8efe6a64b40a1be5becbeac",
  )
  assert_eq(
    effect_dispatch_key_cid(keys[1]),
    "sha256:a2a427868e99cdc2dd78395b271479dab795afe56af0e6f949c45136472f073d",
  )
  assert_true(
    effect_dispatch_key_cid(keys[0]) != effect_dispatch_key_cid(keys[1]),
  )
  assert_eq(
    @publication.effect_preview_row_correlation_wire(identity, 0, 0),
    @publication.effect_preview_row_correlation_wire(identity, 0, 1),
  )
  let completed = @publication.complete_effect_preview_dispatch_keys(
    semantic,
    [keys.map(effect_dispatch_key_cid)],
    preview_footprint_test_cid("a"),
    "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a",
    16384,
    1024,
    16,
  ).unwrap()
  let admitted = admit_effect_preview_apply_identity(
    completed,
    preview_footprint_test_cid("a"),
    "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a",
    scope,
    [keys],
    16384,
    1024,
    16,
  ).unwrap()
  let recovered = recover_effect_preview_apply_keys(
    admitted, scope, 1, 2, 4, 4096, 64, 8,
  ).unwrap()
  let bindings = prepare_effect_recovery_bindings(
    admitted, scope, "program", "unit", 2, 3,
  ).unwrap()
  let owned = prepare_effect_recovery_bindings_from_keys(
    admitted, scope, "program", "unit", recovered, 2, 3,
  ).unwrap()
  for row in 0..<2 {
    assert_eq(
      effect_dispatch_key_cid(recovered[0][row]),
      effect_dispatch_key_cid(keys[row]),
    )
    let locator = prepare_logical_item_locator(
      scope,
      "program",
      "unit",
      "write",
      effect_dispatch_key_correlation_wire(recovered[0][row]),
      64,
      4096,
      64,
      8,
    ).unwrap()
    assert_true(physical_equal(owned[0][row].key, recovered[0][row]))
    assert_eq(
      effect_dispatch_key_cid(bindings[0][row].key),
      effect_dispatch_key_cid(keys[row]),
    )
    assert_eq(
      logical_item_locator_cid(bindings[0][row].locator),
      logical_item_locator_cid(locator),
    )
    assert_eq(
      logical_item_locator_cid(owned[0][row].locator),
      logical_item_locator_cid(locator),
    )
    assert_true(
      admit_effect_single_row(
        admitted,
        0,
        row,
        "command",
        scope,
        @publication.effect_preview_row_identity(admitted, 0, row).unwrap(),
        locator,
        recovered[0][row],
      )
      is Ok(_),
    )
  }
  assert_true(
    check_admitted_effect_preview_apply_keys(admitted, scope, [
      [keys[1], keys[0]],
    ])
    is Err(RowKeyMismatch(0, 0)),
  )
  let foreign = prepare_logical_request_scope(
    preview_footprint_test_cid("a"),
    "different-request",
    32,
  ).unwrap()
  assert_true(
    recover_effect_preview_apply_keys(admitted, foreign, 1, 2, 4, 4096, 64, 8)
    is Err(Mismatch(RowKeyMismatch(0, 0))),
  )
  assert_true(
    check_admitted_effect_preview_apply_keys(admitted, foreign, [keys])
    is Err(ForeignKeyScope(0, 0)),
  )
  assert_true(
    prepare_effect_recovery_bindings_from_keys(
      admitted, foreign, "program", "unit", recovered, 2, 3,
    )
    is Err(ForeignPreviewRow(0, 0)),
  )
  assert_true(
    prepare_effect_recovery_bindings_from_keys(
      admitted,
      scope,
      "program",
      "unit",
      [[keys[1], keys[0]]],
      2,
      3,
    )
    is Err(ForeignPreviewRow(0, 0)),
  )
  assert_true(
    prepare_effect_recovery_bindings_from_keys(
      admitted,
      scope,
      "program",
      "unit",
      [[keys[0]]],
      2,
      3,
    )
    is Err(InvalidLimits),
  )
  assert_true(
    prepare_effect_recovery_bindings_from_keys(
      admitted, scope, "program", "unit", recovered, 1, 3,
    )
    is Err(InvalidLimits),
  )
  assert_true(
    prepare_effect_recovery_bindings_from_keys(
      admitted, scope, "program", "unit", recovered, 2, 2,
    )
    is Err(InvalidLimits),
  )
  assert_true(
    recover_effect_preview_apply_keys(admitted, scope, 1, 2, 2, 4096, 64, 8)
    is Err(CapacityExceeded),
  )
  assert_true(
    prepare_effect_preview_row_dispatch_key(identity, scope, 0, 0, 72, 64, 8)
    is Err(InvalidRowKey),
  )
  assert_true(
    prepare_effect_preview_row_dispatch_key(identity, scope, 0, 2, 4096, 64, 8)
    is Err(InvalidRowKey),
  )
}

///|
test "singleton Command Saved keeps its exact legacy dispatch and locator" {
  let (semantic, identity) = command_dispatch_fixture(false)
  let scope = prepare_logical_request_scope(
    preview_footprint_test_cid("a"),
    "command-request",
    32,
  ).unwrap()
  let key = prepare_effect_preview_row_dispatch_key(
    identity, scope, 0, 0, 4096, 64, 8,
  ).unwrap()
  assert_eq(
    effect_dispatch_key_cid(key),
    "sha256:e9843c0a274f9851eaf2d441a1d976c2049e53dbac507cdb4f10450e0435dc07",
  )
  let raw = @publication.effect_preview_row_correlation_wire(identity, 0, 0).unwrap()
  assert_eq(effect_dispatch_key_correlation_wire(key), raw)
  let legacy = prepare_effect_dispatch_key(
    scope,
    @publication.effect_preview_semantic_identity(identity),
    raw,
    4096,
    64,
    8,
  ).unwrap()
  assert_eq(effect_dispatch_key_cid(key), effect_dispatch_key_cid(legacy))
  let completed = @publication.complete_effect_preview_dispatch_keys(
    semantic,
    [[effect_dispatch_key_cid(legacy)]],
    preview_footprint_test_cid("a"),
    "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a",
    16384,
    1024,
    16,
  ).unwrap()
  let admitted = admit_effect_preview_apply_identity(
    completed,
    preview_footprint_test_cid("a"),
    "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a",
    scope,
    [[legacy]],
    16384,
    1024,
    16,
  ).unwrap()
  let recovered = recover_effect_preview_apply_keys(
      admitted, scope, 1, 1, 2, 4096, 64, 8,
    ).unwrap()[0][0]
  assert_eq(effect_dispatch_key_cid(recovered), effect_dispatch_key_cid(legacy))
  let locator = prepare_logical_item_locator(
    scope, "program", "unit", "write", raw, 64, 4096, 64, 8,
  ).unwrap()
  let restored = prepare_logical_item_locator(
    scope,
    "program",
    "unit",
    "write",
    effect_dispatch_key_correlation_wire(recovered),
    64,
    4096,
    64,
    8,
  ).unwrap()
  assert_eq(
    logical_item_locator_cid(locator),
    logical_item_locator_cid(restored),
  )
  for
    bindings in [
      prepare_effect_recovery_bindings(admitted, scope, "program", "unit", 1, 2).unwrap(),
      prepare_effect_recovery_bindings_from_keys(
        admitted,
        scope,
        "program",
        "unit",
        [[recovered]],
        1,
        2,
      ).unwrap(),
    ] {
    assert_eq(
      effect_dispatch_key_cid(bindings[0][0].key),
      effect_dispatch_key_cid(legacy),
    )
    assert_eq(
      logical_item_locator_cid(bindings[0][0].locator),
      logical_item_locator_cid(locator),
    )
  }
  assert_true(
    admit_effect_single_row(
      admitted,
      0,
      0,
      "command",
      scope,
      @publication.effect_preview_row_identity(admitted, 0, 0).unwrap(),
      restored,
      recovered,
    )
    is Ok(_),
  )
}

///|
test "Command recovery borrows physical keys in independently declared row order" {
  let (original_wire, original) = command_dispatch_fixture(true)
  let row0 = @publication.effect_preview_row_identity(original, 0, 0).unwrap()
  let row1 = @publication.effect_preview_row_identity(original, 0, 1).unwrap()
  // A saved admitted Preview may carry a row order distinct from its physical
  // change enumeration. Authoring itself selects source order, so admit the
  // explicit reversed permutation with freshly derived semantic identities.
  let reordered = original_wire.replace_all(
    old="\"row_order\":[\"" + row0 + "\",\"" + row1 + "\"]",
    new="\"row_order\":[\"" + row1 + "\",\"" + row0 + "\"]",
  )
  let (set_cid, member_cids) = @publication.derive_effect_preview_identities(
    reordered, 16384, 1024, 16,
  ).unwrap()
  let semantic = reordered
    .replace_all(
      old=@publication.effect_preview_semantic_identity(original),
      new=set_cid,
    )
    .replace_all(
      old=@publication.effect_preview_member_identity(original, 0).unwrap(),
      new=member_cids[0],
    )
  let identity = @publication.admit_effect_preview_identity(
    semantic,
    preview_footprint_test_cid("a"),
    "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a",
    16384,
    1024,
    16,
  ).unwrap()
  let scope = prepare_logical_request_scope(
    preview_footprint_test_cid("a"),
    "command-request",
    32,
  ).unwrap()
  let keys = [0, 1].map(row => {
    prepare_effect_preview_row_dispatch_key(
      identity, scope, 0, row, 4096, 64, 8,
    ).unwrap()
  })
  let completed = semantic
    .replace_all(
      old="\"row_idempotency_key\":\"" + row0 + "\"",
      new="\"row_idempotency_key\":\"" + effect_dispatch_key_cid(keys[0]) + "\"",
    )
    .replace_all(
      old="\"row_idempotency_key\":\"" + row1 + "\"",
      new="\"row_idempotency_key\":\"" + effect_dispatch_key_cid(keys[1]) + "\"",
    )
  let admitted = admit_effect_preview_apply_identity(
    completed,
    preview_footprint_test_cid("a"),
    "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a",
    scope,
    [keys],
    16384,
    1024,
    16,
  ).unwrap()
  assert_eq(
    @publication.effect_preview_ordered_row_identity(admitted, 0, 0),
    @publication.effect_preview_row_identity(admitted, 0, 1),
  )
  let owned = prepare_effect_recovery_bindings_from_keys(
    admitted,
    scope,
    "program",
    "unit",
    [keys],
    2,
    3,
  ).unwrap()
  let legacy = prepare_effect_recovery_bindings(
    admitted, scope, "program", "unit", 2, 3,
  ).unwrap()
  for ordered in 0..<2 {
    let physical = 1 - ordered
    assert_true(physical_equal(owned[0][ordered].key, keys[physical]))
    assert_eq(
      effect_dispatch_key_cid(legacy[0][ordered].key),
      effect_dispatch_key_cid(keys[physical]),
    )
    assert_eq(
      owned[0][ordered].locator.item_correlation_wire,
      effect_dispatch_key_correlation_wire(keys[physical]),
    )
  }
}
