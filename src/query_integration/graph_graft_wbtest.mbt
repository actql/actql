///|
fn graft_receiver(owner : @lower.BoundPrepared) -> @lower.BoundPrepared {
  union_receiver(owner, body="[{\"graft_graph\":{\"with\":\"g1\"}}]")
}

///|
test "Graph graft selected provider binds both occurrences and retains output independently" {
  let owner = equality_alignment_owner(equality_alignment_carrier(false, false))
  let graph = equality_alignment_output(owner, false, [2, 7])
  let receiver = graft_receiver(owner)
  let sequence = prepared_sequence(receiver)
  let reads = [0, 1].map(index => {
    @graphs.prepare_producer_read(receiver, index, owner, graph).unwrap()
  })
  let views = reads.map(read => @graphs.producer_read_view(read).unwrap())
  assert_true(
    @local_sga.start_union_views(
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
  let generated = @execution.select_generated_sequence_step(
    task_test_generated(receiver),
    0,
  ).unwrap()
  let provider = @local_sga_provider.provider(
    subtraction_storage_limits(),
    65536L,
    @execution.execution_capacity(4096L, 65536L).unwrap(),
  )
  assert_true(@local_connector.managed_provider_accepts(provider, generated))
  let active = start_delta_provider(
    provider,
    generated,
    views.map(@local_connector.managed_provider_carrier_input),
    10,
    10000,
  ).unwrap()
  let mut output = None
  for _ in 0..<10000 {
    match @local_connector.advance_managed_provider(active, 1).unwrap() {
      @local_connector.Continue(work~, ..) =>
        assert_true(work > 0L && work <= 1L)
      @local_connector.CarrierComplete(material, ..) => {
        output = Some(material)
        break
      }
      _ => fail("graft selected provider did not return its retained Graph")
    }
  } nobreak {
    fail("graft selected provider did not settle")
  }
  let material = output.unwrap()
  let consumer = keyed_graph_receiver(receiver, body="[{\"node_rows\":true}]")
  let view = @carrier_runtime.material_prepare_view(
    material, consumer, 0, receiver,
  ).unwrap()
  assert_eq(@carrier_runtime.producer_view_node_count(view), Some(1))
  for (index, expected) in [(0, 2.0), (1, 7.0)] {
    assert_true(
      @carrier_runtime.producer_view_node_property(view, 0, index).unwrap().value
      is @admitted.Number(actual) &&
      actual == expected,
    )
  }
  let work = @local_connector.managed_provider_cumulative_work(active).unwrap()
  assert_true(work > 0L)
  assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
  assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
  assert_eq(@local_connector.managed_provider_cumulative_work(active), Ok(work))
  assert_true(@graphs.discard_completed(graph))
  assert_true(@carrier_runtime.material_available(material))
  assert_true(@carrier_runtime.reclaim_material(material))
}

///|
test "Graph graft empty work and workspace exact one short are independently bounded" {
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
  let receiver = graft_receiver(owner)
  let reads = [0, 1].map(index => {
    @graphs.prepare_producer_read(receiver, index, owner, graph).unwrap()
  })
  let views = reads.map(read => @graphs.producer_read_view(read).unwrap())
  // One fold: setup + four empty family scans + seal + output handoff.
  let work = 1 + 4 + 1 + 1
  // One key/two properties: append stacks 5366, value/order frames 2400,
  // two occurrence controls 8, and fixed control state 64. No stored records.
  let slots = 3200 + 800 + 1200 + 6 + 160 + 1600 + 800 + 8 + 64
  assert_eq(work, 7)
  assert_eq(slots, 7838)
  for quantum in [1, 64] {
    for
      (work_limit, slot_limit) in [
        (work, slots),
        (work - 1, slots),
        (work, slots - 1),
      ] {
      let active = @local_sga.start_union_views(
        @bounded.control(),
        prepared_sequence(receiver),
        0,
        views,
        {
          ..subtraction_storage_limits(),
          max_work: work_limit,
          max_workspace_slots: slot_limit,
        },
        65536L,
        () => true,
      ).unwrap()
      for _ in 0..<20 {
        match @local_sga.advance_union(active, quantum).unwrap() {
          @local_sga.UnionContinue(work=used, ..) =>
            assert_true(used <= work_limit.to_int64())
          @local_sga.UnionComplete(output, work=used, ..) => {
            assert_eq((work_limit, slot_limit), (work, slots))
            assert_eq(used, work.to_int64())
            assert_eq(
              @graph_storage.node_count(
                @graphs.completed_storage(output).unwrap(),
              ),
              0,
            )
            assert_true(@graphs.discard_completed(output))
            break
          }
          @local_sga.UnionFailed(@local_sga.UnionFoldWorkLimit, work=used, ..) => {
            assert_eq((work_limit, slot_limit), (work - 1, slots))
            assert_eq(used, (work - 1).to_int64())
            break
          }
          @local_sga.UnionFailed(
            @local_sga.UnionFoldWorkspaceLimit,
            work=used,
            ..
          ) => {
            assert_eq((work_limit, slot_limit), (work, slots - 1))
            assert_eq(used, 1L)
            break
          }
          _ => fail("graft failed at an unrelated resource boundary")
        }
      } nobreak {
        fail("graft resource boundary did not settle")
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
test "Graph graft provider observes cancellation before output handoff and preserves input custody" {
  let owner = equality_alignment_owner(equality_alignment_carrier(false, false))
  let graph = equality_alignment_output(owner, false, [2, 7])
  let receiver = graft_receiver(owner)
  let reads = [0, 1].map(index => {
    @graphs.prepare_producer_read(receiver, index, owner, graph).unwrap()
  })
  let generated = @execution.select_generated_sequence_step(
    task_test_generated(receiver),
    0,
  ).unwrap()
  let provider = @local_sga_provider.provider(
    subtraction_storage_limits(),
    65536L,
    @execution.execution_capacity(4096L, 65536L).unwrap(),
  )
  let active = start_delta_provider(
    provider,
    generated,
    reads.map(read => {
      @local_connector.managed_provider_carrier_input(
        @graphs.producer_read_view(read).unwrap(),
      )
    }),
    10,
    10000,
  ).unwrap()
  assert_true(
    @local_connector.advance_managed_provider(active, 1).unwrap()
    is @local_connector.Continue(work=1L, ..),
  )
  assert_true(@local_connector.cancel_managed_provider(active))
  for _ in 0..<20 {
    match @local_connector.advance_managed_provider(active, 1).unwrap() {
      @local_connector.Continue(_) => ()
      @local_connector.Stopped(..) => break
      _ => fail("cancelled graft must not hand off a Graph")
    }
  } nobreak {
    fail("cancelled graft did not confirm stopping")
  }
  assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
  for read in reads {
    assert_true(@graphs.producer_read_available(read))
  }
  assert_true(@graphs.discard_completed(graph))
}
