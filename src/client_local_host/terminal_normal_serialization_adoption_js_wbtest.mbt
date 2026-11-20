///|
// Exact existing installed workspace ceilings, not an observed-row estimate.
fn terminal_normal_workspace_fixture() -> ClientSerializationWorkspaceLimits {
  {
    generation_bytes: 10000000,
    generation_nodes: 100000,
    generation_depth: 64,
    generation_frames: 256,
    identity_slots: 4000800,
    reference_bytes: 16384,
    reference_nodes: 256,
    reference_depth: 32,
    contract_bytes: 1000000,
    contract_nodes: 100000,
    contract_depth: 64,
    export_limits: {
      max_result_fields: 10,
      max_result_mapping_work: 1000,
      max_result_order_work: 10000,
      max_result_workspace_entries: 100,
      max_rows: 10000,
      values: {
        max_nodes: 1000000,
        max_text_bytes: 10000000,
        max_depth: 64,
        max_work: 1000000,
      },
      payload_wire: {
        max_bytes: 10000000,
        max_nodes: 1000000,
        max_depth: 64,
        max_columns: 100,
        max_order_work: 1000000,
      },
      logical_wire: {
        max_bytes: 10000000,
        max_nodes: 1000003,
        max_depth: 66,
        max_columns: 100,
        max_order_work: 1000000,
      },
      schema: {
        max_fields: 100,
        max_bytes: 100000,
        max_nodes: 10000,
        max_depth: 64,
      },
      max_batch_bytes: 65536,
    },
  }
}

///|
test "normal terminal Serialization adopts under its original unchanged Content geometry" {
  let text =
    #|{"version":"actql/0.1","id":"mock-terminal-content","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1},{"id":2}]},"as":"seed"},{"serialize":{"format":"jsonl","fields":["id"],"name":"two.jsonl","preserve_order":true,"bounds":{"max_rows":2,"max_bytes":64}},"as":"file"}],"results":{"file":{"from":"file","fields":["name","content","media_type","size_bytes","row_count"]}}}],"results":{"file":{"from":{"stage":"main","result":"file"}}}}
  let f = request_serialization_plan_fixture(text~, max_bytes=64)
  let selected_limits = prepare_request_serialization_output_limits(
    f.parent,
    f.input,
    f.compiled,
    @publication_host.client_compiled_run_serialization(f.compiled).unwrap(),
    10000,
    () => Some(terminal_normal_workspace_fixture()),
  ).unwrap()
  let workspace = selected_limits.capacity
  // Exact seven normal installed prefix fields, not a new resource policy.
  let values : @execution.ValueLimits = {
    max_nodes: 100000,
    max_text_bytes: 1000000,
    max_depth: 64,
    max_work: 1000000,
  }
  let execution : @execution.SequenceExecutionLimits = {
    rows: {
      max_rows: 10000,
      metadata_entries: 100000,
      retained_entries: 100000,
      operation_entries: 100000,
      input_values: values,
      output_values: values,
    },
    max_work: 1000000,
    max_frames: 256,
  }
  let measurement : @execution.FixedInputGuardMeasureLimits = {
    max_work: 1000000,
    max_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 64,
  }
  let selected = prepare_request_serialization_plan(
    f.parent,
    f.input,
    f.request,
    f.compiled,
    f.definition,
    execution,
    measurement,
    Some(workspace),
  ).unwrap()
  complete_request_serialization_preparation(f.parent, f.input, selected).unwrap()
  let limits = client_local_preparation_initial_limits(
    client_local_resource_policy(),
  ).unwrap()
  println(
    "NORMAL_SERIALIZATION required_retained=" +
    selected.limits.retained_bytes.to_string() +
    " required_execution=" +
    selected.limits.execution_bytes.to_string() +
    " admitted_retained=" +
    limits.retained_bytes.to_string() +
    " admitted_execution=" +
    limits.execution_bytes.to_string(),
  )
  let result = begin_request_content_managed_run(f.parent, f.request)
  let accepted = result is Ok(_)
  match result {
    Err(InsufficientCapacity) =>
      println("NORMAL_SERIALIZATION typed_adopt_issue=InsufficientCapacity")
    Err(_) =>
      println("NORMAL_SERIALIZATION typed_adopt_issue=OTHER_UNCLASSIFIED")
    Ok(_) => println("NORMAL_SERIALIZATION typed_adopt_issue=NONE")
  }
  // Preserve the manager's actual held inventory through completion/adoption.
  assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
  match result {
    Ok(run) => retire_installed_managed_run(run).unwrap()
    Err(_) => abort_request_preparation_after_cleanup(f.parent).unwrap()
  }
  assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
  assert_true(accepted)
}

///|
fn terminal_output_fixture_cleanup(
  f : RequestSerializationPlanFixture,
) -> Unit raise {
  assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
  abort_request_preparation_after_cleanup(f.parent).unwrap()
  assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
}

///|
test "Content output demand exact and one-short fund the constructor before any projection" {
  // Independent fixed carrier census, not product-produced expected bytes.
  let retained = 13L * 16L + (15L + 70L) * 8L
  let execution = 82L * 16L + (82L + 325L) * 8L
  for retention in [true, false] {
    for short in [false, true] {
      let f = request_serialization_plan_fixture()
      let capacity = f.parent.program_capacity.unwrap()
      let before = @resources.preparation_capacity_working_extents(
        capacity,
        f.input,
      ).unwrap()
      let ceiling = @resources.ledger_limits(f.parent.ledger)
      let blocker = @resources.reserve_capacity(
        f.parent.ledger,
        if retention {
          ceiling.retained_bytes -
          before.0 -
          retained +
          (if short { 1L } else { 0L })
        } else {
          0L
        },
        if retention {
          0L
        } else {
          ceiling.execution_bytes -
          before.1 -
          execution +
          (if short { 1L } else { 0L })
        },
      ).unwrap()
      let projections = Ref(0)
      let selected = prepare_request_serialization_output_limits(
        f.parent,
        f.input,
        f.compiled,
        @publication_host.client_compiled_run_serialization(f.compiled).unwrap(),
        10000,
        () => {
          projections.val += 1
          Some(terminal_normal_workspace_fixture())
        },
      )
      assert_true(f.parent.phase == ContentPlanReserved)
      assert_true(f.parent.program_content is NoContent)
      if short {
        assert_eq(projections.val, 0)
        assert_true(
          if retention {
            selected is Err(Capacity(Resource(RetentionLimit)))
          } else {
            selected is Err(Capacity(Resource(ExecutionLimit)))
          },
        )
        assert_eq(
          @resources.preparation_capacity_working_extents(capacity, f.input),
          Ok(before),
        )
      } else {
        assert_eq(projections.val, 1)
        let demand = selected.unwrap()
        assert_eq(demand.limits.generation_bytes, 128)
        assert_eq(demand.limits.export_limits.max_rows, 2)
        assert_eq(demand.limits.export_limits.values.max_nodes, 7)
        assert_eq(demand.limits.export_limits.payload_wire.max_nodes, 5)
        assert_eq(demand.limits.export_limits.logical_wire.max_nodes, 8)
        assert_eq(demand.limits.export_limits.values.max_text_bytes, 10000000)
        assert_eq(demand.limits.export_limits.payload_wire.max_bytes, 10000000)
        assert_eq(
          @resources.preparation_capacity_working_extents(capacity, f.input),
          Ok((before.0 + retained, before.1 + execution)),
        )
      }
      @resources.settle_capacity(f.parent.ledger, blocker).unwrap()
      terminal_output_fixture_cleanup(f)
    }
  }
}

///|
test "Content output demand rejects foreign input compiler and same-body other Graph before projection" {
  for which in 0..<3 {
    let f = request_serialization_plan_fixture()
    let foreign = request_serialization_plan_fixture()
    let projections = Ref(0)
    let selected = prepare_request_serialization_output_limits(
      f.parent,
      if which == 0 {
        foreign.input
      } else {
        f.input
      },
      if which == 1 {
        foreign.compiled
      } else {
        f.compiled
      },
      @publication_host.client_compiled_run_serialization(
        if which == 2 {
          foreign.compiled
        } else {
          f.compiled
        },
      ).unwrap(),
      10000,
      () => {
        projections.val += 1
        Some(terminal_normal_workspace_fixture())
      },
    )
    assert_true(selected is Err(ForeignOriginal))
    assert_eq(projections.val, 0)
    assert_true(f.parent.phase == ContentPlanReserved)
    terminal_output_fixture_cleanup(f)
    terminal_output_fixture_cleanup(foreign)
  }
}

///|
test "Content output demand preserves original current failure on both sides and fences constructor reentry" {
  for fail_after_projection in [false, true] {
    let armed = Ref(false)
    let projected = Ref(false)
    let f = request_serialization_plan_fixture(current=() => {
      !armed.val || (fail_after_projection && !projected.val)
    })
    let graph = @publication_host.client_compiled_run_serialization(f.compiled).unwrap()
    let projections = Ref(0)
    let reentry = Ref(false)
    armed.val = true
    let result = prepare_request_serialization_output_limits(
      f.parent,
      f.input,
      f.compiled,
      graph,
      10000,
      () => {
        projections.val += 1
        reentry.val = prepare_request_serialization_output_limits(
            f.parent,
            f.input,
            f.compiled,
            graph,
            10000,
            () => Some(terminal_normal_workspace_fixture()),
          )
          is Err(ForeignOriginal)
        projected.val = true
        Some(terminal_normal_workspace_fixture())
      },
    )
    assert_true(result is Err(Capacity(_)))
    assert_eq(projections.val, if fail_after_projection { 1 } else { 0 })
    assert_eq(reentry.val, fail_after_projection)
    assert_true(f.parent.phase == ContentPlanReserved)
    armed.val = false
    assert_true(
      prepare_request_serialization_output_limits(
        f.parent,
        f.input,
        f.compiled,
        graph,
        10000,
        () => Some(terminal_normal_workspace_fixture()),
      )
      is Err(Capacity(_)),
    )
    terminal_output_fixture_cleanup(f)
  }
  let after_projection = Ref(false)
  let original : Ref[ClientRequestPreparation[Array[Int]]?] = Ref(None)
  let foreign = request_serialization_plan_fixture()
  let f = request_serialization_plan_fixture(current=() => {
    if after_projection.val {
      original.val.unwrap().program_compilation = foreign.parent.program_compilation
    }
    true
  })
  original.val = Some(f.parent)
  let compilation = f.parent.program_compilation
  let selected = prepare_request_serialization_output_limits(
    f.parent,
    f.input,
    f.compiled,
    @publication_host.client_compiled_run_serialization(f.compiled).unwrap(),
    10000,
    () => {
      after_projection.val = true
      Some(terminal_normal_workspace_fixture())
    },
  )
  assert_true(selected is Err(ForeignOriginal))
  after_projection.val = false
  f.parent.program_compilation = compilation
  terminal_output_fixture_cleanup(f)
  terminal_output_fixture_cleanup(foreign)
}

///|
test "Content output demand preserves opaque profile and refuses checked scalar overflow" {
  let nested =
    #|{"version":"actql/0.1","id":"request-content-compilation","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"array","nullable":false,"items":{"type":"number","nullable":false},"max_items":2}},"rows":[{"id":[2]},{"id":[1]}]},"as":"seed"},{"serialize":{"format":"jsonl","fields":["id"],"name":"out.jsonl","preserve_order":true,"bounds":{"max_rows":2,"max_bytes":128}},"as":"attachment"}],"results":{"file":{"from":"attachment","fields":["name","content"]}}}],"results":{"file":{"from":{"stage":"main","result":"file"}}}}
  let f = request_serialization_plan_fixture(text=nested)
  let demand = prepare_request_serialization_output_limits(
    f.parent,
    f.input,
    f.compiled,
    @publication_host.client_compiled_run_serialization(f.compiled).unwrap(),
    1,
    () => Some(terminal_normal_workspace_fixture()),
  ).unwrap()
  assert_eq(demand.generation_rows, 1)
  assert_eq(demand.limits.export_limits.max_rows, 10000)
  assert_eq(demand.limits.export_limits.values.max_nodes, 1000000)
  assert_eq(demand.limits.identity_slots, 4000800)
  assert_true(
    @execution.execution_capacity_execution_bytes(demand.capacity) > 536870912L,
  )
  terminal_output_fixture_cleanup(f)
  let large = request_serialization_document.replace(
    old="\"max_rows\":2",
    new="\"max_rows\":2147483647",
  )
  let f = request_serialization_plan_fixture(text=large, max_rows=2147483647)
  let profile = terminal_normal_workspace_fixture()
  let selected = prepare_request_serialization_output_limits(
    f.parent,
    f.input,
    f.compiled,
    @publication_host.client_compiled_run_serialization(f.compiled).unwrap(),
    2147483647,
    () => {
      Some({
        ..profile,
        export_limits: { ..profile.export_limits, max_rows: 2147483647, },
      })
    },
  )
  assert_true(selected is Err(Policy))
  terminal_output_fixture_cleanup(f)
}

///|
test "Model output demand shares the same funded checked input projection with complete schema" {
  let f = request_serialized_model_fixture(single_capture=true)
  let demand = prepare_request_serialization_output_limits(
    f.parent,
    f.input,
    f.compiled,
    f.graph.serialization.unwrap(),
    10000,
    () => Some(terminal_normal_workspace_fixture()),
  ).unwrap()
  assert_eq(demand.limits.export_limits.max_rows, 1)
  assert_eq(demand.limits.export_limits.values.max_nodes, 8)
  assert_eq(demand.limits.export_limits.payload_wire.max_nodes, 5)
  assert_eq(demand.limits.export_limits.payload_wire.max_columns, 3)
  assert_eq(demand.limits.generation_bytes, 128)
  assert_true(
    @execution.execution_capacity_execution_bytes(demand.capacity) < 536870912L,
  )
  assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
  abort_request_preparation_after_cleanup(f.parent).unwrap()
  assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
}

///|
test "Content output demand preserves a lower generation row ceiling and refuses its real two-row input" {
  let text = request_serialization_document.replace(
    old="\"max_rows\":2",
    new="\"max_rows\":10",
  )
  let f = request_serialization_plan_fixture(text~, max_rows=10)
  let graph = @publication_host.client_compiled_run_serialization(f.compiled).unwrap()
  assert_eq(graph.max_rows, 10)
  let template = terminal_normal_workspace_fixture()
  let demand = prepare_request_serialization_output_limits(
    f.parent,
    f.input,
    f.compiled,
    graph,
    1,
    () => {
      Some({
        ..template,
        export_limits: { ..template.export_limits, max_rows: 10, },
      })
    },
  ).unwrap()
  assert_eq(demand.generation_rows, 1)
  assert_eq(demand.limits.export_limits.max_rows, 1)
  assert_eq(demand.limits.export_limits.values.max_nodes, 4)
  assert_eq(demand.limits.export_limits.payload_wire.max_nodes, 3)
  assert_eq(demand.limits.export_limits.logical_wire.max_nodes, 6)
  let selected = prepare_request_serialization_plan(
    f.parent,
    f.input,
    f.request,
    f.compiled,
    f.definition,
    f.execution,
    f.measurement,
    Some(demand.capacity),
  ).unwrap()
  complete_request_serialization_preparation(f.parent, f.input, selected).unwrap()
  let run = begin_request_content_managed_run(f.parent, f.request).unwrap()
  let prefix = start_installed_managed_serialization_prefix(
    run,
    f.prepared,
    selected,
  ).unwrap()
  let mut output : @execution.CompletedOutput? = None
  let mut polls = 0
  while output is None && polls < 1000 {
    polls += 1
    match advance_client_serialization_prefix(prefix, 1).unwrap() {
      @local.Complete(value, ..) => output = Some(value)
      @local.Continue(..) | @local.Waiting(..) | @local.Settling(_, ..) => ()
      _ => fail("same original two-row prefix")
    }
  }
  let output = output.unwrap()
  assert_eq(@execution.completed_row_count(output), 2)
  let encoder = @publication_host.start_client_serialization_encoder(
    graph.barrier,
    max_rows=demand.generation_rows,
    max_bytes=demand.limits.generation_bytes,
    max_value_nodes=demand.limits.generation_nodes,
    max_value_depth=demand.limits.generation_depth,
    max_frames=demand.limits.generation_frames,
  ).unwrap()
  let bound = @publication_host.bind_client_serialization_completed_input(
    graph.barrier,
    output,
    encoder,
  )
  @publication.cancel_content_byte_encoder(encoder)
  assert_true(
    cleanup_installed_managed_serialization_prefix(run, selected).unwrap(),
  )
  assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
  assert_true(bound is Err(Encoding(ContentRowLimit)))
}
