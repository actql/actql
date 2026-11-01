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
