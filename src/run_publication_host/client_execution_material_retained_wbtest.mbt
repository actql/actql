///|
fn retained_execution_material_fixture() -> (
  PreparedClientProgram,
  ClientExecutionMaterial,
) {
  let prepared = values_compilation_parts_prepared()
  let material = issue_prepared_client_values_execution_material(
    prepared,
    run_materials_manifests(),
    run_materials_limits().sequence,
    100000,
    10000,
    100,
  ).unwrap()
  (prepared, material)
}

///|
test "fresh execution material returns the same admitted tree and original wire" {
  let (prepared, material) = retained_execution_material_fixture()
  let first = client_execution_material_body(
    material, prepared, 100000, 10000, 100,
  ).unwrap()
  let second = client_execution_material_body(
    material, prepared, 100000, 10000, 100,
  ).unwrap()
  assert_true(physical_equal(first, material.body))
  assert_true(physical_equal(first, second))
  assert_eq(
    @canonical.stringify_value(first, 100000, 10000, 100),
    client_execution_material_wire(material),
  )
  let external = parse_plan_identity_value(material.wire, 100000, 10000, 100).unwrap()
  assert_eq(
    @canonical.stringify_value(first, 100000, 10000, 100),
    @canonical.stringify_value(external, 100000, 10000, 100),
  )
  assert_true(!physical_equal(first, external))
  let foreign = values_compilation_parts_prepared()
  assert_eq(
    prepared_client_identity(prepared),
    prepared_client_identity(foreign),
  )
  assert_true(
    client_execution_material_body(material, foreign, 100000, 10000, 100)
    is None,
  )
}

///|
test "retained material uses the complete original wire extent under tighter bounds" {
  let (prepared, material) = retained_execution_material_fixture()
  for
    (bytes, nodes, depth) in [
      (material.wire_bytes, material.wire_nodes, material.wire_depth),
      (material.wire_bytes - 1, material.wire_nodes, material.wire_depth),
      (material.wire_bytes, material.wire_nodes - 1, material.wire_depth),
      (material.wire_bytes, material.wire_nodes, material.wire_depth - 1),
      (
        material.wire_bytes + 1,
        material.wire_nodes + 1,
        material.wire_depth + 1,
      ),
      (0, material.wire_nodes, material.wire_depth),
      (material.wire_bytes, 0, material.wire_depth),
      (material.wire_bytes, material.wire_nodes, 0),
    ] {
    let retained = client_execution_material_body(
      material, prepared, bytes, nodes, depth,
    )
    // The independent existing external reader remains the bounded control;
    // a larger earlier admission cannot waive a later smaller limit.
    let external = parse_plan_identity_value(material.wire, bytes, nodes, depth)
    match (retained, external) {
      (Some(left), Some(right)) =>
        assert_eq(
          @canonical.stringify_value(left, bytes, nodes, depth),
          @canonical.stringify_value(right, bytes, nodes, depth),
        )
      (None, None) => ()
      _ => fail("retained material changed the external admission bound")
    }
  }
  assert_eq(
    material.wire_bytes,
    @utf8.encode(client_execution_material_wire(material)).length(),
  )
  assert_true(material.wire_nodes > 1)
  assert_true(material.wire_depth > 1)
}

///|
test "executable plan consumes its original typed material without changing the embedded body" {
  let (prepared, material) = retained_execution_material_fixture()
  let graph = issue_prepared_client_values_plan_graph(
    prepared,
    run_materials_limits().sequence,
    100000,
    10000,
    100,
  ).unwrap()
  let plan = issue_prepared_client_executable_plan_with_parts(
    prepared,
    graph.wire,
    graph.transformations,
    material,
    1000,
    1000,
    100000,
    10000,
    100,
  ).unwrap()
  let body = parse_plan_identity_value(plan.wire, 100000, 10000, 100).unwrap()
  let embedded = @canonical.object_field(body, "execution_material").unwrap()
  assert_eq(
    @canonical.stringify_value(embedded, 100000, 10000, 100),
    material.wire,
  )
  assert_true(
    admit_prepared_client_values_execution_material(
      prepared,
      "{}",
      run_materials_manifests(),
      run_materials_limits().sequence,
      100000,
      10000,
      100,
    )
    is Err(ClientExecutionMaterialAdmissionIssue::MismatchedMaterial),
  )
  let foreign = values_compilation_parts_prepared()
  assert_true(
    issue_prepared_client_executable_plan_with_parts(
      foreign,
      graph.wire,
      graph.transformations,
      material,
      1000,
      1000,
      100000,
      10000,
      100,
    )
    is Err(Encoding),
  )
}
