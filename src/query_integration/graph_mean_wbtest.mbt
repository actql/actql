///|
fn mean_receiver(owner : @lower.BoundPrepared) -> @lower.BoundPrepared {
  union_receiver(
    owner,
    body="[{\"mean_graphs\":{\"with\":[\"g2\",\"g0\",\"g2\"],\"weights\":[1,2,0],\"support\":{\"nodes\":1,\"edges\":1},\"properties\":{\"nodes\":{\"p\":{\"mean\":{\"missing\":\"exclude\",\"nulls\":\"exclude\"}},\"q\":\"exact_equal\"},\"edges\":{}}},\"as\":\"combined\"}]",
  )
}

///|
fn mean_provider_policy() -> @local_sga_provider.MeanPolicy {
  {
    limits: {
      max_samples: 3,
      max_exact_operations: 100000,
      max_coefficient_bits: 8192,
      max_temporary_bytes: 36400,
    },
    max_workspace_slots: 100000,
    workspace_bytes: 2000000L,
  }
}

///|
fn mean_test_reads(
  receiver : @lower.BoundPrepared,
  owner : @lower.BoundPrepared,
  output : @graphs.Completed,
) -> Array[@graphs.ProducerRead] {
  // The generator's operation-port order is g2, g0, g2. Stage-input order
  // and repeated occurrence identity must never replace these bindings.
  [2, 0, 2].map(index => {
    @graphs.prepare_producer_read(receiver, index, owner, output).unwrap()
  })
}

///|
test "Mean provider requires its finite profile and owns an independent completed Graph" {
  let owner = equality_alignment_owner(equality_alignment_carrier(false, false))
  let graph = equality_alignment_output(owner, false, [2, 7])
  let receiver = mean_receiver(owner)
  let sequence = @execution.select_generated_sequence_step(
    task_test_generated(receiver),
    0,
  ).unwrap()
  let capacity = @execution.execution_capacity(4096L, 65536L).unwrap()
  let unconfigured = @local_sga_provider.provider(
    subtraction_storage_limits(),
    65536L,
    capacity,
  )
  assert_false(
    @local_connector.managed_provider_accepts(unconfigured, sequence),
  )
  let provider = @local_sga_provider.provider(
    subtraction_storage_limits(),
    65536L,
    capacity,
    mean_policy=Some(mean_provider_policy()),
  )
  assert_true(@local_connector.managed_provider_accepts(provider, sequence))
  for quantum in [1, 7, 64] {
    let reads = mean_test_reads(receiver, owner, graph)
    let active = start_delta_provider(
      provider,
      sequence,
      reads.map(read => {
        @local_connector.managed_provider_carrier_input(
          @graphs.producer_read_view(read).unwrap(),
        )
      }),
      10,
      10000,
    ).unwrap()
    let mut result = None
    for _ in 0..<10000 {
      match
        @local_connector.advance_managed_provider(active, quantum).unwrap() {
        @local_connector.Continue(work~, ..) =>
          assert_true(work > 0L && work <= quantum.to_int64())
        @local_connector.CarrierComplete(material, ..) => {
          result = Some(material)
          break
        }
        _ => fail("mean selected provider did not complete")
      }
    } nobreak {
      fail("mean selected provider did not settle")
    }
    let material = result.unwrap()
    let consumer = keyed_graph_receiver(receiver, body="[{\"node_rows\":true}]")
    let view = @carrier_runtime.material_prepare_view(
      material, consumer, 0, receiver,
    ).unwrap()
    assert_eq(@carrier_runtime.producer_view_node_count(view), Some(1))
    assert_eq(@carrier_runtime.producer_view_edge_count(view), Some(0))
    for (index, expected) in [(0, 2.0), (1, 7.0)] {
      assert_true(
        @carrier_runtime.producer_view_node_property(view, 0, index).unwrap().value
        is @admitted.Number(actual) &&
        actual == expected,
      )
    }
    assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
    assert_true(@carrier_runtime.material_available(material))
    for read in reads {
      assert_true(@graphs.producer_read_available(read))
    }
    assert_true(@carrier_runtime.reclaim_material(material))
  }
  assert_true(@graphs.discard_completed(graph))
}

///|
test "Mean observes every positive-work yield cancellation including private output handoff" {
  let owner = equality_alignment_owner(equality_alignment_carrier(false, false))
  let graph = equality_alignment_output(owner, false, [2, 7])
  let receiver = mean_receiver(owner)
  let reads = mean_test_reads(receiver, owner, graph)
  let views = reads.map(read => @graphs.producer_read_view(read).unwrap())
  // Independently finite bound: enumerate each resume prefix until the first
  // normal completion, without deriving a resource expectation from its work.
  let mut completed = false
  for prefix in 1..<2000 {
    let control = @bounded.control()
    let active = @local_sga.start_mean_views(
      control,
      prepared_sequence(receiver),
      0,
      views,
      { ..subtraction_storage_limits(), max_workspace_slots: 100000, },
      mean_provider_policy().limits,
      65536L,
      () => true,
    ).unwrap()
    let mut finished = None
    for _ in 0..<prefix {
      match @local_sga.advance_mean(active, 1).unwrap() {
        @local_sga.MeanContinue(..) => ()
        @local_sga.MeanComplete(output, ..) => {
          finished = Some(output)
          break
        }
        _ => fail("mean failed before cancellation")
      }
    }
    if finished is Some(output) {
      assert_true(@graphs.discard_completed(output))
      assert_true(@local_sga.cleanup_mean(active).unwrap())
      completed = true
      break
    }
    assert_true(
      @local_sga.cleanup_mean(active)
      is Err(@local_sga.MeanExecutionFailure(@bounded.NotStopped)),
    )
    assert_true(@bounded.request_cancel(control))
    for read in reads {
      assert_true(@graphs.producer_read_available(read))
    }
    assert_true(
      @local_sga.advance_mean(active, 1).unwrap()
      is @local_sga.MeanStopped(_, ..),
    )
    assert_true(@local_sga.mean_cleanup_pending(active))
    assert_true(@local_sga.cleanup_mean(active).unwrap())
    assert_false(@local_sga.mean_cleanup_pending(active))
    for read in reads {
      assert_true(@graphs.producer_read_available(read))
    }
  }
  assert_true(completed)
  assert_true(@graphs.discard_completed(graph))
}

///|
test "Mean managed empty fold has independent work workspace and exact-operation boundaries" {
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
  let receiver = mean_receiver(owner)
  let reads = mean_test_reads(receiver, owner, graph)
  let views = reads.map(read => @graphs.producer_read_view(read).unwrap())
  // Three occurrence checks plus their phase transition, output preparation,
  // 17 empty-fold control transitions, and one successful output handoff.
  let work = 3 + 1 + 1 + 17 + 1
  // Append width three: 5366 slots. Mean roots use six occurrence entries,
  // ten possible node tokens, 1600 value frames, 800 depth frames and 64 state.
  let slots = 5366 + 6 + 10 + 1600 + 800 + 64
  // Three weight additions, including the declared zero-weight occurrence.
  let exact_operations = 3
  for quantum in [1, 7, 64] {
    for
      (work_limit, slot_limit, exact_limit) in [
        (work, slots, exact_operations),
        (work - 1, slots, exact_operations),
        (work, slots - 1, exact_operations),
        (work, slots, exact_operations - 1),
      ] {
      let active = @local_sga.start_mean_views(
        @bounded.control(),
        prepared_sequence(receiver),
        0,
        views,
        {
          ..subtraction_storage_limits(),
          max_work: work_limit,
          max_workspace_slots: slot_limit,
        },
        { ..mean_provider_policy().limits, max_exact_operations: exact_limit, },
        65536L,
        () => true,
      )
      if slot_limit < slots {
        assert_true(
          active is Err(@local_sga.MeanResources(@local_sga.MeanWorkspaceLimit)),
        )
        continue
      }
      let active = active.unwrap()
      for _ in 0..<100 {
        match @local_sga.advance_mean(active, quantum).unwrap() {
          @local_sga.MeanContinue(..) => ()
          @local_sga.MeanComplete(output, work=used, ..) => {
            assert_eq(
              (work_limit, slot_limit, exact_limit),
              (work, slots, exact_operations),
            )
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
          @local_sga.MeanFailed(
            @local_sga.MeanFoldFailure(@local_sga.MeanFoldWorkLimit),
            work=used,
            ..
          ) => {
            assert_eq(
              (work_limit, slot_limit, exact_limit),
              (work - 1, slots, exact_operations),
            )
            assert_eq(used, (work - 1).to_int64())
            break
          }
          @local_sga.MeanFailed(
            @local_sga.MeanFoldFailure(@local_sga.MeanExactWorkLimit),
            ..
          ) => {
            assert_eq(exact_limit, exact_operations - 1)
            break
          }
          _ => fail("empty mean failed for an unrelated reason")
        }
      } nobreak {
        fail("empty mean did not settle")
      }
      assert_true(@local_sga.cleanup_mean(active).unwrap())
      assert_false(@local_sga.mean_cleanup_pending(active))
      for read in reads {
        assert_true(@graphs.producer_read_available(read))
      }
    }
  }
  let foreign = @local_sga.start_mean_views(
    @bounded.control(),
    prepared_sequence(receiver),
    0,
    [views[1], views[0], views[2]],
    subtraction_storage_limits(),
    mean_provider_policy().limits,
    65536L,
    () => true,
  ).unwrap()
  assert_true(
    @local_sga.advance_mean(foreign, 1).unwrap()
    is @local_sga.MeanFailed(@local_sga.MeanInputBinding, work=1L, ..),
  )
  assert_true(@local_sga.cleanup_mean(foreign).unwrap())
  assert_true(@graphs.discard_completed(graph))
}
