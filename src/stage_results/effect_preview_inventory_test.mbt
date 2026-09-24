///|
fn checked_preview_test_cid(digit : String) -> String {
  "sha256:" + digit.repeat(64)
}

///|
fn checked_preview_test_canonical(wire : String) -> String {
  let parsed = @source.parse_json(wire, {
    max_input_bytes: 8192,
    max_nodes: 256,
    max_depth: 12,
  }).unwrap()
  let value = @json.from_source(parsed, 256, 12, 8192) catch {
    _ => abort("Expected Preview fixture")
  }
  @json.stringify_value(value, 8192, 256, 12) catch {
    _ => abort("Expected canonical Preview fixture")
  }
}

///|
fn checked_preview_test_member(
  id : String,
  kind : String,
  policy : String,
  placeholder : String,
  reference : String,
  resolved_cid : String,
  plan_cid? : String? = None,
) -> String {
  let cid = checked_preview_test_cid("a")
  let contract_fields = if kind == "command" {
    "\"contract\":\"" +
    reference +
    "\",\"resolved_command_contract_cid\":\"" +
    resolved_cid +
    "\","
  } else {
    "\"mapping\":\"" +
    reference +
    "\",\"resolved_mapping_contract_cid\":\"" +
    resolved_cid +
    "\","
  }
  "{\"effect_id\":\"" +
  id +
  "\",\"effect_kind\":\"" +
  kind +
  "\",\"target\":\"Object\"," +
  contract_fields +
  "\"effect_identity_cid\":\"" +
  cid +
  "\",\"preview_strength\":\"full_diff\",\"source_binding_cid\":\"" +
  cid +
  "\",\"capability_evidence_cid\":\"" +
  cid +
  "\",\"authority_scope_cid\":\"" +
  cid +
  "\",\"write_footprint\":{\"kind\":\"exact_targets\"," +
  "\"resource_identity_scheme_cid\":\"" +
  cid +
  "\",\"provider_namespace\":\"provider\",\"provider_boundary_cid\":\"" +
  cid +
  "\",\"resource_kind\":\"Object\",\"provider_object_identity_cids\":[]}," +
  "\"count\":0,\"max_items\":1,\"required_permissions\":[\"write\"]," +
  "\"approval\":\"none\",\"on_item_failure\":\"" +
  policy +
  "\"," +
  (if plan_cid is Some(plan) {
    "\"effect_plan_logical_cid\":\"" + plan + "\","
  } else {
    ""
  }) +
  "\"changes\":[],\"row_order\":[],\"effect_member_preview_cid\":\"" +
  placeholder +
  "\",\"executed\":false}"
}

///|
fn checked_preview_test_identity(
  first : String,
  second : String,
  include_second? : Bool = true,
  first_kind? : String = "update",
  second_kind? : String = "update",
  second_policy? : String? = None,
  contract_reference? : String = "mapping:fixture",
  resolved_contract_cid? : String? = None,
  first_plan_cid? : String? = None,
  second_plan_cid? : String? = None,
) -> @publication.EffectPreviewIdentity {
  let cid = checked_preview_test_cid("a")
  let resolved_cid = match resolved_contract_cid {
    Some(value) => value
    None => cid
  }
  let authoring = "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a"
  let first_placeholder = checked_preview_test_cid("b")
  let second_placeholder = checked_preview_test_cid("c")
  let first_policy = if first == "second" { "continue" } else { "halt" }
  let selected_second_policy = match second_policy {
    Some(value) => value
    None => if second == "second" { "continue" } else { "halt" }
  }
  let first_member = checked_preview_test_member(
    first,
    first_kind,
    first_policy,
    first_placeholder,
    contract_reference,
    resolved_cid,
    plan_cid=first_plan_cid,
  )
  let members = if include_second {
    first_member +
    "," +
    checked_preview_test_member(
      second,
      second_kind,
      selected_second_policy,
      second_placeholder,
      contract_reference,
      resolved_cid,
      plan_cid=second_plan_cid,
    )
  } else {
    first_member
  }
  let raw = "{\"version\":\"actql-effect-preview/0.1\"," +
    "\"sensitivity\":\"private\",\"retention_class\":\"authority-evidence\"," +
    "\"encryption_required\":true,\"program_semantics_cid\":\"" +
    cid +
    "\",\"program_definition_cid\":\"" +
    cid +
    "\",\"invocation_cid\":\"" +
    cid +
    "\",\"run_identity_cid\":\"" +
    cid +
    "\",\"compiled_plan_cid\":\"" +
    cid +
    "\",\"check_environment_cid\":\"" +
    cid +
    "\",\"authoring_context\":{\"version\":\"actql-authoring-context/0.1\"," +
    "\"program_definition_cid\":\"" +
    cid +
    "\",\"annotations\":[],\"authoring_context_cid\":\"" +
    authoring +
    "\"},\"barrier_provenance_cids\":[],\"model_derived\":false," +
    "\"model_task_contract_cids\":[],\"model_invocation_evidence_cids\":[]," +
    "\"model_response_artifact_cids\":[],\"effects\":[" +
    members +
    "],\"executed\":false,\"effect_preview_cid\":\"" +
    cid +
    "\"}"
  let canonical = checked_preview_test_canonical(raw)
  let (_, member_cids) = @publication.derive_effect_preview_identities(
    canonical, 8192, 256, 12,
  ).unwrap()
  let with_first = canonical.replace_all(
    old="\"effect_member_preview_cid\":\"" + first_placeholder + "\"",
    new="\"effect_member_preview_cid\":\"" + member_cids[0] + "\"",
  )
  let with_members = checked_preview_test_canonical(
    if include_second {
      with_first.replace_all(
        old="\"effect_member_preview_cid\":\"" + second_placeholder + "\"",
        new="\"effect_member_preview_cid\":\"" + member_cids[1] + "\"",
      )
    } else {
      with_first
    },
  )
  let (preview_cid, _) = @publication.derive_effect_preview_identities(
    with_members, 8192, 256, 12,
  ).unwrap()
  let final_wire = with_members.replace_all(
    old="\"effect_preview_cid\":\"" + cid + "\"",
    new="\"effect_preview_cid\":\"" + preview_cid + "\"",
  )
  @publication.admit_effect_preview_identity(
    final_wire, cid, authoring, 8192, 256, 12,
  ).unwrap()
}

///|
test "checked Effect inventory rejects foreign Preview members" {
  let effects = "{\"first\":{\"update\":{\"target\":\"crm\",\"mapping\":\"mapping:crm.update.v1\",\"from\":{\"result\":\"r\"},\"id\":\"amount\",\"set\":{\"value\":{\"field\":\"amount\"}}}}," +
    "\"second\":{\"update\":{\"target\":\"crm\",\"mapping\":\"mapping:crm.update.v1\",\"from\":{\"result\":\"r\"},\"id\":\"amount\",\"set\":{\"value\":{\"field\":\"amount\"}},\"on_item_failure\":\"continue\"}}}"
  let (checked, headers) = effect_binding_inputs(effects)
  let bindings = bind_effect_results(headers, checked, 12).unwrap()
  let valid = checked_preview_test_identity("second", "first")
  assert_true(
    check_effect_preview_checked_inventory(bindings, 0, valid, 9) is Ok(_),
  )
  assert_true(
    check_effect_preview_checked_inventory(bindings, 0, valid, 8)
    is Err(WorkLimit),
  )
  assert_true(
    check_effect_preview_checked_inventory(bindings, 2, valid, 9)
    is Err(InvalidStage),
  )
  let foreign = checked_preview_test_identity("second", "foreign")
  assert_true(
    check_effect_preview_checked_inventory(bindings, 0, foreign, 9)
    is Err(MissingMember("first")),
  )
  let omitted = checked_preview_test_identity(
    "first",
    "second",
    include_second=false,
  )
  assert_true(
    check_effect_preview_checked_inventory(bindings, 0, omitted, 9)
    is Err(MemberCountMismatch),
  )
  let wrong_kind = checked_preview_test_identity(
    "second",
    "first",
    second_kind="create",
  )
  assert_true(
    check_effect_preview_checked_inventory(bindings, 0, wrong_kind, 9)
    is Err(KindMismatch("first")),
  )
  let wrong_policy = checked_preview_test_identity(
    "second",
    "first",
    second_policy=Some("continue"),
  )
  assert_true(
    check_effect_preview_checked_inventory(bindings, 0, wrong_policy, 9)
    is Err(FailurePolicyMismatch("first")),
  )
}

///|
test "static Effect inventory binds exact Mapping contract" {
  let effects = "{\"create\":{\"create\":{\"target\":\"connector://crm/account\",\"mapping\":\"mapping:crm.account.v1\",\"payload\":{\"Name\":7}}}}"
  let (checked, headers) = effect_binding_inputs(effects)
  let mappings = effect_mapping_shape_fixture()
  let candidate = prepare_effect_static_candidate(
    headers,
    checked,
    @environment.mapping_shape_environment(mappings),
    mappings,
    effect_static_candidate_catalogs(mappings),
    effect_static_candidate_limits(),
  ).unwrap()
  let mapping = @environment.mapping_shape_at(mappings, 0).unwrap()
  let reference = @environment.mapping_shape_reference(mapping)
  let resolved = @environment.mapping_shape_cid(mapping)
  let preview = checked_preview_test_identity(
    "create",
    "unused",
    include_second=false,
    first_kind="create",
    contract_reference=reference,
    resolved_contract_cid=Some(resolved),
  )
  assert_true(
    check_effect_preview_static_inventory(candidate, 0, preview, 20) is Ok(_),
  )
  assert_true(
    check_effect_preview_static_inventory(candidate, 0, preview, 0)
    is Err(Inventory(WorkLimit)),
  )
  let foreign_cid = checked_preview_test_identity(
    "create",
    "unused",
    include_second=false,
    first_kind="create",
    contract_reference=reference,
    resolved_contract_cid=Some(checked_preview_test_cid("f")),
  )
  assert_true(
    check_effect_preview_static_inventory(candidate, 0, foreign_cid, 20)
    is Err(ForeignResolvedContract("create")),
  )
  let foreign_ref = checked_preview_test_identity(
    "create",
    "unused",
    include_second=false,
    first_kind="create",
    contract_reference="mapping:crm.foreign.v1",
    resolved_contract_cid=Some(resolved),
  )
  assert_true(
    check_effect_preview_static_inventory(candidate, 0, foreign_ref, 20)
    is Err(ForeignResolvedContract("create")),
  )
}

///|
test "static Effect inventory binds exact Command contract" {
  let effects = "{\"command\":{\"command\":{\"target\":{\"field\":\"ref\"},\"contract\":\"command:crm.invoke.v1\",\"from\":{\"result\":\"r\"},\"input\":{}}}}"
  let (checked, headers) = effect_binding_inputs(
    effects,
    reference_nullable=Some(false),
  )
  let catalogs = command_target_catalog("crm/account")
  let mappings = @environment.check_mapping_contract_shapes(
    @environment.contract_registry_environment(
      @environment.catalog_registry(@environment.reference_contents(catalogs)),
    ),
    effect_static_candidate_environment_limits(),
    100,
  ).unwrap()
  let candidate = prepare_effect_static_candidate(
    headers,
    checked,
    @environment.mapping_shape_environment(mappings),
    mappings,
    catalogs,
    effect_static_candidate_limits(),
  ).unwrap()
  let binding = effect_command_target_at(
    effect_static_candidate_command_targets(candidate),
    0,
  ).unwrap()
  let resolved = @environment.member_cid(
    @environment.command_target_member(effect_command_target_contract(binding)),
  )
  let preview = checked_preview_test_identity(
    "command",
    "unused",
    include_second=false,
    first_kind="command",
    contract_reference="command:crm.invoke.v1",
    resolved_contract_cid=Some(resolved),
  )
  assert_true(
    check_effect_preview_static_inventory(candidate, 0, preview, 20) is Ok(_),
  )
  let foreign = checked_preview_test_identity(
    "command",
    "unused",
    include_second=false,
    first_kind="command",
    contract_reference="command:crm.foreign.v1",
    resolved_contract_cid=Some(resolved),
  )
  assert_true(
    check_effect_preview_static_inventory(candidate, 0, foreign, 20)
    is Err(ForeignResolvedContract("command")),
  )
}
