///|
fn preview_apply_test_canonical(wire : String) -> String {
  let parsed = @source.parse_json(wire, {
    max_input_bytes: 8192,
    max_nodes: 256,
    max_depth: 12,
  }).unwrap()
  let value = @json.from_source(parsed, 256, 12, 8192) catch {
    _ => abort("Expected Preview value")
  }
  @json.stringify_value(value, 8192, 256, 12) catch {
    _ => abort("Expected canonical Preview")
  }
}

///|
fn preview_apply_test_wire(
  scope : LogicalRequestScope,
  policy : String,
) -> (String, EffectDispatchKey) {
  let a = preview_footprint_test_cid("a")
  let authoring = "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a"
  let row = preview_footprint_test_cid("3")
  let placeholder = preview_footprint_test_cid("4")
  let effect = preview_footprint_test_member(
    "write",
    preview_footprint_test_cid("1"),
    "false",
    policy,
  )
  let base = preview_footprint_test_wire(effect).replace_all(
    old="\"authoring_context_cid\":\"" + a + "\"",
    new="\"authoring_context_cid\":\"" + authoring + "\"",
  )
  let change = "{\"target_row_identity\":\"row-1\"," +
    "\"before\":{\"state\":\"present\",\"value\":{}}," +
    "\"after\":{\"state\":\"present\",\"value\":{}}," +
    "\"row_preview_cid\":\"" +
    row +
    "\",\"row_idempotency_key\":\"" +
    placeholder +
    "\"}"
  let with_change = preview_apply_test_canonical(
    base
    .replace_all(old="\"changes\":[]", new="\"changes\":[" + change + "]")
    .replace_all(old="\"row_order\":[]", new="\"row_order\":[\"" + row + "\"]"),
  )
  let (_, members) = @publication.derive_effect_preview_identities(
    with_change, 8192, 256, 12,
  ).unwrap()
  let with_member = with_change.replace_all(
    old="\"effect_member_preview_cid\":\"" + a + "\"",
    new="\"effect_member_preview_cid\":\"" + members[0] + "\"",
  )
  let (preview_cid, _) = @publication.derive_effect_preview_identities(
    with_member, 8192, 256, 12,
  ).unwrap()
  let key = prepare_effect_dispatch_key(
    scope, preview_cid, "\"row-1\"", 128, 8, 3,
  ).unwrap()
  let wire = with_member
    .replace_all(
      old="\"effect_preview_cid\":\"" + a + "\"",
      new="\"effect_preview_cid\":\"" + preview_cid + "\"",
    )
    .replace_all(
      old="\"row_idempotency_key\":\"" + placeholder + "\"",
      new="\"row_idempotency_key\":\"" + key.cid + "\"",
    )
  (wire, key)
}

///|
test "Effect apply admits semantic Preview and exact derived row keys" {
  let a = preview_footprint_test_cid("a")
  let authoring = "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a"
  let scope = prepare_logical_request_scope(a, "request-1", 32).unwrap()
  let (wire, key) = preview_apply_test_wire(scope, "halt")
  assert_true(
    admit_effect_preview_apply_identity(
      wire,
      a,
      authoring,
      scope,
      [[key]],
      8192,
      256,
      12,
    )
    is Ok(_),
  )
  let wrong_key = wire.replace_all(
    old="\"row_idempotency_key\":\"" + key.cid + "\"",
    new="\"row_idempotency_key\":\"" + preview_footprint_test_cid("5") + "\"",
  )
  assert_true(
    admit_effect_preview_apply_identity(
      wrong_key,
      a,
      authoring,
      scope,
      [[key]],
      8192,
      256,
      12,
    )
    is Err(RowKeyMismatch(0, 0)),
  )
  let foreign_run = wire.replace_all(
    old="\"run_identity_cid\":\"" + a + "\"",
    new="\"run_identity_cid\":\"" + preview_footprint_test_cid("6") + "\"",
  )
  assert_true(
    admit_effect_preview_apply_identity(
      foreign_run,
      a,
      authoring,
      scope,
      [[key]],
      8192,
      256,
      12,
    )
    is Err(Preview(@publication.RunBindingMismatch)),
  )
  let other_scope = prepare_logical_request_scope(a, "request-2", 32).unwrap()
  assert_true(
    admit_effect_preview_apply_identity(
      wire,
      a,
      authoring,
      other_scope,
      [[key]],
      8192,
      256,
      12,
    )
    is Err(ForeignKeyScope(0, 0)),
  )
}

///|
test "Collections send rows match the admitted Preview and request scope" {
  let authority = preview_footprint_test_cid("a")
  let authoring = "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a"
  let row = preview_footprint_test_cid("3")
  let scope = prepare_logical_request_scope(authority, "request-1", 32).unwrap()
  let (wire, key) = preview_apply_test_wire(scope, "continue")
  let preview = admit_effect_preview_apply_identity(
    wire,
    authority,
    authoring,
    scope,
    [[key]],
    8192,
    256,
    12,
  ).unwrap()
  let locator = prepare_logical_item_locator(
    scope, "program-1", "node-1", "write", "\"row-1\"", 64, 128, 8, 3,
  ).unwrap()
  assert_true(
    admit_effect_collection_batch(
      preview,
      0,
      0,
      "update",
      scope,
      [row],
      [locator],
      [key],
      200,
      100,
    )
    is Ok(_),
  )
  assert_true(
    admit_effect_collection_batch(
      preview,
      0,
      0,
      "create",
      scope,
      [row],
      [locator],
      [key],
      200,
      100,
    )
    is Err(ForeignKind),
  )
  assert_true(
    admit_effect_collection_batch(
      preview,
      0,
      0,
      "update",
      scope,
      [preview_footprint_test_cid("5")],
      [locator],
      [key],
      200,
      100,
    )
    is Err(ForeignRow(0)),
  )
  let wrong_key = prepare_effect_dispatch_key(
    scope,
    @publication.effect_preview_semantic_identity(preview),
    "\"row-2\"",
    128,
    8,
    3,
  ).unwrap()
  assert_true(
    admit_effect_collection_batch(
      preview,
      0,
      0,
      "update",
      scope,
      [row],
      [locator],
      [wrong_key],
      200,
      100,
    )
    is Err(ForeignKey(0)),
  )
  let foreign = prepare_logical_item_locator(
    scope, "program-1", "node-1", "other", "\"row-1\"", 64, 128, 8, 3,
  ).unwrap()
  assert_true(
    admit_effect_collection_batch(
      preview,
      0,
      0,
      "update",
      scope,
      [row],
      [foreign],
      [key],
      200,
      100,
    )
    is Err(ForeignLocator(0)),
  )
  let foreign_row = prepare_logical_item_locator(
    scope, "program-1", "node-1", "write", "\"row-2\"", 64, 128, 8, 3,
  ).unwrap()
  assert_true(
    admit_effect_collection_batch(
      preview,
      0,
      0,
      "update",
      scope,
      [row],
      [foreign_row],
      [key],
      200,
      100,
    )
    is Err(ForeignLocator(0)),
  )
  assert_true(
    admit_effect_collection_batch(
      preview,
      0,
      1,
      "update",
      scope,
      [row],
      [locator],
      [key],
      200,
      100,
    )
    is Err(InvalidSlice),
  )
  assert_true(
    admit_effect_collection_batch(
      preview,
      0,
      0,
      "update",
      scope,
      [row],
      [locator],
      [key],
      200,
      1,
    )
    is Err(CapacityExceeded),
  )
  let (halt_wire, halt_key) = preview_apply_test_wire(scope, "halt")
  let halt_preview = admit_effect_preview_apply_identity(
    halt_wire,
    authority,
    authoring,
    scope,
    [[halt_key]],
    8192,
    256,
    12,
  ).unwrap()
  assert_true(
    admit_effect_collection_batch(
      halt_preview,
      0,
      0,
      "update",
      scope,
      [row],
      [locator],
      [halt_key],
      200,
      100,
    )
    is Err(ForeignPolicy),
  )
  assert_true(
    admit_effect_single_row(
      halt_preview, 0, 0, "update", scope, row, locator, halt_key,
    )
    is Ok(_),
  )
}

///|
test "Collections slices follow Preview row order rather than change order" {
  let authority = preview_footprint_test_cid("a")
  let authoring = "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a"
  let row_one = preview_footprint_test_cid("3")
  let row_two = preview_footprint_test_cid("5")
  let placeholder_one = preview_footprint_test_cid("4")
  let placeholder_two = preview_footprint_test_cid("6")
  let scope = prepare_logical_request_scope(authority, "request-1", 32).unwrap()
  let change = (row : String, key : String, identity : String) => {
    "{\"target_row_identity\":\"" +
    identity +
    "\",\"before\":{\"state\":\"present\",\"value\":{}}," +
    "\"after\":{\"state\":\"present\",\"value\":{}},\"row_preview_cid\":\"" +
    row +
    "\",\"row_idempotency_key\":\"" +
    key +
    "\"}"
  }
  let base = preview_footprint_test_wire(
    preview_footprint_test_member(
      "write",
      preview_footprint_test_cid("1"),
      "false",
      "continue",
    ),
  )
  let with_rows = preview_apply_test_canonical(
    base
    .replace_all(
      old="\"authoring_context_cid\":\"" + authority + "\"",
      new="\"authoring_context_cid\":\"" + authoring + "\"",
    )
    .replace_all(old="\"count\":1", new="\"count\":2")
    .replace_all(old="\"max_items\":1", new="\"max_items\":2")
    .replace_all(
      old="\"changes\":[]",
      new="\"changes\":[" +
        change(row_one, placeholder_one, "row-1") +
        "," +
        change(row_two, placeholder_two, "row-2") +
        "]",
    )
    .replace_all(
      old="\"row_order\":[]",
      new="\"row_order\":[\"" + row_two + "\",\"" + row_one + "\"]",
    ),
  )
  let (_, member_cids) = @publication.derive_effect_preview_identities(
    with_rows, 8192, 256, 12,
  ).unwrap()
  let with_member = with_rows.replace_all(
    old="\"effect_member_preview_cid\":\"" + authority + "\"",
    new="\"effect_member_preview_cid\":\"" + member_cids[0] + "\"",
  )
  let (preview_cid, _) = @publication.derive_effect_preview_identities(
    with_member, 8192, 256, 12,
  ).unwrap()
  let first_key = prepare_effect_dispatch_key(
    scope, preview_cid, "\"row-1\"", 128, 8, 3,
  ).unwrap()
  let second_key = prepare_effect_dispatch_key(
    scope, preview_cid, "\"row-2\"", 128, 8, 3,
  ).unwrap()
  let wire = with_member
    .replace_all(
      old="\"effect_preview_cid\":\"" + authority + "\"",
      new="\"effect_preview_cid\":\"" + preview_cid + "\"",
    )
    .replace_all(old=placeholder_one, new=effect_dispatch_key_cid(first_key))
    .replace_all(old=placeholder_two, new=effect_dispatch_key_cid(second_key))
  let preview = admit_effect_preview_apply_identity(
    wire,
    authority,
    authoring,
    scope,
    [[first_key, second_key]],
    8192,
    256,
    12,
  ).unwrap()
  let second_locator = prepare_logical_item_locator(
    scope, "program-1", "node-1", "write", "\"row-2\"", 64, 128, 8, 3,
  ).unwrap()
  let first_locator = prepare_logical_item_locator(
    scope, "program-1", "node-1", "write", "\"row-1\"", 64, 128, 8, 3,
  ).unwrap()
  assert_true(
    admit_effect_collection_batch(
      preview,
      0,
      0,
      "update",
      scope,
      [row_two, row_one],
      [second_locator, first_locator],
      [second_key, first_key],
      200,
      100,
    )
    is Ok(_),
  )
  assert_true(
    admit_effect_collection_batch(
      preview,
      0,
      0,
      "update",
      scope,
      [row_two, row_one],
      [second_locator, first_locator],
      [first_key, second_key],
      200,
      100,
    )
    is Err(ForeignKey(0)),
  )
  assert_true(
    admit_effect_collection_batch(
      preview,
      0,
      1,
      "update",
      scope,
      [row_one],
      [first_locator],
      [first_key],
      200,
      2,
    )
    is Ok(_),
  )
  assert_true(
    admit_effect_collection_batch(
      preview,
      0,
      0,
      "update",
      scope,
      [row_two, row_one],
      [second_locator, first_locator],
      [second_key, first_key],
      200,
      2,
    )
    is Err(CapacityExceeded),
  )
}
