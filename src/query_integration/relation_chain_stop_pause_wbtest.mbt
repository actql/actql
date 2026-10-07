///|
/// A diagnostic child exposes pause custody independently of the chain's
/// terminal flag. It performs exactly one Compute step before either an
/// explicit cancellation or productive budget exhaustion enters stop-only poll.
fn chain_stop_pause_audit(budget_exhausted : Bool) -> Unit raise {
  let sequence = chain_evidence_sequence(2)
  let actual = chain_evidence_family(sequence, chain_evidence_probe())
  let starts = Ref(0)
  let computes = Ref(0)
  let requests = Ref(0)
  let stop_index = Ref(0)
  let stopped = Ref(false)
  let cleanup_calls = Ref(0)
  let holding = Ref(true)
  let child_work : Array[Int64] = []
  let family = @local_connector.managed_provider(
    s => @local_connector.managed_provider_accepts(actual, s),
    s => @local_connector.managed_provider_capacity(actual, s),
    fn(_, _, _, _, _) {
      starts.val += 1
      let cancelled = Ref(false)
      Ok(
        @local_connector.managed_provider_execution(
          fn(q) {
            if q != 1 || stopped.val || !holding.val {
              return Err(@connector.InvalidLimits)
            }
            if !cancelled.val {
              computes.val += 1
              child_work.push(1L)
              return Ok(@local_connector.managed_provider_continue(0L, 1L))
            }
            let index = stop_index.val
            stop_index.val += 1
            let work = if index == 1 { 1L } else { 0L }
            child_work.push(work)
            if index == 0 {
              Ok(@local_connector.managed_provider_waiting(0L, work))
            } else if index == 1 || index == 2 {
              Ok(@local_connector.managed_provider_settling(7, 0L, work))
            } else {
              stopped.val = true
              Ok(@local_connector.managed_provider_stopped_poll(0L, work))
            }
          },
          fn() {
            if cancelled.val {
              false
            } else {
              cancelled.val = true
              requests.val += 1
              true
            }
          },
          fn() { stopped.val },
          fn() {
            cleanup_calls.val += 1
            if !stopped.val || !holding.val {
              return Err(@connector.InvalidLimits)
            }
            if cleanup_calls.val == 1 {
              Ok(false)
            } else if cleanup_calls.val == 2 {
              Err(@connector.Execution(@execution.InputSet))
            } else {
              holding.val = false
              Ok(true)
            }
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
    {
      ..dispatch_test_limits().local_execution,
      max_work: if budget_exhausted {
        1
      } else {
        10
      },
    },
  ).unwrap()
  assert_true(
    @local_connector.advance_managed_provider(chain, 1).unwrap()
    is @local_connector.Continue(work=1L, ..),
  )
  if !budget_exhausted {
    assert_true(@local_connector.cancel_managed_provider(chain))
    assert_false(@local_connector.cancel_managed_provider(chain))
  }
  let expected_work = [0L, 1L, 0L]
  let mut total = 1L
  for index in 0..<3 {
    let poll = @local_connector.advance_managed_provider(chain, 1).unwrap()
    if index == 0 {
      assert_true(poll is @local_connector.Waiting(progress=0L, work=0L))
    } else {
      match poll {
        @local_connector.Settling(slot, progress~, work~) => {
          assert_eq(slot, 7)
          assert_eq(progress, 0L)
          assert_eq(work, expected_work[index])
        }
        _ => fail("stop pause lost its exact kind or slot")
      }
    }
    total += expected_work[index]
    assert_eq(
      @local_connector.managed_provider_cumulative_work(chain),
      Ok(total),
    )
    assert_false(@local_connector.managed_provider_stopped(chain))
    assert_false(@local_connector.cleanup_managed_provider(chain).unwrap())
    // A pause must keep the same child live, without trying its cleanup early.
    assert_true(holding.val)
    assert_eq(cleanup_calls.val, 0)
    assert_eq((starts.val, computes.val, requests.val), (1, 1, 1))
  }
  let terminal = @local_connector.advance_managed_provider(chain, 1).unwrap()
  if budget_exhausted {
    assert_true(
      terminal
      is @local_connector.Failed(
        @connector.Execution(@execution.InputLimit),
        progress=0L,
        work=0L
      ),
    )
  } else {
    assert_true(terminal is @local_connector.Stopped(progress=0L, work=0L))
  }
  assert_true(@local_connector.managed_provider_stopped(chain))
  assert_eq(child_work, [1L, 0L, 1L, 0L, 0L])
  assert_eq(@local_connector.managed_provider_cumulative_work(chain), Ok(2L))
  assert_true(holding.val)
  assert_false(@local_connector.cleanup_managed_provider(chain).unwrap())
  assert_true(holding.val)
  assert_true(@local_connector.cleanup_managed_provider(chain) is Err(_))
  assert_true(holding.val)
  assert_true(@local_connector.cleanup_managed_provider(chain).unwrap())
  assert_false(holding.val)
  assert_true(@local_connector.cleanup_managed_provider(chain).unwrap())
  assert_eq(cleanup_calls.val, 3)
  assert_eq((starts.val, computes.val, requests.val), (1, 1, 1))
  assert_eq(@local_connector.managed_provider_cumulative_work(chain), Ok(2L))
  assert_true(@local_connector.advance_managed_provider(chain, 1) is Err(_))
}

///|
test "explicit stop preserves Waiting and Settling custody through cleanup retry" {
  chain_stop_pause_audit(false)
}

///|
test "budget stop preserves Waiting and Settling custody through cleanup retry" {
  chain_stop_pause_audit(true)
}
