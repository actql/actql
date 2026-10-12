///|
/// Produce, export and readmit a real checked completion. The generated
/// contract bodies are authoritative inputs, not generated expected work.
fn retained_content_test_fixture() -> (
  @execution.GeneratedSequence,
  ClientInferRetainedInputExport,
) raise {
  let cursor = @decode.admit(
    @source.parse_json(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":9}]},\"as\":\"seed\"}]",
      { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      source_path="retained-content-work.json",
    ).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
  let checked = @pipeline.check(cursor, [], None, None, {
    max_steps: 100,
    max_work: 10000,
    max_text_bytes: 10000,
    max_nodes: 1000,
    max_tokens: 1000,
    max_depth: 100,
  }).unwrap()
  let owner = @lower.bind_parameters(
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
  let sequence = @lower.prepare_sequence(
    owner,
    @publication_host.client_standard_values_sequence_limits(),
  ).unwrap()
  let contracts = @execution.admit_relation_registry(
    content_recovery_registered_body(),
    content_recovery_registered_values(),
    { max_body_bytes: 100000, max_body_nodes: 10000, max_body_depth: 100, },
  ).unwrap()
  let generated = @execution.prepare_generated_sequence(
    contracts,
    sequence,
    [],
    [
      @lower.node_id(
        @lower.node_at(@lower.bound_preparation(owner), 0).unwrap(),
      ),
    ],
    100000,
    10000,
  ).unwrap()
  let output = @execution.completed_output(
    @execution.execute_generated_sequence(generated, [], {
      rows: {
        max_rows: 100,
        metadata_entries: 10000,
        retained_entries: 10000,
        operation_entries: 10000,
        input_values: source_capture_values(),
        output_values: source_capture_values(),
      },
      max_work: 100000,
      max_frames: 100,
    }).unwrap(),
    @pipeline.Step(0),
  ).unwrap()
  let exported = export_client_infer_retained_input(output, "original-custody").unwrap()
  // Each row measurement charges row root(1) + UTF-8 name "id"(2) +
  // numeric scalar(1) = 4. Retained read(4), import row buffer(4), import
  // verification stream(4) and handoff(1) independently fix total work=13.
  let descriptor = read_client_infer_retained_input_descriptor(
    exported.descriptor_wire,
  ).unwrap()
  assert_eq(descriptor.values.work, 4)
  assert_eq(exported.rows, ["{\"id\":9}"])
  (generated, exported)
}

///|
fn retained_content_test_input() -> (ClientInferRetainedInput, Ref[Bool]) raise {
  let (generated, exported) = retained_content_test_fixture()
  let custody = Ref(true)
  let actual_work = Ref(0L)
  let retained = restore_client_retained_completion(
    @execution.generated_completion_preparation(generated),
    0,
    "original-custody",
    exported.binding,
    exported.descriptor_wire,
    exported.rows,
    () => custody.val,
    value_work_limit=Some(4),
    report_work=work => actual_work.val = work,
  ).unwrap()
  assert_eq(actual_work.val, 12L)
  assert_true(
    @execution.completed_cell(retained.output, 0, 0) is Some(Number(9)),
  )
  (retained, custody)
}

///|
test "restored Content child start enforces exact whole allowance before real readmission" {
  for budget in [9, 12, 13] {
    let (generated, exported) = retained_content_test_fixture()
    let reads = Ref(0)
    let observed_limit = Ref(-1)
    let closes = Ref(0)
    let observed_work = Ref(0L)
    let started = start_client_retained_content_readmission(
      4,
      budget,
      () => true,
      {
        cancel: () => true,
        stopped: () => true,
        cleanup: () => {
          closes.val += 1
          Ok(true)
        },
      },
      (limit, report_work) => {
        reads.val += 1
        observed_limit.val = limit
        restore_client_retained_completion(
          @execution.generated_completion_preparation(generated),
          0,
          "original-custody",
          exported.binding,
          exported.descriptor_wire,
          exported.rows,
          () => true,
          value_work_limit=Some(limit),
          report_work=work => {
            observed_work.val = work
            report_work(work)
          },
        )
      },
    )
    if budget < 13 {
      assert_true(started is Err(@connector.Execution(@execution.InputLimit)))
      assert_eq(reads.val, 0)
      assert_eq(observed_limit.val, -1)
      assert_eq(observed_work.val, 0L)
      assert_eq(closes.val, 0)
    } else {
      let child = started.unwrap()
      assert_eq(reads.val, 1)
      assert_eq(observed_limit.val, 4)
      assert_eq(observed_work.val, 12L)
      let mut completed = false
      for _ in 0..<14 {
        match @local.advance_managed_provider(child, 1).unwrap() {
          Continue(progress=0L, work=1L) => ()
          Complete(output, progress=1L, work=1L) => {
            assert_true(
              @execution.completed_cell(output, 0, 0) is Some(Number(9)),
            )
            completed = true
            break
          }
          _ => fail("exact startup budget did not preserve original completion")
        }
      }
      assert_true(completed)
      assert_eq(@local.managed_provider_cumulative_work(child), Ok(13L))
      assert_true(@local.cleanup_managed_provider(child).unwrap())
      assert_true(@local.cleanup_managed_provider(child).unwrap())
      assert_eq(closes.val, 1)
    }
  }
}

///|
test "restored Content child start exposes partial failed work instead of a zero-work factory error" {
  let (generated, exported) = retained_content_test_fixture()
  let reads = Ref(0)
  let child = start_client_retained_content_readmission(
    4,
    13,
    () => true,
    { cancel: () => true, stopped: () => true, cleanup: () => Ok(true), },
    (limit, report_work) => {
      reads.val += 1
      restore_client_retained_completion(
        @execution.generated_completion_preparation(generated),
        0,
        "original-custody",
        exported.binding,
        exported.descriptor_wire,
        ["{\"id\":10}"],
        () => true,
        value_work_limit=Some(limit),
        report_work~,
      )
    },
  ).unwrap()
  assert_eq(reads.val, 1)
  assert_true(
    @local.advance_managed_provider(child, 7)
    is Ok(
      Failed(@connector.Execution(@execution.InputSet), progress=0L, work=4L)
    ),
  )
  assert_eq(@local.managed_provider_cumulative_work(child), Ok(4L))
  assert_true(@local.cleanup_managed_provider(child).unwrap())
  assert_eq(@local.managed_provider_cumulative_work(child), Ok(4L))
}

///|
test "failed retained Content readmission reports only consumed work and keeps cleanup custody" {
  for phase in ["changed-row", "after-read", "after-import"] {
    for quantum in [1, 7] {
      let (generated, exported) = retained_content_test_fixture()
      let custody = Ref(true)
      let actual_work = Ref(0L)
      let expected_work = if phase == "after-import" { 12L } else { 4L }
      let rows = if phase == "changed-row" {
        ["{\"id\":10}"]
      } else {
        exported.rows
      }
      let failed = restore_client_retained_completion(
        @execution.generated_completion_preparation(generated),
        0,
        "original-custody",
        exported.binding,
        exported.descriptor_wire,
        rows,
        () => custody.val,
        value_work_limit=Some(4),
        report_work=work => {
          actual_work.val = work
          if phase != "changed-row" && work == expected_work {
            custody.val = false
          }
        },
      )
      assert_true(failed is Err(_))
      if phase == "changed-row" {
        assert_true(failed is Err(Content(@execution.IdentityMismatch)))
      }
      // One numeric row consumes 4, not the successful three-pass 12.
      // A repeated cumulative observation never becomes an extra delta.
      assert_eq(actual_work.val, expected_work)
      let physical_stop = Ref(false)
      let cancels = Ref(0)
      let closes = Ref(0)
      let child = client_retained_content_handoff(
        failed,
        () => custody.val,
        {
          cancel: () => {
            cancels.val += 1
            true
          },
          stopped: () => physical_stop.val,
          cleanup: () => {
            closes.val += 1
            if closes.val == 1 {
              Err(@connector.Execution(@execution.InputSet))
            } else {
              Ok(true)
            }
          },
        },
        actual_work.val,
      )
      let ledger = serialization_test_ledger(10L, 20L)
      let reservation = @resources.reserve_attempt(ledger, 0L, 10L, 20L).unwrap()
      let prefix = bind_serialization_prefix_reservation(
        child, ledger, reservation,
      )
      let mut terminal = false
      for _ in 0..<13 {
        match advance_client_serialization_prefix(prefix, quantum).unwrap() {
          Continue(progress=0L, ..) => ()
          Failed(_, progress=0L, ..) => {
            terminal = true
            break
          }
          _ => fail("failed readmission handed off a completion")
        }
      }
      assert_true(terminal)
      assert_eq(client_serialization_prefix_work(prefix), Ok(expected_work))
      assert_false(cleanup_client_serialization_prefix(prefix).unwrap())
      assert_eq(closes.val, 0)
      assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 20L)
      physical_stop.val = true
      assert_true(
        cleanup_client_serialization_prefix(prefix) is Err(Provider(_)),
      )
      assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 20L)
      assert_true(cleanup_client_serialization_prefix(prefix).unwrap())
      assert_true(cleanup_client_serialization_prefix(prefix).unwrap())
      assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
      assert_eq(client_serialization_prefix_work(prefix), Ok(expected_work))
      assert_eq(cancels.val, 1)
      assert_eq(closes.val, 2)
    }
  }
}

///|
test "restored Content handoff reports exact admission and completion work across quantum and preserves transferred output" {
  for quantum in [1, 7] {
    let (retained, custody) = retained_content_test_input()
    let closes = Ref(0)
    let child = client_retained_content_handoff(
      Ok(retained),
      () => custody.val,
      {
        cancel: () => true,
        stopped: () => true,
        cleanup: () => {
          closes.val += 1
          Ok(true)
        },
      },
      client_retained_content_admission_work(4, 13).unwrap(),
    )
    let mut completed = false
    for _ in 0..<14 {
      match @local.advance_managed_provider(child, quantum).unwrap() {
        Continue(progress=0L, ..) => ()
        Complete(output, progress=1L, work=1L) => {
          assert_true(physical_equal(output, retained.output))
          completed = true
          break
        }
        _ => fail("restored Content did not hand off its exact completion")
      }
    }
    assert_true(completed)
    assert_eq(@local.managed_provider_cumulative_work(child), Ok(13L))
    assert_true(@local.cleanup_managed_provider(child).unwrap())
    assert_true(@local.cleanup_managed_provider(child).unwrap())
    assert_eq(closes.val, 1)
    assert_true(retained.live.val)
    assert_true(@execution.completed_output_available(retained.output))
    assert_eq(@local.managed_provider_cumulative_work(child), Ok(13L))
    custody.val = false
    assert_false(@execution.completed_output_available(retained.output))
  }
}

///|
test "restored Content cancellation drains actual work and retains reservation until physical stop and cleanup retry" {
  let (retained, custody) = retained_content_test_input()
  let physical_stop = Ref(false)
  let cancels = Ref(0)
  let closes = Ref(0)
  let child = client_retained_content_handoff(
    Ok(retained),
    () => custody.val,
    {
      cancel: () => {
        cancels.val += 1
        true
      },
      stopped: () => physical_stop.val,
      cleanup: () => {
        closes.val += 1
        match closes.val {
          1 => Err(@connector.Execution(@execution.InputSet))
          2 => Ok(false)
          _ => Ok(true)
        }
      },
    },
    client_retained_content_admission_work(4, 13).unwrap(),
  )
  let ledger = serialization_test_ledger(10L, 20L)
  let reservation = @resources.reserve_attempt(ledger, 0L, 10L, 20L).unwrap()
  let prefix = bind_serialization_prefix_reservation(child, ledger, reservation)
  assert_true(
    advance_client_serialization_prefix(prefix, 1)
    is Ok(Continue(progress=0L, work=1L)),
  )
  assert_true(cancel_client_serialization_prefix(prefix))
  assert_false(cleanup_client_serialization_prefix(prefix).unwrap())
  assert_eq(closes.val, 0)
  for _ in 0..<10 {
    assert_true(
      advance_client_serialization_prefix(prefix, 1)
      is Ok(Continue(progress=0L, work=1L)),
    )
  }
  assert_true(
    advance_client_serialization_prefix(prefix, 1)
    is Ok(Stopped(progress=0L, work=1L)),
  )
  assert_eq(client_serialization_prefix_work(prefix), Ok(12L))
  assert_false(@local.managed_provider_stopped(child))
  assert_false(cleanup_client_serialization_prefix(prefix).unwrap())
  assert_eq(closes.val, 0)
  physical_stop.val = true
  assert_true(@local.managed_provider_stopped(child))
  assert_true(cleanup_client_serialization_prefix(prefix) is Err(Provider(_)))
  assert_false(cleanup_client_serialization_prefix(prefix).unwrap())
  assert_true(retained.live.val)
  assert_true(@execution.completed_output_available(retained.output))
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 20L)
  assert_true(cleanup_client_serialization_prefix(prefix).unwrap())
  assert_true(cleanup_client_serialization_prefix(prefix).unwrap())
  assert_false(retained.live.val)
  assert_false(@execution.completed_output_available(retained.output))
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(client_serialization_prefix_work(prefix), Ok(12L))
  assert_eq(client_serialization_prefix_work(prefix), Ok(12L))
  assert_true(
    advance_client_serialization_prefix(prefix, 1)
    is Ok(Stopped(progress=0L, work=0L)),
  )
  assert_eq(cancels.val, 1)
  assert_eq(closes.val, 3)
}

///|
test "restored Content custody loss reports consumed work without successful handoff" {
  let (retained, custody) = retained_content_test_input()
  let cancels = Ref(0)
  let child = client_retained_content_handoff(
    Ok(retained),
    () => custody.val,
    {
      cancel: () => {
        cancels.val += 1
        true
      },
      stopped: () => true,
      cleanup: () => Ok(true),
    },
    client_retained_content_admission_work(4, 13).unwrap(),
  )
  assert_true(
    @local.advance_managed_provider(child, 1)
    is Ok(Continue(progress=0L, work=1L)),
  )
  custody.val = false
  for _ in 0..<10 {
    assert_true(
      @local.advance_managed_provider(child, 1)
      is Ok(Continue(progress=0L, work=1L)),
    )
  }
  assert_true(
    @local.advance_managed_provider(child, 1)
    is Ok(Failed(_, progress=0L, work=1L)),
  )
  assert_eq(@local.managed_provider_cumulative_work(child), Ok(12L))
  assert_true(@local.cleanup_managed_provider(child).unwrap())
  assert_true(@local.cleanup_managed_provider(child).unwrap())
  assert_false(retained.live.val)
  assert_eq(@local.managed_provider_cumulative_work(child), Ok(12L))
  assert_eq(cancels.val, 1)
}

///|
test "restored Content admission checks the independent three-pass budget before reading" {
  assert_eq(client_retained_content_admission_work(4, 13), Some(12L))
  assert_eq(client_retained_content_admission_work(4, 12), None)
  assert_eq(client_retained_content_admission_work(4, 9), None)
  assert_eq(client_retained_content_admission_work(0, 1), Some(0L))
  assert_eq(client_retained_content_admission_work(0, 0), None)
  assert_eq(client_retained_content_admission_work(-1, 13), None)
  assert_eq(client_retained_content_admission_work(4, -1), None)
  assert_eq(
    client_retained_content_admission_work(2147483647, 2147483647),
    None,
  )
}
