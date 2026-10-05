///|
fn delta_view_bind(checked : @pipeline.CheckedPipeline) -> @lower.BoundPrepared {
  @lower.bind_parameters(
    @lower.prepare(checked, {
      max_nodes: 100,
      max_references: 100,
      max_work: 10000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn delta_view_check_limits() -> @pipeline.Limits {
  {
    max_steps: 10,
    max_work: 100000,
    max_text_bytes: 100000,
    max_nodes: 10000,
    max_tokens: 10000,
    max_depth: 100,
  }
}

///|
// Use the real Graph retention/read owner. An external input receipt does not
// claim that normal Program selection or Delta resource resolution is complete.
fn delta_fixture_view() -> (
  @lifecycle.ProducerView,
  @graph_runtime.Completed,
  Ref[Bool],
) raise {
  let graph = @graph_contract.graph(delta_fixture_contract())
  let owner = delta_view_bind(
    @pipeline.check_carriers(
      delta_cursor("[]"),
      [("g", @carrier.graph_carrier(graph))],
      None,
      Some(delta_cursor("\"g\"")),
      delta_view_check_limits(),
    ).unwrap(),
  )
  let output_live = Ref(true)
  let output = @graph_runtime.prepare_output(
    owner,
    @pipeline.Input(0),
    @storage.DeclaredNodes,
    storage_limits(),
    100000L,
    () => output_live.val,
  ).unwrap()
  @graph_runtime.append_property_node(output, 1, [delta_number(2.0)], [
    delta_score(None),
  ]).unwrap()
  @graph_runtime.append_property_node(output, 0, [delta_number(1.0)], []).unwrap()
  @graph_runtime.append_property_node(output, 1, [delta_number(1.0)], [
    delta_score(Some(7.0)),
  ]).unwrap()
  for key in [11.0, 10.0] {
    @graph_runtime.append_property_edge(
      output,
      0,
      [delta_number(key)],
      [delta_number(1.0)],
      [delta_number(2.0)],
      [],
    ).unwrap()
  }
  let completed = @graph_runtime.finish_output(output).unwrap()
  let receiver = delta_view_bind(
    @pipeline.check_with_evidence(
      delta_cursor("[]"),
      [
        (
          "g",
          @pipeline.ProducedInput(
            @pipeline.produced_input(
              @lower.pipeline(@lower.bound_preparation(owner)),
              @pipeline.Input(0),
            ).unwrap(),
          ),
        ),
      ],
      None,
      Some(delta_cursor("\"g\"")),
      delta_view_check_limits(),
    ).unwrap(),
  )
  let read = @graph_runtime.prepare_producer_read(receiver, 0, owner, completed).unwrap()
  (@graph_runtime.producer_read_view(read).unwrap(), completed, output_live)
}

///|
test "Delta apply borrows managed view without relabeling or copying input custody" {
  let (view, completed, _) = delta_fixture_view()
  let graph = @graph_contract.graph(delta_fixture_contract())
  let apply = prepare_apply_view(
    view,
    graph,
    delta_cursor(delta_fixture_expected()),
    delta_fixture_limits(),
    storage_limits(),
  ).unwrap()
  let result = complete_apply(apply, 1)
  assert_eq(delta_snapshot_wire(result), delta_expected_target_snapshot())
  assert_true(cleanup_apply(apply))
  let base = @graph_runtime.completed_storage(completed).unwrap()
  assert_eq(@storage.node_count(base), 3)
  assert_eq(@storage.edge_count(base), 2)
  assert_true(@lifecycle.producer_view_node_count(view) == Some(3))
  let foreign_contract = @graph_contract.read_cursor(
    delta_cursor(
      delta_fixture_schema().replace_all(
        old="sha256:" + "0".repeat(64),
        new="sha256:" + "1".repeat(64),
      ),
    ),
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, },
  ).unwrap()
  let foreign_graph = @graph_contract.graph(foreign_contract)
  let foreign_delta = delta_fixture_expected().replace_all(
    old=@graph_contract.cid(delta_fixture_contract()),
    new=@graph_contract.cid(foreign_contract),
  )
  assert_true(
    prepare_apply_view(
      view,
      foreign_graph,
      delta_cursor(foreign_delta),
      delta_fixture_limits(),
      storage_limits(),
    )
    is Err(Snapshot(@snapshot.InvalidGraph)),
  )
  assert_true(@lifecycle.producer_view_node_count(view) == Some(3))
  @storage.discard(result)
  assert_true(@graph_runtime.discard_completed(completed))
}

///|
test "Delta apply rejects revoked input after base capture and retains provisional cleanup" {
  for boundary in [ReadBaseBody, ApplyNodes, AppendRecord, TargetSnapshot] {
    let (view, completed, live) = delta_fixture_view()
    let apply = prepare_apply_view(
      view,
      @graph_contract.graph(delta_fixture_contract()),
      delta_cursor(delta_fixture_expected()),
      delta_fixture_limits(),
      storage_limits(),
    ).unwrap()
    let mut reached = false
    for _ in 0..<100000 {
      if apply.phase == boundary {
        reached = true
        break
      }
      assert_true(advance_apply(apply, 1) is Ok(ApplyContinue(..)))
    }
    assert_true(reached)
    live.val = false
    assert_true(
      advance_apply(apply, 1)
      is Ok(ApplyFailed(Snapshot(@snapshot.InvalidGraph), progress=0L, work=0L)),
    )
    assert_true(advance_apply(apply, 1) is Err(Terminal))
    assert_true(cleanup_apply(apply))
    assert_true(cleanup_apply(apply))
    assert_true(apply.builder is None)
    assert_true(apply.result is None)
    assert_true(apply.base_view is None)
    assert_true(
      prepare_apply_view(
        view,
        @graph_contract.graph(delta_fixture_contract()),
        delta_cursor(delta_fixture_expected()),
        delta_fixture_limits(),
        storage_limits(),
      )
      is Err(_),
    )
    assert_true(@graph_runtime.discard_completed(completed))
  }
}
