///|
fn graph_delta_empty_actions() -> String {
  // Both snapshot identities and the contract identity come from the existing
  // independently authored snapshot fixture, not from Apply or snapshot output.
  "{\"version\":\"actql-graph-delta/0.1\",\"graph_contract_cid\":\"sha256:6a0fe1664c431e3b0835ccaf2fff3569e99492ae427eab4ccb65d34096ce604d\",\"base_graph_cid\":\"" +
  snapshot_fixture_cid() +
  "\",\"target_graph_cid\":\"" +
  snapshot_fixture_cid() +
  "\",\"nodes\":{\"add\":[],\"remove\":[],\"update\":[]},\"edges\":{\"add\":[],\"remove\":[],\"update\":[]}}"
}

///|
fn graph_delta_remove_parallel_edge() -> String {
  let node = snapshot_fixture_identity("N", 1)
  let record = "{\"dst\":" +
    node +
    ",\"id\":" +
    snapshot_fixture_identity("E", 11) +
    ",\"key\":[11],\"props\":{},\"src\":" +
    node +
    "}"
  graph_delta_empty_actions()
  .replace(
    old="\"edges\":{\"add\":[],\"remove\":[],\"update\":[]}",
    new="\"edges\":{\"add\":[],\"remove\":[" + record + "],\"update\":[]}",
  )
  .replace(
    old="\"target_graph_cid\":\"" + snapshot_fixture_cid() + "\"",
    new="\"target_graph_cid\":\"sha256:1371549624dd79d7a1121a061fde22c27ef85f8c0fd99f42a28d1fdb26e7ef01\"",
  )
}

///|
fn graph_delta_input_limits() -> @bounded_graph_diff.Limits {
  {
    max_workspace_slots: 100000,
    max_output_nodes: 1000,
    max_output_text_bytes: 10000,
    max_output_depth: 100,
    max_identity_bytes: 100000,
    max_identity_nodes: 1000,
    max_identity_depth: 100,
    value_limits: { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, },
  }
}

///|
fn graph_delta_input_fixture(
  count? : Int = 1,
  text? : String = graph_delta_empty_actions(),
) -> (
  @lower.BoundPrepared,
  @carrier_runtime.ProducerView,
  @execution.ProducerRead,
  @graphs.Completed,
  Ref[Bool],
) raise {
  let graph_owner = snapshot_fixture_owner()
  let graph = snapshot_handoff_source(graph_owner)
  let schema = @schema.from_object(
    @value_contract.object_contract(
      [("delta", @value_contract.primitive(JsonType, nullable=false))],
      nullable=false,
      max_fields=1,
      max_name_bytes=5,
    ).unwrap(),
  ).unwrap()
  let checked_source = @pipeline.check(
    input_cursor("[{\"select\":[\"delta\"]}]"),
    [("raw", schema)],
    None,
    Some(input_cursor("\"raw\"")),
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
  let source = @lower.bind_parameters(
    @lower.prepare(checked_source, {
      max_nodes: 1000,
      max_references: 1000,
      max_work: 100000,
      max_identifier_bytes: 100000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let captured = @execution.capture_input(
    source,
    0,
    Array::make(count, input_cursor("{\"delta\":" + text + "}")),
    max_rows=10,
    property_rows_value_limits(),
  ).unwrap()
  let executed = @execution.execute_generated_sequence(
    compute_test_sequence(source),
    [captured],
    compute_test_limits(),
  ).unwrap()
  let source_output = @execution.completed_output(executed, @pipeline.Step(0)).unwrap()
  let evidence = [
    (
      "g",
      @pipeline.ProducedInput(
        @pipeline.produced_input(
          @lower.pipeline(@lower.bound_preparation(graph_owner)),
          @pipeline.Input(0),
        ).unwrap(),
      ),
    ),
    (
      "changes",
      @pipeline.ProducedInput(
        @pipeline.produced_input(
          @lower.pipeline(@lower.bound_preparation(source)),
          @pipeline.Step(0),
        ).unwrap(),
      ),
    ),
  ]
  let checked = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"from\":\"g\",\"apply_graph_delta\":{\"with\":\"changes\",\"field\":\"delta\"}}]",
    ),
    evidence,
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
  let view = @graphs.producer_read_view(
    @graphs.prepare_producer_read(owner, 0, graph_owner, graph).unwrap(),
  ).unwrap()
  let live = Ref(true)
  let output = @execution.restrict_completed_output(source_output, () => {
    live.val
  })
  let rows = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 1, source, output).unwrap(),
    1000,
    10000,
  ).unwrap()
  (owner, view, rows, graph, live)
}

///|
fn graph_delta_input_ready(
  input : @local_sga.DeltaApplyInputPreparation,
) -> Unit raise {
  for _ in 0..<100000 {
    match @local_sga.advance_delta_apply_input(input, 7).unwrap() {
      @local_sga.DeltaApplyInputContinue(work~) =>
        assert_true(work > 0 && work <= 7)
      @local_sga.DeltaApplyInputReady(work~) => {
        assert_true(work > 0 && work <= 7)
        return
      }
      _ => abort("Delta Relation input did not reach ready")
    }
  }
  abort("Delta Relation input preparation exceeded the fixture ceiling")
}

///|
test "Delta exact Relation input preparation reaches the existing Graph output owner" {
  for removal in [false, true] {
    let mut expected_work = None
    for quantum in [1, 7, 64] {
      let (owner, view, rows, original, _) = graph_delta_input_fixture(
        text=if removal {
          graph_delta_remove_parallel_edge()
        } else {
          graph_delta_empty_actions()
        },
      )
      let input = @local_sga.prepare_delta_apply_input(
        prepared_sequence(owner),
        0,
        view,
        rows,
        graph_delta_input_limits(),
        carrier_graph_storage_limits(),
        4096L,
        () => true,
      ).unwrap()
      let mut preparation_work = 0
      let mut ready = false
      for _ in 0..<100000 {
        let poll = @local_sga.advance_delta_apply_input(input, quantum).unwrap()
        let used = match poll {
          @local_sga.DeltaApplyInputContinue(work~) => work
          @local_sga.DeltaApplyInputReady(work~) => {
            ready = true
            work
          }
          _ => abort("Delta input admission failed")
        }
        assert_true(used > 0 && used <= quantum)
        preparation_work += used
        if ready {
          break
        }
      }
      assert_true(ready)
      if expected_work is Some(expected) {
        assert_eq(preparation_work, expected)
      } else {
        expected_work = Some(preparation_work)
      }
      let active = @local_sga.start_delta_apply_from_admitted_input(
        @bounded.control(),
        input,
      ).unwrap()
      assert_true(
        @local_sga.start_delta_apply_from_admitted_input(
          @bounded.control(),
          input,
        )
        is Err(@local_sga.DeltaApplyInvalidInput),
      )
      let mut result = None
      let mut work = 0L
      for _ in 0..<100000 {
        let poll = @local_sga.advance_delta_apply(active, quantum).unwrap()
        let used = match poll {
          @local_sga.DeltaApplyContinue(work~, ..) => work
          @local_sga.DeltaApplyComplete(value, work~, ..) => {
            result = Some(value)
            work
          }
          _ => abort("bound Delta application failed")
        }
        assert_true(used >= work && used - work <= quantum.to_int64())
        work = used
        if result is Some(_) {
          break
        }
      }
      let result = result.unwrap()
      let expected = if removal {
        (
          "sha256:1371549624dd79d7a1121a061fde22c27ef85f8c0fd99f42a28d1fdb26e7ef01",
          snapshot_fixture_body(keys=[10]),
        )
      } else {
        (snapshot_fixture_cid(), snapshot_fixture_body())
      }
      assert_eq(
        snapshot_capture(@graphs.completed_storage(result).unwrap()),
        expected,
      )
      assert_true(
        @carrier_runtime.completion_reference_matches_port(
          @graphs.completed_carrier_reference(result),
          owner,
          @pipeline.Step(0),
        ),
      )
      @local_sga.cleanup_delta_apply_input(input)
      assert_true(@local_sga.cleanup_delta_apply(active).unwrap())
      assert_true(@graphs.completed_available(original))
      assert_true(@execution.producer_read_available(rows))
      assert_true(@graphs.discard_completed(result))
      assert_true(@graphs.discard_completed(original))
    }
  }
}

///|
test "Delta Relation input rejects wrong row count foreign bindings and workspace" {
  for count in [0, 2] {
    let (owner, view, rows, original, _) = graph_delta_input_fixture(count~)
    assert_true(
      @local_sga.prepare_delta_apply_input(
        prepared_sequence(owner),
        0,
        view,
        rows,
        graph_delta_input_limits(),
        carrier_graph_storage_limits(),
        4096L,
        () => true,
      )
      is Err(@local_sga.DeltaApplyInvalidInput),
    )
    assert_true(@graphs.completed_available(original))
    assert_true(@graphs.discard_completed(original))
  }
  let (owner, view, rows, original, _) = graph_delta_input_fixture()
  let (_, other_view, other_rows, other, _) = graph_delta_input_fixture()
  for (base, changes) in [(other_view, rows), (view, other_rows)] {
    assert_true(
      @local_sga.prepare_delta_apply_input(
        prepared_sequence(owner),
        0,
        base,
        changes,
        graph_delta_input_limits(),
        carrier_graph_storage_limits(),
        4096L,
        () => true,
      )
      is Err(@local_sga.DeltaApplyInvalidInput),
    )
  }
  assert_true(
    @local_sga.prepare_delta_apply_input(
      prepared_sequence(owner),
      0,
      view,
      rows,
      { ..graph_delta_input_limits(), max_workspace_slots: 0, },
      carrier_graph_storage_limits(),
      4096L,
      () => true,
    )
    is Err(@local_sga.DeltaApplyWorkspaceLimit),
  )
  assert_true(@graphs.discard_completed(original))
  assert_true(@graphs.discard_completed(other))
}

///|
test "Delta input recheck observes the same effective bounds as conversion workspace admission" {
  for
    limits in [
      { ..graph_delta_input_limits(), max_output_nodes: 1, },
      { ..graph_delta_input_limits(), max_output_depth: 1, },
      { ..graph_delta_input_limits(), max_output_text_bytes: 1, },
    ] {
    let (owner, view, rows, original, _) = graph_delta_input_fixture()
    let input = @local_sga.prepare_delta_apply_input(
      prepared_sequence(owner),
      0,
      view,
      rows,
      limits,
      carrier_graph_storage_limits(),
      4096L,
      () => true,
    ).unwrap()
    let mut failed = false
    let mut work = 0
    for _ in 0..<10000 {
      match @local_sga.advance_delta_apply_input(input, 1).unwrap() {
        @local_sga.DeltaApplyInputContinue(work=used) => {
          assert_eq(used, 1)
          work += used
        }
        @local_sga.DeltaApplyInputFailed(
          @local_sga.DeltaApplyInvalidInput,
          work=used
        ) => {
          assert_eq(used, 1)
          work += used
          failed = true
          break
        }
        _ => abort("over-limit Delta input was admitted")
      }
    }
    assert_true(failed)
    // This independent fixture's root has six fields; its first child exhausts
    // a node/text ceiling of one and its second child is already a container.
    // Refusal must occur during recheck, not after a full larger-budget walk.
    assert_true(work <= 8)
    @local_sga.cleanup_delta_apply_input(input)
    assert_true(@execution.producer_read_available(rows))
    assert_true(@graphs.completed_available(original))
    assert_true(@graphs.discard_completed(original))
  }
}

///|
test "Delta preparation loses no input custody on revocation cleanup or invalid body" {
  for stop_after in [1, 20, 100] {
    let (owner, view, rows, original, live) = graph_delta_input_fixture()
    let input = @local_sga.prepare_delta_apply_input(
      prepared_sequence(owner),
      0,
      view,
      rows,
      graph_delta_input_limits(),
      carrier_graph_storage_limits(),
      4096L,
      () => true,
    ).unwrap()
    for _ in 0..<stop_after {
      assert_true(
        @local_sga.advance_delta_apply_input(input, 1)
        is Ok(@local_sga.DeltaApplyInputContinue(work=1)),
      )
    }
    live.val = false
    assert_true(
      @local_sga.advance_delta_apply_input(input, 1)
      is Ok(
        @local_sga.DeltaApplyInputFailed(
          @local_sga.DeltaApplyInputUnavailable,
          work=0
        )
      ),
    )
    @local_sga.cleanup_delta_apply_input(input)
    @local_sga.cleanup_delta_apply_input(input)
    assert_true(
      @local_sga.start_delta_apply_from_admitted_input(
        @bounded.control(),
        input,
      )
      is Err(@local_sga.DeltaApplyInvalidInput),
    )
    assert_true(@graphs.completed_available(original))
    assert_true(@graphs.discard_completed(original))
  }
  let (owner, view, rows, original, _) = graph_delta_input_fixture(text="{}")
  let input = @local_sga.prepare_delta_apply_input(
    prepared_sequence(owner),
    0,
    view,
    rows,
    graph_delta_input_limits(),
    carrier_graph_storage_limits(),
    4096L,
    () => true,
  ).unwrap()
  let mut ready = false
  for _ in 0..<100000 {
    match @local_sga.advance_delta_apply_input(input, 1).unwrap() {
      @local_sga.DeltaApplyInputContinue(..) => ()
      @local_sga.DeltaApplyInputReady(..) => {
        ready = true
        break
      }
      _ => abort("ordinary JSON preparation failed")
    }
  }
  assert_true(ready)
  assert_true(
    @local_sga.start_delta_apply_from_admitted_input(@bounded.control(), input)
    is Err(@local_sga.DeltaApplyKernel(@bounded_graph_diff.InvalidDelta)),
  )
  @local_sga.cleanup_delta_apply_input(input)
  assert_true(@graphs.completed_available(original))
  assert_true(@execution.producer_read_available(rows))
  assert_true(@graphs.discard_completed(original))
}

///|
test "Delta ready input rechecks both current permission and Relation custody before start" {
  for revoke_permission in [false, true] {
    let (owner, view, rows, original, live) = graph_delta_input_fixture()
    let permitted = Ref(true)
    let input = @local_sga.prepare_delta_apply_input(
      prepared_sequence(owner),
      0,
      view,
      rows,
      graph_delta_input_limits(),
      carrier_graph_storage_limits(),
      4096L,
      () => permitted.val,
    ).unwrap()
    graph_delta_input_ready(input)
    if revoke_permission {
      permitted.val = false
    } else {
      live.val = false
    }
    assert_true(
      @local_sga.start_delta_apply_from_admitted_input(
        @bounded.control(),
        input,
      )
      is Err(@local_sga.DeltaApplyInvalidInput),
    )
    @local_sga.cleanup_delta_apply_input(input)
    @local_sga.cleanup_delta_apply_input(input)
    assert_true(@graphs.completed_available(original))
    assert_eq(@execution.producer_read_available(rows), revoke_permission)
    assert_true(@graphs.discard_completed(original))
  }
}

///|
test "Delta admitted input keeps borrowed owners across stop loss and exhausted compute budget" {
  for cause in ["cancel", "loss", "budget"] {
    let (owner, view, rows, original, live) = graph_delta_input_fixture(
      text=graph_delta_remove_parallel_edge(),
    )
    let input = @local_sga.prepare_delta_apply_input(
      prepared_sequence(owner),
      0,
      view,
      rows,
      graph_delta_input_limits(),
      carrier_graph_storage_limits(),
      4096L,
      () => true,
    ).unwrap()
    graph_delta_input_ready(input)
    let control = @bounded.control()
    let active = @local_sga.start_delta_apply_from_admitted_input(
      control,
      input,
      control_work_limit=if cause == "budget" { Some(0) } else { None },
    ).unwrap()
    // The private input preparation has transferred custody. Repeated cleanup
    // must not invalidate the session's reads or release their upstream owner.
    @local_sga.cleanup_delta_apply_input(input)
    @local_sga.cleanup_delta_apply_input(input)
    if cause == "cancel" {
      assert_true(@bounded.request_cancel(control))
    } else if cause == "loss" {
      live.val = false
    }
    let poll = @local_sga.advance_delta_apply(active, 1).unwrap()
    assert_true(
      match cause {
        "cancel" =>
          poll
          is @local_sga.DeltaApplyStopped(
            @bounded.Cancelled,
            progress=0L,
            work=0L
          )
        "loss" =>
          poll
          is @local_sga.DeltaApplyFailed(
            @local_sga.DeltaApplyInputUnavailable,
            progress=0L,
            work=0L
          )
        _ =>
          poll
          is @local_sga.DeltaApplyFailed(
            @local_sga.DeltaApplyControlWorkLimit,
            progress=0L,
            work=0L
          )
      },
    )
    assert_true(@local_sga.delta_apply_cleanup_pending(active))
    assert_true(@local_sga.cleanup_delta_apply(active).unwrap())
    // Existing bounded cleanup reports a change, not a success flag. A second
    // call must do nothing after the first call closes the one owned custody.
    assert_false(@local_sga.cleanup_delta_apply(active).unwrap())
    assert_false(@local_sga.delta_apply_cleanup_pending(active))
    assert_true(@graphs.completed_available(original))
    assert_eq(@execution.producer_read_available(rows), cause != "loss")
    assert_eq(
      snapshot_capture(@graphs.completed_storage(original).unwrap()),
      (snapshot_fixture_cid(), snapshot_fixture_body()),
    )
    assert_true(@graphs.discard_completed(original))
  }
}
