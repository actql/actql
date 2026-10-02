///|
test "Infer boundary preserves checked suffix coordinates without becoming Compute" {
  let source = infer_fixture_program
    .replace(
      old="\"as\":\"captured\"}],",
      new="\"as\":\"captured\"},{\"select\":[\"id\",\"outcome\",\"value\"],\"as\":\"projected\"}],",
    )
    .replace(old="\"from\":\"captured\"", new="\"from\":\"projected\"")
  assert_true(source != infer_fixture_program)
  let prepared = fixture_prepared(source~)
  let owner = @publication_host.client_infer_prefix_owner(prepared, 0, 2).unwrap()
  let limits = @publication_host.client_standard_values_sequence_limits()
  assert_true(
    @lower.prepare_sequence(owner, limits)
    is Err(@lower.KernelFailure(2, @lower.MissingKernelNode)),
  )
  let sequence = @lower.prepare_sequence_with_infer_boundary(owner, 2, limits).unwrap()
  assert_true(physical_equal(@lower.sequence_owner(sequence), owner))
  assert_eq(@lower.sequence_count(sequence), 4)
  assert_true(
    @lower.sequence_step(sequence, 2) is Some(@lower.InferBoundary(2)),
  )
  assert_true(@lower.sequence_step(sequence, 3) is Some(@lower.RowStep(_)))
  assert_true(
    @lower.prepare_sequence_with_infer_boundary(owner, 1, limits)
    is Err(@lower.KernelFailure(1, @lower.MissingKernelNode)),
  )
  let writer = @encode.writer(100000, 10000, 100)
  let rejected = try {
    @lower.emit_sequence_steps(sequence, writer)
    false
  } catch {
    @encode.InvalidStructure => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "bounded Compute suffix consumes exact Infer output without redispatch" {
  let source = infer_fixture_program
    .replace(
      old="\"as\":\"captured\"}],",
      new="\"as\":\"captured\"},{\"select\":[\"id\",\"outcome\",\"value\"]},{\"select\":[\"id\",\"outcome\"],\"as\":\"projected\"}],",
    )
    .replace(
      old="\"from\":\"captured\",\"fields\":[\"id\",\"outcome\",\"value\"]",
      new="\"from\":\"projected\",\"fields\":[\"id\",\"outcome\"]",
    )
  let prepared = fixture_prepared(source~)
  let sequence = @input.prepare_client_infer_suffix(
    prepared, 2, infer_fixture_registry, infer_fixture_values,
  ).unwrap()
  let limits = standard_limits()
  assert_true(
    @input.start_client_infer_suffix(
      sequence,
      [],
      limits.input,
      limits.measurement,
    )
    is Err(@input.UnsupportedProgram),
  )
  let calls = Ref(0)
  let active = fixture_start(prepared, () => calls.val += 1)
  guard fixture_finish(active) is Complete(inferred, ..) else {
    abort("expected model output")
  }
  let output_use = acquire_output(active).unwrap()
  let child = @input.start_client_infer_suffix(
    sequence,
    [inferred],
    limits.input,
    limits.measurement,
  ).unwrap()
  let mut result = None
  for _ in 0..<2000 {
    match @local.advance_managed_provider(child, 1).unwrap() {
      @local.Continue(work~, ..) => assert_true(work <= 1L)
      @local.Complete(output, work~, ..) => {
        assert_true(work <= 1L)
        result = Some(output)
        break
      }
      _ => abort("expected bounded suffix success")
    }
  }
  let result = result.unwrap()
  assert_eq(@relation.completed_row_count(result), 1)
  assert_eq(@relation.completed_column_count(result), 2)
  assert_true(
    @relation.completed_cell(result, 0, 0) is Some(@relation.Text("a")),
  )
  assert_true(
    @relation.completed_cell(result, 0, 1) is Some(@relation.Text("ok")),
  )
  assert_eq(calls.val, 1)
  assert_true(!cleanup(active).unwrap())
  assert_true(@local.cleanup_managed_provider(child).unwrap())
  assert_true(release_output(output_use))
  assert_true(cleanup(active).unwrap())
  assert_eq(calls.val, 1)
}

///|
test "Infer execution owns the suffix across completion and cancellation" {
  let source = infer_fixture_program
    .replace(
      old="\"as\":\"captured\"}],",
      new="\"as\":\"captured\"},{\"select\":[\"id\",\"outcome\",\"value\"]},{\"select\":[\"id\",\"outcome\"],\"as\":\"projected\"}],",
    )
    .replace(
      old="\"from\":\"captured\",\"fields\":[\"id\",\"outcome\",\"value\"]",
      new="\"from\":\"projected\",\"fields\":[\"id\",\"outcome\"]",
    )
  for cancelled in [false, true] {
    let prepared = fixture_prepared(source~)
    let plan = call_identity_plan(prepared)
    let wire = @publication_host.client_infer_plan_graph_wire(plan)
    assert_true(wire.contains("\"node_id\":\"task_0_after_infer_3\""))
    assert_true(wire.contains("\"node_id\":\"task_0_after_infer_4\""))
    assert_true(
      wire.contains(
        "\"from\":{\"node_id\":\"task_0_infer_2\",\"port\":\"infer_2\"}",
      ),
    )
    let sequence = @input.prepare_client_infer_suffix(
      prepared, 2, infer_fixture_registry, infer_fixture_values,
    ).unwrap()
    let calls = Ref(0)
    let active = fixture_start(prepared, () => calls.val += 1)
    bind_compute_suffix(active, sequence).unwrap()
    assert_true(bind_compute_suffix(active, sequence) is Err(InvalidAdvance))
    let mut last = 0L
    for _ in 0..<2000 {
      if active.phase is Compute {
        break
      }
      guard advance(active, 1).unwrap() is Continue(work~) else {
        abort("expected progress before suffix")
      }
      assert_true(work >= last && work - last <= 1L)
      last = work
    }
    assert_true(active.phase is Compute)
    assert_eq(calls.val, 1)
    assert_true(acquire_output(active) is None)
    assert_true(!cleanup(active).unwrap())
    if cancelled {
      assert_true(cancel(active))
      assert_true(!execution_stopped(active))
      assert_true(fixture_finish(active, initial_work=last) is Stopped(..))
      assert_true(acquire_output(active) is None)
    } else {
      guard fixture_finish(active, initial_work=last) is Complete(result, ..) else {
        abort("expected completed suffix")
      }
      assert_eq(@relation.completed_column_count(result), 2)
      assert_true(
        @relation.completed_cell(result, 0, 0) is Some(@relation.Text("a")),
      )
      assert_true(
        @relation.completed_cell(result, 0, 1) is Some(@relation.Text("ok")),
      )
    }
    assert_true(execution_stopped(active))
    assert_true(cleanup(active).unwrap())
    assert_true(cleanup(active).unwrap())
    assert_eq(calls.val, 1)
  }
}
