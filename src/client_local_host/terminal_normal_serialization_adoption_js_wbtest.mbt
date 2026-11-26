///|
test "normal terminal Serialization encodes the same admitted ordered input and retires" {
  let text =
    #|{"version":"actql/0.1","id":"mock-terminal-content","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":1},{"id":2}]},"as":"seed"},{"serialize":{"format":"jsonl","fields":["id"],"name":"two.jsonl","preserve_order":true,"bounds":{"max_rows":2,"max_bytes":64}},"as":"file"}],"results":{"file":{"from":"file","fields":["name","content","media_type","size_bytes","row_count"]}}}],"results":{"file":{"from":{"stage":"main","result":"file"}}}}
  let f = request_serialization_plan_fixture(text~, max_bytes=64)
  let selected = prepare_request_terminal_serialization_plan(
    f.parent,
    f.input,
    f.request,
    f.compiled,
    f.definition,
  ).unwrap()
  complete_request_serialization_preparation(f.parent, f.input, selected).unwrap()
  assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
  let run = begin_request_content_managed_run(f.parent, f.request).unwrap()
  let foreign = request_serialization_plan_fixture(text~, max_bytes=64)
  let before = @resources.ledger_usage(f.parent.ledger)
  assert_true(
    start_installed_managed_terminal_serialization(
      run,
      f.request,
      foreign.compiled,
      f.definition,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    start_installed_managed_terminal_serialization(
      run,
      foreign.request,
      f.compiled,
      f.definition,
    )
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(f.parent.ledger), before)
  terminal_output_fixture_cleanup(foreign)
  let (original, prefix, demand) = start_installed_managed_terminal_serialization(
    run,
    f.request,
    f.compiled,
    f.definition,
  ).unwrap()
  assert_true(physical_equal(original, selected))
  assert_true(physical_equal(demand, selected.terminal_output.unwrap()))
  let entered = @resources.ledger_usage(f.parent.ledger)
  assert_true(
    start_installed_managed_terminal_serialization(
      run,
      f.request,
      f.compiled,
      f.definition,
    )
    is Err(AlreadyBound),
  )
  assert_eq(@resources.ledger_usage(f.parent.ledger), entered)
  let mut completed : @execution.CompletedOutput? = None
  for _ in 0..<1000 {
    match advance_client_serialization_prefix(prefix, 1).unwrap() {
      @local.Complete(value, ..) => {
        completed = Some(value)
        break
      }
      @local.Continue(..) | @local.Waiting(..) | @local.Settling(_, ..) => ()
      _ => fail("original terminal prefix did not complete")
    }
  }
  let graph = @publication_host.client_compiled_run_serialization(f.compiled).unwrap()
  let encoder = @publication_host.start_client_serialization_encoder(
    graph.barrier,
    max_rows=demand.generation_rows,
    max_bytes=demand.limits.generation_bytes,
    max_value_nodes=demand.limits.generation_nodes,
    max_value_depth=demand.limits.generation_depth,
    max_frames=demand.limits.generation_frames,
  ).unwrap()
  let input = @publication_host.bind_client_serialization_completed_input(
    graph.barrier,
    completed.unwrap(),
    encoder,
  ).unwrap()
  assert_eq(@publication_host.client_serialization_input_rows(input), 2)
  let encoded = StringBuilder()
  for phase in 0..<=2 {
    if phase > 0 {
      @publication_host.start_client_serialization_input_row(input, phase - 1).unwrap()
    }
    let mut ready = false
    for _ in 0..<1000 {
      match @publication.advance_content_bytes(encoder, 7) {
        ContentBytesContinue(piece, ..) => encoded.write_string(piece)
        ContentBytesReady(piece, ..) => {
          encoded.write_string(piece)
          ready = true
          break
        }
        ContentBytesFailed(_, ..) => fail("original terminal encoding failed")
      }
    }
    assert_true(ready)
  }
  let output = @publication.finish_content_bytes(encoder).unwrap()
  assert_eq(encoded.to_string(), "{\"id\":1}\n{\"id\":2}\n")
  assert_eq((output.row_count, output.size_bytes), (2, 18))
  assert_eq(
    output.content_cid,
    "sha256:c63f6dd68b68601e7315ea40d28bc34e55379e4fa65f82b1d32228429aeafcde",
  )
  let limits = demand.limits
  let export_limits = limits.export_limits
  let scan = @publication_host.start_client_serialization_input_identity(
    input,
    export_limits.values,
    export_limits.payload_wire,
    export_limits.logical_wire,
    export_limits.schema,
    10000,
    limits.identity_slots,
  ).unwrap()
  let mut scanned = false
  for _ in 0..<1000 {
    if @execution.advance_completed_relation_identity_scan(scan, 7).unwrap().0 {
      scanned = true
      break
    }
  }
  assert_true(scanned)
  let receipt = @execution.finish_completed_relation_identity_scan(scan).unwrap()
  let evidence = @publication_host.bind_client_serialization_input_identity(
    f.compiled,
    input,
    receipt,
    limits.contract_bytes,
    limits.contract_nodes,
    limits.contract_depth,
  ).unwrap()
  @execution.cancel_completed_relation_export_receipt(receipt)
  @execution.cancel_completed_relation_identity_scan(scan) |> ignore
  let reference_limits : @admitted.ReferenceLimits = {
    max_bytes: limits.reference_bytes,
    max_nodes: limits.reference_nodes,
    max_depth: limits.reference_depth,
    max_text_units: limits.reference_bytes,
  }
  let scope = @publication_host.client_request_authority_scope_cid(f.request)
  let candidate = @publication.prepare_generated_content_reference(
    encoder,
    {
      content_store_id: "terminal-content-fixture",
      content_store_cid: "sha256:" + "1".repeat(64),
      workspace_scope_cid: scope,
      storage_scope: "workspace",
      retention_class: "local-content",
      expires_at: None,
      availability_evidence_cid: "sha256:" + "2".repeat(64),
      effective_data_policy_cid: @publication.captured_effect_dependency_body_cid(
        graph.policy,
      ),
      data_classification: @publication.captured_effective_data_policy_classification(
        graph.policy,
      ).unwrap(),
      issuer_contract_cid: "sha256:" + "3".repeat(64),
      capture_authority_cid: scope,
    },
    reference_limits,
  ).unwrap()
  let candidate_wire = @publication.generated_content_reference_wire(candidate)
  let issuer = @admitted.bind_reference_issuer(
    (_, wire) => wire == candidate_wire,
    _ => true,
  )
  let reference = @publication.issue_generated_content_reference(
    candidate, issuer, reference_limits,
  ).unwrap()
  let generation = @publication_host.complete_client_serialization_generation(
    f.compiled,
    f.definition,
    input,
    evidence,
    candidate,
    reference,
    () => true,
    export_limits.values,
    256,
  ).unwrap()
  assert_true(
    issue_program_terminal_serialization_invocation(
      run,
      foreign.request,
      f.compiled,
      f.definition,
      generation,
      demand,
      65536,
      8192,
      64,
    )
    is Err(ForeignOriginal),
  )
  let (observation, invocation, content) = issue_program_terminal_serialization_invocation(
    run,
    f.request,
    f.compiled,
    f.definition,
    generation,
    demand,
    65536,
    8192,
    64,
  ).unwrap()
  assert_eq(
    @publication.run_evidence_value_name(observation),
    "observation_set",
  )
  assert_eq(
    @publication.publication_contract_name(invocation),
    "run_invocation",
  )
  assert_true(@publication.bound_content_generation_value(content) is Some(_))
  assert_true(
    issue_program_terminal_serialization_invocation(
      run,
      f.request,
      f.compiled,
      f.definition,
      generation,
      demand,
      65536,
      8192,
      64,
    )
    is Err(WrongPhase),
  )
  let result_limits = demand.result_limits.unwrap()
  let native_output = @publication_host.client_serialization_generation_output_for(
    generation,
    f.compiled,
  ).unwrap()
  let result = @publication_host.prepare_client_result_transformation(
    f.prepared,
    0,
    result_limits.schema.max_bytes,
    result_limits.schema.max_nodes,
    result_limits.schema.max_depth,
  ).unwrap()
  assert_eq(@publication_host.client_result_transformation_name(result), "file")
  let view = @publication_host.start_client_result_transformation(
    result, native_output, result_limits,
  ).unwrap()
  let mut ready = false
  for _ in 0..<1000 {
    let (done, work, issue) = view.advance_progress(7)
    assert_true(issue is None && work >= 0 && work <= 7)
    if done {
      ready = true
      break
    }
  }
  assert_true(ready)
  let result_export = view.finish().unwrap()
  view.cancel() |> ignore
  let row = result_export.next().unwrap().unwrap()
  assert_true(row.contains("\"name\":\"two.jsonl\""))
  assert_true(row.contains("\"size_bytes\":18"))
  assert_true(row.contains("\"row_count\":2"))
  assert_true(row.contains(output.content_cid))
  assert_true(result_export.next().unwrap() is None)
  result_export.finish().unwrap() |> ignore
  assert_eq(result_export.row_count().unwrap(), 1)
  result_export.cancel()
  assert_true(cleanup_installed_managed_terminal_serialization(run).unwrap())
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(f.parent.ledger).live_reservations, 0)
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
test "terminal Content Store funds only the original prefix at its exact remaining byte limit" {
  let f = request_serialization_plan_fixture()
  let selected = prepare_request_terminal_serialization_plan(
    f.parent,
    f.input,
    f.request,
    f.compiled,
    f.definition,
  ).unwrap()
  complete_request_serialization_preparation(f.parent, f.input, selected).unwrap()
  assert_false(@resources.return_preparation_body_borrow(f.holder).unwrap())
  let run = begin_request_content_managed_run(f.parent, f.request).unwrap()
  let units : @execution.PreparationRepresentationUnits = {
    record_headers: 0L,
    reference_slots: 0L,
    scalar_words: 0L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 64L,
  }
  let ledger = f.parent.ledger
  let unentered = @resources.ledger_usage(ledger)
  assert_true(
    fund_terminal_serialization_store(
      run,
      f.request,
      f.compiled,
      f.definition,
      units,
    )
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(ledger), unentered)
  let (_, prefix, _) = start_installed_managed_terminal_serialization(
    run,
    f.request,
    f.compiled,
    f.definition,
  ).unwrap()
  // Native asks for Store backing after the prefix really completed. An
  // unadvanced child can still owe its original physical stop.
  let mut complete = false
  for _ in 0..<1000 {
    match advance_client_serialization_prefix(prefix, 1).unwrap() {
      @local.Complete(_, ..) => {
        complete = true
        break
      }
      @local.Continue(..) | @local.Settling(_, ..) => ()
      _ => fail("terminal Content prefix did not complete")
    }
  }
  assert_true(complete)
  let original = @resources.ledger_usage(ledger)
  let foreign = request_serialization_plan_fixture()
  assert_true(
    fund_terminal_serialization_store(
      run,
      f.request,
      foreign.compiled,
      f.definition,
      units,
    )
    is Err(ForeignOriginal),
  )
  assert_eq(@resources.ledger_usage(ledger), original)
  terminal_output_fixture_cleanup(foreign)
  let ceiling = @resources.ledger_limits(ledger)
  let retained = ceiling.retained_bytes -
    original.held_bytes -
    original.reserved_retention_bytes
  let execution = ceiling.execution_bytes - original.reserved_execution_bytes
  let blocker = @resources.reserve_capacity(
    ledger,
    retained - 64L,
    execution - 63L,
  ).unwrap()
  let short = @resources.ledger_usage(ledger)
  assert_true(
    fund_terminal_serialization_store(
      run,
      f.request,
      f.compiled,
      f.definition,
      units,
    )
    is Err(Ledger(ExecutionLimit)),
  )
  assert_eq(@resources.ledger_usage(ledger), short)
  @resources.settle_capacity(ledger, blocker).unwrap()
  let blocker = @resources.reserve_capacity(
    ledger,
    retained - 64L,
    execution - 64L,
  ).unwrap()
  let before = @resources.ledger_usage(ledger)
  fund_terminal_serialization_store(
    run,
    f.request,
    f.compiled,
    f.definition,
    units,
  ).unwrap()
  let after = @resources.ledger_usage(ledger)
  assert_eq(
    after.reserved_retention_bytes,
    before.reserved_retention_bytes + 64L,
  )
  assert_eq(
    after.reserved_execution_bytes,
    before.reserved_execution_bytes + 64L,
  )
  assert_eq(after.live_reservations, before.live_reservations)
  assert_eq(after.attempts, before.attempts)
  fund_terminal_serialization_store(
    run,
    f.request,
    f.compiled,
    f.definition,
    units,
  ).unwrap()
  assert_eq(@resources.ledger_usage(ledger), after)
  @resources.settle_capacity(ledger, blocker).unwrap()
  assert_true(cleanup_installed_managed_terminal_serialization(run).unwrap())
  retire_installed_managed_run(run).unwrap()
  let closed = @resources.ledger_usage(ledger)
  assert_eq(closed.live_reservations, 0)
  assert_eq(closed.reserved_retention_bytes, 0L)
  assert_eq(closed.reserved_execution_bytes, 0L)
}

///|
test "Content output demand exact and one-short fund the constructor before any projection" {
  // Independent fixed carrier census, not product-produced expected bytes.
  let retained = 13L * 16L + (16L + 70L) * 8L
  let execution = 82L * 16L + (83L + 325L) * 8L
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
          Some(client_terminal_serialization_workspace_limits())
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
        Some(client_terminal_serialization_workspace_limits())
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
            () => Some(client_terminal_serialization_workspace_limits()),
          )
          is Err(ForeignOriginal)
        projected.val = true
        Some(client_terminal_serialization_workspace_limits())
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
        () => Some(client_terminal_serialization_workspace_limits()),
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
      Some(client_terminal_serialization_workspace_limits())
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
    () => Some(client_terminal_serialization_workspace_limits()),
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
  let profile = client_terminal_serialization_workspace_limits()
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
    () => Some(client_terminal_serialization_workspace_limits()),
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
  let template = client_terminal_serialization_workspace_limits()
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
