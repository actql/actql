///|
fn bind_serialization_prefix_reservation(
  child : @local.ManagedProviderExecution,
  ledger : @resources.Ledger,
  reservation : @resources.Reservation,
) -> ClientSerializationPrefix {
  {
    child: Some(child),
    ledger,
    reservation,
    final_work: None,
    cleanup_busy: false,
    child_cleaned: false,
    released: false,
  }
}

///|
fn serialization_test_ledger(
  retained : Int64,
  execution : Int64,
) -> @resources.Ledger {
  @resources.create_ledger({
    planning_work: 0,
    attempts: 1,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: retained,
    execution_bytes: execution,
  }).unwrap()
}

///|
test "original serialization prefix cleanup preserves same census until child and Run ACK" {
  let ledger = @resources.create_ledger({
    planning_work: 3,
    attempts: 2,
    holdings: 1,
    transfer_bytes: 0L,
    retained_bytes: 20L,
    execution_bytes: 12L,
  }).unwrap()
  let bootstrap = @resources.reserve_capacity(ledger, 3L, 2L).unwrap()
  let identity = @resources.begin_original_ledger_inventory(
    ledger, bootstrap, 3, 1, 0,
  ).unwrap()
  assert_true(@resources.original_ledger_prefix_available(identity))
  let reservation = @resources.reserve_attempt(ledger, 0L, 7L, 5L).unwrap()
  let closes = Ref(0)
  let child = @local.managed_provider_execution(
    _ => Ok(@local.managed_provider_continue(1L, 1L)),
    () => true,
    () => true,
    () => {
      closes.val += 1
      match closes.val {
        1 => Err(@connector.Execution(@execution.InputSet))
        2 => Ok(false)
        _ => Ok(true)
      }
    },
  )
  let prefix = bind_serialization_prefix_reservation(child, ledger, reservation)
  assert_true(cleanup_client_serialization_prefix(prefix) is Err(Provider(_)))
  assert_true(cleanup_client_serialization_prefix(prefix) is Ok(false))
  assert_false(@resources.original_ledger_prefix_available(identity))
  assert_false(
    @resources.finish_original_ledger_inventory(ledger, false).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 10L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 7L)
  assert_true(@resources.reservation_open(reservation))
  assert_true(cleanup_client_serialization_prefix(prefix) is Ok(true))
  assert_false(@resources.original_ledger_prefix_available(identity))
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  assert_true(
    @resources.finish_original_ledger_inventory(ledger, true).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_true(cleanup_client_serialization_prefix(prefix) is Ok(true))
  assert_eq(closes.val, 3)
}

///|
test "serialization input keeps the original reservation through cleanup failure and retry" {
  let ledger = serialization_test_ledger(10L, 20L)
  let reservation = @resources.reserve_attempt(ledger, 0L, 10L, 20L).unwrap()
  let cleanup_calls = Ref(0)
  let advances = Ref(0)
  let stopped = Ref(false)
  let child = @local.managed_provider_execution(
    _ => {
      advances.val += 1
      Ok(@local.managed_provider_continue(1L, 1L))
    },
    () => {
      stopped.val = true
      true
    },
    () => stopped.val,
    () => {
      cleanup_calls.val += 1
      match cleanup_calls.val {
        1 => Err(@connector.Execution(@execution.InputSet))
        2 => Ok(false)
        _ => Ok(true)
      }
    },
  )
  let prefix = bind_serialization_prefix_reservation(child, ledger, reservation)
  assert_true(advance_client_serialization_prefix(prefix, 1) is Ok(_))
  assert_eq(@local.managed_provider_cumulative_work(child), Ok(1L))
  assert_true(cancel_client_serialization_prefix(prefix))
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 10L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 20L)
  assert_true(cleanup_client_serialization_prefix(prefix) is Err(Provider(_)))
  assert_true(cleanup_client_serialization_prefix(prefix) is Ok(false))
  assert_false(prefix.released)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 10L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 20L)
  assert_true(cleanup_client_serialization_prefix(prefix) is Ok(true))
  assert_true(prefix.released)
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  assert_true(cleanup_client_serialization_prefix(prefix) is Ok(true))
  assert_eq(cleanup_calls.val, 3)
  assert_true(
    advance_client_serialization_prefix(prefix, 1)
    is Ok(Stopped(progress=0L, work=0L)),
  )
  assert_eq(advances.val, 1)
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
}

///|
test "serialization prefix observes failed and stop-only work through the same owner after close" {
  let ledger = serialization_test_ledger(10L, 20L)
  let reservation = @resources.reserve_attempt(ledger, 0L, 10L, 20L).unwrap()
  let polls = Ref(0)
  let cleanup_calls = Ref(0)
  let cancellation = Ref(false)
  let child = @local.managed_provider_execution(
    _ => {
      polls.val += 1
      match polls.val {
        1 => Ok(@local.managed_provider_continue(1L, 1L))
        2 =>
          Ok(
            @local.managed_provider_failed(
              @connector.Execution(@execution.InputSet),
              1L,
              1L,
            ),
          )
        _ => Ok(@local.managed_provider_stopped_poll(1L, 1L))
      }
    },
    () => {
      cancellation.val = true
      true
    },
    () => cancellation.val && polls.val >= 3,
    () => {
      cleanup_calls.val += 1
      if cleanup_calls.val == 1 {
        Ok(false)
      } else {
        Ok(true)
      }
    },
  )
  let prefix = bind_serialization_prefix_reservation(child, ledger, reservation)
  assert_eq(client_serialization_prefix_work(prefix), Ok(0L))
  assert_true(
    advance_client_serialization_prefix(prefix, 1) is Ok(Continue(..)),
  )
  assert_eq(client_serialization_prefix_work(prefix), Ok(1L))
  assert_true(
    advance_client_serialization_prefix(prefix, 1) is Ok(Failed(_, ..)),
  )
  assert_eq(client_serialization_prefix_work(prefix), Ok(2L))
  assert_true(cancel_client_serialization_prefix(prefix))
  assert_true(advance_client_serialization_prefix(prefix, 1) is Ok(Stopped(..)))
  assert_eq(client_serialization_prefix_work(prefix), Ok(3L))
  assert_eq(client_serialization_prefix_work(prefix), Ok(3L))
  assert_true(cleanup_client_serialization_prefix(prefix) is Ok(false))
  assert_eq(client_serialization_prefix_work(prefix), Ok(3L))
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 20L)
  assert_true(cleanup_client_serialization_prefix(prefix) is Ok(true))
  assert_true(cleanup_client_serialization_prefix(prefix) is Ok(true))
  assert_true(
    advance_client_serialization_prefix(prefix, 1)
    is Ok(Stopped(progress=0L, work=0L)),
  )
  assert_eq(client_serialization_prefix_work(prefix), Ok(3L))
  assert_eq(polls.val, 3)
  assert_eq(cleanup_calls.val, 2)
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "serialization prefix does not turn an invalid child report into a normal zero after cleanup" {
  let ledger = serialization_test_ledger(10L, 20L)
  let reservation = @resources.reserve_attempt(ledger, 0L, 10L, 20L).unwrap()
  let cancelled = Ref(false)
  let child = @local.managed_provider_execution(
    _ => Ok(@local.managed_provider_continue(0L, 0L)),
    () => {
      cancelled.val = true
      true
    },
    () => cancelled.val,
    () => Ok(true),
  )
  let prefix = bind_serialization_prefix_reservation(child, ledger, reservation)
  advance_client_serialization_prefix(prefix, 1).unwrap() |> ignore
  assert_true(cancelled.val)
  assert_eq(client_serialization_prefix_work(prefix), Err(@local.InvalidReport))
  assert_true(cleanup_client_serialization_prefix(prefix) is Ok(true))
  assert_true(cleanup_client_serialization_prefix(prefix) is Ok(true))
  assert_eq(client_serialization_prefix_work(prefix), Err(@local.InvalidReport))
  assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
}

///|
test "serialization input never reports release before the original ledger confirms it" {
  let ledger = serialization_test_ledger(10L, 20L)
  let reservation = @resources.reserve_attempt(ledger, 0L, 10L, 20L).unwrap()
  let closes = Ref(0)
  let advances = Ref(0)
  let child = @local.managed_provider_execution(
    _ => {
      advances.val += 1
      Ok(@local.managed_provider_stopped_poll(0L, 0L))
    },
    () => true,
    () => true,
    () => {
      closes.val += 1
      Ok(true)
    },
  )
  let prefix = bind_serialization_prefix_reservation(child, ledger, reservation)
  // Fault injection: another caller incorrectly settled the borrowed token.
  // This is not a valid release acknowledgement for this composition handle.
  @resources.settle_reservation(ledger, reservation).unwrap() |> ignore
  assert_true(
    cleanup_client_serialization_prefix(prefix)
    is Err(Physical(ClosedReservation)),
  )
  assert_false(prefix.released)
  assert_true(
    cleanup_client_serialization_prefix(prefix)
    is Err(Physical(ClosedReservation)),
  )
  assert_eq(closes.val, 1)
  assert_true(
    advance_client_serialization_prefix(prefix, 1)
    is Ok(Stopped(progress=0L, work=0L)),
  )
  assert_eq(advances.val, 0)
}

///|
test "prefix retirement cuts its acknowledged child alias once while preserving original nonzero work and refusing cleanup reentry" {
  let ledger = serialization_test_ledger(10L, 20L)
  let reservation = @resources.reserve_attempt(ledger, 0L, 10L, 20L).unwrap()
  let original : Ref[ClientSerializationPrefix?] = Ref(None)
  let ready = Ref(false)
  let closes = Ref(0)
  let nested_pending = Ref(false)
  let advance_refused = Ref(false)
  let cancel_refused = Ref(false)
  let child = @local.managed_provider_execution(
    _ => Ok(@local.managed_provider_continue(1L, 1L)),
    () => true,
    () => true,
    () => {
      closes.val += 1
      if !ready.val {
        return Ok(false)
      }
      if closes.val == 2 {
        let prefix = original.val.unwrap()
        nested_pending.val = cleanup_client_serialization_prefix(prefix)
          is Ok(false)
        advance_refused.val = advance_client_serialization_prefix(prefix, 1)
          is Err(_)
        cancel_refused.val = !cancel_client_serialization_prefix(prefix)
      }
      Ok(true)
    },
  )
  let prefix = bind_serialization_prefix_reservation(child, ledger, reservation)
  original.val = Some(prefix)
  advance_client_serialization_prefix(prefix, 1).unwrap() |> ignore
  assert_eq(client_serialization_prefix_work(prefix), Ok(1L))
  assert_true(cleanup_client_serialization_prefix(prefix) is Ok(false))
  assert_true(prefix.child is Some(value) && physical_equal(value, child))
  assert_true(@resources.reservation_open(reservation))
  ready.val = true
  assert_true(cleanup_client_serialization_prefix(prefix) is Ok(true))
  assert_true(prefix.child is None && prefix.child_cleaned && prefix.released)
  assert_true(nested_pending.val && advance_refused.val && cancel_refused.val)
  assert_eq(client_serialization_prefix_work(prefix), Ok(1L))
  // Retaining the old provider independently cannot rewrite this retired
  // prefix's already observed total or explain its alias cut by garbage collection.
  @local.managed_provider_record_handoff_work(child, 7L).unwrap()
  assert_eq(client_serialization_prefix_work(prefix), Ok(1L))
  assert_true(cleanup_client_serialization_prefix(prefix) is Ok(true))
  assert_eq(closes.val, 2)
  assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
}

///|
test "prefix retirement drops its invalid-report child without replacing the original work error by zero" {
  let ledger = serialization_test_ledger(10L, 20L)
  let reservation = @resources.reserve_attempt(ledger, 0L, 10L, 20L).unwrap()
  let child = @local.managed_provider_execution(
    _ => Ok(@local.managed_provider_continue(0L, 0L)),
    () => true,
    () => true,
    () => Ok(true),
  )
  let prefix = bind_serialization_prefix_reservation(child, ledger, reservation)
  advance_client_serialization_prefix(prefix, 1).unwrap() |> ignore
  assert_eq(client_serialization_prefix_work(prefix), Err(@local.InvalidReport))
  assert_true(cleanup_client_serialization_prefix(prefix) is Ok(true))
  assert_true(prefix.child is None)
  assert_eq(client_serialization_prefix_work(prefix), Err(@local.InvalidReport))
  assert_true(cleanup_client_serialization_prefix(prefix) is Ok(true))
}

///|
test "prefix retirement cuts only the acknowledged child before same original reservation settlement failure" {
  let ledger = serialization_test_ledger(10L, 20L)
  let reservation = @resources.reserve_attempt(ledger, 0L, 10L, 20L).unwrap()
  let closes = Ref(0)
  let child = @local.managed_provider_execution(
    _ => Ok(@local.managed_provider_stopped_poll(0L, 1L)),
    () => true,
    () => true,
    () => {
      closes.val += 1
      Ok(true)
    },
  )
  let prefix = bind_serialization_prefix_reservation(child, ledger, reservation)
  advance_client_serialization_prefix(prefix, 1).unwrap() |> ignore
  // Existing explicit misuse fixture: a foreign caller spent this exact token.
  // Provider cleanup cannot promote that failure to a release acknowledgement.
  @resources.settle_reservation(ledger, reservation).unwrap() |> ignore
  assert_true(
    cleanup_client_serialization_prefix(prefix)
    is Err(Physical(ClosedReservation)),
  )
  assert_true(prefix.child is None && prefix.child_cleaned && !prefix.released)
  assert_eq(client_serialization_prefix_work(prefix), Ok(1L))
  assert_true(
    cleanup_client_serialization_prefix(prefix)
    is Err(Physical(ClosedReservation)),
  )
  assert_eq(closes.val, 1)
}
