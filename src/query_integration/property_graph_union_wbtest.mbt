///|
fn union_receiver(
  owner : @lower.BoundPrepared,
  body? : String = "[{\"union_graphs\":{\"with\":[\"g1\",\"g2\"],\"merge\":{\"node_properties\":{\"p\":\"number_sum\"}}}}]",
) -> @lower.BoundPrepared {
  let input = @pipeline.ProducedInput(
    @pipeline.produced_input(
      @lower.pipeline(@lower.bound_preparation(owner)),
      @pipeline.Input(0),
    ).unwrap(),
  )
  let checked = @pipeline.check_with_evidence(
    input_cursor(body),
    [("g0", input), ("g1", input), ("g2", input)],
    None,
    Some(input_cursor("\"g0\"")),
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 1000,
      max_references: 1000,
      max_work: 100000,
      max_identifier_bytes: 100000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
test "property Graph union consumes every shared input occurrence on one bounded session" {
  let owner = equality_alignment_owner(equality_alignment_carrier(false, false))
  let graph = equality_alignment_output(owner, false, [2, 7])
  let receiver = union_receiver(owner)
  let reads = [0, 1, 2].map(index => {
    @graphs.prepare_producer_read(receiver, index, owner, graph).unwrap()
  })
  let views = reads.map(read => @graphs.producer_read_view(read).unwrap())
  let limits = {
    ..carrier_graph_storage_limits(),
    max_value_nodes: 100,
    max_value_depth: 100,
    max_work: 100000,
    max_workspace_slots: 100000,
    max_input_rows: 100,
  }
  let active = @local_sga.start_union_views(
    @bounded.control(),
    prepared_sequence(receiver),
    0,
    views,
    limits,
    65536L,
    () => true,
  ).unwrap()
  let mut output = None
  let mut work = 0L
  for _ in 0..<10000 {
    match @local_sga.advance_union(active, 1).unwrap() {
      @local_sga.UnionContinue(work=current, ..) => {
        assert_eq(current, work + 1L)
        work = current
      }
      @local_sga.UnionComplete(result, work=current, ..) => {
        assert_eq(current, work + 1L)
        output = Some(result)
        break
      }
      _ => fail("shared union failed")
    }
  } nobreak {
    fail("shared union did not finish")
  }
  let output = output.unwrap()
  let storage = @graphs.completed_storage(output).unwrap()
  assert_eq(@graph_storage.node_count(storage), 1)
  assert_true(
    @graph_storage.node_property(storage, 0, 0).unwrap().value
    is @admitted.Number(6),
  )
  assert_true(
    @graph_storage.node_property(storage, 0, 1).unwrap().value
    is @admitted.Number(7),
  )
  assert_true(@local_sga.cleanup_union(active).unwrap())
  assert_false(@local_sga.union_cleanup_pending(active))
  for read in reads {
    assert_true(@graphs.producer_read_available(read))
  }
  // The retained result is a new generation, not a borrowed-input alias.
  assert_true(@graphs.discard_completed(graph))
  assert_true(@graphs.completed_available(output))
  assert_true(@graph_storage.available(storage))
  assert_true(@graphs.discard_completed(output))
}

///|
test "property Graph union preserves ordered occurrences and independent retained generations" {
  // A non-associative mean distinguishes port order from a commutative sum.
  // (2 mean 10) mean 30 = 18; repeating the first generation in port two
  // instead gives (2 mean 10) mean 2 = 4, not the deduplicated value 6.
  for quantum in [1, 7] {
    for repeated in [false, true] {
      let owner = equality_alignment_owner(
        equality_alignment_carrier(false, false),
      )
      let first = equality_alignment_output(owner, false, [2, 7])
      let second = equality_alignment_output(owner, false, [10, 7])
      let third = equality_alignment_output(owner, false, [30, 7])
      let sources = [first, second, if repeated { first } else { third }]
      let receiver = union_receiver(
        owner,
        body="[{\"union_graphs\":{\"with\":[\"g1\",\"g2\"],\"merge\":{\"node_properties\":{\"p\":\"number_mean\"}}}}]",
      )
      let reads = sources.mapi((index, source) => {
        @graphs.prepare_producer_read(receiver, index, owner, source).unwrap()
      })
      for index, read in reads {
        assert_true(
          @graphs.producer_read_matches_operation_input(
            read, receiver, 0, index,
          ),
        )
        for other in 0..<reads.length() {
          if other != index {
            assert_false(
              @graphs.producer_read_matches_operation_input(
                read, receiver, 0, other,
              ),
            )
          }
        }
      }
      let views = reads.map(read => @graphs.producer_read_view(read).unwrap())
      let limits = {
        ..carrier_graph_storage_limits(),
        max_value_nodes: 10000,
        max_value_depth: 100,
        max_work: 100000,
        max_workspace_slots: 2000000,
        max_input_rows: 100,
      }
      // Even when ports zero and two borrow the same generation, a view
      // bound to another occurrence must not be accepted at this position.
      assert_true(
        @local_sga.start_union_views(
          @bounded.control(),
          prepared_sequence(receiver),
          0,
          [views[2], views[1], views[0]],
          limits,
          65536L,
          () => true,
        )
        is Err(_),
      )
      let generated = @execution.select_generated_sequence_step(
        task_test_generated(receiver),
        0,
      ).unwrap()
      let provider = @local_sga_provider.provider(
        limits,
        65536L,
        @execution.execution_capacity(4096L, 65536L).unwrap(),
      )
      let active = start_delta_provider(
        provider,
        generated,
        views.map(@local_connector.managed_provider_carrier_input),
        10,
        10000,
      ).unwrap()
      let mut result = None
      for _ in 0..<10000 {
        match
          @local_connector.advance_managed_provider(active, quantum).unwrap() {
          @local_connector.Continue(_) => ()
          @local_connector.CarrierComplete(material, ..) => {
            result = Some(material)
            break
          }
          _ => fail("ordered union did not return its own retained generation")
        }
      } nobreak {
        fail("ordered union did not finish")
      }
      let result = result.unwrap()
      let consumer = keyed_graph_receiver(
        receiver,
        body="[{\"node_rows\":true}]",
      )
      let view = @carrier_runtime.material_prepare_view(
        result, consumer, 0, receiver,
      ).unwrap()
      let expected = if repeated { 4.0 } else { 18.0 }
      assert_true(
        @carrier_runtime.producer_view_node_property(view, 0, 0).unwrap().value
        is @admitted.Number(value) &&
        value == expected,
      )
      let work = @local_connector.managed_provider_cumulative_work(active).unwrap()
      assert_true(work > 0L)
      assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
      assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
      assert_eq(
        @local_connector.managed_provider_cumulative_work(active),
        Ok(work),
      )
      for read in reads {
        assert_true(@graphs.producer_read_available(read))
      }
      // Reclaiming the output must not dispose either borrowed generation.
      assert_true(@carrier_runtime.reclaim_material(result))
      assert_false(@carrier_runtime.material_available(result))
      assert_true(@graphs.completed_available(first))
      assert_true(@graphs.completed_available(second))
      assert_true(@graphs.completed_available(third))
      assert_true(@graphs.discard_completed(first))
      assert_false(@graphs.producer_read_available(reads[0]))
      assert_eq(@graphs.producer_read_available(reads[2]), !repeated)
      assert_true(@graphs.producer_read_available(reads[1]))
      assert_true(@graphs.discard_completed(second))
      assert_true(@graphs.discard_completed(third))
    }
  }
}

///|
test "property Graph union cancellation after positive work keeps shared input custody" {
  let owner = equality_alignment_owner(equality_alignment_carrier(false, false))
  let graph = equality_alignment_output(owner, false, [2, 7])
  let receiver = union_receiver(owner)
  let reads = [0, 1, 2].map(index => {
    @graphs.prepare_producer_read(receiver, index, owner, graph).unwrap()
  })
  let views = reads.map(read => @graphs.producer_read_view(read).unwrap())
  let limits = {
    ..carrier_graph_storage_limits(),
    max_value_nodes: 100,
    max_value_depth: 100,
    max_work: 100000,
    max_workspace_slots: 100000,
    max_input_rows: 100,
  }
  let control = @bounded.control()
  let active = @local_sga.start_union_views(
    control,
    prepared_sequence(receiver),
    0,
    views,
    limits,
    65536L,
    () => true,
  ).unwrap()
  assert_true(
    @local_sga.advance_union(active, 1).unwrap()
    is @local_sga.UnionContinue(work=1L, ..),
  )
  assert_true(@bounded.request_cancel(control))
  assert_true(
    @local_sga.advance_union(active, 1).unwrap()
    is @local_sga.UnionStopped(_, work=1L, ..),
  )
  assert_true(@local_sga.cleanup_union(active).unwrap())
  // False reports that the second call reclaimed nothing new, not a failure.
  assert_false(@local_sga.cleanup_union(active).unwrap())
  assert_false(@local_sga.union_cleanup_pending(active))
  for read in reads {
    assert_true(@graphs.producer_read_available(read))
  }
  assert_true(@graphs.discard_completed(graph))
}

///|
test "property Graph union selected managed provider retains its completed generation" {
  let owner = equality_alignment_owner(equality_alignment_carrier(false, false))
  let graph = equality_alignment_output(owner, false, [2, 7])
  let receiver = union_receiver(owner)
  let reads = [0, 1, 2].map(index => {
    @graphs.prepare_producer_read(receiver, index, owner, graph).unwrap()
  })
  let views = reads.map(read => @graphs.producer_read_view(read).unwrap())
  let limits = {
    ..carrier_graph_storage_limits(),
    max_value_nodes: 10000,
    max_value_depth: 100,
    max_work: 100000,
    max_workspace_slots: 10000,
    max_input_rows: 100,
  }
  let provider = @local_sga_provider.provider(
    limits,
    65536L,
    @execution.execution_capacity(4096L, 65536L).unwrap(),
    union_policy=Some({
      max_workspace_slots: 2000000,
      workspace_bytes: 67108864L,
    }),
  )
  let generated = @execution.select_generated_sequence_step(
    task_test_generated(receiver),
    0,
  ).unwrap()
  let unconfigured = @local_sga_provider.provider(
    limits,
    65536L,
    @execution.execution_capacity(4096L, 65536L).unwrap(),
  )
  let reserved = @local_connector.managed_provider_capacity(provider, generated).unwrap()
  let ordinary = @local_connector.managed_provider_capacity(
    unconfigured, generated,
  ).unwrap()
  assert_eq(
    @execution.execution_capacity_execution_bytes(reserved) -
    @execution.execution_capacity_execution_bytes(ordinary),
    67108864L,
  )
  let insufficient = start_delta_provider(
    unconfigured,
    generated,
    views.map(@local_connector.managed_provider_carrier_input),
    10,
    10000,
  ).unwrap()
  assert_true(
    @local_connector.advance_managed_provider(insufficient, 1).unwrap()
    is @local_connector.Failed(_, work=1L, ..),
  )
  assert_true(@local_connector.cleanup_managed_provider(insufficient).unwrap())
  let invalid_policies : Array[@local_sga_provider.UnionPolicy] = [
    { max_workspace_slots: 9999, workspace_bytes: 67108864L, },
    { max_workspace_slots: 2000000, workspace_bytes: -1L, },
    { max_workspace_slots: 2000000, workspace_bytes: 9223372036854775807L, },
  ]
  for policy in invalid_policies {
    let invalid = @local_sga_provider.provider(
      limits,
      65536L,
      @execution.execution_capacity(4096L, 65536L).unwrap(),
      union_policy=Some(policy),
    )
    assert_true(
      @local_connector.managed_provider_capacity(invalid, generated) is None,
    )
  }
  assert_true(@local_connector.managed_provider_accepts(provider, generated))
  let active = start_delta_provider(
    provider,
    generated,
    views.map(@local_connector.managed_provider_carrier_input),
    10,
    10000,
  ).unwrap()
  let mut material = None
  let mut total = 0L
  for _ in 0..<10000 {
    match @local_connector.advance_managed_provider(active, 7).unwrap() {
      @local_connector.Continue(work~, ..) => {
        assert_true(work > 0L && work <= 7L)
        total += work
      }
      @local_connector.CarrierComplete(output, work~, ..) => {
        total += work
        material = Some(output)
        break
      }
      _ =>
        fail(
          "managed union did not complete through the existing Graph output owner",
        )
    }
  } nobreak {
    fail("managed union did not terminate")
  }
  let material = material.unwrap()
  assert_eq(
    @local_connector.managed_provider_cumulative_work(active),
    Ok(total),
  )
  assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
  assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
  assert_true(@carrier_runtime.material_available(material))
  for read in reads {
    assert_true(@graphs.producer_read_available(read))
  }
  let consumer = keyed_graph_receiver(receiver, body="[{\"node_rows\":true}]")
  let view = @carrier_runtime.material_prepare_view(
    material, consumer, 0, receiver,
  ).unwrap()
  assert_eq(@carrier_runtime.producer_view_node_count(view), Some(1))
  assert_true(
    @carrier_runtime.producer_view_node_property(view, 0, 0).unwrap().value
    is @admitted.Number(6),
  )
  assert_true(
    @carrier_runtime.producer_view_node_property(view, 0, 1).unwrap().value
    is @admitted.Number(7),
  )
  assert_true(@graphs.discard_completed(graph))
  assert_true(@carrier_runtime.material_available(material))
  assert_true(@carrier_runtime.reclaim_material(material))
}

///|
test "formal Graph union Plan retains each ordered operand occurrence" {
  let (_, environment, limits) = local_effect_export_fixture(
    property_graph=true,
  )
  let document =
    #|{"version":"actql/0.1","id":"graph-union-plan","stages":[{"id":"source","inputs":{},"steps":[
    #|{"values":{"schema":{"person_key":{"type":"number","nullable":false},"score":{"type":"number","nullable":false}},"rows":[{"person_key":1,"score":2}]},"as":"nodes"},
    #|{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["person_key"],"labels":[{"name":"Node","properties":{"mode":"columns","columns":[{"from":"score","to":"score"}]}}]}],"edges":[]},"as":"g"},
    #|{"from":"g","union_graphs":{"with":["g","g"],"merge":{"node_properties":{"score":"number_sum"}}},"as":"combined"},
    #|{"from":"combined","node_rows":true,"as":"rows"}],"results":{"out":{"from":"rows","fields":["id","score"]}}}],"results":{"answer":{"from":{"stage":"source","result":"out"}}}}
  let prepared = match
    @publication_host.prepare_effect_free_client_program(
      document,
      Json,
      environment,
      None,
      { ..limits.program, max_tasks: 10, max_graph_work: 100000, },
    ) {
    Ok(prepared) => prepared
    Err(@publication_host.Graph(_)) =>
      abort("formal union Graph preparation failed")
    Err(@publication_host.Check(diagnostic)) =>
      raise @program_check.diagnostic_cause(diagnostic)
    Err(@publication_host.NeedsInputs(_)) => abort("formal union needs inputs")
    Err(@publication_host.Lowering(_)) => abort("formal union lowering failed")
    Err(_) => abort("formal union syntax, stage identity or binding failed")
  }
  let graph = @publication_host.prepared_client_graph(prepared)
  assert_eq(@strategy.graph_task_count(graph), 4)
  assert_eq(@strategy.graph_task_input_count(graph, 2), Some(3))
  assert_eq(@strategy.graph_task_selected_step(graph, 2), Some(2))
  let sequence : @lower.SequenceLimits = {
    max_steps: 100,
    max_rows: 100,
    max_cells: 10000,
    max_bindings: 100,
    max_name_bytes: 100000,
    expressions: {
      max_nodes: 10000,
      max_work: 100000,
      max_depth: 100,
      max_literal_nodes: 10000,
      max_literal_text_bytes: 10000,
    },
  }
  let plan = @publication_host.issue_prepared_client_task_plan_graph(
    prepared, sequence, 1000000, 100000, 100,
  ).unwrap()
  let wire = @publication_host.client_task_plan_graph_wire(plan)
  assert_true(wire.contains("\"op\":\"SGA.union_structural\""))
  assert_true(
    @publication_host.admit_prepared_client_task_plan_graph(
      prepared, wire, sequence, 1000000, 100000, 100,
    )
    is Ok(_),
  )
}

///|
test "property Graph union empty occurrences share one independent operation wide work budget" {
  let owner = equality_alignment_owner(equality_alignment_carrier(false, false))
  let graph = @graphs.finish_output(
    @graphs.prepare_output(
      owner,
      @pipeline.Input(0),
      DeclaredNodes,
      carrier_graph_storage_limits(),
      4096L,
      () => true,
    ).unwrap(),
  ).unwrap()
  let receiver = union_receiver(owner)
  let reads = [0, 1, 2].map(index => {
    @graphs.prepare_producer_read(receiver, index, owner, graph).unwrap()
  })
  let views = reads.map(read => @graphs.producer_read_view(read).unwrap())
  // Two authored folds, each with one setup and four empty family scans plus
  // one Store seal. The final output authority consumes one more work unit.
  let preparation = 2
  let scans = 2 * 2 * 2
  let seals = 2
  let completion = 1
  let total = preparation + scans + seals + completion
  assert_eq(total, 13)
  for quantum in [1, 64] {
    for ceiling in [total - 1, total] {
      let limits = {
        ..carrier_graph_storage_limits(),
        max_value_nodes: 100,
        max_value_depth: 100,
        max_work: ceiling,
        max_workspace_slots: 100000,
        max_input_rows: 100,
      }
      let active = @local_sga.start_union_views(
        @bounded.control(),
        prepared_sequence(receiver),
        0,
        views,
        limits,
        65536L,
        () => true,
      ).unwrap()
      for _ in 0..<20 {
        match @local_sga.advance_union(active, quantum).unwrap() {
          @local_sga.UnionContinue(work~, ..) =>
            assert_true(work <= ceiling.to_int64())
          @local_sga.UnionComplete(result, work~, ..) => {
            assert_eq(ceiling, total)
            assert_eq(work, total.to_int64())
            assert_eq(
              @graph_storage.node_count(
                @graphs.completed_storage(result).unwrap(),
              ),
              0,
            )
            assert_true(@graphs.discard_completed(result))
            break
          }
          @local_sga.UnionFailed(@local_sga.UnionFoldWorkLimit, work~, ..) => {
            assert_eq(ceiling, total - 1)
            assert_eq(work, (total - completion).to_int64())
            break
          }
          _ => fail("unexpected operation wide empty union work boundary")
        }
      } nobreak {
        fail("empty occurrence union did not terminate")
      }
      assert_true(@local_sga.cleanup_union(active).unwrap())
      assert_false(@local_sga.union_cleanup_pending(active))
      for read in reads {
        assert_true(@graphs.producer_read_available(read))
      }
    }
  }
  assert_true(@graphs.discard_completed(graph))
}

///|
test "property Graph union retained snapshot matches independent bytes after source invalidation and reload" {
  let owner = snapshot_fixture_owner()
  let graph = snapshot_handoff_source(owner)
  let receiver = union_receiver(
    owner,
    body="[{\"union_graphs\":{\"with\":[\"g1\",\"g2\"]}}]",
  )
  let views = [0, 1, 2].map(index => {
    @graphs.producer_read_view(
      @graphs.prepare_producer_read(receiver, index, owner, graph).unwrap(),
    ).unwrap()
  })
  let limits = {
    ..carrier_graph_storage_limits(),
    max_work: 100000,
    max_workspace_slots: 100000,
    max_input_rows: 100,
  }
  let provider = @local_sga_provider.provider(
    limits,
    65536L,
    @execution.execution_capacity(4096L, 65536L).unwrap(),
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
  let generated = @execution.select_generated_sequence_step(
    task_test_generated(receiver),
    0,
  ).unwrap()
  let active = start_delta_provider(
    provider,
    generated,
    views.map(@local_connector.managed_provider_carrier_input),
    10,
    10000,
  ).unwrap()
  let mut material = None
  for _ in 0..<10000 {
    match @local_connector.advance_managed_provider(active, 7).unwrap() {
      @local_connector.Continue(..) => ()
      @local_connector.CarrierComplete(output, ..) => {
        material = Some(output)
        break
      }
      _ => fail("snapshot-enabled union provider failed")
    }
  } nobreak {
    fail("snapshot-enabled union did not terminate")
  }
  let material = material.unwrap()
  assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
  assert_true(@graphs.discard_completed(graph))
  assert_true(@carrier_runtime.material_available(material))
  let snapshot = @carrier_runtime.material_prepare_snapshot(material)
    .unwrap()
    .unwrap()
  let saved = StringBuilder()
  let mut save_complete = false
  for _ in 0..<10000 {
    let poll = (snapshot.advance_save)(7).unwrap()
    saved.write_string((snapshot.take_output)().unwrap())
    if poll.complete {
      save_complete = true
      break
    }
  }
  assert_true(save_complete)
  let content = (snapshot.content)().unwrap()
  // Repeated exact-equal operands preserve this independently authored keyed
  // snapshot, including two independent edges with identical endpoints.
  assert_eq(saved.to_string(), snapshot_fixture_body())
  assert_eq(content.cid, snapshot_fixture_cid())
  let consumer = keyed_graph_receiver(receiver, body="[{\"node_rows\":true}]")
  (snapshot.release_source)(content.cid).unwrap()
  assert_false(@carrier_runtime.material_available(material))
  assert_true(
    @carrier_runtime.material_prepare_view(material, consumer, 0, receiver)
    is Err(_),
  )
  (snapshot.begin_reload)(saved.to_string(), () => true).unwrap()
  let mut reload_complete = false
  for _ in 0..<10000 {
    if (snapshot.advance_reload)(7).unwrap().complete {
      reload_complete = true
      break
    }
  }
  assert_true(reload_complete)
  let restored = (snapshot.take_material)().unwrap()
  let view = @carrier_runtime.material_prepare_view(
    restored, consumer, 0, receiver,
  ).unwrap()
  assert_eq(@carrier_runtime.producer_view_node_count(view), Some(1))
  assert_eq(@carrier_runtime.producer_view_edge_count(view), Some(2))
  assert_true(
    @carrier_runtime.producer_view_node_key(view, 0, 0).unwrap().value
    is @admitted.Number(1),
  )
  assert_true(
    @carrier_runtime.producer_view_node_property(view, 0, 0).unwrap().value
    is @admitted.Text("one"),
  )
  for edge in 0..<2 {
    assert_true(
      @carrier_runtime.producer_view_edge_key(view, edge, 0).unwrap().value
      is @admitted.Number(key) &&
      key == (10 + edge).to_double(),
    )
    assert_eq(
      @carrier_runtime.producer_view_edge_endpoints(view, edge),
      Ok((0, 0)),
    )
  }
  let projection = @execution.select_generated_sequence_step(
    task_test_generated(consumer),
    0,
  ).unwrap()
  let projecting = start_delta_provider(
    delta_provider_fixture(delta_policy=None),
    projection,
    [@local_connector.managed_provider_carrier_input(view)],
    10,
    10000,
  ).unwrap()
  let mut relation = None
  for _ in 0..<10000 {
    match @local_connector.advance_managed_provider(projecting, 7).unwrap() {
      @local_connector.Continue(..) => ()
      @local_connector.Complete(output, ..) => {
        relation = Some(output)
        break
      }
      _ => fail("reloaded union did not reach the ordinary Relation owner")
    }
  } nobreak {
    fail("reloaded union projection did not terminate")
  }
  let relation = relation.unwrap()
  assert_eq(@execution.completed_row_count(relation), 1)
  let expected = "{\"id\":" +
    snapshot_fixture_identity("N", 1) +
    ",\"labels\":[\"Node\",\"Person\"],\"name\":\"one\"}"
  assert_eq(
    @execution.completed_output_row_wire(relation, 0, 10000, 10000, 50).unwrap(),
    expected,
  )
  assert_true(@local_connector.cleanup_managed_provider(projecting).unwrap())
  assert_true(@carrier_runtime.reclaim_material(restored))
  for _ in 0..<2 {
    (snapshot.cleanup)().unwrap() |> ignore
  }
  assert_true((snapshot.cleanup)().unwrap())
}

///|
test "property Graph union reserves independent workspace before the first fold" {
  let owner = equality_alignment_owner(equality_alignment_carrier(false, false))
  let graph = @graphs.finish_output(
    @graphs.prepare_output(
      owner,
      @pipeline.Input(0),
      DeclaredNodes,
      carrier_graph_storage_limits(),
      4096L,
      () => true,
    ).unwrap(),
  ).unwrap()
  let receiver = union_receiver(owner)
  let reads = [0, 1, 2].map(index => {
    @graphs.prepare_producer_read(receiver, index, owner, graph).unwrap()
  })
  let views = reads.map(read => @graphs.producer_read_view(read).unwrap())
  // One key and two properties, 100 value nodes and depth 100. The append
  // owner's stacks/staging need 3200+800+1200+6+160 = 5366 slots. Union's
  // sets/order/control and three occurrences add 1600+800+12+64 = 2476.
  // Empty retained generations consume no additional record slots.
  let append_slots = 3200 + 800 + 1200 + 6 + 160
  let union_slots = 1600 + 800 + 12 + 64
  let required = append_slots + union_slots
  assert_eq(required, 7842)
  for quantum in [1, 64] {
    for slots in [required - 1, required] {
      let limits = {
        ..carrier_graph_storage_limits(),
        max_value_nodes: 100,
        max_value_depth: 100,
        max_work: 13,
        max_workspace_slots: slots,
        max_input_rows: 100,
      }
      let active = @local_sga.start_union_views(
        @bounded.control(),
        prepared_sequence(receiver),
        0,
        views,
        limits,
        65536L,
        () => true,
      ).unwrap()
      for _ in 0..<20 {
        match @local_sga.advance_union(active, quantum).unwrap() {
          @local_sga.UnionContinue(..) => assert_eq(slots, required)
          @local_sga.UnionComplete(result, work~, ..) => {
            assert_eq(slots, required)
            assert_eq(work, 13L)
            assert_true(@graphs.discard_completed(result))
            break
          }
          @local_sga.UnionFailed(@local_sga.UnionFoldWorkspaceLimit, work~, ..) => {
            assert_eq(slots, required - 1)
            assert_eq(work, 1L)
            break
          }
          _ => fail("unexpected union workspace boundary")
        }
      } nobreak {
        fail("bounded union workspace fixture did not terminate")
      }
      assert_true(@local_sga.cleanup_union(active).unwrap())
      assert_false(@local_sga.cleanup_union(active).unwrap())
      assert_false(@local_sga.union_cleanup_pending(active))
      for read in reads {
        assert_true(@graphs.producer_read_available(read))
      }
    }
  }
  assert_true(@graphs.discard_completed(graph))
}
