///|
fn preview_footprint_test_cid(digit : String) -> String {
  "sha256:" + digit.repeat(64)
}

///|
fn preview_footprint_test_member(
  effect_id : String,
  target : String,
  executed : String,
) -> String {
  let cid = preview_footprint_test_cid("a")
  "{\"effect_id\":\"" +
  effect_id +
  "\",\"effect_kind\":\"update\",\"target\":\"Object\",\"mapping\":\"mapping:fixture\"," +
  "\"resolved_mapping_contract_cid\":\"" +
  cid +
  "\",\"effect_identity_cid\":\"" +
  cid +
  "\",\"preview_strength\":\"full_diff\",\"source_binding_cid\":\"" +
  cid +
  "\",\"capability_evidence_cid\":\"" +
  cid +
  "\",\"authority_scope_cid\":\"" +
  cid +
  "\",\"write_footprint\":{\"kind\":\"exact_targets\",\"resource_identity_scheme_cid\":\"" +
  cid +
  "\",\"provider_namespace\":\"provider\",\"provider_boundary_cid\":\"" +
  cid +
  "\",\"resource_kind\":\"Object\",\"provider_object_identity_cids\":[\"" +
  target +
  "\"]},\"count\":1,\"max_items\":1,\"required_permissions\":[\"write\"]," +
  "\"approval\":\"none\",\"on_item_failure\":\"halt\",\"changes\":[],\"row_order\":[]," +
  "\"effect_member_preview_cid\":\"" +
  cid +
  "\",\"executed\":" +
  executed +
  "}"
}

///|
fn preview_footprint_test_wire(effects : String) -> String {
  let cid = preview_footprint_test_cid("a")
  let raw = "{\"version\":\"actql-effect-preview/0.1\",\"sensitivity\":\"private\"," +
    "\"retention_class\":\"authority-evidence\",\"encryption_required\":true," +
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
    "\",\"authoring_context\":{\"version\":\"actql-authoring-context/0.1\"," +
    "\"program_definition_cid\":\"" +
    cid +
    "\",\"annotations\":[],\"authoring_context_cid\":\"" +
    cid +
    "\"},\"barrier_provenance_cids\":[],\"model_derived\":false," +
    "\"model_task_contract_cids\":[],\"model_invocation_evidence_cids\":[]," +
    "\"model_response_artifact_cids\":[],\"effects\":[" +
    effects +
    "],\"executed\":false,\"effect_preview_cid\":\"" +
    cid +
    "\"}"
  let parsed = @source.parse_json(raw, {
    max_input_bytes: 8192,
    max_nodes: 256,
    max_depth: 12,
  }).unwrap()
  let value = @json.from_source(parsed, 256, 12, 8192) catch {
    _ => abort("Expected Preview fixture value")
  }
  @json.stringify_value(value, 8192, 256, 12) catch {
    _ => abort("Expected canonical Preview fixture")
  }
}

///|
test "Preview-derived footprint check sees every Effect Set member" {
  let first = preview_footprint_test_member(
    "first",
    preview_footprint_test_cid("1"),
    "false",
  )
  let second = preview_footprint_test_member(
    "second",
    preview_footprint_test_cid("2"),
    "false",
  )
  let disjoint = preview_footprint_test_wire(first + "," + second)
  assert_true(
    check_effect_preview_footprint_conflicts(disjoint, 8192, 256, 12, 2, 2, 100)
    is Ok(_),
  )
  assert_true(
    check_effect_preview_footprint_conflicts(disjoint, 8192, 256, 12, 2, 1, 100)
    is Err(Conflict(CapacityExceeded)),
  )
  let overlapping = preview_footprint_test_wire(
    first +
    "," +
    preview_footprint_test_member(
      "second",
      preview_footprint_test_cid("1"),
      "false",
    ),
  )
  assert_true(
    check_effect_preview_footprint_conflicts(
      overlapping, 8192, 256, 12, 2, 2, 100,
    )
    is Err(Conflict(OverlappingTarget)),
  )
}

///|
test "Preview shape failure cannot become a successful conflict check" {
  let invalid = preview_footprint_test_wire(
    preview_footprint_test_member(
      "first",
      preview_footprint_test_cid("1"),
      "true",
    ),
  )
  assert_true(
    check_effect_preview_footprint_conflicts(invalid, 8192, 256, 12, 1, 1, 100)
    is Err(PreviewShape(_)),
  )
  assert_true(
    check_effect_preview_footprint_conflicts("{}", 8192, 256, 12, 1, 1, 100)
    is Err(PreviewShape(_)),
  )
}
