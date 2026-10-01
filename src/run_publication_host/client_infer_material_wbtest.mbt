///|
fn client_infer_material_test_graph(
  prepared : PreparedClientProgram,
) -> ClientInferPlanGraph {
  // These references prove compilation identity only. No egress or physical
  // envelope is admitted and no provider is installed by this helper.
  issue_prepared_client_infer_plan_graph(
    prepared,
    2,
    client_infer_graph_test_execution(prepared),
    "sha256:" + "b".repeat(64),
    "sha256:" + "c".repeat(64),
    run_materials_limits().sequence,
    100000,
    10000,
    100,
  ).unwrap()
}

///|
test "Infer template binds the registered profile rather than the task contract" {
  let prepared = client_infer_prefix_test_program()
  let graph = client_infer_material_test_graph(prepared)
  let manifests = run_materials_manifests()
  let template = issue_prepared_client_infer_bound_template(
    prepared, graph, manifests, 100000, 10000, 100,
  ).unwrap()
  let wire = @publication.run_evidence_value_json(template)
  let body = parse_plan_identity_value(wire, 100000, 10000, 100).unwrap()
  guard @canonical.object_field(body, "required_profile_contracts")
    is Some(@canonical.Array(profiles)) else {
    abort("required profile fixture")
  }
  let profiles = @canonical.array_values(profiles)
  assert_eq(profiles.length(), 1)
  assert_true(
    @canonical.object_field(profiles[0], "profile_id")
    is Some(@canonical.String("actql-infer/0.1")),
  )
  // Independent normative schema pin, not the installed ModelTask CID.
  assert_true(
    @canonical.object_field(profiles[0], "contract_cid")
    is Some(
      @canonical.String(
        "sha256:34f1a37cbaea973964f4cf84ca3806b2492df545b718042ad8057604c95cb6dd"
      )
    ),
  )
  let identity = prepared_client_identity(prepared)
  let bindings = issue_prepared_client_empty_invocation_bindings(
    prepared, 100000, 10000, 100,
  ).unwrap()
  for
    (field, expected) in [
      ("program_definition_cid", identity.program_definition_cid),
      ("parameter_values_cid", identity.parameter_values_cid),
      ("check_environment_cid", prepared_client_check_environment_cid(prepared)),
      (
        "invocation_bindings_cid",
        @publication.run_evidence_value_identity(bindings),
      ),
      (
        "grammar_manifest_cid",
        client_compilation_grammar_manifest_cid(manifests),
      ),
      (
        "barrier_contract_manifest_cid",
        client_compilation_barrier_manifest_cid(manifests),
      ),
    ] {
    assert_true(
      @canonical.object_field(body, field) is Some(@canonical.String(actual)) &&
      actual == expected,
    )
  }
  assert_true(
    @canonical.object_field(body, "source_evidence")
    is Some(@canonical.String("unbound")),
  )
  assert_true(
    @canonical.object_field(body, "model_invocation_evidence") is None,
  )
  assert_true(@canonical.object_field(body, "slot_cid") is None)
  assert_eq(
    @publication.run_evidence_value_json(
      @publication.admit_run_evidence_value(
        "bound_invocation_template", wire, 100000, 10000, 100,
      ).unwrap(),
    ),
    wire,
  )
}

///|
test "Infer material retains checked Program Result maps and rejects saved substitutions" {
  let prepared = client_infer_prefix_test_program(
    result_fields="[\"id\",\"value\"]",
  )
  let graph = client_infer_material_test_graph(prepared)
  let manifests = run_materials_manifests()
  let material = issue_prepared_client_infer_execution_material(
    prepared, graph, manifests, 100000, 10000, 100,
  ).unwrap()
  let body = parse_plan_identity_value(material.wire, 100000, 10000, 100).unwrap()
  assert_true(
    @canonical.object_field(body, "invocation_template_cid")
    is Some(@canonical.String(cid)) &&
    cid == material.invocation_template_cid,
  )
  guard @canonical.object_field(body, "result_plan_logical_cids")
    is Some(results) else {
    abort("Result identity map fixture")
  }
  let result = issue_prepared_client_result_plan(
    prepared, 0, 100000, 10000, 100,
  ).unwrap()
  assert_eq(client_result_plan_name(result), "answer")
  assert_true(
    @canonical.object_field(results, "answer") is Some(@canonical.String(cid)) &&
    cid == client_result_plan_cid(result),
  )
  let template = parse_plan_identity_value(
    material.invocation_template_wire,
    100000,
    10000,
    100,
  ).unwrap()
  assert_true(
    @canonical.object_field(template, "bound_invocation_template_cid")
    is Some(@canonical.String(cid)) &&
    cid == material.invocation_template_cid,
  )
  assert_eq(
    client_execution_material_wire(
      admit_prepared_client_infer_execution_material(
        prepared,
        graph,
        material.wire,
        manifests,
        100000,
        10000,
        100,
      ).unwrap(),
    ),
    material.wire,
  )
  for
    changed in [
      material.wire.replace(
        old=material.invocation_template_cid,
        new="sha256:" + "d".repeat(64),
      ),
      material.wire.replace(old="\"answer\":", new="\"missing\":"),
      material.wire.replace(old="\"actql/0.1\"", new="\"actql/9.9\""),
    ] {
    assert_true(changed != material.wire)
    assert_true(
      admit_prepared_client_infer_execution_material(
        prepared, graph, changed, manifests, 100000, 10000, 100,
      )
      is Err(MismatchedMaterial),
    )
  }
}

///|
test "Infer template refuses foreign graph owners and finite encoding shortages" {
  let prepared = client_infer_prefix_test_program()
  let graph = client_infer_material_test_graph(prepared)
  let foreign = client_infer_prefix_test_program()
  let manifests = run_materials_manifests()
  assert_true(
    issue_prepared_client_infer_bound_template(
      foreign, graph, manifests, 100000, 10000, 100,
    )
    is Err(ForeignGraph),
  )
  assert_true(
    issue_prepared_client_infer_execution_material(
      foreign, graph, manifests, 100000, 10000, 100,
    )
    is Err(InferTemplate(ForeignGraph)),
  )
  for
    (bytes, nodes, depth) in [
      (0, 10000, 100),
      (100000, 0, 100),
      (100000, 10000, 0),
    ] {
    assert_true(
      issue_prepared_client_infer_bound_template(
        prepared, graph, manifests, bytes, nodes, depth,
      )
      is Err(InvalidLimits),
    )
  }
  for
    (bytes, nodes, depth) in [
      (1, 10000, 100),
      (100000, 1, 100),
      (100000, 10000, 1),
    ] {
    assert_true(
      issue_prepared_client_infer_bound_template(
        prepared, graph, manifests, bytes, nodes, depth,
      )
      is Err(Template(_)),
    )
  }
  for empty in [false, true] {
    let actual = client_infer_prefix_test_program(
      input_rows=if empty {
        "[]"
      } else {
        "[{\"id\":\"a\",\"text\":\"hello\"}]"
      },
      strict=true,
    )
    let graph = client_infer_material_test_graph(actual)
    let material = issue_prepared_client_infer_execution_material(
      actual, graph, manifests, 100000, 10000, 100,
    ).unwrap()
    assert_true(material.invocation_template_wire.contains("actql-infer/0.1"))
    assert_true(
      material.invocation_template_wire !=
      issue_prepared_client_infer_execution_material(
        prepared,
        client_infer_material_test_graph(prepared),
        manifests,
        100000,
        10000,
        100,
      ).unwrap().invocation_template_wire,
    )
  }
}
