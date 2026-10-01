///|
fn protocol_test_property_node(
  name : String,
  path : Array[String],
) -> (Array[ProtocolSchemaRule], Int) {
  let nodes = generated_protocol_schema_nodes()
  let mut index = generated_protocol_schema_root(name, false).unwrap()
  for field in path {
    index = protocol_test_find_property(nodes, index, field).unwrap()
  }
  (nodes, index)
}

///|
fn protocol_test_find_property(
  nodes : Array[ProtocolSchemaRule],
  index : Int,
  field : String,
) -> Int? {
  match nodes[index] {
    ObjectRule(properties, _, _, _, _, _) =>
      protocol_property_schema(properties, field)
    AllOfRule(children) | OneOfRule(children) | AnyOfRule(children) => {
      for child in children {
        if protocol_test_find_property(nodes, child, field) is Some(found) {
          return Some(found)
        }
      }
      None
    }
    _ => None
  }
}

///|
fn protocol_test_accepts(
  nodes : Array[ProtocolSchemaRule],
  index : Int,
  wire : String,
) -> Bool {
  let value = parse_contract_wire(wire, 4096, 64, 8).unwrap()
  validate_protocol_node(value, index, nodes, {
    remaining: 64,
    max_wire_bytes: 4096,
    max_nodes: 64,
    max_depth: 8,
  })
}

///|
test "protocol array ceilings apply before traversing items" {
  let nodes = [protocol_any_rule(), protocol_array_rule(0, 0, false, 2)]
  assert_true(protocol_test_accepts(nodes, 1, "[]"))
  assert_true(protocol_test_accepts(nodes, 1, "[{},{}]"))
  assert_false(protocol_test_accepts(nodes, 1, "[{},{},{}]"))
  let (generated, index) = protocol_test_property_node("captured_run", [
    "effect_context", "effect_dependency_inventory",
  ])
  guard generated[index] is ArrayRule(_, _, _, maximum) else {
    fail("Expected bounded dependency inventory")
  }
  assert_eq(maximum, 4096)
}

///|
test "all generated Run evidence versions are exact" {
  let cases = [
    ("result_plan", "actql-result-plan/0.1"),
    ("invocation_bindings", "actql-invocation-bindings/0.1"),
    ("bound_invocation_template", "actql-bound-invocation-template/0.1"),
    ("prepared_invocation", "actql-prepared-invocation/0.1"),
    ("run_authorization", "actql-run-authorization/0.1"),
    ("observation_set", "actql-observation-set/0.1"),
    ("normalization_journal", "actql-normalization-journal/0.1"),
    ("source_evidence", "actql-source-evidence/0.1"),
    ("source_input_logical", "actql-source-input-logical/0.1"),
    ("authoring_context", "actql-authoring-context/0.1"),
    ("model_invocation_evidence", "actql-model-invocation-evidence/0.1"),
    ("model_capture_bundle", "actql-model-capture-bundle/0.1"),
    ("model_slot_capture", "actql-model-slot-capture/0.1"),
    ("run_receipt", "actql-run-receipt/0.1"),
    ("captured_run", "actql-captured-run/0.1"),
    ("result_delivery_receipt", "actql-result-delivery-receipt/0.1"),
    ("effect_preview", "actql-effect-preview/0.1"),
    ("effect_apply_receipt", "actql-effect-apply-receipt/0.1"),
    ("effect_set_apply_receipt", "actql-effect-set-apply-receipt/0.1"),
    ("effect_reconciliation_receipt", "actql-effect-reconciliation-receipt/0.1"),
  ]
  for (name, version) in cases {
    let (nodes, index) = protocol_test_property_node(name, ["version"])
    assert_true(protocol_test_accepts(nodes, index, "\"" + version + "\""))
    assert_false(
      protocol_test_accepts(nodes, index, "\"" + version + "-wrong\""),
    )
  }
}

///|
test "Invocation Binding names are exact declared identifiers" {
  let (nodes, index) = protocol_test_property_node("invocation_bindings", [
    "bindings",
  ])
  assert_true(
    protocol_test_accepts(
      nodes, index, "{\"target_file\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}",
    ),
  )
  assert_false(
    protocol_test_accepts(
      nodes, index, "{\"bad-name\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}",
    ),
  )
}

///|
test "generated Result Plan type and order domains are closed" {
  let (nodes, index) = protocol_test_property_node("result_plan", [
    "typed_output_port", "carrier",
  ])
  assert_true(protocol_test_accepts(nodes, index, "\"relation\""))
  assert_false(protocol_test_accepts(nodes, index, "\"graph\""))
  let (nodes, index) = protocol_test_property_node("result_plan", [
    "order", "strategy",
  ])
  assert_true(protocol_test_accepts(nodes, index, "\"inherited\""))
  assert_false(protocol_test_accepts(nodes, index, "\"unknown\""))
}

///|
test "generated fixed values reject validly typed substitutions" {
  let (nodes, index) = protocol_test_property_node(
    "bound_invocation_template",
    ["source_evidence"],
  )
  assert_true(protocol_test_accepts(nodes, index, "\"unbound\""))
  assert_false(protocol_test_accepts(nodes, index, "\"bound\""))
  let (nodes, index) = protocol_test_property_node(
    "model_invocation_evidence",
    ["attempt"],
  )
  assert_true(protocol_test_accepts(nodes, index, "1"))
  assert_false(protocol_test_accepts(nodes, index, "2"))
  let (nodes, index) = protocol_test_property_node("captured_run", [
    "encryption_required",
  ])
  assert_true(protocol_test_accepts(nodes, index, "true"))
  assert_false(protocol_test_accepts(nodes, index, "false"))
  let (nodes, index) = protocol_test_property_node("run_receipt", [
    "run_authorization", "decision",
  ])
  assert_true(protocol_test_accepts(nodes, index, "\"allowed\""))
  assert_true(protocol_test_accepts(nodes, index, "\"approved\""))
  assert_false(protocol_test_accepts(nodes, index, "\"denied\""))
}

///|
test "protocol conjunction checks both branches" {
  let nodes = [
    protocol_string_rule(None, [], 0, 0),
    protocol_string_rule(Some("expected"), [], 0, 0),
    AllOfRule([0, 1]),
  ]
  assert_true(protocol_test_accepts(nodes, 2, "\"expected\""))
  assert_false(protocol_test_accepts(nodes, 2, "\"different\""))
  assert_false(protocol_test_accepts(nodes, 2, "42"))
}

///|
test "negated schema cannot accept a branch that ran out of validation work" {
  let nodes = [protocol_object_rule([], ["forbidden"], -2, 0, None), NotRule(0)]
  let value = parse_contract_wire("{}", 1024, 8, 4).unwrap()
  assert_false(
    validate_protocol_node(value, 1, nodes, {
      remaining: 2,
      max_wire_bytes: 1024,
      max_nodes: 8,
      max_depth: 4,
    }),
  )
  assert_true(
    validate_protocol_node(value, 1, nodes, {
      remaining: 3,
      max_wire_bytes: 1024,
      max_nodes: 8,
      max_depth: 4,
    }),
  )
}

///|
fn protocol_test_effect_member(
  kind : String,
  contract_fields : String,
  executed : String,
) -> String {
  let cid = "sha256:" + "a".repeat(64)
  "{\"effect_id\":\"WriteOne\",\"effect_kind\":\"" +
  kind +
  "\",\"target\":\"Object\",\"effect_identity_cid\":\"" +
  cid +
  "\",\"preview_strength\":\"blind\",\"source_binding_cid\":\"" +
  cid +
  "\",\"capability_evidence_cid\":\"" +
  cid +
  "\",\"authority_scope_cid\":\"" +
  cid +
  "\",\"write_footprint\":{\"kind\":\"opaque\",\"resource_identity_scheme_cid\":\"" +
  cid +
  "\",\"provider_namespace\":\"provider\",\"provider_boundary_cid\":\"" +
  cid +
  "\",\"resource_kind\":\"Object\",\"provider_object_identity_cids\":[]}," +
  "\"count\":0,\"max_items\":1,\"required_permissions\":[],\"approval\":\"none\"," +
  "\"on_item_failure\":\"halt\",\"changes\":[],\"row_order\":[]," +
  "\"effect_member_preview_cid\":\"" +
  cid +
  "\",\"executed\":" +
  executed +
  contract_fields +
  "}"
}

///|
test "Effect Preview member schema keeps Command and Mapping branches distinct" {
  let (nodes, effects_index) = protocol_test_property_node("effect_preview", [
    "effects",
  ])
  let member_index = match nodes[effects_index] {
    ArrayRule(items, _, _, _) => items
    _ => abort("Expected Effect member array")
  }
  let cid = "sha256:" + "a".repeat(64)
  let command = ",\"contract\":\"command:fixture\",\"resolved_command_contract_cid\":\"" +
    cid +
    "\""
  let mapping = ",\"mapping\":\"mapping:fixture\",\"resolved_mapping_contract_cid\":\"" +
    cid +
    "\""
  assert_true(
    protocol_test_accepts(
      nodes,
      member_index,
      protocol_test_effect_member("command", command, "false"),
    ),
  )
  assert_true(
    protocol_test_accepts(
      nodes,
      member_index,
      protocol_test_effect_member("create", mapping, "false"),
    ),
  )
  assert_false(
    protocol_test_accepts(
      nodes,
      member_index,
      protocol_test_effect_member("command", mapping, "false"),
    ),
  )
  assert_false(
    protocol_test_accepts(
      nodes,
      member_index,
      protocol_test_effect_member("create", command, "false"),
    ),
  )
  assert_false(
    protocol_test_accepts(
      nodes,
      member_index,
      protocol_test_effect_member("command", command, "true"),
    ),
  )
}

///|
test "generated EffectOutcome shape keeps the four states closed" {
  let cid = "sha256:" + "a".repeat(64)
  let contract = "{\"cid\":\"" +
    cid +
    "\",\"id\":\"manual\",\"version\":\"0.1\"}"
  let accepted = "{\"cancel_capability\":\"unsupported\",\"operation_ref\":{\"$actql_ref\":\"resource\",\"authority_scope_cid\":\"" +
    cid +
    "\",\"boundary_cid\":\"" +
    cid +
    "\",\"identity_cid\":\"" +
    cid +
    "\",\"provider_identity_cid\":\"" +
    cid +
    "\",\"provider_namespace\":\"salesforce\",\"resource_kind\":\"operation\",\"version\":\"actql-resource-ref/0.1\"},\"poll_contract\":" +
    contract +
    ",\"reconciliation_contract\":" +
    contract +
    ",\"result_schema\":" +
    contract +
    ",\"state\":\"accepted\"}"
  let unknown = "{\"command_id\":\"write-a\",\"idempotency_key\":\"key-a\",\"reason\":\"connection_lost\",\"reconciliation_contract\":" +
    contract +
    ",\"state\":\"unknown\"}"
  for
    wire in [
      "{\"result\":{\"record_id\":\"a001\"},\"state\":\"applied\"}", "{\"error\":{\"code\":\"INVALID_FIELD\",\"message\":\"Bad field\"},\"state\":\"failed\"}",
      accepted, unknown,
    ] {
    assert_true(parse_effect_outcome_shape(wire, 4096, 128, 16) is Ok(_))
  }
  assert_true(
    parse_effect_outcome_shape(
      "{\"state\":\"applied\",\"result\":{}}", 4096, 128, 16,
    )
    is Err(InvalidWire),
  )
  for
    wire in [
      "{\"state\":\"applied\"}", "{\"error\":{\"code\":\"x\",\"message\":\"x\"},\"state\":\"failed\",\"extra\":1}",
      "{\"command_id\":\"write-a\",\"idempotency_key\":\"key-a\",\"reason\":\"transport_timeout\",\"state\":\"unknown\"}",
    ] {
    assert_true(parse_effect_outcome_shape(wire, 4096, 128, 16) is Err(_))
  }
}
