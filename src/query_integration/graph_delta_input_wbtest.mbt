///|
fn graph_delta_empty_actions() -> String {
  // Both snapshot identities and the contract identity come from the existing
  // independently authored snapshot fixture, not from Apply or snapshot output.
  "{\"version\":\"actql-graph-delta/0.1\",\"graph_contract_cid\":\"sha256:df3a17807922ac2f939372e0cd59b31ecc7e6c860bc22c985aa8acf05971f166\",\"base_graph_cid\":\"" +
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
    new="\"target_graph_cid\":\"sha256:d1da1fc1037556e8fc76bb828587be6c88342ace1b6fe5ee17da7ec7bba15d57\"",
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
fn graph_delta_separate_work(
  owner : @lower.BoundPrepared,
  view : @carrier_runtime.ProducerView,
  rows : @execution.ProducerRead,
) -> (Int64, Int64) raise {
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
  let mut conversion = 0L
  let mut ready = false
  for _ in 0..<100000 {
    match @local_sga.advance_delta_apply_input(input, 7).unwrap() {
      @local_sga.DeltaApplyInputContinue(work~) => conversion += work.to_int64()
      @local_sga.DeltaApplyInputReady(work~) => {
        conversion += work.to_int64()
        ready = true
        break
      }
      _ => abort("separate input preparation failed")
    }
  }
  assert_true(ready)
  let active = @local_sga.start_delta_apply_from_admitted_input(
    @bounded.control(),
    input,
  ).unwrap()
  for _ in 0..<100000 {
    match @local_sga.advance_delta_apply(active, 7).unwrap() {
      @local_sga.DeltaApplyContinue(..) => ()
      @local_sga.DeltaApplyComplete(output, work~, ..) => {
        assert_true(@graphs.discard_completed(output))
        assert_true(@local_sga.cleanup_delta_apply(active).unwrap())
        return (conversion, work)
      }
      _ => abort("separate application failed")
    }
  }
  abort("separate application exceeded the fixture ceiling")
}

///|
test "Delta input conversion and application share one session without resetting work" {
  for removal in [false, true] {
    let mut expected_work = None
    for quantum in [1, 7, 64] {
      let (owner, view, rows, original, live) = graph_delta_input_fixture(
        text=if removal {
          graph_delta_remove_parallel_edge()
        } else {
          graph_delta_empty_actions()
        },
      )
      let (conversion, application) = graph_delta_separate_work(
        owner, view, rows,
      )
      // Count existing conversion/application work exactly once, plus the
      // explicit, constant one-use handoff. Snapshot expectations below remain
      // independent literals, not values generated by either execution path.
      let total = conversion + application + 1L
      if expected_work is Some(expected) {
        assert_eq(total, expected)
      } else {
        expected_work = Some(total)
      }
      let active = @local_sga.start_delta_apply_inputs(
        @bounded.control(),
        prepared_sequence(owner),
        0,
        view,
        rows,
        graph_delta_input_limits(),
        carrier_graph_storage_limits(),
        4096L,
        () => true,
        control_work_limit=Some(total.to_int()),
      ).unwrap()
      let mut result = None
      let mut prior = 0L
      for _ in 0..<100000 {
        let poll = @local_sga.advance_delta_apply(active, quantum).unwrap()
        let work = match poll {
          @local_sga.DeltaApplyContinue(work~, ..) => work
          @local_sga.DeltaApplyComplete(output, work~, ..) => {
            result = Some(output)
            work
          }
          _ => abort("combined input/application failed")
        }
        assert_true(work > prior && work - prior <= quantum.to_int64())
        prior = work
        if result is Some(_) {
          break
        }
      }
      assert_eq(prior, total)
      let result = result.unwrap()
      let expected = if removal {
        (
          "sha256:d1da1fc1037556e8fc76bb828587be6c88342ace1b6fe5ee17da7ec7bba15d57",
          snapshot_fixture_body(keys=[10]),
        )
      } else {
        (snapshot_fixture_cid(), snapshot_fixture_body())
      }
      assert_eq(
        snapshot_capture(@graphs.completed_storage(result).unwrap()),
        expected,
      )
      assert_true(@local_sga.cleanup_delta_apply(active).unwrap())
      assert_false(@local_sga.cleanup_delta_apply(active).unwrap())
      live.val = false
      assert_true(@graphs.discard_completed(original))
      assert_true(@graphs.completed_available(result))
      assert_eq(
        snapshot_capture(@graphs.completed_storage(result).unwrap()),
        expected,
      )
      assert_true(@graphs.discard_completed(result))
    }
  }
}

///|
test "Delta input work budget covers conversion handoff application and final completion" {
  let (owner, view, rows, original, _) = graph_delta_input_fixture(
    text=graph_delta_remove_parallel_edge(),
  )
  let (conversion, application) = graph_delta_separate_work(owner, view, rows)
  let total = conversion + application + 1L
  assert_true(conversion > 1L && application > 1L)
  assert_true(
    @local_sga.start_delta_apply_inputs(
      @bounded.control(),
      prepared_sequence(owner),
      0,
      view,
      rows,
      graph_delta_input_limits(),
      carrier_graph_storage_limits(),
      4096L,
      () => true,
      control_work_limit=Some(-1),
    )
    is Err(@local_sga.DeltaApplyControlWorkLimit),
  )
  for ceiling in [0L, 1L, conversion, conversion + 1L, total - 1L] {
    let active = @local_sga.start_delta_apply_inputs(
      @bounded.control(),
      prepared_sequence(owner),
      0,
      view,
      rows,
      graph_delta_input_limits(),
      carrier_graph_storage_limits(),
      4096L,
      () => true,
      control_work_limit=Some(ceiling.to_int()),
    ).unwrap()
    let mut prior = 0L
    let mut failed = false
    for _ in 0..<100000 {
      match @local_sga.advance_delta_apply(active, 64).unwrap() {
        @local_sga.DeltaApplyContinue(work~, ..) => {
          assert_true(work > prior && work - prior <= 64L)
          assert_true(work <= ceiling)
          prior = work
        }
        @local_sga.DeltaApplyFailed(
          @local_sga.DeltaApplyControlWorkLimit,
          work~,
          ..
        ) => {
          assert_eq(work, ceiling)
          assert_eq(work, prior)
          failed = true
          break
        }
        _ =>
          abort(
            "an exhausted budget restarted application or published a Graph",
          )
      }
    }
    assert_true(failed)
    assert_true(
      @local_sga.advance_delta_apply(active, 1)
      is Err(@local_sga.DeltaApplyExecutionIssue(@bounded.Terminal)),
    )
    assert_true(@local_sga.delta_apply_cleanup_pending(active))
    assert_true(@local_sga.cleanup_delta_apply(active).unwrap())
    assert_false(@local_sga.cleanup_delta_apply(active).unwrap())
    assert_false(@local_sga.delta_apply_cleanup_pending(active))
    assert_true(@graphs.completed_available(original))
    assert_true(@execution.producer_read_available(rows))
    assert_eq(
      snapshot_capture(@graphs.completed_storage(original).unwrap()),
      (snapshot_fixture_cid(), snapshot_fixture_body()),
    )
  }
  assert_true(@graphs.discard_completed(original))
}

///|
test "Delta input cancellation and loss retain cumulative work before and after handoff" {
  for cause in ["cancel", "loss"] {
    for
      stage in ["before", "conversion", "handoff", "application", "completion"] {
      let (owner, view, rows, original, live) = graph_delta_input_fixture()
      let (conversion, application) = graph_delta_separate_work(
        owner, view, rows,
      )
      assert_true(application > 4L)
      let stop_after = match stage {
        "before" => 0L
        "conversion" => 20L
        "handoff" => conversion + 1L
        "application" => conversion + 4L
        _ => conversion + application
      }
      let control = @bounded.control()
      let active = @local_sga.start_delta_apply_inputs(
        control,
        prepared_sequence(owner),
        0,
        view,
        rows,
        graph_delta_input_limits(),
        carrier_graph_storage_limits(),
        4096L,
        () => true,
      ).unwrap()
      for poll in 0..<stop_after.to_int() {
        assert_true(
          @local_sga.advance_delta_apply(active, 1)
          is Ok(@local_sga.DeltaApplyContinue(work~, ..)) &&
          work == poll.to_int64() + 1L,
        )
      }
      if cause == "cancel" {
        assert_true(@bounded.request_cancel(control))
      } else {
        live.val = false
      }
      let poll = @local_sga.advance_delta_apply(active, 1).unwrap()
      assert_true(
        if cause == "cancel" {
          poll is @local_sga.DeltaApplyStopped(@bounded.Cancelled, work~, ..) &&
          work == stop_after
        } else {
          poll
          is @local_sga.DeltaApplyFailed(
            @local_sga.DeltaApplyInputUnavailable,
            work~,
            ..
          ) &&
          work == stop_after
        },
      )
      assert_true(
        @local_sga.advance_delta_apply(active, 1)
        is Err(@local_sga.DeltaApplyExecutionIssue(@bounded.Terminal)),
      )
      assert_true(@local_sga.cleanup_delta_apply(active).unwrap())
      assert_false(@local_sga.cleanup_delta_apply(active).unwrap())
      assert_false(@local_sga.delta_apply_cleanup_pending(active))
      assert_true(@graphs.completed_available(original))
      assert_eq(@execution.producer_read_available(rows), cause != "loss")
      assert_true(@graphs.discard_completed(original))
    }
  }
}

///|
test "Delta input malformed envelope fails within the same session and retains conversion work" {
  let (owner, view, rows, original, _) = graph_delta_input_fixture(text="{}")
  let active = @local_sga.start_delta_apply_inputs(
    @bounded.control(),
    prepared_sequence(owner),
    0,
    view,
    rows,
    graph_delta_input_limits(),
    carrier_graph_storage_limits(),
    4096L,
    () => true,
  ).unwrap()
  let mut prior = 0L
  let mut failed = false
  for _ in 0..<100000 {
    match @local_sga.advance_delta_apply(active, 1).unwrap() {
      @local_sga.DeltaApplyContinue(work~, ..) => {
        assert_eq(work, prior + 1L)
        prior = work
      }
      @local_sga.DeltaApplyFailed(
        @local_sga.DeltaApplyKernel(@bounded_graph_diff.InvalidDelta),
        work~,
        ..
      ) => {
        assert_true(prior > 0L)
        assert_eq(work, prior + 1L)
        failed = true
        break
      }
      _ => abort("a malformed envelope escaped the combined input owner")
    }
  }
  assert_true(failed)
  assert_true(@local_sga.cleanup_delta_apply(active).unwrap())
  assert_false(@local_sga.delta_apply_cleanup_pending(active))
  assert_true(@execution.producer_read_available(rows))
  assert_true(@graphs.completed_available(original))
  assert_true(@graphs.discard_completed(original))
}

///|
test "Delta exact Relation input preparation reaches the existing Graph output owner" {
  for removal in [false, true] {
    let mut expected_work = None
    for quantum in [1, 7, 64] {
      let (owner, view, rows, original, live) = graph_delta_input_fixture(
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
          "sha256:d1da1fc1037556e8fc76bb828587be6c88342ace1b6fe5ee17da7ec7bba15d57",
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
      // A successful immutable output is not kept alive by upstream readers.
      // Closing both original operands must not invalidate its snapshot bytes.
      live.val = false
      assert_true(@graphs.discard_completed(original))
      assert_true(@graphs.completed_available(result))
      assert_eq(
        snapshot_capture(@graphs.completed_storage(result).unwrap()),
        expected,
      )
      assert_true(@graphs.discard_completed(result))
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
