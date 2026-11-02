///|
fn plan_inventory_preview(
  kind : String,
  with_plan : Bool,
) -> @publication.EffectPreviewIdentity {
  let cid = "sha256:" + "a".repeat(64)
  let authoring = "sha256:633e8876a362716def8f98ac40a7cc85b5583602690954e890c43372517b4e0a"
  // A shape-admitted empty Preview isolates proof selection, not captured
  // input custody or dispatch authority. The real captured UPDATE caller is
  // tested separately through the Node bridge.
  let contract = if kind == "command" {
    "\"contract\":\"command:fixture\",\"resolved_command_contract_cid\":\"" +
    cid +
    "\","
  } else {
    "\"mapping\":\"mapping:fixture\",\"resolved_mapping_contract_cid\":\"" +
    cid +
    "\","
  }
  let approval = if kind == "command" { "" } else { "\"approval\":\"none\"," }
  let plan = if with_plan {
    "\"effect_plan_logical_cid\":\"" + cid + "\","
  } else {
    ""
  }
  let source = if kind == "create" {
    ""
  } else {
    "\"source_result\":\"r\",\"result_artifact_cid\":\"" + cid + "\","
  }
  let raw = "{\"version\":\"actql-effect-preview/0.1\",\"sensitivity\":\"private\",\"retention_class\":\"authority-evidence\",\"encryption_required\":true," +
    "\"program_semantics_cid\":\"" +
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
    "\"," +
    "\"authoring_context\":{\"version\":\"actql-authoring-context/0.1\",\"program_definition_cid\":\"" +
    cid +
    "\",\"annotations\":[],\"authoring_context_cid\":\"" +
    authoring +
    "\"}," +
    "\"barrier_provenance_cids\":[],\"model_derived\":false,\"model_task_contract_cids\":[],\"model_invocation_evidence_cids\":[],\"model_response_artifact_cids\":[]," +
    "\"effects\":[{\"effect_id\":\"save\",\"effect_kind\":\"" +
    kind +
    "\",\"target\":\"Object\"," +
    contract +
    plan +
    source +
    "\"effect_identity_cid\":\"" +
    cid +
    "\",\"preview_strength\":\"full_diff\",\"source_binding_cid\":\"" +
    cid +
    "\",\"capability_evidence_cid\":\"" +
    cid +
    "\",\"authority_scope_cid\":\"" +
    cid +
    "\"," +
    "\"write_footprint\":{\"kind\":\"exact_targets\",\"resource_identity_scheme_cid\":\"" +
    cid +
    "\",\"provider_namespace\":\"fixture\",\"provider_boundary_cid\":\"" +
    cid +
    "\",\"resource_kind\":\"Object\",\"provider_object_identity_cids\":[]}," +
    "\"count\":0,\"max_items\":1,\"required_permissions\":[\"write\"]," +
    approval +
    "\"on_item_failure\":\"halt\",\"changes\":[],\"row_order\":[],\"effect_member_preview_cid\":\"" +
    cid +
    "\",\"executed\":false}],\"executed\":false,\"effect_preview_cid\":\"" +
    cid +
    "\"}"
  let parsed = @source.parse_json(raw, {
    max_input_bytes: 8192,
    max_nodes: 512,
    max_depth: 16,
  }).unwrap()
  let canonical = @identity.stringify_value(
    @identity.from_source(parsed, 512, 16, 8192),
    8192,
    512,
    16,
  ) catch {
    issue => abort(issue.to_string())
  }
  @publication.author_effect_preview_semantic_wire(
    canonical, cid, authoring, 8192, 512, 16,
  ).unwrap().1
}

///|
test "Command payload proof is required without a Mapping Plan CID" {
  let command = plan_inventory_preview("command", false)
  assert_eq(@publication.effect_preview_member_plan_cid(command, 0), None)
  assert_true(captured_effect_member_requires_plan_proof(command, 0))
  assert_false(captured_effect_member_requires_plan_proof(command, -1))
  assert_false(captured_effect_member_requires_plan_proof(command, 1))
}

///|
test "Mapping payload proof selection retains the existing Plan obligation" {
  assert_true(
    captured_effect_member_requires_plan_proof(
      plan_inventory_preview("update", true),
      0,
    ),
  )
  assert_false(
    captured_effect_member_requires_plan_proof(
      plan_inventory_preview("create", false),
      0,
    ),
  )
}
