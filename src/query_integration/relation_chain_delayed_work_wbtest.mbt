///|
/// Diagnostic fixture only: the registered first child performs one productive
/// work unit, then acknowledges cancellation on its second stop-only poll.
/// Count child operations independently of the parent reports. No successor
/// completion or handoff is needed to expose the exhausted-budget branch.
struct DelayedChainWorkProbe {
  child_charges : Array[Int64]
  starts : Ref[Int]
  compute_steps : Ref[Int]
  cancellations : Ref[Int]
  cleanup_calls : Ref[Int]
}

///|
fn delayed_chain_work_family(
  sequence : @execution.GeneratedSequence,
  stop_work : Array[Int64],
) -> (@local_connector.ManagedProvider, DelayedChainWorkProbe) {
  let actual = chain_evidence_family(sequence, chain_evidence_probe())
  let child_charges : Array[Int64] = []
  let starts = Ref(0)
  let compute_steps = Ref(0)
  let cancellations = Ref(0)
  let cleanup_calls = Ref(0)
  let stopped = Ref(false)
  let family = @local_connector.managed_provider(
    s => @local_connector.managed_provider_accepts(actual, s),
    s => @local_connector.managed_provider_capacity(actual, s),
    fn(_, _, _, _, _) {
      starts.val += 1
      let cancelled = Ref(false)
      let stop_index = Ref(0)
      Ok(
        @local_connector.managed_provider_execution(
          q => {
            if q != 1 || stopped.val {
              return Err(@connector.InvalidLimits)
            }
            if !cancelled.val {
              compute_steps.val += 1
              child_charges.push(1L)
              return Ok(@local_connector.managed_provider_continue(0L, 1L))
            }
            let charge = stop_work[stop_index.val]
            child_charges.push(charge)
            stop_index.val += 1
            if stop_index.val == stop_work.length() {
              stopped.val = true
              Ok(@local_connector.managed_provider_stopped_poll(0L, charge))
            } else {
              Ok(@local_connector.managed_provider_continue(0L, charge))
            }
          },
          fn() {
            if cancelled.val {
              false
            } else {
              cancelled.val = true
              cancellations.val += 1
              true
            }
          },
          fn() { stopped.val },
          fn() {
            if !stopped.val {
              return Ok(false)
            }
            cleanup_calls.val += 1
            if cleanup_calls.val == 1 {
              Ok(false)
            } else if cleanup_calls.val == 2 {
              Err(@connector.Execution(@execution.InputSet))
            } else {
              Ok(true)
            }
          },
        ),
      )
    },
  )
  (
    family,
    { child_charges, starts, compute_steps, cancellations, cleanup_calls, },
  )
}

///|
fn delayed_chain_work_audit(
  stop_work : Array[Int64],
) -> (Array[Int64], Array[Int64]) raise {
  let sequence = chain_evidence_sequence(2)
  let (family, probe) = delayed_chain_work_family(sequence, stop_work)
  let chain = @local_connector.start_managed_provider_with_execution(
    chain_evidence_provider(sequence, family),
    sequence,
    [],
    100,
    10000,
    { ..dispatch_test_limits().local_execution, max_work: 1, },
  ).unwrap()
  let chain_charges : Array[Int64] = []
  let mut total = 0L
  for index in 0..<3 {
    let poll = @local_connector.advance_managed_provider(chain, 1).unwrap()
    match poll {
      @local_connector.Continue(work~, ..) => {
        assert_true(index < 2)
        chain_charges.push(work)
      }
      @local_connector.Failed(
        @connector.Execution(@execution.InputLimit),
        work~,
        ..
      ) => {
        assert_eq(index, 2)
        chain_charges.push(work)
      }
      _ => fail("unexpected delayed-stop chain poll")
    }
    total += chain_charges[index]
    assert_eq(
      @local_connector.managed_provider_cumulative_work(chain),
      Ok(total),
    )
    assert_eq(
      @local_connector.managed_provider_cumulative_work(chain),
      Ok(total),
    )
  }
  assert_true(@local_connector.managed_provider_stopped(chain))
  assert_false(@local_connector.cleanup_managed_provider(chain).unwrap())
  assert_true(@local_connector.cleanup_managed_provider(chain) is Err(_))
  assert_true(@local_connector.cleanup_managed_provider(chain).unwrap())
  assert_true(@local_connector.cleanup_managed_provider(chain).unwrap())
  assert_eq(
    (probe.starts.val, probe.compute_steps.val, probe.cancellations.val),
    (1, 1, 1),
  )
  assert_eq(probe.cleanup_calls.val, 3)
  assert_true(@local_connector.advance_managed_provider(chain, 1) is Err(_))
  assert_eq(@local_connector.managed_provider_cumulative_work(chain), Ok(total))
  (probe.child_charges, chain_charges)
}

///|
test "delayed-stop work audit preserves final physical stop work" {
  let (child, chain) = delayed_chain_work_audit([1L, 1L])
  assert_eq(child, [1L, 1L, 1L])
  // Independent child operations total three, despite productive max_work=1.
  assert_eq(chain, child)
}

///|
test "delayed-stop work audit confirms a zero-work terminal stop control" {
  let (child, chain) = delayed_chain_work_audit([1L, 0L])
  assert_eq(child, [1L, 1L, 0L])
  // Zero-work terminal observations are admissible. Do not use a zero-work
  // Continue as a counterexample: upper drivers currently require positive
  // Continue work, so that would introduce an additional contract question.
  assert_eq(chain, child)
}

///|
test "budget stop retains cleanup when a stopped child rejects further polling" {
  let sequence = chain_evidence_sequence(2)
  let actual = chain_evidence_family(sequence, chain_evidence_probe())
  let stopped = Ref(false)
  let computes = Ref(0)
  let cleaned = Ref(0)
  let family = @local_connector.managed_provider(
    s => @local_connector.managed_provider_accepts(actual, s),
    s => @local_connector.managed_provider_capacity(actual, s),
    fn(_, _, _, _, _) {
      Ok(
        @local_connector.managed_provider_execution(
          fn(_) {
            if stopped.val {
              return Err(@connector.InvalidLimits)
            }
            computes.val += 1
            Ok(@local_connector.managed_provider_continue(0L, 1L))
          },
          fn() {
            stopped.val = true
            true
          },
          fn() { stopped.val },
          fn() {
            cleaned.val += 1
            Ok(true)
          },
        ),
      )
    },
  )
  let chain = @local_connector.start_managed_provider_with_execution(
    chain_evidence_provider(sequence, family),
    sequence,
    [],
    100,
    10000,
    { ..dispatch_test_limits().local_execution, max_work: 1, },
  ).unwrap()
  @local_connector.advance_managed_provider(chain, 1).unwrap() |> ignore
  assert_true(
    @local_connector.advance_managed_provider(chain, 1)
    is Ok(
      @local_connector.Failed(
        @connector.Execution(@execution.InputLimit),
        work=0L,
        ..
      )
    ),
  )
  assert_true(@local_connector.managed_provider_stopped(chain))
  assert_true(@local_connector.cleanup_managed_provider(chain).unwrap())
  assert_true(@local_connector.cleanup_managed_provider(chain).unwrap())
  assert_eq((computes.val, cleaned.val), (1, 1))
  assert_eq(@local_connector.managed_provider_cumulative_work(chain), Ok(1L))
}

///|
test "chain retains child accounting failure through stop and cleanup" {
  let sequence = chain_evidence_sequence(2)
  let (family, probe) = delayed_chain_work_family(sequence, [2L, 1L])
  let chain = @local_connector.start_managed_provider_with_execution(
    chain_evidence_provider(sequence, family),
    sequence,
    [],
    100,
    10000,
    { ..dispatch_test_limits().local_execution, max_work: 1, },
  ).unwrap()
  @local_connector.advance_managed_provider(chain, 1).unwrap() |> ignore
  assert_true(@local_connector.advance_managed_provider(chain, 1) is Err(_))
  assert_eq(
    @local_connector.managed_provider_cumulative_work(chain),
    Err(@local_connector.InvalidReport),
  )
  assert_false(@local_connector.managed_provider_stopped(chain))
  assert_true(
    @local_connector.advance_managed_provider(chain, 1).unwrap()
    is @local_connector.Failed(@connector.Execution(@execution.InputLimit), ..),
  )
  assert_true(@local_connector.managed_provider_stopped(chain))
  assert_false(@local_connector.cleanup_managed_provider(chain).unwrap())
  assert_true(@local_connector.cleanup_managed_provider(chain) is Err(_))
  assert_true(@local_connector.cleanup_managed_provider(chain).unwrap())
  assert_eq(
    @local_connector.managed_provider_cumulative_work(chain),
    Err(@local_connector.InvalidReport),
  )
  assert_eq(probe.compute_steps.val, 1)
}

///|
test "work audit records the existing completed-only observation boundary" {
  // Reuse the real retained-input materializing fixture. This is a passing
  // diagnostic of the existing API, not a proposed change to its contract.
  let (run, producer, ticket, attempt) = provider_work_attempt()
  let step = @local_connector.advance_local_materializing_attempt(attempt, 1).unwrap()
  assert_false(step.complete)
  assert_true(step.work > 0L)
  assert_true(@local_connector.cancel_local_materializing_attempt(attempt))
  assert_true(
    @local_connector.advance_local_materializing_attempt(attempt, 1) is Err(_),
  )
  assert_true(@local_connector.local_materializing_stopped(attempt))
  assert_true(
    @local_connector.local_materializing_provider_work(attempt) is None,
  )
  assert_eq(
    @local_connector.local_materializing_cumulative_work(attempt),
    Ok(step.work),
  )
  @local_connector.close_local_materializing_attempt(attempt)
  assert_true(
    @local_connector.local_materializing_provider_work(attempt) is None,
  )
  assert_eq(
    @local_connector.local_materializing_cumulative_work(attempt),
    Ok(step.work),
  )
  provider_work_close(run, producer, ticket)
}

///|
test "standard driver retains exhausted chain work through failure and cleanup" {
  let (run, issuer) = captured_graph_fixture(
    local_time_series_chain=true,
    local_relation_family_suffix=true,
  )
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let sequences = dispatch_test_generated(run)
  assert_eq(@execution.generated_sequence_step_count(sequences[0]), 2)
  let (family, probe) = delayed_chain_work_family(sequences[0], [1L, 1L])
  let modules = @builtin.configure_compute_modules(
    @host_driver.open_dispatch_driver(run),
    registry,
    1,
    _ => @strategy.RunIssue::ForeignCandidate,
    with_local=Some(
      (
        @connector.capability_registration_at(registry, 0).unwrap(),
        {
          sequences,
          managed_providers: [family],
          managed_capacity: limits.capacity,
          execution: { ..limits.local_execution, max_work: 1, },
          measurement: limits.guards,
          max_work: limits.candidate_work,
        },
        _ => @strategy.RunIssue::ForeignCandidate,
        _ => @strategy.RunIssue::ForeignCandidate,
      ),
    ),
  ).unwrap()
  let installed = @builtin.configured_local_module(modules).unwrap()
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: limits.local_execution.rows.input_values,
      wire: retained_attempt_wire_limits(),
      row: { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
      max_batch_bytes: 64,
    },
    None,
  ).unwrap()
  let operations = start_local_managed_test_task_operations(
    installed,
    run,
    1,
    [],
    [],
    require_provider=true,
  )
  for index in 0..<2 {
    let step = (operations.advance)(1).unwrap()
    assert_false(step.complete)
    assert_eq(step.work, 1L)
    assert_eq(
      (operations.cumulative_provider_work)(),
      Ok((index + 1).to_int64()),
    )
  }
  let failure = (operations.advance)(1)
  assert_true(
    failure
    is Err(
      @local_driver.Configuration(@connector.Execution(@execution.InputLimit))
    ),
  )
  assert_eq(probe.child_charges, [1L, 1L, 1L])
  assert_eq((operations.cumulative_provider_work)(), Ok(3L))
  assert_true(
    (operations.advance)(1)
    is Err(
      @local_driver.Configuration(@connector.Execution(@execution.InputLimit))
    ),
  )
  assert_true((operations.execution_stopped)())
  assert_false(@strategy.captured_task_completed(run, 1))
  (operations.settle)().unwrap()
  (operations.close)()
  for _ in 0..<3 {
    (operations.cleanup_refresh)() |> ignore
    assert_eq((operations.cumulative_provider_work)(), Ok(3L))
  }
  (operations.close)()
  (operations.cleanup_refresh)() |> ignore
  assert_eq(probe.cleanup_calls.val, 3)
  assert_eq(
    (probe.starts.val, probe.compute_steps.val, probe.cancellations.val),
    (1, 1, 1),
  )
  assert_eq((operations.cumulative_provider_work)(), Ok(3L))
  @strategy.stop_captured_dag(run)
  for task in 0..<@strategy.graph_task_count(@strategy.captured_dag_graph(run)) {
    @strategy.close_captured_task_output(run, task)
  }
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  @mock.close_mock_query_issuer(issuer)
}
