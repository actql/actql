///|
fn subtraction_receiver(
  owner : @lower.BoundPrepared,
  merge? : String = "",
) -> @lower.BoundPrepared {
  union_receiver(
    owner,
    body="[{\"subtract_graphs\":{\"with\":\"g1\"" + merge + "}}]",
  )
}

///|
fn subtraction_storage_limits() -> @graph_storage.Limits {
  {
    ..carrier_graph_storage_limits(),
    max_value_nodes: 100,
    max_value_depth: 100,
    max_work: 100000,
    max_workspace_slots: 100000,
    max_input_rows: 100,
  }
}

///|
test "property Graph subtraction binds ordered occurrences and reuses the selected managed output owner" {
  let owner = equality_alignment_owner(equality_alignment_carrier(false, false))
  let graph = equality_alignment_output(owner, false, [2, 7])
  let receiver = subtraction_receiver(
    owner,
    merge=",\"merge\":{\"node_properties\":{\"p\":\"number_sum\"}}",
  )
  let reads = [0, 1].map(index => {
    @graphs.prepare_producer_read(receiver, index, owner, graph).unwrap()
  })
  let views = reads.map(read => @graphs.producer_read_view(read).unwrap())
  let sequence = prepared_sequence(receiver)
  assert_true(
    @local_sga.start_union_views(
      @bounded.control(),
      sequence,
      0,
      views,
      subtraction_storage_limits(),
      65536L,
      () => true,
    )
    is Err(@local_sga.InvalidUnionFold),
  )
  // Equal Graph content does not authorize exchanging the two occurrence-bound
  // read references. The checked Plan, not an array's incidental content, owns
  // left/right selection.
  assert_true(
    @local_sga.start_subtraction_views(
      @bounded.control(),
      sequence,
      0,
      [views[1], views[0]],
      subtraction_storage_limits(),
      65536L,
      () => true,
    )
    is Err(@local_sga.InvalidUnionFold),
  )
  let provider = @local_sga_provider.provider(
    subtraction_storage_limits(),
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
  assert_true(@local_connector.managed_provider_accepts(provider, generated))
  assert_true(
    @local_connector.managed_provider_capacity(provider, generated) is Some(_),
  )
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
      _ => fail("managed subtraction failed before its Graph handoff")
    }
  } nobreak {
    fail("managed subtraction did not finish")
  }
  assert_eq(
    @local_connector.managed_provider_cumulative_work(active),
    Ok(total),
  )
  assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
  assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
  let material = material.unwrap()
  let consumer = keyed_graph_receiver(receiver, body="[{\"node_rows\":true}]")
  let view = @carrier_runtime.material_prepare_view(
    material, consumer, 0, receiver,
  ).unwrap()
  assert_eq(@carrier_runtime.producer_view_node_count(view), Some(1))
  assert_true(
    @carrier_runtime.producer_view_node_property(view, 0, 0).unwrap().value
    is @admitted.Number(4),
  )
  assert_true(
    @carrier_runtime.producer_view_node_property(view, 0, 1).unwrap().value
    is @admitted.Number(7),
  )
  for read in reads {
    assert_true(@graphs.producer_read_available(read))
  }
  assert_true(@graphs.discard_completed(graph))
  assert_true(@carrier_runtime.material_available(material))
  assert_true(@carrier_runtime.reclaim_material(material))
}

///|
test "property Graph subtraction cancellation after positive work preserves borrowed input custody" {
  let owner = equality_alignment_owner(equality_alignment_carrier(false, false))
  let graph = equality_alignment_output(owner, false, [2, 7])
  let receiver = subtraction_receiver(owner)
  let reads = [0, 1].map(index => {
    @graphs.prepare_producer_read(receiver, index, owner, graph).unwrap()
  })
  let control = @bounded.control()
  let active = @local_sga.start_subtraction_views(
    control,
    prepared_sequence(receiver),
    0,
    reads.map(read => @graphs.producer_read_view(read).unwrap()),
    subtraction_storage_limits(),
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
  assert_false(@local_sga.cleanup_union(active).unwrap())
  assert_false(@local_sga.union_cleanup_pending(active))
  for read in reads {
    assert_true(@graphs.producer_read_available(read))
  }
  assert_true(@graphs.discard_completed(graph))
}

///|
test "property Graph subtraction empty occurrences have independent work seven and one short rejection" {
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
  let receiver = subtraction_receiver(owner)
  let reads = [0, 1].map(index => {
    @graphs.prepare_producer_read(receiver, index, owner, graph).unwrap()
  })
  let views = reads.map(read => @graphs.producer_read_view(read).unwrap())
  // One preparation, four empty node/edge family scans, one Store seal and
  // one final output handoff. The expectation is not measured from the kernel.
  let total = 1 + 4 + 1 + 1
  assert_eq(total, 7)
  for quantum in [1, 64] {
    for ceiling in [total - 1, total] {
      let active = @local_sga.start_subtraction_views(
        @bounded.control(),
        prepared_sequence(receiver),
        0,
        views,
        { ..subtraction_storage_limits(), max_work: ceiling, },
        65536L,
        () => true,
      ).unwrap()
      for _ in 0..<20 {
        match @local_sga.advance_union(active, quantum).unwrap() {
          @local_sga.UnionContinue(work~, ..) =>
            assert_true(work <= ceiling.to_int64())
          @local_sga.UnionComplete(output, work~, ..) => {
            assert_eq(ceiling, total)
            assert_eq(work, total.to_int64())
            assert_eq(
              @graph_storage.node_count(
                @graphs.completed_storage(output).unwrap(),
              ),
              0,
            )
            assert_true(@graphs.discard_completed(output))
            break
          }
          @local_sga.UnionFailed(@local_sga.UnionFoldWorkLimit, work~, ..) => {
            assert_eq(ceiling, total - 1)
            assert_eq(work, (total - 1).to_int64())
            break
          }
          _ => fail("unexpected subtraction work boundary")
        }
      } nobreak {
        fail("empty subtraction did not finish")
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
test "formal Graph subtraction Plan retains binary occurrence order and its native operation" {
  let (_, environment, limits) = local_effect_export_fixture(
    property_graph=true,
  )
  let document =
    #|{"version":"actql/0.1","id":"graph-subtraction-plan","stages":[{"id":"source","inputs":{},"steps":[
    #|{"values":{"schema":{"person_key":{"type":"number","nullable":false},"score":{"type":"number","nullable":false}},"rows":[{"person_key":1,"score":2}]},"as":"nodes"},
    #|{"property_graph":{"version":"actql-property-graph-constructor/0.1","nodes":[{"name":"N","from":"nodes","key":["person_key"],"labels":[{"name":"Node","properties":{"mode":"columns","columns":[{"from":"score","to":"score"}]}}]}],"edges":[]},"as":"g"},
    #|{"from":"g","subtract_graphs":{"with":"g","merge":{"node_properties":{"score":"number_sum"}}},"as":"remaining"},
    #|{"from":"remaining","node_rows":true,"as":"rows"}],"results":{"out":{"from":"rows","fields":["id","score"]}}}],"results":{"answer":{"from":{"stage":"source","result":"out"}}}}
  let prepared = match
    @publication_host.prepare_effect_free_client_program(
      document,
      Json,
      environment,
      None,
      { ..limits.program, max_tasks: 10, max_graph_work: 100000, },
    ) {
    Ok(prepared) => prepared
    Err(@publication_host.Check(diagnostic)) =>
      match @program_check.diagnostic_cause(diagnostic) {
        @program_check.LocalConstructionFailure::Units(
          @program_check.UnitBuildFailure::UnsupportedStaticPath(_)
        ) =>
          fail(
            "formal subtraction refused at the Local static operation boundary",
          )
        cause => raise cause
      }
    Err(_) => fail("formal subtraction Program preparation failed")
  }
  let graph = @publication_host.prepared_client_graph(prepared)
  assert_eq(@strategy.graph_task_count(graph), 4)
  assert_eq(@strategy.graph_task_input_count(graph, 2), Some(2))
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
  assert_true(wire.contains("\"op\":\"SGA.diff_structural\""))
  assert_false(wire.contains("\"op\":\"SGA.union_structural\""))
  assert_true(
    @publication_host.admit_prepared_client_task_plan_graph(
      prepared, wire, sequence, 1000000, 100000, 100,
    )
    is Ok(_),
  )
}
