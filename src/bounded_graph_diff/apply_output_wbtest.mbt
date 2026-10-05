///|
fn delta_apply_owner(graph : @carrier.Graph) -> @lower.BoundPrepared {
  let rows = @carrier.relation(
    @carrier.rows(
      [(@schema.Unqualified("delta"), Some(json_contract()))],
      field_set=@carrier.Closed,
      max_fields=1,
      max_name_bytes=5,
    ).unwrap(),
  )
  delta_view_bind(
    @pipeline.check_carriers(
      delta_cursor(
        "[{\"from\":\"g\",\"apply_graph_delta\":{\"with\":\"changes\",\"field\":\"delta\"}}]",
      ),
      [("g", @carrier.graph_carrier(graph)), ("changes", rows)],
      None,
      None,
      delta_view_check_limits(),
    ).unwrap(),
  )
}

///|
test "Delta target completes on the exact checked Graph output without a second copy" {
  let (view, input, _) = delta_fixture_view()
  let graph = @graph_contract.graph(delta_fixture_contract())
  let owner = delta_apply_owner(graph)
  let output = @graph_runtime.prepare_output(
    owner,
    @pipeline.Step(0),
    DeclaredNodes,
    storage_limits(),
    100000L,
    () => true,
  ).unwrap()
  let builder = @graph_runtime.output_storage_builder(output).unwrap()
  let apply = prepare_apply_view(
    view,
    graph,
    delta_cursor(delta_fixture_expected()),
    delta_fixture_limits(),
    storage_limits(),
    output_builder=Some(builder),
  ).unwrap()
  let result = complete_apply(apply, 1)
  assert_eq(delta_snapshot_wire(result), delta_expected_target_snapshot())
  assert_true(@storage.builder_owns_storage(builder, result))
  let completed = @graph_runtime.finish_output_storage(output, result).unwrap()
  assert_true(
    physical_equal(@graph_runtime.completed_storage(completed).unwrap(), result),
  )
  assert_true(
    @lifecycle.completion_reference_matches_port(
      @graph_runtime.completed_carrier_reference(completed),
      owner,
      @pipeline.Step(0),
    ),
  )
  assert_true(cleanup_apply(apply))
  assert_eq(
    delta_snapshot_wire(@graph_runtime.completed_storage(completed).unwrap()),
    delta_expected_target_snapshot(),
  )
  assert_eq(
    @storage.node_count(@graph_runtime.completed_storage(input).unwrap()),
    3,
  )
  assert_true(@graph_runtime.discard_completed(completed))
  assert_true(@graph_runtime.discard_completed(input))
}

///|
test "Delta failure retains the shared target for cleanup and cannot complete a port" {
  let (view, input, _) = delta_fixture_view()
  let graph = @graph_contract.graph(delta_fixture_contract())
  let owner = delta_apply_owner(graph)
  let output = @graph_runtime.prepare_output(
    owner,
    @pipeline.Step(0),
    DeclaredNodes,
    storage_limits(),
    100000L,
    () => true,
  ).unwrap()
  let builder = @graph_runtime.output_storage_builder(output).unwrap()
  let bad = delta_fixture_expected().replace_all(
    old="sha256:84a3ee72261465a8864d987b0215329de2222270827c7f0436a449ec55ac1e3f",
    new="sha256:" + "f".repeat(64),
  )
  let apply = prepare_apply_view(
    view,
    graph,
    delta_cursor(bad),
    delta_fixture_limits(),
    storage_limits(),
    output_builder=Some(builder),
  ).unwrap()
  assert_eq(apply_failure_issue(apply), TargetMismatch)
  // Finished-but-unpublished storage stays in the existing kernel's custody.
  let provisional = apply.result.unwrap()
  assert_true(@storage.builder_owns_storage(builder, provisional))
  assert_true(cleanup_apply(apply))
  assert_false(@storage.builder_owns_storage(builder, provisional))
  assert_true(
    @graph_runtime.finish_output_storage(output, provisional)
    is Err(@graph_runtime.Lifecycle(@lifecycle.Unverified)),
  )
  assert_true(@graph_runtime.output_storage_builder(output) is None)
  assert_true(@graph_runtime.discard_completed(input))
}
