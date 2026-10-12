///|
fn serialization_preparation_test_program(
  detour? : Bool = false,
  empty? : Bool = false,
  ordered? : Bool = false,
  projected? : Bool = false,
  consumer? : Bool = false,
) -> PreparedClientProgram raise {
  let environment = admit_client_check_environment(
    run_materials_environment_wire,
    run_materials_environment_cid,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"content-preparation","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":2},{"id":1}]},"as":"seed"},{"serialize":{"format":"jsonl","fields":["id"],"name":"out.jsonl","preserve_order":true,"bounds":{"max_rows":2,"max_bytes":128}},"as":"attachment"}],"results":{"file":{"from":"attachment","fields":["name","content","media_type","size_bytes","row_count"]}}}],"results":{"file":{"from":{"stage":"main","result":"file"}}}}
  let document = if detour {
    document.replace(
      old="{\"serialize\":",
      new="{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":9}]},\"as\":\"other\"},{\"from\":\"seed\",\"serialize\":",
    )
  } else {
    document
  }
  let document = if empty {
    document.replace(old="[{\"id\":2},{\"id\":1}]", new="[]")
  } else {
    document
  }
  let document = if ordered {
    document.replace(
      old="\"preserve_order\":true",
      new="\"order_by\":[{\"id\":\"asc\"}]",
    )
  } else {
    document
  }
  let document = if projected {
    document.replace(
      old="[\"name\",\"content\",\"media_type\",\"size_bytes\",\"row_count\"]",
      new="[\"name\",\"content\"]",
    )
  } else {
    document
  }
  let document = if consumer {
    document
    .replace(
      old="\"as\":\"attachment\"}],\"results\"",
      new="\"as\":\"attachment\"},{\"select\":[\"name\",\"content\"],\"as\":\"consumer\"}],\"results\"",
    )
    .replace(old="\"from\":\"attachment\"", new="\"from\":\"consumer\"")
    .replace(
      old="[\"name\",\"content\",\"media_type\",\"size_bytes\",\"row_count\"]",
      new="[\"name\",\"content\"]",
    )
  } else {
    document
  }
  match
    prepare_effect_free_client_program(
      document,
      Json,
      environment,
      None,
      client_standard_program_preparation_limits(),
    ) {
    Ok(value) => value
    Err(Check(diagnostic)) =>
      match @checked.diagnostic_cause(diagnostic) {
        Units(issue) => raise issue
        issue => raise issue
      }
    Err(Graph(_)) => fail("Graph preparation failure")
    Err(_) => fail("unexpected preparation failure")
  }
}

///|
test "Serialize task boundary retains original kernels without claiming generation completion" {
  let owner = serialization_preparation_test_program(consumer=true)
  let barrier = prepare_client_serialization(owner, 0, 1, max_work=3).unwrap()
  let original = @lower.serialization_owner(barrier)
  let limits = run_materials_limits().sequence
  let sequence = @lower.prepare_sequence_with_serialization_boundary(
    original, 1, limits,
  ).unwrap()
  assert_true(physical_equal(@lower.sequence_owner(sequence), original))
  assert_eq(@lower.sequence_count(sequence), 3)
  assert_true(@lower.sequence_step(sequence, 0) is Some(@lower.ValuesStep(_)))
  assert_true(
    @lower.sequence_step(sequence, 1) is Some(@lower.SerializationBoundary(1)),
  )
  assert_true(@lower.sequence_step(sequence, 2) is Some(@lower.RowStep(_)))
  assert_true(@lower.sequence_serialization_input_kernel(sequence, 1) is None)
  assert_true(
    @lower.prepare_fragment_pipeline(sequence, 1, {
      max_roots: 100,
      max_pointer_bytes: 10000,
      max_work: 100000,
    })
    is Err(@lower.NotExpressionKernel),
  )
  let writer = @encode.writer(10000, 1000, 100)
  let emitted = try {
    @lower.emit_sequence_node(sequence, 1, writer)
    true
  } catch {
    _ => false
  }
  assert_false(emitted)
  let registry = @execution.admit_relation_registry(
    parse_plan_identity_value(
      compiler_registered_body_wire(),
      100000,
      10000,
      100,
    ).unwrap(),
    parse_plan_identity_value(
      compiler_registered_values_wire(),
      100000,
      10000,
      100,
    ).unwrap(),
    { max_body_bytes: 100000, max_body_nodes: 10000, max_body_depth: 100, },
  ).unwrap()
  let terminal = @lower.node_at(@lower.bound_preparation(original), 2).unwrap()
  let generated = @execution.prepare_generated_sequence(
    registry,
    sequence,
    [],
    [@lower.node_id(terminal)],
    100000,
    10000,
  ).unwrap()
  let values : @execution.ValueLimits = {
    max_nodes: 1000,
    max_text_bytes: 10000,
    max_depth: 100,
    max_work: 100000,
  }
  let execution : @execution.SequenceExecutionLimits = {
    rows: {
      max_rows: 2,
      metadata_entries: 1000,
      retained_entries: 1000,
      operation_entries: 1000,
      input_values: values,
      output_values: values,
    },
    max_work: 100000,
    max_frames: 100,
  }
  assert_true(
    @execution.execute_generated_sequence(generated, [], execution) is Err(_),
  )
  assert_true(
    @local.local_bounded_relation_provider(
      execution,
      { max_work: 100000, max_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      generated,
    )
    is None,
  )
  // Selection metadata cannot replace real generation or admit pure execution.
  assert_true(
    @lower.prepare_sequence(original, limits)
    is Err(@lower.KernelFailure(1, @lower.MissingKernelNode)),
  )
  for step in [-1, 0, 2, 3] {
    assert_true(
      @lower.prepare_sequence_with_serialization_boundary(
        original, step, limits,
      )
      is Err(_),
    )
  }
  assert_true(
    @lower.prepare_sequence_with_serialization_boundary(original, 1, {
      ..limits,
      max_steps: 2,
    })
    is Err(@lower.SequenceLimit),
  )
}

///|
test "Serialize consumer lowering keeps generation outside pure Compute" {
  let owner = serialization_preparation_test_program(consumer=true)
  let barrier = prepare_client_serialization(owner, 0, 1, max_work=3).unwrap()
  let original = @lower.serialization_owner(barrier)
  let limits = run_materials_limits().sequence
  let sequence = @lower.prepare_serialization_consumer_sequence(
    original, 1, 2, limits,
  ).unwrap()
  assert_eq(@lower.sequence_count(sequence), 3)
  assert_true(
    @lower.sequence_step(sequence, 0)
    is Some(@lower.CompletedProducerBoundary(0)),
  )
  assert_true(
    @lower.sequence_step(sequence, 1)
    is Some(@lower.CompletedProducerBoundary(1)),
  )
  assert_true(@lower.sequence_step(sequence, 2) is Some(@lower.RowStep(_)))
  // Preparing a suffix must not make whole-sequence execution admissible.
  assert_true(
    @lower.prepare_sequence(original, limits)
    is Err(@lower.KernelFailure(1, @lower.MissingKernelNode)),
  )
  for (producer, terminal) in [(0, 2), (1, 1), (1, 3), (-1, 2)] {
    assert_true(
      @lower.prepare_serialization_consumer_sequence(
        original, producer, terminal, limits,
      )
      is Err(_),
    )
  }
}

///|
test "Serialize whole input rejects partial completion skipped and repeated rows" {
  for quantum in [1, 7, 64] {
    let owner = serialization_preparation_test_program()
    let barrier = prepare_client_serialization(owner, 0, 1, max_work=3).unwrap()
    let (active, output) = serialization_completed_test_input(barrier)
    let encoder = start_client_serialization_encoder(
      barrier,
      max_rows=2,
      max_bytes=18,
      max_value_nodes=100,
      max_value_depth=10,
      max_frames=20,
    ).unwrap()
    let input = bind_client_serialization_completed_input(
      barrier, output, encoder,
    ).unwrap()
    assert_eq(client_serialization_input_rows(input), 2)
    assert_true(
      bind_client_serialization_completed_input(barrier, output, encoder)
      is Err(Encoding(ContentBusy)),
    )
    assert_eq(serialization_test_drain(encoder), "")
    assert_true(
      @publication.finish_content_bytes(encoder) is Err(ContentIncompleteInput),
    )
    assert_true(
      start_client_serialization_input_row(input, 1) is Err(InvalidRow),
    )
    start_client_serialization_input_row(input, 0).unwrap()
    assert_true(
      start_client_serialization_input_row(input, 0)
      is Err(Encoding(ContentBusy)),
    )
    let bytes = StringBuilder()
    let mut work = 0
    for row in 0..<2 {
      if row == 1 {
        assert_true(
          @publication.finish_content_bytes(encoder)
          is Err(ContentIncompleteInput),
        )
        assert_true(
          start_client_serialization_input_row(input, 0) is Err(InvalidRow),
        )
        start_client_serialization_input_row(input, 1).unwrap()
      }
      for _ in 0..<10000 {
        match @publication.advance_content_bytes(encoder, quantum) {
          ContentBytesContinue(piece, work=used) => {
            bytes.write_string(piece)
            work += used
          }
          ContentBytesReady(piece, work=used) => {
            bytes.write_string(piece)
            work += used
            break
          }
          ContentBytesFailed(_, ..) => fail("whole input generation failed")
        }
      }
    }
    assert_true(work > 0)
    assert_eq(bytes.to_string(), "{\"id\":2}\n{\"id\":1}\n")
    let complete = @publication.finish_content_bytes(encoder).unwrap()
    assert_eq((complete.row_count, complete.size_bytes), (2, 18))
    assert_eq(
      complete.content_cid,
      "sha256:982974408fc3063d258439d976049c7f4863d98bedfe933132af17b3636ffd60",
    )
    assert_true(@execution.completed_output_available(output))
    assert_true(@execution.cleanup_bounded_values(active).unwrap())
  }
}

///|
test "Serialize whole input binds typed empty completion and its lifetime" {
  let owner = serialization_preparation_test_program(empty=true)
  let barrier = prepare_client_serialization(owner, 0, 1, max_work=3).unwrap()
  let (active, output) = serialization_completed_test_input(barrier)
  for revoke_after_header in [false, true] {
    let live = Ref(true)
    let borrow = @execution.restrict_completed_output(output, () => live.val)
    let encoder = start_client_serialization_encoder(
      barrier,
      max_rows=0,
      max_bytes=0,
      max_value_nodes=100,
      max_value_depth=10,
      max_frames=20,
    ).unwrap()
    let input = bind_client_serialization_completed_input(
      barrier, borrow, encoder,
    ).unwrap()
    assert_eq(client_serialization_input_rows(input), 0)
    assert_true(
      start_client_serialization_input_row(input, 0) is Err(InvalidRow),
    )
    if revoke_after_header {
      assert_eq(serialization_test_drain(encoder), "")
    }
    live.val = false
    if revoke_after_header {
      assert_true(
        @publication.finish_content_bytes(encoder)
        is Err(ContentInputUnavailableIssue),
      )
    } else {
      assert_true(
        @publication.advance_content_bytes(encoder, 1)
        is ContentBytesFailed(ContentInputUnavailableIssue, work=0),
      )
    }
    assert_true(
      @publication.finish_content_bytes(encoder)
      is Err(ContentInputUnavailableIssue),
    )
    assert_true(@execution.completed_output_available(output))
  }
  let encoder = start_client_serialization_encoder(
    barrier,
    max_rows=0,
    max_bytes=0,
    max_value_nodes=100,
    max_value_depth=10,
    max_frames=20,
  ).unwrap()
  ignore(
    bind_client_serialization_completed_input(barrier, output, encoder).unwrap(),
  )
  assert_eq(serialization_test_drain(encoder), "")
  let complete = @publication.finish_content_bytes(encoder).unwrap()
  assert_eq((complete.row_count, complete.size_bytes), (0, 0))
  assert_eq(
    complete.content_cid,
    "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  assert_true(@execution.cleanup_bounded_values(active).unwrap())
}

///|
test "Serialize whole input rejects foreign completion ceilings and unrealized sort" {
  let owner = serialization_preparation_test_program()
  let barrier = prepare_client_serialization(owner, 0, 1, max_work=3).unwrap()
  let (active, output) = serialization_completed_test_input(barrier)
  let encoder = start_client_serialization_encoder(
    barrier,
    max_rows=1,
    max_bytes=128,
    max_value_nodes=100,
    max_value_depth=10,
    max_frames=20,
  ).unwrap()
  assert_true(
    bind_client_serialization_completed_input(barrier, output, encoder)
    is Err(Encoding(ContentRowLimit)),
  )
  let other = prepare_client_serialization(
    serialization_preparation_test_program(),
    0,
    1,
    max_work=3,
  ).unwrap()
  assert_true(
    bind_client_serialization_completed_input(other, output, encoder)
    is Err(ForeignInput),
  )
  let ordered = prepare_client_serialization(
    serialization_preparation_test_program(ordered=true),
    0,
    1,
    max_work=3,
  ).unwrap()
  let (ordered_active, ordered_output) = serialization_completed_test_input(
    ordered,
  )
  let ordered_encoder = start_client_serialization_encoder(
    ordered,
    max_rows=2,
    max_bytes=128,
    max_value_nodes=100,
    max_value_depth=10,
    max_frames=20,
  ).unwrap()
  assert_true(
    bind_client_serialization_completed_input(
      ordered, ordered_output, ordered_encoder,
    )
    is Err(InputOrderUnfulfilled),
  )
  assert_true(@execution.cleanup_bounded_values(ordered_active).unwrap())
  assert_true(@execution.cleanup_bounded_values(active).unwrap())
}

///|
test "Serialize Program keeps the exact checked task input without pure Compute encoding" {
  let owner = serialization_preparation_test_program()
  assert_eq(@strategy.graph_task_count(owner.graph), 1)
  let barrier = prepare_client_serialization(owner, 0, 1, max_work=3).unwrap()
  assert_true(
    physical_equal(
      @lower.serialization_owner(barrier),
      @strategy.graph_task_owner(owner.graph, 0).unwrap(),
    ),
  )
  assert_eq(@lower.serialization_author_guards(barrier), (Some(2L), Some(128L)))
  assert_eq(
    @pipeline.serialization_order_input(@lower.serialization_order(barrier)),
    Step(0),
  )
  assert_eq(prepared_client_result_count(owner), 1)
  assert_eq(prepared_client_result_name(owner, 0), Some("file"))
  assert_true(
    prepare_client_serialization(owner, 1, 1, max_work=3) is Err(MissingTask),
  )
  assert_true(
    prepare_client_serialization(owner, 0, 2, max_work=3) is Err(OutsideTask),
  )
  assert_true(
    prepare_client_serialization(owner, 0, 0, max_work=3)
    is Err(Barrier({ kind: NotSerialization, .. })),
  )
  assert_true(
    @lower.prepare_sequence(
      @lower.serialization_owner(barrier),
      run_materials_limits().sequence,
    )
    is Err(KernelFailure(1, MissingKernelNode)),
  )
}

///|
test "Serialize prefix follows the bound input instead of the previous step" {
  let owner = serialization_preparation_test_program(detour=true)
  let barrier = prepare_client_serialization(owner, 0, 2, max_work=3).unwrap()
  assert_eq(
    @pipeline.serialization_order_input(@lower.serialization_order(barrier)),
    Step(0),
  )
  let limits = { ..run_materials_limits().sequence, max_steps: 2, }
  let fragment = issue_prepared_client_serialization_prefix_fragment(
    owner, 0, 2, 3, limits, 100000, 10000, 100,
  ).unwrap()
  assert_eq(fragment.node_id, "task_0_before_serialize_2")
  let input = @lower.node_at(
    @lower.bound_preparation(@lower.serialization_owner(barrier)),
    0,
  ).unwrap()
  assert_eq(fragment.output_port, @lower.node_id(input))
  assert_eq(fragment.output_carrier, "relation")
  assert_true(!fragment.wire.contains("Content.serialize"))
  // The output is the earlier input but all preceding authored work stays in
  // the fragment. No liveness pruning can suppress failure or its work charge.
  assert_true(fragment.wire.contains("values_1"))
  assert_true(
    issue_prepared_client_serialization_prefix_fragment(
      owner,
      0,
      2,
      3,
      { ..limits, max_steps: 1, },
      100000,
      10000,
      100,
    )
    is Err(Fragment(Pipeline(Sequence(SequenceLimit)))),
  )
  assert_true(
    issue_prepared_client_serialization_prefix_fragment(
      owner, 0, 2, 2, limits, 100000, 10000, 100,
    )
    is Err(Preparation(Barrier({ kind: BudgetExceeded, .. }))),
  )
  assert_true(
    issue_prepared_client_serialization_prefix_fragment(
      owner, 0, 2, 3, limits, 0, 10000, 100,
    )
    is Err(Fragment(InvalidLimits)),
  )
}

///|
fn serialization_completed_test_input(
  barrier : @lower.PreparedSerialization,
) -> (@execution.BoundedValuesExecution, @execution.CompletedOutput) raise {
  let registry = @execution.admit_relation_registry(
    parse_plan_identity_value(
      compiler_registered_body_wire(),
      100000,
      10000,
      100,
    ).unwrap(),
    parse_plan_identity_value(
      compiler_registered_values_wire(),
      100000,
      10000,
      100,
    ).unwrap(),
    { max_body_bytes: 100000, max_body_nodes: 10000, max_body_depth: 100, },
  ).unwrap()
  let owner = @lower.serialization_owner(barrier)
  let sequence = @lower.prepare_sequence_prefix(
    owner,
    0,
    run_materials_limits().sequence,
  ).unwrap()
  let node = @lower.node_at(@lower.bound_preparation(owner), 0).unwrap()
  let generated = @execution.prepare_generated_sequence(
    registry,
    sequence,
    [],
    [@lower.node_id(node)],
    100000,
    10000,
  ).unwrap()
  let values : @execution.ValueLimits = {
    max_nodes: 1000,
    max_text_bytes: 10000,
    max_depth: 100,
    max_work: 100000,
  }
  // The synchronous full-Stage driver deliberately requires complete wiring.
  // Use the installed bounded operation owner for this checked prefix instead
  // of weakening that driver's full-sequence invariant.
  let active = @execution.start_bounded_values(
    @bounded.control(),
    generated,
    2,
    values,
    values,
    100000,
    100,
    1000,
    10000,
  ).unwrap()
  for _ in 0..<10000 {
    match @execution.advance_bounded_values(active, 1).unwrap() {
      BoundedValuesContinue(..) => ()
      BoundedValuesComplete(output, ..) => return (active, output)
      _ => fail("bounded Compute prefix did not complete")
    }
  }
  fail("bounded Compute prefix exceeded the fixture poll ceiling")
}

///|
fn serialization_test_drain(
  encoder : @publication.ContentByteEncoder,
) -> String raise {
  let output = StringBuilder()
  for _ in 0..<10000 {
    match @publication.advance_content_bytes(encoder, 1) {
      ContentBytesContinue(piece, ..) => output.write_string(piece)
      ContentBytesReady(piece, ..) => {
        output.write_string(piece)
        return output.to_string()
      }
      ContentBytesFailed(_, ..) => fail("unexpected content generation failure")
    }
  }
  fail("bounded serialization fixture did not finish")
}

///|
test "Serialize encoder uses finite Host ceilings without relaxing author guards" {
  let owner = serialization_preparation_test_program()
  let barrier = prepare_client_serialization(owner, 0, 1, max_work=3).unwrap()
  let (active, input) = serialization_completed_test_input(barrier)
  let encoder = start_client_serialization_encoder(
    barrier,
    max_rows=1,
    max_bytes=128,
    max_value_nodes=100,
    max_value_depth=10,
    max_frames=20,
  ).unwrap()
  assert_eq(serialization_test_drain(encoder), "")
  start_client_serialization_completed_row(barrier, input, 0, encoder).unwrap()
  assert_eq(serialization_test_drain(encoder), "{\"id\":2}\n")
  assert_true(
    start_client_serialization_completed_row(barrier, input, 1, encoder)
    is Err(Encoding(ContentRowLimit)),
  )
  assert_true(
    @publication.finish_content_bytes(encoder) is Err(ContentRowLimit),
  )
  let author_limited = start_client_serialization_encoder(
    barrier,
    max_rows=100,
    max_bytes=10000,
    max_value_nodes=100,
    max_value_depth=10,
    max_frames=20,
  ).unwrap()
  assert_eq(serialization_test_drain(author_limited), "")
  for row in 0..<2 {
    start_client_serialization_completed_row(
      barrier, input, row, author_limited,
    ).unwrap()
    ignore(serialization_test_drain(author_limited))
  }
  assert_eq(
    @publication.finish_content_bytes(author_limited).unwrap().row_count,
    2,
  )
  assert_true(@execution.completed_output_available(input))
  assert_true(@execution.cleanup_bounded_values(active).unwrap())
  assert_true(!@execution.bounded_values_cleanup_pending(active))
}

///|
test "Serialize borrows the exact executed prefix into the common byte encoder" {
  let owner = serialization_preparation_test_program(detour=true)
  let barrier = prepare_client_serialization(owner, 0, 2, max_work=3).unwrap()
  let (active, input) = serialization_completed_test_input(barrier)
  let profile = @pipeline.serialization_profile(
    @lower.serialization_checked(barrier),
  )
  let encoder = @publication.start_content_byte_encoder(
    profile,
    max_rows=2,
    max_bytes=18,
    max_value_nodes=100,
    max_value_depth=10,
    max_frames=20,
  ).unwrap()
  assert_eq(serialization_test_drain(encoder), "")
  let output = StringBuilder()
  for row in 0..<2 {
    start_client_serialization_completed_row(barrier, input, row, encoder).unwrap()
    output.write_string(serialization_test_drain(encoder))
  }
  assert_eq(output.to_string(), "{\"id\":2}\n{\"id\":1}\n")
  let completion = @publication.finish_content_bytes(encoder).unwrap()
  assert_eq((completion.size_bytes, completion.row_count), (18, 2))
  // Independent SHA-256 of the literal UTF-8 vector, not encoder output.
  assert_eq(
    completion.content_cid,
    "sha256:982974408fc3063d258439d976049c7f4863d98bedfe933132af17b3636ffd60",
  )
  assert_true(@execution.completed_output_available(input))
  let other = prepare_client_serialization(
    serialization_preparation_test_program(detour=true),
    0,
    2,
    max_work=3,
  ).unwrap()
  assert_true(
    start_client_serialization_completed_row(other, input, 0, encoder)
    is Err(ForeignInput),
  )
  assert_true(
    start_client_serialization_completed_row(barrier, input, 2, encoder)
    is Err(InvalidRow),
  )
  let live = Ref(true)
  let restricted = @execution.restrict_completed_output(input, () => live.val)
  let encoder = @publication.start_content_byte_encoder(
    profile,
    max_rows=2,
    max_bytes=18,
    max_value_nodes=100,
    max_value_depth=10,
    max_frames=20,
  ).unwrap()
  ignore(serialization_test_drain(encoder))
  start_client_serialization_completed_row(barrier, restricted, 0, encoder).unwrap()
  ignore(@publication.advance_content_bytes(encoder, 1))
  live.val = false
  assert_true(
    @publication.advance_content_bytes(encoder, 1)
    is ContentBytesFailed(ContentInputUnavailableIssue, work=0),
  )
  assert_true(
    @publication.finish_content_bytes(encoder)
    is Err(ContentInputUnavailableIssue),
  )
  assert_true(@execution.completed_output_available(input))
  assert_true(@execution.cleanup_bounded_values(active).unwrap())
  assert_true(!@execution.bounded_values_cleanup_pending(active))
}
