///|
fn binding_construction_plan_fixture() -> PublicationContract {
  let plan = seal_publication_contract(
    "compiled_plan", "{\"aoa_contract_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"aoa_ir_version\":\"0.1\",\"aoa_logical_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"compiler_version\":\"0.1\",\"executable_plan_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"program_definition_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"program_semantics_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"version\":\"actql-compiled-plan/0.1\"}",
    20000, 2000, 32,
  ).unwrap()
  plan
}

///|
fn binding_construction_map_fixture() -> RunEvidenceValue {
  let view = parse_contract_wire(validator_plan_view_fixture, 65536, 8192, 64).unwrap()
  let map = @json.object_field(view, "logical_map").unwrap()
  let wire = @json.stringify_value(map, 65536, 8192, 64) catch {
    _ => abort("fixture encoding")
  }
  admit_run_evidence_value("logical_map", wire, 65536, 8192, 64).unwrap()
}

///|
test "binding construction measures original closed keys and borrowed map entries" {
  let map = binding_construction_map_fixture()
  let plan = binding_construction_plan_fixture()
  check_interactive_logical_map_binding(map, plan, 65536, 8192, 64).unwrap()
  let geometry = interactive_logical_map_binding_construction(
    map, plan, 65536, 8192, 64,
  ).unwrap()
  assert_eq((geometry.steps, geometry.ports, geometry.outputs), (1, 2, 1))
  assert_eq(geometry.max_ports_per_step, 2)
  assert_eq(geometry.max_coordinate_units, "output:0".length())
  assert_eq(
    geometry.coordinate_retained_units,
    "input:0output:0".length().to_int64(),
  )
  assert_true(
    geometry.owned_utf16_units >=
    geometry.coordinate_retained_units + geometry.port_body.0.to_int64(),
  )
  assert_eq(geometry.step_key_preimage_fields, 4)
  guard @json.object_field(map.value, "steps") is Some(@json.Array(steps)) else {
    fail("steps")
  }
  for i in 0..<@json.array_count(steps) {
    let step = @json.array_at(steps, i).unwrap()
    let key = @json.object_field(step, "key").unwrap()
    let (_, bytes, nodes, depth) = @json.stringify_value_with_usage(
      key, 65536, 8192, 64,
    )
    assert_true(bytes <= geometry.step_key.0)
    assert_eq(nodes, geometry.step_key.1)
    assert_eq(depth, geometry.step_key.2)
    guard @json.object_field(step, "ports") is Some(@json.Array(ports)) else {
      fail("ports")
    }
    for j in 0..<@json.array_count(ports) {
      let port = @json.array_at(ports, j).unwrap()
      let role = evidence_string(port, "role").unwrap()
      let ordinal = interactive_integer(port, "port_ordinal").unwrap()
      let body = "{\"version\":\"actql-logical-port-key/0.1\",\"compiled_plan_cid\":\"" +
        plan.identity +
        "\",\"step_id\":\"" +
        evidence_string(step, "step_id").unwrap() +
        "\",\"role\":\"" +
        role +
        "\",\"port_ordinal\":" +
        ordinal.to_string() +
        "}"
      assert_true(body.length() <= geometry.port_body.0)
      let admitted = seal_run_evidence_value(
        "logical_port_key", body, 65536, 8192, 64,
      ).unwrap()
      let (bytes, nodes, depth) = admitted.wire_usage.unwrap()
      assert_true(bytes <= geometry.port_complete.0)
      assert_eq(nodes, geometry.port_complete.1)
      assert_eq(depth, geometry.port_complete.2)
      assert_true(geometry.port_body_concat_units >= body.length().to_int64())
    }
  }
  assert_true(
    interactive_logical_map_binding_construction(map, plan, 65536, 2, 64)
    is None,
  )
  assert_true(
    interactive_logical_map_binding_construction(map, plan, 0, 8192, 64) is None,
  )
}

///|
test "binding measurement does not replace identity validation and uses cold ordinal width" {
  let original = binding_construction_map_fixture()
  let plan = binding_construction_plan_fixture()
  let body = @json.object_without_field(original.value, "self_cid").unwrap()
  let wire = @json.stringify_value(body, 65536, 8192, 64)
  let changed = seal_run_evidence_value(
    "logical_map",
    wire
    .replace(old="\"port_ordinal\":0", new="\"port_ordinal\":2147483647")
    .replace(old="\"port_ordinal\":0", new="\"port_ordinal\":2147483647"),
    65536,
    8192,
    64,
  ).unwrap()
  let geometry = interactive_logical_map_binding_construction(
    changed, plan, 65536, 8192, 64,
  ).unwrap()
  assert_eq(geometry.max_coordinate_units, "output:2147483647".length())
  assert_true(
    check_interactive_logical_map_binding(changed, plan, 65536, 8192, 64)
    is Err(_),
  )
  for
    (value, width) in [
      (0L, 1),
      (9L, 1),
      (10L, 2),
      (-1L, 2),
      (-10L, 3),
      (9007199254740991L, 16),
      (-9223372036854775807L - 1L, 20),
    ] {
    assert_eq(interactive_binding_decimal_units(value), width)
    assert_eq(
      interactive_binding_decimal_units(value),
      value.to_string().length(),
    )
  }
}

///|
test "binding scanner exposes a fixed prefunded control recipe independent of document size" {
  let (controls, references, words) = interactive_logical_map_binding_scanner_controls()
  let quote = @shape.collection_construction_quotation_extent()
  assert_eq(controls.record_headers, 29L + quote.record_headers)
  assert_eq(controls.reference_slots, 19L + quote.reference_slots)
  assert_eq(controls.scalar_words, 45L + quote.scalar_words)
  assert_eq((references, words), (4, 10))
  assert_eq(
    interactive_logical_map_binding_scanner_controls(),
    (controls, references, words),
  )
}
