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
) -> (String, EffectDispatchKey) {
  let a = preview_footprint_test_cid("a")
  let authoring = "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a"
  let row = preview_footprint_test_cid("3")
  let placeholder = preview_footprint_test_cid("4")
  let effect = preview_footprint_test_member(
    "write",
    preview_footprint_test_cid("1"),
    "false",
    "halt",
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
  let (wire, key) = preview_apply_test_wire(scope)
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
