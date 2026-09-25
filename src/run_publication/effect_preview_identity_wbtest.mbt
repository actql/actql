///|
fn preview_identity_test_cid(digit : String) -> String {
  "sha256:" + digit.repeat(64)
}

///|
fn preview_identity_test_canonical(wire : String) -> String {
  let parsed = @source.parse_json(wire, {
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
      "\",\"target_guard\":{\"state\":\"version\",\"version_cid\":\"" +
      a +
      "\"},\"intended_changes\":{\"state\":\"present\",\"value\":{\"Name\":\"After\"}}," +
      "\"before\":{\"state\":\"present\",\"value\":{\"Name\":\"Before\"}}," +
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
  let canonical = @json.stringify_value(value, 8192, 256, 12) catch {
    _ => abort("Expected canonical Preview fixture")
  }
  if empty {
    canonical
  } else {
    let rows = derive_effect_preview_row_identities(canonical, 8192, 256, 12).unwrap()
    canonical.replace_all(old=row, new=rows[0][0])
  }
}

///|
test "Preview authoring seals row, member, set and late dispatch bindings" {
  let a = preview_identity_test_cid("a")
  let run = preview_identity_test_cid("b")
  let authoring = "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a"
  let template = preview_identity_test_wire(
    run,
    authoring,
    preview_identity_test_cid("4"),
    "001000000000001",
    a,
    a,
  )
  let (semantic_wire, semantic) = author_effect_preview_semantic_wire(
    template, run, authoring, 8192, 256, 12,
  ).unwrap()
  assert_eq(
    effect_preview_semantic_identity(semantic),
    "sha256:2fe7f8e93988fcf4d7804e86b69a72d00e1c7bfd946c8fa29d6e91c706593409",
  )
  assert_eq(
    effect_preview_row_key(semantic, 0, 0),
    effect_preview_row_identity(semantic, 0, 0),
  )
  let final_wire = complete_effect_preview_dispatch_keys(
    semantic_wire,
    [[preview_identity_test_cid("4")]],
    run,
    authoring,
    8192,
    256,
    12,
  ).unwrap()
  let final_identity = admit_effect_preview_identity(
    final_wire, run, authoring, 8192, 256, 12,
  ).unwrap()
  assert_eq(
    effect_preview_semantic_identity(final_identity),
    effect_preview_semantic_identity(semantic),
  )
  assert_eq(
    effect_preview_row_key(final_identity, 0, 0),
    Some(preview_identity_test_cid("4")),
  )
  assert_true(
    complete_effect_preview_dispatch_keys(
      semantic_wire,
      [[]],
      run,
      authoring,
      8192,
      256,
      12,
    )
    is Err(InvalidMember),
  )
  assert_true(
    author_effect_preview_semantic_wire(
      template,
      preview_identity_test_cid("c"),
      authoring,
      8192,
      256,
      12,
    )
    is Err(RunBindingMismatch),
  )
}

///|
test "Effect Preview 0.1 semantic and member CID exclude only derived bindings" {
  let a = preview_identity_test_cid("a")
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
  let row = derive_effect_preview_row_identities(placeholder, 8192, 256, 12).unwrap()[0][0]
  assert_eq(
    row, "sha256:4531682e916a81a555998f41de7fef4c505a841b83d794d09d95db899d6e55c8",
  )
  assert_eq(member_cids.length(), 1)
  let expected_member = member_cids[0]
  assert_eq(
    expected_member, "sha256:099721c928770511d95faed4eaeef3fef768c4b573c714fc0af16c0b5439b5b6",
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
    preview_cid, "sha256:2fe7f8e93988fcf4d7804e86b69a72d00e1c7bfd946c8fa29d6e91c706593409",
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
  assert_eq(
    effect_preview_private_holding_cid(admitted, preview_identity_test_cid("c")),
    Some(
      "sha256:3a6b74ed61b92f77c62ac07d1a09e4f35b5952631374560d0da6c7235f21625b",
    ),
  )
  assert_eq(effect_preview_private_holding_cid(admitted, "foreign"), None)
  assert_true(
    effect_preview_private_holding_cid(admitted, preview_identity_test_cid("d")) !=
    effect_preview_private_holding_cid(admitted, preview_identity_test_cid("c")),
  )
  let another_run_wire = valid.replace_all(
    old=preview_identity_test_cid("b"),
    new=preview_identity_test_cid("d"),
  )
  let another_run = admit_effect_preview_identity(
    another_run_wire,
    preview_identity_test_cid("d"),
    authoring,
    8192,
    256,
    12,
  ).unwrap()
  assert_eq(effect_preview_semantic_identity(another_run), preview_cid)
  assert_true(
    effect_preview_private_holding_cid(
      another_run,
      preview_identity_test_cid("c"),
    ) !=
    effect_preview_private_holding_cid(admitted, preview_identity_test_cid("c")),
  )
  assert_eq(effect_preview_member_identity(admitted, 0), Some(expected_member))
  assert_eq(effect_preview_member_identity(admitted, 1), None)
  assert_eq(effect_preview_member_capability_evidence_cid(admitted, 0), Some(a))
  assert_eq(effect_preview_member_authority_scope_cid(admitted, 0), Some(a))
  assert_eq(effect_preview_member_source_binding_cid(admitted, 0), Some(a))
  assert_eq(effect_preview_member_resolved_contract_cid(admitted, 0), Some(a))
  assert_eq(effect_preview_member_capability_evidence_cid(admitted, 1), None)
  assert_eq(effect_preview_member_authority_scope_cid(admitted, 1), None)
  assert_eq(effect_preview_member_source_binding_cid(admitted, 1), None)
  assert_eq(effect_preview_member_resolved_contract_cid(admitted, 1), None)
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
  assert_eq(effect_preview_row_guard_version_cid(admitted, 0, 0), Some(a))
  assert_eq(effect_preview_row_guard_version_cid(admitted, 0, 1), None)
  assert_eq(effect_preview_row_index(admitted, 0, row), Some(0))
  assert_eq(
    effect_preview_row_intended_value_wire(admitted, 0, 0),
    Some("{\"Name\":\"After\"}"),
  )
  assert_eq(
    effect_preview_row_intended_changes_wire(admitted, 0, 0),
    Some("{\"state\":\"present\",\"value\":{\"Name\":\"After\"}}"),
  )
  assert_eq(
    effect_preview_ordered_row_intended_changes_wire(admitted, 0, 0),
    Some("{\"state\":\"present\",\"value\":{\"Name\":\"After\"}}"),
  )
  assert_eq(effect_preview_row_intended_changes_wire(admitted, 0, 1), None)
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
        "\"target_guard\":{\"state\":\"version\",\"version_cid\":\"" +
        a +
        "\"},\"intended_changes\":{\"state\":\"present\",\"value\":{\"Name\":\"After\"}}," +
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
  assert_true(
    derive_effect_preview_identities(changed_payload, 8192, 256, 12)
    is Err(RowIdentityMismatch(0, 0)),
  )
  let changed_intended = valid.replace_all(
    old="\"intended_changes\":{\"state\":\"present\",\"value\":{\"Name\":\"After\"}}",
    new="\"intended_changes\":{\"state\":\"present\",\"value\":{\"Name\":\"Different\"}}",
  )
  assert_true(
    derive_effect_preview_identities(changed_intended, 8192, 256, 12)
    is Err(RowIdentityMismatch(0, 0)),
  )
  let changed_guard = valid.replace_all(
    old="\"version_cid\":\"" + a + "\"",
    new="\"version_cid\":\"" + preview_identity_test_cid("d") + "\"",
  )
  assert_true(
    admit_effect_preview_identity(
      changed_guard,
      preview_identity_test_cid("b"),
      authoring,
      8192,
      256,
      12,
    )
    is Err(RowIdentityMismatch(0, 0)),
  )
  let missing_guard = valid.replace_all(
    old="\"target_guard\":{\"state\":\"version\",\"version_cid\":\"" +
      a +
      "\"},",
    new="",
  )
  assert_true(
    admit_effect_preview_identity(
      missing_guard,
      preview_identity_test_cid("b"),
      authoring,
      8192,
      256,
      12,
    )
    is Err(PreviewShape(_)),
  )
  let missing_intended = valid.replace_all(
    old="\"intended_changes\":{\"state\":\"present\",\"value\":{\"Name\":\"After\"}},",
    new="",
  )
  assert_true(
    admit_effect_preview_identity(
      missing_intended,
      preview_identity_test_cid("b"),
      authoring,
      8192,
      256,
      12,
    )
    is Err(PreviewShape(_)),
  )
  let borrowed_row_cid = valid.replace_all(
    old="\"target_row_identity\":\"001000000000001\"",
    new="\"target_row_identity\":\"001000000000002\"",
  )
  assert_true(
    admit_effect_preview_identity(
      borrowed_row_cid,
      preview_identity_test_cid("b"),
      authoring,
      8192,
      256,
      12,
    )
    is Err(RowIdentityMismatch(0, 0)),
  )
  let foreign_program = valid.replace_all(
    old="\"program_definition_cid\":\"" + a + "\"",
    new="\"program_definition_cid\":\"" + preview_identity_test_cid("d") + "\"",
  )
  assert_true(
    admit_effect_preview_identity(
      foreign_program,
      preview_identity_test_cid("b"),
      authoring,
      8192,
      256,
      12,
    )
    is Err(RowIdentityMismatch(0, 0)),
  )
  let foreign_invocation = valid.replace_all(
    old="\"invocation_cid\":\"" + a + "\"",
    new="\"invocation_cid\":\"" + preview_identity_test_cid("d") + "\"",
  )
  assert_true(
    derive_effect_preview_identities(foreign_invocation, 8192, 256, 12)
    is Err(RowIdentityMismatch(0, 0)),
  )
  let changed_operation = valid.replace_all(
    old="\"effect_kind\":\"update\"",
    new="\"effect_kind\":\"upsert\"",
  )
  assert_true(
    derive_effect_preview_identities(changed_operation, 8192, 256, 12)
    is Err(RowIdentityMismatch(0, 0)),
  )
}

///|
test "Effect row Outcome Receipt binds Preview, dispatch and saved bytes" {
  let authoring = "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a"
  let preview = admit_effect_preview_identity(
    preview_identity_test_wire(
      preview_identity_test_cid("b"),
      authoring,
      preview_identity_test_cid("4"),
      "001000000000001",
      "sha256:099721c928770511d95faed4eaeef3fef768c4b573c714fc0af16c0b5439b5b6",
      "sha256:2fe7f8e93988fcf4d7804e86b69a72d00e1c7bfd946c8fa29d6e91c706593409",
    ),
    preview_identity_test_cid("b"),
    authoring,
    8192,
    256,
    12,
  ).unwrap()
  let response = Bytes::from_array([0x7B, 0x7D])
  let dispatch_entries = [preview_identity_test_cid("5")]
  let saved_response = admit_effect_saved_response_evidence(
    dispatch_entries,
    preview_identity_test_cid("6"),
    response,
    201,
    8192,
  ).unwrap()
  dispatch_entries[0] = preview_identity_test_cid("7")
  assert_true(
    issue_effect_row_outcome_receipt_from_response(
      preview,
      0,
      0,
      preview_identity_test_cid("5"),
      saved_response,
      "{\"result\":{\"id\":\"001\"},\"state\":\"applied\"}",
      8192,
      256,
      12,
    )
    is Ok(_),
  )
  assert_true(
    issue_effect_row_outcome_receipt_from_response(
      preview,
      0,
      0,
      preview_identity_test_cid("7"),
      saved_response,
      "{\"result\":{\"id\":\"001\"},\"state\":\"applied\"}",
      8192,
      256,
      12,
    )
    is Err(InvalidDispatch),
  )
  let first = issue_effect_row_outcome_receipt(
    preview,
    0,
    0,
    preview_identity_test_cid("5"),
    preview_identity_test_cid("6"),
    response,
    201,
    "{\"result\":{\"id\":\"001\"},\"state\":\"applied\"}",
    8192,
    8192,
    256,
    12,
  ).unwrap()
  assert_eq(first.name, "effect_row_outcome_receipt")
  assert_eq(
    first.identity,
    "sha256:0b54f40a3e03a7840f08737b5efd2380f006aea8c4161a6ffeea0af461fe076f",
  )
  assert_eq(
    contract_string(first, "row_preview_cid"),
    effect_preview_row_identity(preview, 0, 0),
  )
  assert_eq(
    contract_string(first, "response_physical_sha256"),
    Some(@sha.hex(response)),
  )
  assert_true(
    admit_effect_row_outcome_receipt(
      preview,
      0,
      0,
      preview_identity_test_cid("5"),
      preview_identity_test_cid("6"),
      response,
      201,
      first.wire,
      8192,
      8192,
      256,
      12,
    )
    is Ok(_),
  )
  assert_true(
    admit_effect_row_outcome_receipt(
      preview,
      0,
      0,
      preview_identity_test_cid("7"),
      preview_identity_test_cid("6"),
      response,
      201,
      first.wire,
      8192,
      8192,
      256,
      12,
    )
    is Err(ForeignResponse),
  )
  assert_true(
    issue_effect_row_outcome_receipt(
      preview,
      0,
      1,
      preview_identity_test_cid("5"),
      preview_identity_test_cid("6"),
      response,
      201,
      "{\"result\":{},\"state\":\"applied\"}",
      8192,
      8192,
      256,
      12,
    )
    is Err(InvalidRow),
  )
  let changed = issue_effect_row_outcome_receipt(
    preview,
    0,
    0,
    preview_identity_test_cid("5"),
    preview_identity_test_cid("6"),
    Bytes::from_array([0x5B, 0x5D]),
    201,
    "{\"result\":{\"id\":\"001\"},\"state\":\"applied\"}",
    8192,
    8192,
    256,
    12,
  ).unwrap()
  assert_true(first.identity != changed.identity)
}

///|
test "Effect Preview source and captured Artifact cannot be split" {
  let cid = preview_identity_test_cid("a")
  let authoring = "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a"
  let raw = preview_identity_test_wire(
    cid,
    authoring,
    cid,
    "target",
    cid,
    cid,
    empty=true,
  )
  let without_artifact = preview_identity_test_canonical(
    raw.replace(
      old="\"preview_strength\":",
      new="\"source_result\":\"answer\",\"preview_strength\":",
    ),
  )
  assert_true(
    admit_effect_preview_identity(
      without_artifact, cid, authoring, 8192, 256, 12,
    )
    is Err(InvalidMember),
  )
  let without_source = preview_identity_test_canonical(
    raw.replace(
      old="\"preview_strength\":",
      new="\"result_artifact_cid\":\"" + cid + "\",\"preview_strength\":",
    ),
  )
  assert_true(
    admit_effect_preview_identity(without_source, cid, authoring, 8192, 256, 12)
    is Err(InvalidMember),
  )
}
