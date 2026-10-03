///|
test "current Graph material remains owned across two MATCH consumers cancellation and final reclaim" {
  let nodes = keyed_node_source()
  let edges = keyed_edge_source()
  let owner = keyed_bridge_owner(nodes, edges)
  let generated = @execution.select_generated_sequence_step(
    task_test_generated(owner),
    0,
  ).unwrap()
  let provider = @local_sga_provider.provider(
    carrier_graph_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
  )
  let construction = @local_connector.start_managed_provider_with_inputs(
    provider,
    generated,
    keyed_bridge_inputs(owner, nodes, edges).map(
      @local_connector.managed_provider_relation_input,
    ),
    10,
    1000,
  ).unwrap()
  let mut material = None
  for _ in 0..<1000 {
    match @local_connector.advance_managed_provider(construction, 1).unwrap() {
      @local_connector.Continue(work~, ..) => assert_true(work > 0L)
      @local_connector.CarrierComplete(output, ..) => {
        material = Some(output)
        break
      }
      _ => fail("constructor did not deliver a current Graph")
    }
  }
  let material = material.unwrap()
  assert_true(@local_connector.cleanup_managed_provider(construction).unwrap())
  assert_true(@carrier_runtime.material_available(material))
  let first = keyed_graph_receiver(
    owner,
    body="[{\"from\":\"g\",\"match_nodes\":{\"definition\":\"N\",\"where\":\"true\",\"fields\":[\"display\"]}}]",
  )
  let second = keyed_graph_receiver(
    owner,
    body="[{\"from\":\"g\",\"match_edges\":{\"definition\":\"E\",\"bindings\":{\"identity\":\"id\"},\"fields\":[\"id\"]}}]",
  )
  let foreign = keyed_bridge_owner(nodes, edges)
  assert_true(
    @carrier_runtime.material_prepare_view(material, first, 0, foreign)
    is Err(_),
  )
  let first_view = @carrier_runtime.material_prepare_view(
    material, first, 0, owner,
  ).unwrap()
  let second_view = @carrier_runtime.material_prepare_view(
    material, second, 0, owner,
  ).unwrap()
  let start = fn(receiver, view) raise {
    let selected = @execution.select_generated_sequence_step(
      task_test_generated(receiver),
      0,
    ).unwrap()
    let selected_provider = @local_sga_provider.provider(
      carrier_graph_storage_limits(),
      4096L,
      @execution.generated_sequence_capacity(
        selected,
        dispatch_test_limits().local_execution,
        dispatch_test_limits().guards,
      ).unwrap(),
    )
    assert_true(
      @local_connector.managed_provider_accepts(selected_provider, selected),
    )
    @local_connector.start_managed_provider_with_inputs(
      selected_provider,
      selected,
      [@local_connector.managed_provider_carrier_input(view)],
      10,
      1000,
    ).unwrap()
  }
  let first_run = start(first, first_view)
  let second_run = start(second, second_view)
  let finish = fn(run) raise {
    for _ in 0..<10000 {
      match @local_connector.advance_managed_provider(run, 1).unwrap() {
        @local_connector.Continue(work~, ..) => assert_true(work > 0L)
        @local_connector.Complete(output, ..) => return output
        _ => fail("MATCH provider failed")
      }
    }
    fail("MATCH exceeded independent fixture allowance")
  }
  let first_output = finish(first_run)
  assert_eq(@execution.completed_row_count(first_output), 1)
  assert_eq(
    @execution.completed_output_row_wire(first_output, 0, 10000, 10000, 50).unwrap(),
    "{\"display\":\"one\"}",
  )
  assert_true(@local_connector.cleanup_managed_provider(first_run).unwrap())
  assert_true(@local_connector.cleanup_managed_provider(first_run).unwrap())
  assert_true(@carrier_runtime.material_available(material))
  let second_output = finish(second_run)
  assert_eq(@execution.completed_row_count(second_output), 2)
  guard @pipeline.carrier_at(
      @lower.pipeline(@lower.bound_preparation(owner)),
      @pipeline.Step(0),
    )
    is Some(@carrier_contract.GraphValue(schema)) else {
    fail("current contract")
  }
  let domain = @carrier_contract.property_graph_domain(
    @carrier_contract.graph_property_definition(schema),
  )
  for row in 0..<2 {
    let expected = "{\"id\":{\"definition\":\"E\",\"domain\":\"" +
      domain +
      "\",\"key\":[" +
      (10 + row).to_string() +
      "],\"key_types\":[{\"kind\":\"number\"}]}}"
    assert_eq(
      @execution.completed_output_row_wire(second_output, row, 10000, 10000, 50).unwrap(),
      expected,
    )
  }
  assert_true(@local_connector.cleanup_managed_provider(second_run).unwrap())
  assert_true(@carrier_runtime.material_available(material))
  let cancelling = start(
    first,
    @carrier_runtime.material_prepare_view(material, first, 0, owner).unwrap(),
  )
  assert_true(@local_connector.cancel_managed_provider(cancelling))
  assert_true(
    @local_connector.advance_managed_provider(cancelling, 1).unwrap()
    is @local_connector.Stopped(..),
  )
  assert_true(@local_connector.cleanup_managed_provider(cancelling).unwrap())
  assert_true(@local_connector.cleanup_managed_provider(cancelling).unwrap())
  assert_true(@local_connector.managed_provider_stopped(cancelling))
  assert_true(@carrier_runtime.material_available(material))
  assert_true(@carrier_runtime.reclaim_material(material))
  assert_false(@carrier_runtime.material_available(material))
  assert_true(@carrier_runtime.producer_view_node_count(first_view) is None)
  assert_true(@carrier_runtime.producer_view_edge_count(second_view) is None)
  assert_true(@execution.completed_output_available(first_output))
  assert_true(@execution.completed_output_available(second_output))
}

///|
test "provider scratch cleanup preserves the transferred snapshot generation" {
  let nodes = keyed_node_source()
  let edges = keyed_edge_source()
  let owner = keyed_bridge_owner(nodes, edges)
  let generated = @execution.select_generated_sequence_step(
    task_test_generated(owner),
    0,
  ).unwrap()
  let provider = @local_sga_provider.provider(
    carrier_graph_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      dispatch_test_limits().local_execution,
      dispatch_test_limits().guards,
    ).unwrap(),
    snapshot_policy=Some({
      serialization: snapshot_caps(),
      read: {
        max_nodes: 10000,
        max_depth: 100,
        max_string_bytes: 100000,
        max_total_string_bytes: 100000,
      },
      maximum_bytes: 100000,
      maximum_frame_bytes: 100000,
      workspace_bytes: 1000000L,
    }),
  )
  let construction = @local_connector.start_managed_provider_with_inputs(
    provider,
    generated,
    keyed_bridge_inputs(owner, nodes, edges).map(
      @local_connector.managed_provider_relation_input,
    ),
    10,
    1000,
  ).unwrap()
  let mut material = None
  for _ in 0..<1000 {
    match @local_connector.advance_managed_provider(construction, 1).unwrap() {
      @local_connector.Continue(..) => ()
      @local_connector.CarrierComplete(output, ..) => {
        material = Some(output)
        break
      }
      _ => fail("constructor did not deliver a current Graph")
    }
  }
  let source = material.unwrap()
  let operation = @carrier_runtime.material_prepare_snapshot(source)
    .unwrap()
    .unwrap()
  let saved = StringBuilder()
  let mut complete = false
  for _ in 0..<10000 {
    let advanced = (operation.advance_save)(1).unwrap()
    saved.write_string((operation.take_output)().unwrap())
    if advanced.complete {
      complete = true
      break
    }
  }
  assert_true(complete)
  let content = (operation.content)().unwrap()
  (operation.release_source)(content.cid).unwrap()
  assert_false(@carrier_runtime.material_available(source))
  (operation.begin_reload)(saved.to_string(), () => true).unwrap()
  complete = false
  for _ in 0..<10000 {
    if (operation.advance_reload)(1).unwrap().complete {
      complete = true
      break
    }
  }
  assert_true(complete)
  let restored = (operation.take_material)().unwrap()
  @carrier_runtime.reclaim_material(source) |> ignore
  assert_false(@carrier_runtime.material_cleanup_pending(source))
  assert_eq(@carrier_runtime.material_storage_bytes(restored), Some(4096L))
  assert_true(@local_connector.cleanup_managed_provider(construction).unwrap())
  assert_true(@local_connector.cleanup_managed_provider(construction).unwrap())
  assert_true(@carrier_runtime.material_available(restored))
  assert_eq(@carrier_runtime.material_storage_bytes(restored), Some(4096L))
  let receiver = keyed_graph_receiver(
    owner,
    body="[{\"from\":\"g\",\"match_nodes\":{\"definition\":\"N\",\"where\":\"true\",\"fields\":[\"display\"]}}]",
  )
  let read = @carrier_runtime.material_prepare_view(
    restored, receiver, 0, owner,
  ).unwrap()
  assert_eq(@carrier_runtime.producer_view_node_count(read), Some(1))
  assert_true(@carrier_runtime.reclaim_material(restored))
  assert_false(@carrier_runtime.material_available(restored))
  assert_true(@carrier_runtime.producer_view_node_count(read) is None)
}
