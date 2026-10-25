///|
test "materializing unverified import keeps reservation until sliced cleanup" {
  // The source has one verified row. This deliberately overlong receiving
  // stream is cancelled before identity finalization, not adopted as input.
  let (run, producer, ticket, attempt) = provider_work_attempt(
    imported_rows=100,
    finish_input=false,
  )
  assert_false(@local_connector.local_materializing_started(attempt))
  let ledger = @strategy.captured_dag_ledger(run)
  let source = @strategy.captured_task_output(run, 1, Step(1)).unwrap()
  let before = @resources.ledger_usage(ledger)
  assert_true(@local_connector.cancel_local_materializing_attempt(attempt))
  assert_false(@local_connector.cancel_local_materializing_attempt(attempt))
  assert_true(@local_connector.local_materializing_stopped(attempt))
  assert_false(@local_connector.local_materializing_started(attempt))
  assert_true(
    @local_connector.append_local_materializing_input(attempt, 0, "{\"id\":3}")
    is Err(State),
  )
  assert_true(
    @local_connector.finish_local_materializing_input(attempt, 0) is Err(State),
  )
  assert_false(@local_connector.advance_local_materializing_cleanup(attempt, 0))
  @strategy.close_task_execution(run, ticket)
  @strategy.settle_task_execution(run, ticket, true).unwrap()
  let pending = @resources.ledger_usage(ledger)
  assert_eq(pending.reserved_execution_bytes, before.reserved_execution_bytes)
  assert_true(pending.reserved_execution_bytes > 0L)
  // Common observations are pure; only the installed cleanup poll advances.
  for _ in 0..<2 {
    assert_false(@strategy.refresh_task_execution_cleanup(run, ticket).unwrap())
    assert_eq(@resources.ledger_usage(ledger), pending)
  }
  let mut finished = false
  for _ in 0..<400 {
    if @local_connector.advance_local_materializing_cleanup(attempt, 1) {
      finished = true
      break
    }
    assert_false(@strategy.refresh_task_execution_cleanup(run, ticket).unwrap())
    assert_eq(@resources.ledger_usage(ledger), pending)
  }
  assert_true(finished)
  assert_true(@strategy.refresh_task_execution_cleanup(run, ticket).unwrap())
  let released = @resources.ledger_usage(ledger)
  assert_eq(released.reserved_execution_bytes, 0L)
  assert_eq(released.transferred_bytes, before.transferred_bytes)
  assert_eq(
    @local_connector.local_materializing_cumulative_work(attempt),
    Ok(0L),
  )
  assert_false(@strategy.captured_task_completed(run, 3))
  assert_true(
    @local_connector.local_materializing_completed_output(attempt) is None,
  )
  assert_true(@execution.completed_output_available(source))
  assert_true(@local_connector.advance_local_materializing_cleanup(attempt, 1))
  assert_true(@strategy.refresh_task_execution_cleanup(run, ticket).unwrap())
  assert_eq(@resources.ledger_usage(ledger), released)
  provider_work_close(run, producer, ticket)
  for task in 0..<@strategy.graph_task_count(@strategy.captured_dag_graph(run)) {
    @strategy.close_captured_task_output(run, task)
  }
  @strategy.refresh_captured_retention(run)
  let released = @resources.ledger_usage(ledger)
  assert_eq(released.reserved_execution_bytes, 0L)
  assert_eq(released.reserved_retention_bytes, 0L)
  assert_eq(released.held_bytes, 0L)
}

///|
test "materializing close retains stopped provider through cleanup error and retry" {
  let permit_stop = Ref(false)
  let permit_cleanup = Ref(false)
  let cleanup_calls = Ref(0)
  let starts = Ref(0)
  let compute_advances = Ref(0)
  let requested = Ref(false)
  let (run, producer, ticket, attempt) = provider_work_attempt(
    transform_provider=Some(base => {
      @local_connector.managed_provider(
        sequence => @local_connector.managed_provider_accepts(base, sequence),
        sequence => @local_connector.managed_provider_capacity(base, sequence),
        fn(sequence, inputs, max_rows, max_bytes, limits) {
          starts.val += 1
          let child = @local_connector.start_managed_provider_with_execution(
            base, sequence, inputs, max_rows, max_bytes, limits,
          ).unwrap()
          Ok(
            @local_connector.managed_provider_execution(
              fn(quantum) {
                if requested.val && !permit_stop.val {
                  return Ok(@local_connector.managed_provider_waiting(0L, 0L))
                }
                if !requested.val {
                  compute_advances.val += 1
                }
                @local_connector.advance_managed_provider(child, quantum)
              },
              fn() {
                requested.val = true
                @local_connector.cancel_managed_provider(child)
              },
              () => {
                permit_stop.val &&
                @local_connector.managed_provider_stopped(child)
              },
              fn() {
                cleanup_calls.val += 1
                if cleanup_calls.val == 1 {
                  return Err(InvalidLimits)
                }
                if !permit_cleanup.val {
                  return Ok(false)
                }
                @local_connector.cleanup_managed_provider(child)
              },
            ),
          )
        },
      )
    }),
  )
  assert_false(@local_connector.local_materializing_started(attempt))
  let first = @local_connector.advance_local_materializing_attempt(attempt, 1).unwrap()
  assert_false(first.complete)
  assert_eq(first.work, 1L)
  assert_eq(starts.val, 1)
  assert_true(@local_connector.local_materializing_started(attempt))
  assert_eq(compute_advances.val, 1)
  let source = @strategy.captured_task_output(run, 1, Step(1)).unwrap()
  let ledger = @strategy.captured_dag_ledger(run)
  let before = @resources.ledger_usage(ledger)
  @strategy.close_task_execution(run, ticket)
  assert_true(@local_connector.local_materializing_started(attempt))
  assert_false(@local_connector.local_materializing_stopped(attempt))
  assert_eq(cleanup_calls.val, 0)
  assert_false(
    @local_connector.advance_local_materializing_cleanup(attempt, 64),
  )
  assert_eq(cleanup_calls.val, 0)
  assert_eq(@resources.ledger_usage(ledger), before)
  permit_stop.val = true
  assert_true(
    @local_connector.advance_local_materializing_attempt(attempt, 1)
    is Err(State),
  )
  assert_true(@local_connector.local_materializing_stopped(attempt))
  assert_true(@local_connector.local_materializing_started(attempt))
  @strategy.settle_task_execution(run, ticket, true).unwrap()
  assert_false(
    @local_connector.advance_local_materializing_cleanup(attempt, 64),
  )
  assert_eq(cleanup_calls.val, 1)
  assert_false(@strategy.refresh_task_execution_cleanup(run, ticket).unwrap())
  assert_false(
    @local_connector.advance_local_materializing_cleanup(attempt, 64),
  )
  assert_eq(cleanup_calls.val, 2)
  assert_eq(
    @resources.ledger_usage(ledger).reserved_execution_bytes,
    before.reserved_execution_bytes,
  )
  assert_true(@execution.completed_output_available(source))
  let work = @local_connector.local_materializing_cumulative_work(attempt)
  permit_cleanup.val = true
  assert_true(@local_connector.advance_local_materializing_cleanup(attempt, 64))
  assert_true(@strategy.refresh_task_execution_cleanup(run, ticket).unwrap())
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_eq(@local_connector.local_materializing_cumulative_work(attempt), work)
  assert_eq(starts.val, 1)
  assert_eq(compute_advances.val, 1)
  assert_true(@local_connector.advance_local_materializing_cleanup(attempt, 64))
  assert_eq(cleanup_calls.val, 3)
  assert_false(@strategy.captured_task_completed(run, 3))
  provider_work_close(run, producer, ticket)
}
