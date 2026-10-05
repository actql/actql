///|
fn delta_apply_session_fixture() -> (
  @bounded.Control,
  ApplyPreparation,
  @graph_runtime.OutputBuilder,
  @graph_runtime.Completed,
) raise {
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
  let apply = start_apply_view(
    view,
    graph,
    delta_cursor(delta_fixture_expected()),
    delta_fixture_limits(),
    storage_limits(),
    output_builder=@graph_runtime.output_storage_builder(output),
  ).unwrap()
  (@bounded.control(), apply, output, input)
}

///|
test "Delta apply session preserves actual quantum accounting and formal output custody" {
  for quantum in [1, 7, 64] {
    let (control, apply, output, input) = delta_apply_session_fixture()
    let active = @sga.start_prepared_delta_apply(control, apply, output, () => {
      true
    }).unwrap()
    let mut work = 0L
    let mut result = None
    for _ in 0..<100000 {
      let poll = @sga.advance_delta_apply(active, quantum).unwrap()
      let used = match poll {
        @sga.DeltaApplyContinue(work~, ..) => work
        @sga.DeltaApplyComplete(completed, work~, ..) => {
          result = Some(completed)
          work
        }
        _ => fail("prepared Delta execution failed")
      }
      assert_true(used >= work && used - work <= quantum.to_int64())
      work = used
      if result is Some(_) {
        break
      }
    }
    let completed = result.unwrap()
    assert_eq(
      delta_snapshot_wire(@graph_runtime.completed_storage(completed).unwrap()),
      delta_expected_target_snapshot(),
    )
    assert_true(@sga.cleanup_delta_apply(active).unwrap())
    assert_false(@sga.delta_apply_cleanup_pending(active))
    assert_true(@graph_runtime.completed_available(input))
    assert_true(@graph_runtime.completed_available(completed))
    assert_true(@graph_runtime.discard_completed(completed))
    assert_true(@graph_runtime.discard_completed(input))
  }
}

///|
test "Delta session cancellation before and after kernel transfer retains cleanup" {
  for after_transfer in [false, true] {
    let (control, apply, output, input) = delta_apply_session_fixture()
    let builder = @graph_runtime.output_storage_builder(output).unwrap()
    let active = @sga.start_prepared_delta_apply(control, apply, output, () => {
      true
    }).unwrap()
    let mut work = 0L
    let mut reached = false
    for i in 0..<100000 {
      guard @sga.advance_delta_apply(active, 1)
        is Ok(@sga.DeltaApplyContinue(work=used, ..)) else {
        fail("early completion")
      }
      work = used
      if (after_transfer && apply.phase == ApplyFinished) ||
        (!after_transfer && i == 10) {
        reached = true
        break
      }
    }
    assert_true(reached)
    assert_true(@bounded.request_cancel(control))
    assert_true(
      @sga.advance_delta_apply(active, 1)
      is Ok(@sga.DeltaApplyStopped(@bounded.Cancelled, work=stopped, ..)) &&
      stopped == work,
    )
    assert_true(@sga.delta_apply_cleanup_pending(active))
    assert_true(@sga.cleanup_delta_apply(active).unwrap())
    assert_false(@sga.cleanup_delta_apply(active).unwrap())
    assert_false(@sga.delta_apply_cleanup_pending(active))
    assert_eq(@storage.builder_node_count(builder), 0)
    assert_eq(@storage.builder_edge_count(builder), 0)
    assert_true(@graph_runtime.completed_available(input))
    assert_true(@graph_runtime.discard_completed(input))
  }
}

///|
test "Delta session budget and lost input fail without returning to Compute" {
  for lost_input in [false, true] {
    let (control, apply, output, input) = delta_apply_session_fixture()
    let live = Ref(true)
    let active = @sga.start_prepared_delta_apply(
      control,
      apply,
      output,
      () => live.val,
      control_work_limit=if lost_input { None } else { Some(3) },
    ).unwrap()
    let mut work = 0L
    let mut failed = false
    for _ in 0..<100000 {
      match @sga.advance_delta_apply(active, 1).unwrap() {
        @sga.DeltaApplyContinue(work=used, ..) => {
          work = used
          if lost_input && apply.phase == ApplyFinished {
            live.val = false
          }
        }
        @sga.DeltaApplyFailed(issue, work=used, ..) => {
          assert_eq(used, work)
          assert_eq(
            issue,
            if lost_input {
              @sga.DeltaApplyInputUnavailable
            } else {
              @sga.DeltaApplyControlWorkLimit
            },
          )
          failed = true
          break
        }
        _ => fail("failed Delta published an output")
      }
    }
    assert_true(failed)
    if !lost_input {
      assert_eq(work, 3L)
    }
    assert_true(@sga.advance_delta_apply(active, 1) is Err(_))
    assert_true(@sga.delta_apply_cleanup_pending(active))
    assert_true(@sga.cleanup_delta_apply(active).unwrap())
    assert_true(@graph_runtime.output_storage_builder(output) is None)
    assert_true(@graph_runtime.completed_available(input))
    assert_true(@graph_runtime.discard_completed(input))
  }
}

///|
test "Delta session start refuses a foreign output without taking either custody" {
  let (control, apply, output, input) = delta_apply_session_fixture()
  let graph = @graph_contract.graph(delta_fixture_contract())
  let foreign = @graph_runtime.prepare_output(
    delta_apply_owner(graph),
    @pipeline.Step(0),
    DeclaredNodes,
    storage_limits(),
    100000L,
    () => true,
  ).unwrap()
  assert_true(
    @sga.start_prepared_delta_apply(control, apply, foreign, () => true)
    is Err(@sga.InvalidDeltaApplyKernel),
  )
  assert_true(@graph_runtime.output_storage_builder(foreign) is Some(_))
  assert_true(@graph_runtime.output_storage_builder(output) is Some(_))
  assert_true(apply.phase == AdmitNodeActions)
  assert_true(cleanup_apply(apply))
  assert_true(@graph_runtime.cancel_output(output))
  assert_true(@graph_runtime.cancel_output(foreign))
  assert_true(@graph_runtime.discard_completed(input))
}

///|
test "Delta cancellation raised by current input check starts no kernel work" {
  let (control, apply, output, input) = delta_apply_session_fixture()
  let active = @sga.start_prepared_delta_apply(control, apply, output, () => {
    @bounded.request_cancel(control) |> ignore
    true
  }).unwrap()
  assert_true(
    @sga.advance_delta_apply(active, 64)
    is Ok(@sga.DeltaApplyStopped(@bounded.Cancelled, progress=0L, work=0L)),
  )
  assert_true(apply.phase == AdmitNodeActions)
  assert_true(@sga.cleanup_delta_apply(active).unwrap())
  assert_true(@graph_runtime.completed_available(input))
  assert_true(@graph_runtime.discard_completed(input))
}

///|
test "Delta cancellation during retention holds the unaccepted completed result" {
  let (view, input, _) = delta_fixture_view()
  let graph = @graph_contract.graph(delta_fixture_contract())
  let owner = delta_apply_owner(graph)
  let control = @bounded.control()
  let output = @graph_runtime.prepare_output(
    owner,
    @pipeline.Step(0),
    DeclaredNodes,
    storage_limits(),
    100000L,
    () => {
      @bounded.request_cancel(control) |> ignore
      true
    },
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
  let active = @sga.start_prepared_delta_apply(control, apply, output, () => {
    true
  }).unwrap()
  let mut stopped = false
  for _ in 0..<100000 {
    match @sga.advance_delta_apply(active, 1).unwrap() {
      @sga.DeltaApplyContinue(..) => ()
      @sga.DeltaApplyStopped(@bounded.Cancelled, work~, ..) => {
        assert_true(work > 0L)
        stopped = true
        break
      }
      _ => fail("cancelled Delta published a completed output")
    }
  }
  assert_true(stopped)
  assert_eq(@storage.builder_node_count(builder), 3)
  assert_eq(@storage.builder_edge_count(builder), 2)
  assert_true(@sga.delta_apply_cleanup_pending(active))
  assert_true(@sga.cleanup_delta_apply(active).unwrap())
  assert_eq(@storage.builder_node_count(builder), 0)
  assert_eq(@storage.builder_edge_count(builder), 0)
  assert_false(@sga.cleanup_delta_apply(active).unwrap())
  assert_true(@graph_runtime.completed_available(input))
  assert_true(@graph_runtime.discard_completed(input))
}
