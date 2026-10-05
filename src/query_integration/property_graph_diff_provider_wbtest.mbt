///|
fn graph_diff_provider_fixture(
  removal? : Bool = false,
  empty? : Bool = false,
) -> (
  @lower.BoundPrepared,
  @carrier_runtime.ProducerView,
  @carrier_runtime.ProducerView,
  @graphs.Completed,
  @graphs.Completed,
) {
  let graph_owner = snapshot_fixture_owner()
  let graph = if empty {
    if removal {
      abort("empty and edge-removal fixtures are mutually exclusive")
    }
    // Independently authored empty snapshot, with the same declared schema.
    // Its CID was calculated from these bytes using Node crypto, not snapshot.
    let body = "[\"actql-property-graph-snapshot/0.1\",\"sha256:6a0fe1664c431e3b0835ccaf2fff3569e99492ae427eab4ccb65d34096ce604d\"," +
      snapshot_fixture_schema() +
      ",[],[]]"
    let active = snapshot_start(
      graph_owner,
      body,
      expected="sha256:b432ac9e6035853bc1e8a7cfcdadd4a98f04f5aeefa279f4287204f33e9f0fec",
    ).unwrap()
    guard snapshot_terminal(active) is @local_bridge.Complete(output, ..) else {
      abort("independent empty snapshot fixture")
    }
    @local_bridge.cleanup_rows_to_graph(active).unwrap() |> ignore
    output
  } else {
    snapshot_handoff_source(graph_owner)
  }
  let target = if removal {
    let active = snapshot_start(
      graph_owner,
      snapshot_fixture_body(keys=[10]),
      expected="sha256:1371549624dd79d7a1121a061fde22c27ef85f8c0fd99f42a28d1fdb26e7ef01",
    ).unwrap()
    guard snapshot_terminal(active) is @local_bridge.Complete(output, ..) else {
      abort("independent target snapshot fixture")
    }
    @local_bridge.cleanup_rows_to_graph(active).unwrap() |> ignore
    output
  } else {
    graph
  }
  let produced = @pipeline.ProducedInput(
    @pipeline.produced_input(
      @lower.pipeline(@lower.bound_preparation(graph_owner)),
      @pipeline.Input(0),
    ).unwrap(),
  )
  let checked = @pipeline.check_with_evidence(
    input_cursor("[{\"from\":\"base\",\"graph_diff\":{\"with\":\"target\"}}]"),
    [("base", produced), ("target", produced)],
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
  let owner = @lower.bind_parameters(
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
  let left = @graphs.producer_read_view(
    @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap(),
  ).unwrap()
  let right = @graphs.producer_read_view(
    @graphs.prepare_producer_read(owner, 1, graph_owner, target).unwrap(),
  ).unwrap()
  (owner, left, right, graph, target)
}

///|
test "Graph diff provider matches independent kernel row admission and completion work" {
  let (owner, left, right, graph, _) = graph_diff_provider_fixture(empty=true)
  // These constants count the independently authored empty fixture, never a
  // baseline execution. See the companion work-breakdown review for the tree
  // inventory and each existing owner's continuation charges.
  let snapshot = 2L
  let body_start = 3L
  // The ASCII wire has 824 scalars: 824 preflight steps plus its end check,
  // followed by 86 grammar transitions. Preflight is not free preparation.
  let parse = 824L + 1L + 86L
  let decode = 103L
  let json_admission = 355L
  let assemble = 1L
  let delta_recheck = 35L
  let kernel = 2L * (snapshot + body_start + parse + decode + json_admission) +
    assemble +
    delta_recheck
  let row_start = 1L
  // Begin/read=2; Delta recheck=35; name=1; value measurement=31;
  // commit/end-of-input/seal=3. Completion authority is separate from import.
  let row_admission = 2L + 35L + 1L + 31L + 3L
  let completion = 1L
  let total = kernel + row_start + row_admission + completion
  assert_eq((kernel, row_admission, total), (2784L, 72L, 2858L))
  for selected in [false, true] {
    let generated = task_test_generated(owner)
    let generated = if selected {
      @execution.select_generated_sequence_step(generated, 0).unwrap()
    } else {
      generated
    }
    for
      (ceiling, quantum) in [
        (kernel, 1),
        (kernel + row_start, 1),
        (total - completion, 1),
        (total, 1),
        (total, 64),
      ] {
      let active = start_delta_provider(
        delta_provider_fixture(),
        generated,
        [
          @local_connector.managed_provider_carrier_input(left),
          @local_connector.managed_provider_carrier_input(right),
        ],
        1,
        10000,
        work=ceiling.to_int(),
      ).unwrap()
      let mut used = 0L
      let mut terminal = false
      for _ in 0..<3000 {
        match
          @local_connector.advance_managed_provider(active, quantum).unwrap() {
          @local_connector.Continue(work~, ..) => used += work
          @local_connector.Complete(output, work~, ..) => {
            used += work
            assert_eq(ceiling, total)
            assert_eq(used, total)
            assert_eq(@execution.completed_row_count(output), 1)
            let expected = "{\"delta\":" +
              graph_delta_empty_actions()
              .replace(
                old=snapshot_fixture_cid(),
                new="sha256:b432ac9e6035853bc1e8a7cfcdadd4a98f04f5aeefa279f4287204f33e9f0fec",
              )
              .replace(
                old=snapshot_fixture_cid(),
                new="sha256:b432ac9e6035853bc1e8a7cfcdadd4a98f04f5aeefa279f4287204f33e9f0fec",
              ) +
              "}"
            let expected = @identity.stringify_value(
              @identity.from_json(@json.parse(expected), 10000, 100, 10000),
              10000,
              10000,
              100,
            )
            assert_eq(
              @execution.completed_output_row_wire(output, 0, 10000, 10000, 100).unwrap(),
              expected,
            )
            terminal = true
            break
          }
          @local_connector.Failed(_, work~, ..) => {
            used += work
            assert_true(ceiling < total)
            terminal = true
            break
          }
          _ => abort("unexpected independent Graph diff work terminal")
        }
      }
      assert_true(terminal)
      assert_eq(used, ceiling)
      assert_eq(
        @local_connector.managed_provider_cumulative_work(active),
        Ok(ceiling),
      )
      assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
      assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
      assert_eq(
        @local_connector.managed_provider_cumulative_work(active),
        Ok(ceiling),
      )
      assert_true(@graphs.completed_available(graph))
    }
  }
  assert_true(@graphs.discard_completed(graph))
}

///|
test "Graph diff provider completes one Delta row without reclaiming borrowed Graphs" {
  for selected in [false, true] {
    for removal in [false, true] {
      let (owner, left, right, graph, target) = graph_diff_provider_fixture(
        removal~,
      )
      let generated = task_test_generated(owner)
      let generated = if selected {
        @execution.select_generated_sequence_step(generated, 0).unwrap()
      } else {
        generated
      }
      let provider = delta_provider_fixture()
      assert_true(
        @local_connector.managed_provider_accepts(provider, generated),
      )
      let active = start_delta_provider(
        provider,
        generated,
        [
          @local_connector.managed_provider_carrier_input(left),
          @local_connector.managed_provider_carrier_input(right),
        ],
        1,
        10000,
      ).unwrap()
      let mut output = None
      let mut total = 0L
      for _ in 0..<100000 {
        let poll = @local_connector.advance_managed_provider(active, 1).unwrap()
        let work = match poll {
          @local_connector.Continue(work~, ..) => work
          @local_connector.Complete(result, work~, ..) => {
            output = Some(result)
            work
          }
          _ => abort("Graph diff failed before Delta row completion")
        }
        assert_true(work > 0L && work <= 1L)
        total += work
        if output is Some(_) {
          break
        }
      }
      let output = output.unwrap()
      let expected = "{\"delta\":" +
        (if removal {
          graph_delta_remove_parallel_edge()
        } else {
          graph_delta_empty_actions()
        }) +
        "}"
      let expected = @identity.stringify_value(
        @identity.from_json(@json.parse(expected), 10000, 100, 10000),
        10000,
        10000,
        100,
      )
      assert_eq(
        @execution.completed_output_row_wire(output, 0, 10000, 10000, 100).unwrap(),
        expected,
      )
      assert_eq(@execution.completed_row_count(output), 1)
      assert_eq(
        @local_connector.managed_provider_cumulative_work(active),
        Ok(total),
      )
      assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
      assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
      assert_eq(
        @execution.completed_output_row_wire(output, 0, 10000, 10000, 100).unwrap(),
        expected,
      )
      assert_true(@graphs.completed_available(graph))
      assert_true(@graphs.completed_available(target))
      assert_true(@graphs.discard_completed(graph))
      if removal {
        assert_true(@graphs.discard_completed(target))
      }
      assert_eq(
        @execution.completed_output_row_wire(output, 0, 10000, 10000, 100).unwrap(),
        expected,
      )
    }
  }
}

///|
test "Graph diff provider requires policy exact ordered views and retains cleanup on work failure" {
  let (owner, left, right, graph, _) = graph_diff_provider_fixture()
  let generated = task_test_generated(owner)
  assert_false(
    @local_connector.managed_provider_accepts(
      delta_provider_fixture(delta_policy=None),
      generated,
    ),
  )
  let provider = delta_provider_fixture()
  assert_true(
    start_delta_provider(
      provider,
      generated,
      [
        @local_connector.managed_provider_carrier_input(right),
        @local_connector.managed_provider_carrier_input(left),
      ],
      1,
      10000,
    )
    is Err(_),
  )
  let active = start_delta_provider(
    provider,
    generated,
    [
      @local_connector.managed_provider_carrier_input(left),
      @local_connector.managed_provider_carrier_input(right),
    ],
    1,
    10000,
    work=1,
  ).unwrap()
  assert_true(
    @local_connector.advance_managed_provider(active, 1).unwrap()
    is @local_connector.Continue(..),
  )
  assert_true(
    @local_connector.advance_managed_provider(active, 1).unwrap()
    is @local_connector.Failed(_, ..),
  )
  assert_eq(@local_connector.managed_provider_cumulative_work(active), Ok(1L))
  assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
  assert_true(@graphs.completed_available(graph))
  assert_true(@graphs.discard_completed(graph))
}

///|
test "Graph diff provider cancellation preserves work and borrowed input custody across import" {
  // First measure the same deterministic operation's complete control work.
  // This is a budget boundary, not an expected content/identity oracle.
  let (owner, left, right, graph, _) = graph_diff_provider_fixture()
  let provider = delta_provider_fixture()
  let generated = task_test_generated(owner)
  let inputs = [
    @local_connector.managed_provider_carrier_input(left),
    @local_connector.managed_provider_carrier_input(right),
  ]
  let baseline = start_delta_provider(provider, generated, inputs, 1, 10000).unwrap()
  let mut total = 0L
  let mut complete = false
  for _ in 0..<100000 {
    match @local_connector.advance_managed_provider(baseline, 1).unwrap() {
      @local_connector.Continue(work~, ..) => total += work
      @local_connector.Complete(_, work~, ..) => {
        total += work
        complete = true
        break
      }
      _ => fail("Diff work baseline failed")
    }
  }
  assert_true(complete && total > 3L)
  assert_true(@local_connector.cleanup_managed_provider(baseline).unwrap())
  for ceiling in [1L, total / 2L, total - 1L] {
    for cancel in [false, true] {
      let active = start_delta_provider(
        provider,
        generated,
        inputs,
        1,
        10000,
        work=if cancel { total.to_int() } else { ceiling.to_int() },
      ).unwrap()
      let mut observed = 0L
      for _ in 0..<ceiling.to_int() {
        guard @local_connector.advance_managed_provider(active, 1).unwrap()
          is @local_connector.Continue(work~, ..) else {
          fail("Diff stopped before its exact boundary")
        }
        observed += work
      }
      assert_eq(observed, ceiling)
      if cancel {
        assert_true(@local_connector.cancel_managed_provider(active))
      }
      let terminal = @local_connector.advance_managed_provider(active, 1).unwrap()
      if cancel {
        assert_true(terminal is @local_connector.Stopped(..))
      } else {
        assert_true(terminal is @local_connector.Failed(_, ..))
      }
      assert_eq(
        @local_connector.managed_provider_cumulative_work(active),
        Ok(ceiling),
      )
      assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
      assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
      assert_eq(
        @local_connector.managed_provider_cumulative_work(active),
        Ok(ceiling),
      )
      assert_true(@graphs.completed_available(graph))
    }
  }
  assert_true(@graphs.discard_completed(graph))
}

///|
test "Graph diff provider admits exact workspace and control work and rejects one short" {
  let (owner, left, right, graph, target) = graph_diff_provider_fixture(
    removal=true,
  )
  // Independent admission arithmetic for the authored one-node/two-edge base
  // and one-node/one-edge target. Snapshot indexes: 19 + 12; decode workspace:
  // 1000*16 + 100*8 + 64; action indexes: (3+2)*3; recheck frames: (100+1)*2;
  // fixed framing slots: 32. This is logical workspace, not total heap bytes.
  let exact = 31 + 16864 + 15 + 202 + 32
  assert_eq(exact, 17144)
  for selected in [false, true] {
    let generated = task_test_generated(owner)
    let generated = if selected {
      @execution.select_generated_sequence_step(generated, 0).unwrap()
    } else {
      generated
    }
    let inputs = [
      @local_connector.managed_provider_carrier_input(left),
      @local_connector.managed_provider_carrier_input(right),
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
      start_delta_provider(one_short, generated, inputs, 1, 10000) is Err(_),
    )
    assert_true(@graphs.completed_available(graph))
    assert_true(@graphs.completed_available(target))
    let provider = delta_provider_fixture(
      delta_policy=Some({
        limits: { ..graph_delta_input_limits(), max_workspace_slots: exact, },
        workspace_bytes: 4000000L,
      }),
    )
    let baseline = start_delta_provider(provider, generated, inputs, 1, 10000).unwrap()
    let mut total = 0L
    let mut completed = false
    for _ in 0..<100000 {
      match @local_connector.advance_managed_provider(baseline, 1).unwrap() {
        @local_connector.Continue(work~, ..) => total += work
        @local_connector.Complete(output, work~, ..) => {
          total += work
          assert_eq(@execution.completed_row_count(output), 1)
          completed = true
          break
        }
        _ => abort("exact Graph diff workspace failed")
      }
    }
    assert_true(completed && total > 1L)
    assert_true(@local_connector.cleanup_managed_provider(baseline).unwrap())
    for short in [false, true] {
      let ceiling = if short { total - 1L } else { total }
      let active = start_delta_provider(
        provider,
        generated,
        inputs,
        1,
        10000,
        work=ceiling.to_int(),
      ).unwrap()
      let mut used = 0L
      let mut finished = false
      for _ in 0..<100000 {
        match @local_connector.advance_managed_provider(active, 1).unwrap() {
          @local_connector.Continue(work~, ..) => used += work
          @local_connector.Complete(output, work~, ..) => {
            assert_false(short)
            assert_eq(@execution.completed_row_count(output), 1)
            used += work
            finished = true
            break
          }
          @local_connector.Failed(_, work~, ..) => {
            assert_true(short)
            used += work
            finished = true
            break
          }
          _ => abort("unexpected exact Graph diff work terminal")
        }
      }
      assert_true(finished)
      assert_eq(used, ceiling)
      assert_eq(
        @local_connector.managed_provider_cumulative_work(active),
        Ok(ceiling),
      )
      assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
      assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
      assert_eq(
        @local_connector.managed_provider_cumulative_work(active),
        Ok(ceiling),
      )
      assert_true(@graphs.completed_available(graph))
      assert_true(@graphs.completed_available(target))
    }
  }
  assert_true(@graphs.discard_completed(graph))
  assert_true(@graphs.discard_completed(target))
}

///|
test "Graph diff provider refuses Delta row and value capacity without publishing or reclaiming inputs" {
  let (owner, left, right, graph, target) = graph_diff_provider_fixture(
    removal=true,
  )
  let provider = delta_provider_fixture()
  let inputs = [
    @local_connector.managed_provider_carrier_input(left),
    @local_connector.managed_provider_carrier_input(right),
  ]
  for selected in [false, true] {
    let generated = task_test_generated(owner)
    let generated = if selected {
      @execution.select_generated_sequence_step(generated, 0).unwrap()
    } else {
      generated
    }
    for (rows, bytes) in [(0, 10000), (1, 1)] {
      let active = start_delta_provider(
        provider, generated, inputs, rows, bytes,
      ).unwrap()
      let mut used = 0L
      let mut failed = false
      for _ in 0..<100000 {
        match @local_connector.advance_managed_provider(active, 1).unwrap() {
          @local_connector.Continue(work~, ..) => used += work
          @local_connector.Failed(issue, work~, ..) => {
            assert_true(issue is @connector.Execution(@execution.InputSet))
            used += work
            failed = true
            break
          }
          _ =>
            abort("capacity failure published or stopped an unrequested Delta")
        }
      }
      assert_true(failed && used > 0L)
      assert_eq(
        @local_connector.managed_provider_cumulative_work(active),
        Ok(used),
      )
      assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
      assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
      assert_eq(
        @local_connector.managed_provider_cumulative_work(active),
        Ok(used),
      )
      assert_true(@graphs.completed_available(graph))
      assert_true(@graphs.completed_available(target))
    }
  }
  assert_true(@graphs.discard_completed(graph))
  assert_true(@graphs.discard_completed(target))
}
