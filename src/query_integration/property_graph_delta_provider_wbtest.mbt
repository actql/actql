///|
fn delta_provider_fixture(
  snapshot? : Bool = false,
  delta_policy? : @local_sga_provider.DeltaPolicy? = Some({
    limits: graph_delta_input_limits(),
    workspace_bytes: 4000000L,
  }),
  work? : Int = 100000,
) -> @local_connector.ManagedProvider {
  @local_sga_provider.provider(
    { ..carrier_graph_storage_limits(), max_work: work, },
    4096L,
    @execution.execution_capacity(4096L, 65536L).unwrap(),
    delta_policy~,
    snapshot_policy=if snapshot {
      Some({
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
      })
    } else {
      None
    },
  )
}

///|
fn start_delta_provider(
  provider : @local_connector.ManagedProvider,
  generated : @execution.GeneratedSequence,
  inputs : Array[@local_connector.ManagedProviderInput],
  max_rows : Int,
  max_value_bytes : Int,
  work? : Int = 100000,
) -> Result[
  @local_connector.ManagedProviderExecution,
  @connector.FixedComputeIssue,
] {
  @local_connector.start_managed_provider_with_inputs_and_execution(
    provider,
    generated,
    inputs,
    max_rows,
    max_value_bytes,
    { ..dispatch_test_limits().local_execution, max_work: work, },
  )
}

///|
test "Delta provider applies exact mixed inputs then saves invalidates and reloads its Graph" {
  for removal in [false, true] {
    for selected in [false, true] {
      let (owner, view, rows, original, live) = graph_delta_input_fixture(
        text=if removal {
          graph_delta_remove_parallel_edge()
        } else {
          graph_delta_empty_actions()
        },
      )
      let generated = task_test_generated(owner)
      let generated = if selected {
        @execution.select_generated_sequence_step(generated, 0).unwrap()
      } else {
        generated
      }
      let provider = delta_provider_fixture(snapshot=true)
      assert_true(
        @local_connector.managed_provider_accepts(provider, generated),
      )
      let node = @lower.node_at(@lower.bound_preparation(owner), 0).unwrap()
      assert_true(@lower.node_supports_selected_managed_execution(node))
      assert_true(@lower.node_can_split_carrier_transform(node))
      assert_true(@lower.node_accepts_managed_carrier_view(node, 0))
      assert_false(@lower.node_accepts_managed_carrier_view(node, 1))
      assert_false(@lower.node_accepts_managed_relation_view(node, 0))
      assert_true(@lower.node_accepts_managed_relation_view(node, 1))
      let active = start_delta_provider(
        provider,
        generated,
        [
          @local_connector.managed_provider_carrier_input(view),
          @local_connector.managed_provider_relation_input(rows),
        ],
        10,
        10000,
      ).unwrap()
      let mut material = None
      let mut total = 0L
      for _ in 0..<100000 {
        let poll = @local_connector.advance_managed_provider(active, 7).unwrap()
        let work = match poll {
          @local_connector.Continue(work~, ..) => work
          @local_connector.CarrierComplete(output, work~, ..) => {
            material = Some(output)
            work
          }
          _ => abort("Delta provider failed before Graph completion")
        }
        assert_true(work > 0L && work <= 7L)
        total += work
        if material is Some(_) {
          break
        }
      }
      let material = material.unwrap()
      let (conversion, application) = graph_delta_separate_work(
        owner, view, rows,
      )
      assert_eq(total, conversion + application + 1L)
      assert_eq(
        @local_connector.managed_provider_cumulative_work(active),
        Ok(total),
      )
      assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
      assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
      assert_eq(
        @local_connector.managed_provider_cumulative_work(active),
        Ok(total),
      )
      assert_true(@graphs.completed_available(original))
      assert_true(@execution.producer_read_available(rows))
      live.val = false
      assert_true(@graphs.discard_completed(original))
      assert_true(@carrier_runtime.material_available(material))
      let snapshot = @carrier_runtime.material_prepare_snapshot(material)
        .unwrap()
        .unwrap()
      let saved = StringBuilder()
      let mut complete = false
      for _ in 0..<10000 {
        let poll = (snapshot.advance_save)(7).unwrap()
        saved.write_string((snapshot.take_output)().unwrap())
        if poll.complete {
          complete = true
          break
        }
      }
      assert_true(complete)
      let content = (snapshot.content)().unwrap()
      let expected_cid = if removal {
        "sha256:1371549624dd79d7a1121a061fde22c27ef85f8c0fd99f42a28d1fdb26e7ef01"
      } else {
        snapshot_fixture_cid()
      }
      assert_eq(content.cid, expected_cid)
      assert_eq(
        saved.to_string(),
        snapshot_fixture_body(keys=if removal { [10] } else { [10, 11] }),
      )
      let consumer = keyed_graph_receiver(owner, body="[{\"node_rows\":true}]")
      (snapshot.release_source)(content.cid).unwrap()
      assert_false(@carrier_runtime.material_available(material))
      assert_true(
        @carrier_runtime.material_prepare_view(material, consumer, 0, owner)
        is Err(_),
      )
      (snapshot.begin_reload)(saved.to_string(), () => true).unwrap()
      let mut reloaded = false
      for _ in 0..<10000 {
        if (snapshot.advance_reload)(7).unwrap().complete {
          reloaded = true
          break
        }
      }
      assert_true(reloaded)
      let restored = (snapshot.take_material)().unwrap()
      let view = @carrier_runtime.material_prepare_view(
        restored, consumer, 0, owner,
      ).unwrap()
      assert_eq(@carrier_runtime.producer_view_node_count(view), Some(1))
      assert_eq(
        @carrier_runtime.producer_view_edge_count(view),
        Some(if removal { 1 } else { 2 }),
      )
      assert_true(
        @carrier_runtime.producer_view_node_key(view, 0, 0).unwrap().value
        is @admitted.Number(1.0),
      )
      assert_true(
        @carrier_runtime.producer_view_node_property(view, 0, 0).unwrap().value
        is @admitted.Text("one"),
      )
      for edge in 0..<(if removal { 1 } else { 2 }) {
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
      let mut output = None
      for _ in 0..<10000 {
        match
          @local_connector.advance_managed_provider(projecting, 7).unwrap() {
          @local_connector.Continue(..) => ()
          @local_connector.Complete(value, ..) => {
            output = Some(value)
            break
          }
          _ =>
            abort(
              "restored Delta Graph did not reach the existing Relation owner",
            )
        }
      }
      let output = output.unwrap()
      assert_eq(@execution.completed_row_count(output), 1)
      let expected = "{\"id\":" +
        snapshot_fixture_identity("N", 1) +
        ",\"labels\":[\"Node\",\"Person\"],\"name\":\"one\"}"
      assert_eq(
        @execution.completed_output_row_wire(output, 0, 10000, 10000, 50).unwrap(),
        expected,
      )
      assert_true(
        @local_connector.cleanup_managed_provider(projecting).unwrap(),
      )
      assert_true((snapshot.cleanup)().unwrap())
      assert_true(@carrier_runtime.reclaim_material(restored))
      assert_eq(
        @execution.completed_output_row_wire(output, 0, 10000, 10000, 50).unwrap(),
        expected,
      )
    }
  }
}

///|
test "Delta provider requires installed limits exact roles and accounted workspace" {
  let (owner, view, rows, original, _) = graph_delta_input_fixture()
  let generated = @execution.select_generated_sequence_step(
    task_test_generated(owner),
    0,
  ).unwrap()
  let missing = delta_provider_fixture(delta_policy=None)
  let invalid = delta_provider_fixture(
    delta_policy=Some({
      limits: graph_delta_input_limits(),
      workspace_bytes: -1L,
    }),
  )
  let inputs = [
    @local_connector.managed_provider_carrier_input(view),
    @local_connector.managed_provider_relation_input(rows),
  ]
  for provider in [missing, invalid] {
    assert_false(@local_connector.managed_provider_accepts(provider, generated))
    assert_true(
      @local_connector.managed_provider_capacity(provider, generated) is None,
    )
    assert_true(
      start_delta_provider(provider, generated, inputs, 10, 10000) is Err(_),
    )
  }
  let memory = delta_provider_fixture()
  let carrier = @lower.preparation_carrier_at(
    @lower.bound_preparation(owner),
    @pipeline.Input(0),
  ).unwrap()
  let difference = @pipeline.check_carriers(
    input_cursor("[{\"from\":\"base\",\"graph_diff\":{\"with\":\"target\"}}]"),
    [("base", carrier), ("target", carrier)],
    None,
    None,
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
  let difference = @lower.bind_parameters(
    @lower.prepare(difference, {
      max_nodes: 1000,
      max_references: 1000,
      max_work: 100000,
      max_identifier_bytes: 100000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let difference = @execution.select_generated_sequence_step(
    task_test_generated(difference),
    0,
  ).unwrap()
  // Graph Diff is installed too, but its second input must be a Graph, not
  // the Relation action rows used by Delta. Capability is not input admission.
  assert_true(@local_connector.managed_provider_accepts(memory, difference))
  assert_true(
    @local_connector.managed_provider_capacity(memory, difference) is Some(_),
  )
  assert_true(
    start_delta_provider(memory, difference, inputs, 10, 10000) is Err(_),
  )
  let persistent = delta_provider_fixture(snapshot=true)
  let memory_capacity = @local_connector.managed_provider_capacity(
    memory, generated,
  ).unwrap()
  let persistent_capacity = @local_connector.managed_provider_capacity(
    persistent, generated,
  ).unwrap()
  assert_eq(
    @execution.execution_capacity_retained_bytes(memory_capacity),
    4096L,
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(memory_capacity),
    65536L + 4096L + 4000000L,
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(persistent_capacity),
    @execution.execution_capacity_execution_bytes(memory_capacity) + 1000000L,
  )
  let overflow = delta_provider_fixture(
    snapshot=true,
    delta_policy=Some({
      limits: graph_delta_input_limits(),
      workspace_bytes: 9223372036854775807L,
    }),
  )
  assert_true(
    @local_connector.managed_provider_capacity(overflow, generated) is None,
  )
  assert_true(
    start_delta_provider(overflow, generated, inputs, 10, 10000) is Err(_),
  )
  let (_, foreign_view, foreign_rows, foreign, _) = graph_delta_input_fixture()
  for
    inputs in [
      [],
      [@local_connector.managed_provider_carrier_input(view)],
      [@local_connector.managed_provider_relation_input(rows)],
      [
        @local_connector.managed_provider_carrier_input(foreign_view),
        @local_connector.managed_provider_relation_input(rows),
      ],
      [
        @local_connector.managed_provider_carrier_input(view),
        @local_connector.managed_provider_relation_input(foreign_rows),
      ],
    ] {
    assert_true(
      start_delta_provider(memory, generated, inputs, 10, 10000) is Err(_),
    )
  }
  let (owner, view, rows, extra, _) = graph_delta_input_fixture(count=2)
  assert_true(
    start_delta_provider(
      memory,
      @execution.select_generated_sequence_step(task_test_generated(owner), 0).unwrap(),
      [
        @local_connector.managed_provider_carrier_input(view),
        @local_connector.managed_provider_relation_input(rows),
      ],
      10,
      10000,
    )
    is Err(_),
  )
  for graph in [original, foreign, extra] {
    assert_true(@graphs.discard_completed(graph))
  }
}

///|
test "Delta provider admits exact combined workspace and rejects one short before work" {
  let (owner, view, rows, original, _) = graph_delta_input_fixture()
  // Independent arithmetic for the authored one-node/two-edge fixture and
  // declared limits, not a value returned by a product workspace helper:
  // snapshot indexes 1*5 + 2*7; base body 1000*16 + 100*8 + 64;
  // provisional Storage 1000; before record 1000*8 + 100*4 + 32;
  // staged output (one key and one property) 100*32 + 10*8 + 100*4*2 + 2*2 + 160;
  // action identity 1000*8 + 100*4 + 64;
  // simultaneous Relation conversion 1000*32 + 100*8 + 128.
  // This tests logical admission, not a physical-byte or total-heap theorem.
  let exact = 19 + 16864 + 1000 + 8432 + 4244 + 8464 + 32928
  assert_eq(exact, 71951)
  for selected in [false, true] {
    let generated = task_test_generated(owner)
    let generated = if selected {
      @execution.select_generated_sequence_step(generated, 0).unwrap()
    } else {
      generated
    }
    let inputs = [
      @local_connector.managed_provider_carrier_input(view),
      @local_connector.managed_provider_relation_input(rows),
    ]
    let one_short = delta_provider_fixture(
      delta_policy=Some({
        limits: {
          ..graph_delta_input_limits(),
          max_workspace_slots: exact - 1,
        },
        workspace_bytes: 4000000L,
      }),
    )
    assert_true(
      start_delta_provider(one_short, generated, inputs, 10, 10000) is Err(_),
    )
    assert_true(@graphs.completed_available(original))
    assert_true(@execution.producer_read_available(rows))
    assert_eq(
      snapshot_capture(@graphs.completed_storage(original).unwrap()),
      (snapshot_fixture_cid(), snapshot_fixture_body()),
    )
    let provider = delta_provider_fixture(
      delta_policy=Some({
        limits: { ..graph_delta_input_limits(), max_workspace_slots: exact, },
        workspace_bytes: 4000000L,
      }),
    )
    let active = start_delta_provider(provider, generated, inputs, 10, 10000).unwrap()
    let mut completed = None
    let mut work = 0L
    for _ in 0..<10000 {
      match @local_connector.advance_managed_provider(active, 1).unwrap() {
        @local_connector.Continue(work=used, ..) => {
          assert_eq(used, 1L)
          work += used
        }
        @local_connector.CarrierComplete(material, work=used, ..) => {
          work += used
          completed = Some(material)
          break
        }
        _ =>
          abort("exact Delta workspace failed or published a different family")
      }
    }
    assert_true(work > 0L)
    assert_eq(
      @local_connector.managed_provider_cumulative_work(active),
      Ok(work),
    )
    assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
    assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
    assert_eq(
      @local_connector.managed_provider_cumulative_work(active),
      Ok(work),
    )
    assert_true(@graphs.completed_available(original))
    assert_true(@execution.producer_read_available(rows))
    guard completed is Some(material) else {
      fail("missing completed Delta Graph")
    }
    assert_true(@carrier_runtime.material_available(material))
    assert_true(@carrier_runtime.reclaim_material(material))
  }
  assert_true(@graphs.discard_completed(original))
}

///|
test "Delta provider preserves failure work and cleanup without reclaiming borrowed inputs" {
  for cause in ["cancel", "loss", "budget", "outer_budget", "envelope"] {
    let (owner, view, rows, original, live) = graph_delta_input_fixture(
      text=if cause == "envelope" { "{}" } else { graph_delta_empty_actions() },
    )
    let generated = @execution.select_generated_sequence_step(
      task_test_generated(owner),
      0,
    ).unwrap()
    let provider = delta_provider_fixture(
      work=if cause == "budget" { 1 } else { 100000 },
    )
    let active = start_delta_provider(
      provider,
      generated,
      [
        @local_connector.managed_provider_carrier_input(view),
        @local_connector.managed_provider_relation_input(rows),
      ],
      10,
      10000,
      work=if cause == "outer_budget" { 1 } else { 100000 },
    ).unwrap()
    let before = if cause == "cancel" || cause == "loss" { 20 } else { 1 }
    for _ in 0..<before {
      assert_true(
        @local_connector.advance_managed_provider(active, 1)
        is Ok(@local_connector.Continue(work=1L, ..)),
      )
    }
    if cause == "cancel" {
      assert_true(@local_connector.cancel_managed_provider(active))
    }
    if cause == "loss" {
      live.val = false
    }
    let mut total = before.to_int64()
    let mut ended = false
    for _ in 0..<10000 {
      match @local_connector.advance_managed_provider(active, 1).unwrap() {
        @local_connector.Continue(work~, ..) => {
          assert_eq(work, 1L)
          total += work
        }
        @local_connector.Stopped(work~, ..) if cause == "cancel" => {
          assert_eq(work, 0L)
          ended = true
          break
        }
        @local_connector.Failed(_, work~, ..) if cause != "cancel" => {
          assert_true(work >= 0L && work <= 1L)
          total += work
          ended = true
          break
        }
        _ => abort("failed Delta provider published or restarted execution")
      }
    }
    assert_true(ended)
    assert_true(@local_connector.managed_provider_stopped(active))
    assert_eq(
      @local_connector.managed_provider_cumulative_work(active),
      Ok(total),
    )
    if cause != "envelope" {
      assert_eq(total, before.to_int64())
    }
    assert_true(@local_connector.advance_managed_provider(active, 1) is Err(_))
    assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
    assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
    assert_eq(
      @local_connector.managed_provider_cumulative_work(active),
      Ok(total),
    )
    assert_true(@graphs.completed_available(original))
    assert_eq(@execution.producer_read_available(rows), cause != "loss")
    assert_eq(
      snapshot_capture(@graphs.completed_storage(original).unwrap()),
      (snapshot_fixture_cid(), snapshot_fixture_body()),
    )
    assert_true(@graphs.discard_completed(original))
  }
}

///|
test "Delta provider exact work one short and handoff cancellation preserve both input owners" {
  let (owner, view, rows, original, _) = graph_delta_input_fixture(
    text=graph_delta_remove_parallel_edge(),
  )
  let generated = @execution.select_generated_sequence_step(
    task_test_generated(owner),
    0,
  ).unwrap()
  let (conversion, application) = graph_delta_separate_work(owner, view, rows)
  let exact = conversion + application + 1L
  // This compares the same documented work units across the standalone and
  // managed entrypoints; it is not a derived count law or a total-memory proof.
  for cause in ["exact", "one_short", "cancel"] {
    let ceiling = if cause == "one_short" { exact - 1L } else { exact }
    let active = start_delta_provider(
      delta_provider_fixture(),
      generated,
      [
        @local_connector.managed_provider_carrier_input(view),
        @local_connector.managed_provider_relation_input(rows),
      ],
      10,
      10000,
      work=ceiling.to_int(),
    ).unwrap()
    let mut total = 0L
    let mut completed = None
    let mut terminal = false
    for _ in 0..<100000 {
      if cause == "cancel" && total == conversion + 1L {
        assert_true(@local_connector.cancel_managed_provider(active))
      }
      match @local_connector.advance_managed_provider(active, 1).unwrap() {
        @local_connector.Continue(work~, ..) => {
          assert_eq(work, 1L)
          total += work
          assert_true(total <= ceiling)
        }
        @local_connector.CarrierComplete(output, work~, ..) if cause == "exact" => {
          total += work
          completed = Some(output)
          terminal = true
          break
        }
        @local_connector.Failed(_, work~, ..) if cause == "one_short" => {
          assert_eq(work, 0L)
          terminal = true
          break
        }
        @local_connector.Stopped(work~, ..) if cause == "cancel" => {
          assert_eq(work, 0L)
          terminal = true
          break
        }
        _ =>
          abort("Delta managed boundary changed outcome or restarted Compute")
      }
    }
    assert_true(terminal)
    assert_eq(total, if cause == "cancel" { conversion + 1L } else { ceiling })
    assert_eq(
      @local_connector.managed_provider_cumulative_work(active),
      Ok(total),
    )
    assert_true(@local_connector.advance_managed_provider(active, 1) is Err(_))
    assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
    assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
    assert_eq(
      @local_connector.managed_provider_cumulative_work(active),
      Ok(total),
    )
    assert_true(@graphs.completed_available(original))
    assert_true(@execution.producer_read_available(rows))
    assert_eq(
      snapshot_capture(@graphs.completed_storage(original).unwrap()),
      (snapshot_fixture_cid(), snapshot_fixture_body()),
    )
    if completed is Some(material) {
      assert_true(@carrier_runtime.material_available(material))
      assert_true(@carrier_runtime.reclaim_material(material))
    }
  }
  assert_true(@graphs.discard_completed(original))
}
