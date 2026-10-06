///|
fn kernel_output(
  owner : @lower.BoundPrepared,
  live : Ref[Bool],
) -> OutputBuilder {
  prepare_output(
    owner,
    @pipeline.Input(0),
    @storage.DeclaredNodes,
    graph_limits(),
    4096L,
    () => live.val,
  ).unwrap()
}

///|
test "Graph kernel output completes once on the existing retention owner" {
  let owner = producer_owner()
  let output = kernel_output(owner, Ref(true))
  let builder = output_storage_builder(output).unwrap()
  @storage.append_node(builder, 0, [number(1.0)], [text("one")]).unwrap()
  let storage = @storage.finish(builder).unwrap()
  let completed = finish_output_storage(output, storage).unwrap()
  assert_true(physical_equal(completed_storage(completed).unwrap(), storage))
  assert_eq(
    completed_measure(completed),
    @lifecycle.GraphMeasure(nodes=1, edges=0),
  )
  assert_eq(completed_storage_bytes(completed), Some(4096L))
  assert_eq(evidence_input_rows(completed_evidence(completed).unwrap()), 1)
  assert_true(
    @lifecycle.completion_reference_matches_port(
      completed_carrier_reference(completed),
      owner,
      @pipeline.Input(0),
    ),
  )
  assert_true(output_storage_builder(output) is None)
  assert_true(finish_output_storage(output, storage) is Err(Closed))
  assert_true(finish_output(output) is Err(Closed))
  assert_false(cancel_output(output))
  assert_true(completed_available(completed))
  assert_eq(@storage.node_count(storage), 1)
  assert_true(discard_completed(completed))
  assert_false(discard_completed(completed))
  assert_eq(@storage.node_count(storage), 0)
}

///|
test "Graph kernel completion rejects foreign Storage without reclaiming its owner" {
  let owner = producer_owner()
  let output = kernel_output(owner, Ref(true))
  let other = kernel_output(owner, Ref(true))
  append_node(other, 0, [number(1.0)], [text("one")]).unwrap()
  let completed = finish_output(other).unwrap()
  let storage = completed_storage(completed).unwrap()
  assert_true(
    finish_output_storage(output, storage)
    is Err(Lifecycle(@lifecycle.Unverified)),
  )
  assert_true(finish_output(output) is Err(Closed))
  assert_true(completed_available(completed))
  assert_eq(@storage.node_count(storage), 1)
  assert_true(discard_completed(completed))
}

///|
test "Graph kernel completion preserves revocation and cancellation cleanup" {
  let owner = producer_owner()
  let live = Ref(true)
  let output = kernel_output(owner, live)
  append_node(output, 0, [number(1.0)], [text("one")]).unwrap()
  let storage = @storage.finish(output_storage_builder(output).unwrap()).unwrap()
  live.val = false
  assert_true(
    finish_output_storage(output, storage)
    is Err(Lifecycle(@lifecycle.Unavailable)),
  )
  assert_eq(@storage.node_count(storage), 0)
  assert_true(finish_output_storage(output, storage) is Err(Closed))
  let cancelled = kernel_output(owner, Ref(true))
  let builder = output_storage_builder(cancelled).unwrap()
  assert_true(cancel_output(cancelled))
  assert_true(@storage.finish(builder) is Err(@storage.Closed))
  assert_true(output_storage_builder(cancelled) is None)
}

///|
test "Graph kernel completion refuses discarded Storage even from its own builder" {
  let owner = producer_owner()
  let output = kernel_output(owner, Ref(true))
  append_node(output, 0, [number(1.0)], [text("one")]).unwrap()
  let storage = @storage.finish(output_storage_builder(output).unwrap()).unwrap()
  @storage.discard(storage)
  assert_true(
    finish_output_storage(output, storage)
    is Err(Lifecycle(@lifecycle.Unverified)),
  )
  assert_true(output_storage_builder(output) is None)
}

///|
test "Graph completion availability follows physical Storage reclamation" {
  let output = kernel_output(producer_owner(), Ref(true))
  append_node(output, 0, [number(1.0)], [text("one")]).unwrap()
  let storage = @storage.finish(output_storage_builder(output).unwrap()).unwrap()
  let completed = finish_output_storage(output, storage).unwrap()
  assert_true(completed_available(completed))
  @storage.discard(storage)
  assert_false(completed_available(completed))
  assert_true(completed_storage(completed) is None)
  assert_true(completed_evidence(completed) is None)
  assert_true(discard_completed(completed))
  assert_false(discard_completed(completed))
}
