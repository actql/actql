///|
fn preview_identity_test_cid(digit : String) -> String {
  "sha256:" + digit.repeat(64)
}

///|
fn preview_identity_test_wire(
  run_cid : String,
  authoring_cid : String,
  row_key : String,
  target : String,
  member_cid : String,
  preview_cid : String,
  empty? : Bool = false,
) -> String {
  let a = preview_identity_test_cid("a")
  let row = preview_identity_test_cid("3")
  let target_cid = preview_identity_test_cid("1")
  let raw = "{\"version\":\"actql-effect-preview/0.1\"," +
    "\"sensitivity\":\"private\",\"retention_class\":\"authority-evidence\"," +
    "\"encryption_required\":true,\"program_semantics_cid\":\"" +
    a +
    "\",\"program_definition_cid\":\"" +
    a +
    "\",\"invocation_cid\":\"" +
    a +
    "\",\"run_identity_cid\":\"" +
    run_cid +
    "\",\"compiled_plan_cid\":\"" +
    a +
    "\",\"check_environment_cid\":\"" +
    a +
    "\",\"authoring_context\":{\"version\":\"actql-authoring-context/0.1\"," +
    "\"program_definition_cid\":\"" +
    a +
    "\",\"annotations\":[],\"authoring_context_cid\":\"" +
    authoring_cid +
    "\"},\"barrier_provenance_cids\":[],\"model_derived\":false," +
    "\"model_task_contract_cids\":[],\"model_invocation_evidence_cids\":[]," +
    "\"model_response_artifact_cids\":[],\"effects\":[{" +
    "\"effect_id\":\"WriteOne\",\"effect_kind\":\"update\",\"target\":\"Object\"," +
    "\"mapping\":\"mapping:fixture\",\"resolved_mapping_contract_cid\":\"" +
    a +
    "\",\"effect_identity_cid\":\"" +
    a +
    "\",\"preview_strength\":\"full_diff\",\"source_binding_cid\":\"" +
    a +
    "\",\"capability_evidence_cid\":\"" +
    a +
    "\",\"authority_scope_cid\":\"" +
    a +
    "\",\"write_footprint\":{\"kind\":\"exact_targets\"," +
    "\"resource_identity_scheme_cid\":\"" +
    a +
    "\",\"provider_namespace\":\"provider\",\"provider_boundary_cid\":\"" +
    a +
    "\",\"resource_kind\":\"Object\",\"provider_object_identity_cids\":[\"" +
    target_cid +
    "\"]},\"count\":" +
    (if empty { "0" } else { "1" }) +
    ",\"max_items\":1,\"required_permissions\":[\"write\"]," +
    "\"approval\":\"none\",\"on_item_failure\":\"halt\"," +
    (if empty {
      "\"changes\":[],\"row_order\":[]"
    } else {
      "\"changes\":[{\"target_row_identity\":\"" +
      target +
      "\",\"before\":{\"state\":\"present\",\"value\":{\"Name\":\"Before\"}}," +
      "\"after\":{\"state\":\"present\",\"value\":{\"Name\":\"After\"}}," +
      "\"row_preview_cid\":\"" +
      row +
      "\",\"row_idempotency_key\":\"" +
      row_key +
      "\"}],\"row_order\":[\"" +
      row +
      "\"]"
    }) +
    ",\"effect_member_preview_cid\":\"" +
    member_cid +
    "\",\"executed\":false}],\"executed\":false,\"effect_preview_cid\":\"" +
    preview_cid +
    "\"}"
  let parsed = @source.parse_json(raw, {
    max_input_bytes: 8192,
    max_nodes: 256,
    max_depth: 12,
  }).unwrap()
  let value = @json.from_source(parsed, 256, 12, 8192) catch {
    _ => abort("Expected canonical Preview fixture")
  }
  @json.stringify_value(value, 8192, 256, 12) catch {
    _ => abort("Expected canonical Preview fixture")
  }
}

///|
test "Effect Preview 0.1 semantic and member CID exclude only derived bindings" {
  let a = preview_identity_test_cid("a")
  let row = preview_identity_test_cid("3")
  let authoring = "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a"
  let placeholder = preview_identity_test_wire(
    preview_identity_test_cid("b"),
    authoring,
    preview_identity_test_cid("4"),
    "001000000000001",
    a,
    a,
  )
  let (placeholder_set_cid, member_cids) = derive_effect_preview_identities(
    placeholder, 8192, 256, 12,
  ).unwrap()
  assert_eq(member_cids.length(), 1)
  let expected_member = member_cids[0]
  assert_eq(
    expected_member, "sha256:8cb73aa63f4fb802dc407177552e0cca0d43315ee8e804c703f2a5a2e9643ff1",
  )
  let member_fixed = preview_identity_test_wire(
    preview_identity_test_cid("b"),
    authoring,
    preview_identity_test_cid("4"),
    "001000000000001",
    expected_member,
    a,
  )
  let (preview_cid, _) = derive_effect_preview_identities(
    member_fixed, 8192, 256, 12,
  ).unwrap()
  assert_eq(
    preview_cid, "sha256:0a35e40b82f30bb3956ba610962a2ca987f4aca6a52bdb1cfac482833010eff5",
  )
  assert_eq(placeholder_set_cid, preview_cid)
  let valid = preview_identity_test_wire(
    preview_identity_test_cid("b"),
    authoring,
    preview_identity_test_cid("4"),
    "001000000000001",
    expected_member,
    preview_cid,
  )
  let admitted = admit_effect_preview_identity(
    valid,
    preview_identity_test_cid("b"),
    authoring,
    8192,
    256,
    12,
  ).unwrap()
  assert_eq(effect_preview_semantic_identity(admitted), preview_cid)
  assert_eq(effect_preview_member_identity(admitted, 0), Some(expected_member))
  assert_eq(effect_preview_member_identity(admitted, 1), None)
  let footprint = effect_preview_member_footprint(admitted, 0).unwrap()
  assert_eq(effect_preview_footprint_kind(footprint), "exact_targets")
  assert_eq(effect_preview_footprint_provider_namespace(footprint), "provider")
  assert_eq(effect_preview_footprint_provider_boundary_cid(footprint), a)
  assert_eq(effect_preview_footprint_resource_identity_scheme_cid(footprint), a)
  assert_eq(effect_preview_footprint_resource_kind(footprint), "Object")
  assert_eq(effect_preview_footprint_target_count(footprint), 1)
  assert_eq(
    effect_preview_footprint_target_cid(footprint, 0),
    Some(preview_identity_test_cid("1")),
  )
  assert_eq(effect_preview_footprint_target_cid(footprint, 1), None)
  assert_true(effect_preview_member_footprint(admitted, 1) is None)
  assert_eq(effect_preview_row_identity(admitted, 0, 0), Some(row))
  assert_eq(effect_preview_ordered_row_identity(admitted, 0, 0), Some(row))
  assert_eq(effect_preview_row_identity(admitted, 0, 1), None)
  let wrong_count = valid.replace_all(old="\"count\":1", new="\"count\":2")
  assert_true(
    admit_effect_preview_identity(
      wrong_count,
      preview_identity_test_cid("b"),
      authoring,
      8192,
      256,
      12,
    )
    is Err(RowInventoryMismatch(0)),
  )
  let second_row = preview_identity_test_cid("5")
  let second_key = preview_identity_test_cid("6")
  let over_limit = valid
    .replace_all(old="\"count\":1", new="\"count\":2")
    .replace_all(
      old="}],\"row_order\":[\"" + row + "\"]",
      new="},{\"target_row_identity\":\"001000000000002\"," +
        "\"before\":{\"state\":\"present\",\"value\":{\"Name\":\"Before\"}}," +
        "\"after\":{\"state\":\"present\",\"value\":{\"Name\":\"After\"}}," +
        "\"row_preview_cid\":\"" +
        second_row +
        "\"," +
        "\"row_idempotency_key\":\"" +
        second_key +
        "\"}]," +
        "\"row_order\":[\"" +
        row +
        "\",\"" +
        second_row +
        "\"]",
    )
  assert_true(
    derive_effect_preview_identities(over_limit, 8192, 256, 12)
    is Err(RowInventoryMismatch(0)),
  )
  assert_true(
    admit_effect_preview_identity(
      over_limit,
      preview_identity_test_cid("b"),
      authoring,
      8192,
      256,
      12,
    )
    is Err(RowInventoryMismatch(0)),
  )
  let foreign_order = valid.replace_all(
    old="\"row_order\":[\"" + row + "\"]",
    new="\"row_order\":[\"" + preview_identity_test_cid("6") + "\"]",
  )
  assert_true(
    admit_effect_preview_identity(
      foreign_order,
      preview_identity_test_cid("b"),
      authoring,
      8192,
      256,
      12,
    )
    is Err(RowInventoryMismatch(0)),
  )
  let forged_authoring = valid.replace_all(
    old="\"authoring_context_cid\":\"" +
      authoring +
      "\",\"program_definition_cid\":\"" +
      a +
      "\"",
    new="\"authoring_context_cid\":\"" +
      authoring +
      "\",\"program_definition_cid\":\"" +
      preview_identity_test_cid("d") +
      "\"",
  )
  let (forged_cid, _) = derive_effect_preview_identities(
    forged_authoring, 8192, 256, 12,
  ).unwrap()
  assert_eq(forged_cid, preview_cid)
  assert_true(
    admit_effect_preview_identity(
      forged_authoring,
      preview_identity_test_cid("b"),
      authoring,
      8192,
      256,
      12,
    )
    is Err(AuthoringIdentityMismatch),
  )
  let changed_bindings = preview_identity_test_wire(
    preview_identity_test_cid("d"),
    preview_identity_test_cid("e"),
    preview_identity_test_cid("5"),
    "001000000000001",
    expected_member,
    preview_cid,
  )
  let (same_cid, same_members) = derive_effect_preview_identities(
    changed_bindings, 8192, 256, 12,
  ).unwrap()
  assert_eq(same_cid, preview_cid)
  assert_eq(same_members[0], expected_member)
  assert_true(
    admit_effect_preview_identity(
      changed_bindings,
      preview_identity_test_cid("b"),
      authoring,
      8192,
      256,
      12,
    )
    is Err(RunBindingMismatch),
  )
  assert_true(
    admit_effect_preview_identity(
      changed_bindings,
      preview_identity_test_cid("d"),
      authoring,
      8192,
      256,
      12,
    )
    is Err(AuthoringBindingMismatch),
  )
  let changed_target = preview_identity_test_wire(
    preview_identity_test_cid("b"),
    authoring,
    preview_identity_test_cid("4"),
    "001000000000002",
    expected_member,
    preview_cid,
  )
  let (different_cid, different_members) = derive_effect_preview_identities(
    changed_target, 8192, 256, 12,
  ).unwrap()
  assert_true(different_cid != preview_cid)
  assert_true(different_members[0] != expected_member)
  assert_true(
    admit_effect_preview_identity(
      changed_target,
      preview_identity_test_cid("b"),
      authoring,
      8192,
      256,
      12,
    )
    is Err(MemberIdentityMismatch(0)),
  )
  let changed_payload = valid.replace_all(
    old="\"Name\":\"After\"",
    new="\"Name\":\"Different\"",
  )
  let (payload_cid, payload_members) = derive_effect_preview_identities(
    changed_payload, 8192, 256, 12,
  ).unwrap()
  assert_true(payload_cid != preview_cid)
  assert_true(payload_members[0] != expected_member)
  let changed_operation = valid.replace_all(
    old="\"effect_kind\":\"update\"",
    new="\"effect_kind\":\"upsert\"",
  )
  let (operation_cid, operation_members) = derive_effect_preview_identities(
    changed_operation, 8192, 256, 12,
  ).unwrap()
  assert_true(operation_cid != preview_cid)
  assert_true(operation_members[0] != expected_member)
}
