///|
test "original Values and Task Plan writer debits preserve bytes and retain closing-byte failure work" {
  for tasks in [false, true] {
    let value = values_compilation_parts_prepared()
    let sequence = prepared_client_values_sequence_limits(value)
    let manifests = run_materials_manifests()
    let original = if tasks {
      issue_prepared_client_task_compilation(
        value, manifests, sequence, 1000, 10000, 1000000, 100000, 100,
      ).unwrap().plan.plan
    } else {
      issue_prepared_client_values_compilation(
        value, manifests, sequence, 1000, 10000, 1000000, 100000, 100,
      ).unwrap().plan
    }
    let parsed = @source.parse_json_bytes_measured(
      @utf8.encode(original.wire),
      { max_input_bytes: 1000000, max_nodes: 100000, max_depth: 100, },
    ).unwrap()
    let expected = 2L * parsed.usage.nodes.to_int64() - 1L
    let observed = Ref(-1L)
    let actual = if tasks {
      observe_prepared_client_task_plan_encoding(
        value,
        manifests,
        sequence,
        1000,
        10000,
        1000000,
        100000,
        100,
        nodes_out=observed,
      ).unwrap().plan.plan
    } else {
      observe_prepared_client_values_plan_encoding(
        value,
        manifests,
        sequence,
        1000,
        10000,
        1000000,
        100000,
        100,
        nodes_out=observed,
      ).unwrap().plan
    }
    assert_eq(actual.wire, original.wire)
    assert_eq(actual.cid, original.cid)
    assert_eq(actual.fact_manifest_wire, original.fact_manifest_wire)
    assert_eq(observed.val, expected)
    // A distinct standalone invocation overwrites its observation output,
    // never a Resource allowance. One byte short rejects the final closing
    // brace after every value node was visited; count != completion proof.
    let short = @utf8.encode(original.wire).length() - 1
    if tasks {
      assert_true(
        observe_prepared_client_task_plan_encoding(
          value,
          manifests,
          sequence,
          1000,
          10000,
          short,
          100000,
          100,
          nodes_out=observed,
        )
        is Err(Plan(Encoding)),
      )
    } else {
      assert_true(
        observe_prepared_client_values_plan_encoding(
          value,
          manifests,
          sequence,
          1000,
          10000,
          short,
          100000,
          100,
          nodes_out=observed,
        )
        is Err(Plan(Encoding)),
      )
    }
    assert_eq(observed.val, expected)
  }
}

///|
test "original Model Plan writer retains exact identity and closing-byte failure work" {
  for projected in [false, true] {
    let value = client_infer_prefix_test_program(
      result_fields=if projected {
        "[\"id\",\"value\"]"
      } else {
        "[\"id\",\"outcome\",\"value\"]"
      },
    )
    let graph = client_infer_material_test_graph(value)
    let manifests = run_materials_manifests()
    let original = issue_prepared_client_infer_compilation(
      value, graph, manifests, 1000, 10000, 1000000, 100000, 100,
    ).unwrap()
    let wire = original.plan.plan.wire
    let parsed = @source.parse_json_bytes_measured(@utf8.encode(wire), {
      max_input_bytes: 1000000,
      max_nodes: 100000,
      max_depth: 100,
    }).unwrap()
    // Each VALUE node is visited once by each original writer. The text
    // contains the additional executable_plan_cid absent from its preimage.
    let expected = 2L * parsed.usage.nodes.to_int64() - 1L
    let observed = Ref(-1L)
    let actual = observe_prepared_client_infer_plan_encoding(
      value,
      graph,
      manifests,
      1000,
      10000,
      1000000,
      100000,
      100,
      nodes_out=observed,
    ).unwrap()
    assert_eq(actual.plan.plan.wire, wire)
    assert_eq(actual.plan.plan.cid, original.plan.plan.cid)
    assert_eq(
      @publication.publication_contract_json(actual.compiled_plan),
      @publication.publication_contract_json(original.compiled_plan),
    )
    assert_eq(
      @publication.run_evidence_value_json(actual.template),
      @publication.run_evidence_value_json(original.template),
    )
    assert_true(
      client_task_compilation_infer(actual) is Some(retained) &&
      physical_equal(retained, graph),
    )
    assert_eq(observed.val, expected)
    assert_true(
      observe_prepared_client_infer_plan_encoding(
        value,
        graph,
        manifests,
        1000,
        10000,
        @utf8.encode(wire).length() - 1,
        100000,
        100,
        nodes_out=observed,
      )
      is Err(Plan(Encoding)),
    )
    assert_eq(observed.val, expected)
  }
}

///|
test "foreign Model graph refuses before Plan work and overwrites the original output" {
  let value = client_infer_prefix_test_program()
  let graph = client_infer_material_test_graph(value)
  let foreign = client_infer_prefix_test_program()
  let observed = Ref(123L)
  assert_true(
    observe_prepared_client_infer_plan_encoding(
      foreign,
      graph,
      run_materials_manifests(),
      1000,
      10000,
      1000000,
      100000,
      100,
      nodes_out=observed,
    )
    is Err(ForeignInferOwner),
  )
  assert_eq(observed.val, 0L)
}
