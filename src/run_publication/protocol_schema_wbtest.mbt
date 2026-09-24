///|
fn protocol_test_property_node(
  name : String,
  path : Array[String],
) -> (Array[ProtocolSchemaRule], Int) {
  let nodes = generated_protocol_schema_nodes()
  let mut index = generated_protocol_schema_root(name, false).unwrap()
  for field in path {
    match nodes[index] {
      ObjectRule(properties, _, _, _, _) =>
        index = protocol_property_schema(properties, field).unwrap()
      _ => abort("Expected protocol object rule")
    }
  }
  (nodes, index)
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
test "all generated Run evidence versions are exact" {
  let cases = [
    ("result_plan", "actql-result-plan/0.1"),
    ("bound_invocation_template", "actql-bound-invocation-template/0.1"),
    ("prepared_invocation", "actql-prepared-invocation/0.1"),
    ("run_authorization", "actql-run-authorization/0.1"),
    ("observation_set", "actql-observation-set/0.1"),
    ("normalization_journal", "actql-normalization-journal/0.1"),
    ("source_evidence", "actql-source-evidence/0.1"),
    ("authoring_context", "actql-authoring-context/0.1"),
    ("model_invocation_evidence", "actql-model-invocation-evidence/0.1"),
    ("run_receipt", "actql-run-receipt/0.1"),
    ("captured_run", "actql-captured-run/0.1"),
    ("result_delivery_receipt", "actql-result-delivery-receipt/0.1"),
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
