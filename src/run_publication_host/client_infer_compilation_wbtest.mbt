///|
test "Infer compilation reaches the shared Run owner with the checked barrier" {
  for projected in [false, true] {
    let prepared = client_infer_prefix_test_program(
      result_fields=if projected {
        "[\"id\",\"value\"]"
      } else {
        "[\"id\",\"outcome\",\"value\"]"
      },
    )
    let graph = client_infer_material_test_graph(prepared)
    let compilation = issue_prepared_client_infer_compilation(
      prepared,
      graph,
      run_materials_manifests(),
      1000,
      1000,
      100000,
      10000,
      100,
    ).unwrap()
    assert_true(
      client_task_compilation_infer(compilation) is Some(selected) &&
      physical_equal(selected, graph),
    )
    assert_eq(client_task_compilation_result_names(compilation), ["answer"])
    let plan = parse_plan_identity_value(
      client_task_executable_plan_wire(compilation.plan),
      100000,
      10000,
      100,
    ).unwrap()
    let template = parse_plan_identity_value(
      @publication.run_evidence_value_json(compilation.template),
      100000,
      10000,
      100,
    ).unwrap()
    assert_eq(
      @canonical.stringify_value(
        @canonical.object_field(plan, "required_profiles").unwrap(),
        10000,
        1000,
        20,
      ),
      @canonical.stringify_value(
        @canonical.object_field(template, "required_profile_contracts").unwrap(),
        10000,
        1000,
        20,
      ),
    )
    assert_true(
      @canonical.object_field(plan, "required_profiles")
      is Some(@canonical.Array(profiles)) &&
      @canonical.array_values(profiles).length() == 1,
    )
    let compiled = parse_plan_identity_value(
      @publication.publication_contract_json(compilation.compiled_plan),
      100000,
      10000,
      100,
    ).unwrap()
    assert_true(
      @canonical.object_field(compiled, "aoa_logical_cid")
      is Some(@canonical.String(actual)) &&
      actual == graph.input_fragment_cid,
    )
    let admitted = issue_client_task_compiled_run(
      prepared,
      compilation,
      "sha256:" + "a".repeat(64),
      "sha256:" + "b".repeat(64),
      "2099-01-01T00:00:00.000Z",
    ).unwrap()
    assert_true(client_compiled_run_matches(admitted, prepared))
    assert_true(
      client_compiled_run_infer(admitted) is Some(selected) &&
      physical_equal(selected, graph),
    )
    let definition = issue_client_compiled_run_definition(
      admitted, "infer-scope", "infer-run", "2026-10-01T00:00:00.000Z", "2099-01-01T00:00:00.000Z",
    ).unwrap()
    assert_true(
      check_client_compiled_run_definition(admitted, definition) is Ok(_),
    )
    let (observation, invocation) = issue_client_compiled_source_free_task_invocation(
      admitted,
      definition,
      "sha256:" + "c".repeat(64),
      100000,
      10000,
      100,
    ).unwrap()
    assert_eq(
      @publication.run_evidence_value_name(observation),
      "observation_set",
    )
    assert_eq(
      @publication.publication_contract_name(invocation),
      "run_invocation",
    )
    assert_eq(
      client_compiled_run_result_transformation(admitted, prepared, 0).unwrap()
      is Some(_),
      projected,
    )
    assert_true(
      issue_prepared_client_infer_compilation(
        client_infer_prefix_test_program(),
        graph,
        run_materials_manifests(),
        1000,
        1000,
        100000,
        10000,
        100,
      )
      is Err(ForeignInferOwner),
    )
  }
}
