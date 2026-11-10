///|
// Whitebox synthetic grants isolate startup and lifetime mechanics. None of
// these bytes is a normal installed-backend bound or durable authentication.
fn original_startup_test_grant(
  rows : @relation.PreparedInferRows,
  limits : ModelExecutionLimits,
  quantities : @resources.QuantityAmounts?,
) -> OriginalModelStartup {
  let ledger = @resources.create_ledger(limits.ledger).unwrap()
  if quantities is Some(value) {
    @resources.configure_quantities(ledger, value).unwrap()
  }
  let capacity = @resources.reserve_capacity(ledger, 100L, 5L).unwrap()
  {
    rows,
    scope: None,
    ledger,
    capacity,
    retained_bytes: 100L,
    execution_bytes: 5L,
    shared_mock: None,
    used: false,
  }
}

///|
fn original_startup_test_start(
  rows : @relation.PreparedInferRows,
  grant : OriginalModelStartup,
  limits : ModelExecutionLimits,
  quantities : ModelQuantityCapacity?,
) -> Result[ModelExecution, ModelExecutionIssue] {
  let provider = install_model_provider("models/fixture", _ => {
    abort("A masked private startup must never send")
  }).unwrap()
  start_model_owned(
    rows,
    Provider(provider),
    "sha256:" + "a".repeat(64),
    limits,
    None,
    durable_calls=true,
    send_mask=Some(
      Array::make(@relation.prepared_infer_rows_count(rows), false),
    ),
    quantity_capacity=quantities,
    original_startup=Some(grant),
  )
}

///|
test "original Model startup uses same Ledger once and keeps pending output custody" {
  let rows = prepared_capacity_test_rows()
  let limits = prepared_capacity_test_limits(100L)
  let grant = original_startup_test_grant(rows, limits, None)
  let before = @resources.ledger_usage(grant.ledger)
  let active = original_startup_test_start(rows, grant, limits, None).unwrap()
  assert_true(physical_equal(active.state.ledger, grant.ledger))
  assert_eq(@resources.ledger_usage(grant.ledger), before)
  assert_true(grant.used)
  assert_false(cleanup_original_model_startup(grant).unwrap())
  assert_true(
    original_startup_test_start(rows, grant, limits, None)
    is Err(RequestIdentity),
  )
  assert_eq(@resources.ledger_usage(grant.ledger), before)
  let cleanup_done = Ref(false)
  active.state.physical_cursors.push({
    advance: () => Err(InvalidProvider),
    cleanup: () => cleanup_done.val,
  })
  assert_true(request_model_cancel(active))
  assert_true(advance_model_execution(active, 1).unwrap() is Stopped(_, _, _))
  active.state.output_uses = 1
  assert_false(cleanup_model_execution(active).unwrap())
  assert_true(@resources.capacity_reservation_open(grant.capacity))
  active.state.output_uses = 0
  assert_false(cleanup_model_execution(active).unwrap())
  assert_true(active.state.original_startup is Some(_))
  assert_true(@resources.capacity_reservation_open(grant.capacity))
  cleanup_done.val = true
  let foreign = original_startup_test_grant(rows, limits, None)
  active.state.original_startup = Some(foreign)
  assert_true(cleanup_model_execution(active) is Err(RequestIdentity))
  assert_true(@resources.capacity_reservation_open(grant.capacity))
  assert_true(@resources.capacity_reservation_open(foreign.capacity))
  active.state.original_startup = Some(grant)
  @resources.settle_capacity(foreign.ledger, foreign.capacity).unwrap()
  assert_true(cleanup_model_execution(active).unwrap())
  assert_true(active.state.original_startup is None)
  assert_false(@resources.capacity_reservation_open(grant.capacity))
  assert_true(cleanup_original_model_startup(grant).unwrap())
  assert_true(cleanup_model_execution(active).unwrap())
  assert_true(
    original_startup_test_start(rows, grant, limits, None)
    is Err(RequestIdentity),
  )
  assert_true(@relation.cleanup_prepared_infer_rows(rows))
}

///|
test "original Model startup unconsumed cleanup checks original row retirement without caller proof" {
  let rows = prepared_capacity_test_rows()
  let limits = prepared_capacity_test_limits(100L)
  let grant = original_startup_test_grant(rows, limits, None)
  let before = @resources.ledger_usage(grant.ledger)
  let input_use = @relation.acquire_prepared_infer_rows(rows).unwrap()
  assert_false(cleanup_original_model_startup(grant).unwrap())
  assert_false(grant.used)
  assert_true(@resources.capacity_reservation_open(grant.capacity))
  assert_eq(@resources.ledger_usage(grant.ledger), before)
  assert_true(@relation.release_prepared_infer_rows_use(input_use))
  assert_true(cleanup_original_model_startup(grant).unwrap())
  assert_true(grant.used)
  assert_false(@resources.capacity_reservation_open(grant.capacity))
  assert_true(cleanup_original_model_startup(grant).unwrap())
  assert_true(
    original_startup_test_start(rows, grant, limits, None)
    is Err(RequestIdentity),
  )
  assert_eq(@resources.ledger_usage(grant.ledger).reserved_retention_bytes, 0L)
}

///|
test "original Model startup refusal does not consume or settle the original grant" {
  let rows = prepared_capacity_test_rows()
  let foreign_rows = prepared_capacity_test_rows()
  let limits = prepared_capacity_test_limits(100L)
  let grant = original_startup_test_grant(rows, limits, None)
  let before = @resources.ledger_usage(grant.ledger)
  assert_true(
    original_startup_test_start(foreign_rows, grant, limits, None)
    is Err(RequestIdentity),
  )
  assert_true(
    original_startup_test_start(
      rows,
      grant,
      prepared_capacity_test_limits(101L),
      None,
    )
    is Err(RequestIdentity),
  )
  assert_false(grant.used)
  assert_eq(@resources.ledger_usage(grant.ledger), before)
  assert_true(@resources.capacity_reservation_open(grant.capacity))
  assert_true(@relation.cleanup_prepared_infer_rows(rows))
  let provider = install_model_provider("models/fixture", _ => {
    abort("Retired rows cannot invoke a provider")
  }).unwrap()
  assert_true(
    start_model_owned(
      rows,
      Provider(provider),
      "sha256:" + "a".repeat(64),
      limits,
      None,
      original_startup=Some(grant),
    )
    is Err(OutputIdentity),
  )
  assert_false(grant.used)
  assert_true(@resources.capacity_reservation_open(grant.capacity))
  assert_eq(@resources.ledger_usage(grant.ledger), before)
  @resources.settle_capacity(grant.ledger, grant.capacity).unwrap()
  assert_true(@relation.cleanup_prepared_infer_rows(foreign_rows))
}

///|
test "original Model startup preserves configured quantities and unknown usage" {
  let rows = prepared_capacity_test_rows()
  let limits = prepared_capacity_test_limits(100L)
  let quantities : ModelQuantityCapacity = {
    limits: { tokens: 10L, cost_units: 5L, duration_ms: 20L, },
    per_attempt: { tokens: 2L, cost_units: 1L, duration_ms: 3L, },
  }
  let grant = original_startup_test_grant(rows, limits, Some(quantities.limits))
  let attempt = @resources.reserve_attempt(
    grant.ledger,
    0L,
    0L,
    0L,
    quantities=Some(quantities.per_attempt),
  ).unwrap()
  @resources.mark_quantities_uncertain(grant.ledger, attempt).unwrap()
  let usage = @resources.quantity_usage(grant.ledger)
  assert_true(
    original_startup_test_start(rows, grant, limits, None)
    is Err(RequestIdentity),
  )
  let active = original_startup_test_start(
    rows,
    grant,
    limits,
    Some(quantities),
  ).unwrap()
  assert_eq(@resources.quantity_usage(active.state.ledger), usage)
  assert_true(request_model_cancel(active))
  advance_model_execution(active, 1).unwrap() |> ignore
  assert_true(cleanup_model_execution(active).unwrap())
  assert_eq(@resources.quantity_usage(grant.ledger), usage)
  assert_true(@relation.cleanup_prepared_infer_rows(rows))
}

///|
test "original Model startup keeps Model work separate from spent original planning" {
  let rows = prepared_capacity_test_rows()
  let old = prepared_capacity_test_limits(100L)
  let limits = {
    ..old,
    max_work: 2,
    ledger: { ..old.ledger, planning_work: 2, },
  }
  let grant = original_startup_test_grant(rows, limits, None)
  let delegation = @resources.reserve_execution_delegation(
    grant.ledger,
    {
      planning_work: 1,
      attempts: 0,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: 0L,
      execution_bytes: 0L,
    },
    0L,
    0L,
  ).unwrap()
  @resources.charge_planning(grant.ledger, 1).unwrap()
  assert_true(
    @resources.charge_planning(grant.ledger, 1) is Err(@resources.PlanningLimit),
  )
  let active = original_startup_test_start(rows, grant, limits, None).unwrap()
  assert_true(advance_model_execution(active, 1).unwrap() is Continue(_, _))
  assert_eq(@resources.ledger_usage(grant.ledger).planning_work, 1)
  assert_true(advance_model_execution(active, 1).unwrap() is Continue(_, _))
  assert_true(
    advance_model_execution(active, 1).unwrap() is Failed(WorkLimit, _, _),
  )
  assert_eq(active.state.work, 2)
  assert_true(cleanup_model_execution(active).unwrap())
  assert_eq(@resources.ledger_usage(grant.ledger).planning_work, 1)
  assert_true(
    @resources.charge_planning(grant.ledger, 1) is Err(@resources.PlanningLimit),
  )
  @resources.settle_execution_delegation(grant.ledger, delegation, None).unwrap()
  assert_eq(@resources.ledger_usage(grant.ledger).planning_work, 2)
  assert_true(@relation.cleanup_prepared_infer_rows(rows))
}

///|
test "original Model startup zero rows retain a positive base and closed tokens refuse" {
  let rows = prepared_capacity_test_rows(empty=true)
  assert_eq(@relation.prepared_infer_rows_count(rows), 0)
  let limits = prepared_capacity_test_limits(100L)
  let grant = original_startup_test_grant(rows, limits, None)
  let active = original_startup_test_start(rows, grant, limits, None).unwrap()
  assert_eq(
    @resources.ledger_usage(grant.ledger).reserved_retention_bytes,
    100L,
  )
  assert_true(request_model_cancel(active))
  advance_model_execution(active, 1).unwrap() |> ignore
  assert_true(cleanup_model_execution(active).unwrap())
  assert_true(@relation.cleanup_prepared_infer_rows(rows))
  let live_rows = prepared_capacity_test_rows()
  let closed = original_startup_test_grant(live_rows, limits, None)
  @resources.settle_capacity(closed.ledger, closed.capacity).unwrap()
  assert_true(
    original_startup_test_start(live_rows, closed, limits, None)
    is Err(RequestIdentity),
  )
  assert_false(closed.used)
  assert_true(@relation.cleanup_prepared_infer_rows(live_rows))
}

///|
test "shared physical provider startup retains the same provider limits and larger parent without a new Ledger" {
  let rows = prepared_capacity_test_rows()
  let limits = prepared_capacity_test_limits(100L)
  let parent_limits = {
    ..limits,
    ledger: {
      ..limits.ledger,
      retained_bytes: limits.ledger.retained_bytes + 1000L,
      execution_bytes: limits.ledger.execution_bytes + 1000L,
    },
  }
  let original = original_startup_test_grant(rows, parent_limits, None)
  let sibling = @resources.reserve_capacity(original.ledger, 50L, 5L).unwrap()
  let provider = install_model_provider("models/fixture", _ => {
    abort("masked provider must not send")
  }).unwrap()
  let startup = {
    ..original,
    shared_mock: Some({
      provider,
      limits,
      publication_retained: 0L,
      publication_execution: 0L,
      publication_planning: 0,
    }),
  }
  let before = @resources.ledger_usage(startup.ledger)
  let foreign = install_model_provider("models/fixture", _ => {
    abort("foreign provider must not send")
  }).unwrap()
  assert_false(
    original_model_startup_limits_match(startup, limits, Some(foreign)),
  )
  assert_false(
    original_model_startup_limits_match(
      startup,
      { ..limits, max_work: limits.max_work, },
      Some(provider),
    ),
  )
  assert_eq(@resources.ledger_usage(startup.ledger), before)
  assert_false(startup.used)
  let active = start_model_owned(
    rows,
    Provider(provider),
    "sha256:" + "a".repeat(64),
    limits,
    None,
    durable_calls=true,
    send_mask=Some(
      Array::make(@relation.prepared_infer_rows_count(rows), false),
    ),
    original_startup=Some(startup),
  ).unwrap()
  assert_true(physical_equal(active.state.ledger, startup.ledger))
  assert_eq(@resources.ledger_usage(startup.ledger), before)
  assert_true(startup.used)
  assert_true(request_model_cancel(active))
  assert_true(advance_model_execution(active, 1).unwrap() is Stopped(_, _, _))
  assert_true(cleanup_model_execution(active).unwrap())
  assert_true(@resources.capacity_reservation_open(sibling))
  @resources.settle_capacity(startup.ledger, sibling).unwrap()
}

///|
test "shared Model startup retains the actual aggregate quantity configuration and its component ceiling" {
  let rows = prepared_capacity_test_rows()
  let limits = prepared_capacity_test_limits(100L)
  let aggregate : @resources.QuantityAmounts = {
    tokens: 132L,
    cost_units: 0L,
    duration_ms: 2000L,
  }
  let quantities : ModelQuantityCapacity = {
    limits: { tokens: 66L, cost_units: 0L, duration_ms: 1000L, },
    per_attempt: { tokens: 33L, cost_units: 0L, duration_ms: 500L, },
  }
  let original = original_startup_test_grant(rows, limits, Some(aggregate))
  let provider = install_model_provider("models/fixture", _ => {
    abort("masked shared startup must not send")
  }).unwrap()
  let startup = {
    ..original,
    shared_mock: Some({
      provider,
      limits,
      publication_retained: 0L,
      publication_execution: 0L,
      publication_planning: 0,
    }),
  }
  // Dedicated startup remains an exact configuration binding. Equal rows or
  // a larger number cannot select the existing shared-provider purpose.
  assert_false(
    original_model_startup_matches(
      original,
      rows,
      None,
      limits,
      Some(quantities),
      Some(provider),
    ),
  )
  let physical = @resources.ledger_usage(startup.ledger)
  let usage = @resources.quantity_usage(startup.ledger)
  let active = start_model_owned(
    rows,
    Provider(provider),
    "sha256:" + "a".repeat(64),
    limits,
    None,
    durable_calls=true,
    send_mask=Some(
      Array::make(@relation.prepared_infer_rows_count(rows), false),
    ),
    quantity_capacity=Some(quantities),
    original_startup=Some(startup),
  ).unwrap()
  assert_true(physical_equal(active.state.ledger, startup.ledger))
  assert_true(
    @resources.quantity_configuration_matches(startup.ledger, Some(aggregate)),
  )
  assert_eq(active.state.quantity_capacity.unwrap().limits, quantities.limits)
  assert_eq(@resources.ledger_usage(startup.ledger), physical)
  assert_eq(@resources.quantity_usage(startup.ledger), usage)
  assert_true(request_model_cancel(active))
  advance_model_execution(active, 1).unwrap() |> ignore
  assert_true(cleanup_model_execution(active).unwrap())
  assert_eq(@resources.quantity_usage(startup.ledger), usage)
}

///|
// A component ceiling is not a request to enlarge its shared parent. Actual
// operations must satisfy BOTH their original component and parent limits.
test "shared Model startup preserves component ceilings while the parent bounds actual work" {
  let rows = prepared_capacity_test_rows()
  let limits = prepared_capacity_test_limits(10000L)
  let parent_limits = {
    ..limits,
    ledger: { ..limits.ledger, attempts: 1, holdings: 1, },
  }
  let original = original_startup_test_grant(rows, parent_limits, None)
  let sends = Ref(0)
  let provider = install_model_provider("models/fixture", _ => {
    sends.val += 1
    Err(ProviderError)
  }).unwrap()
  let startup = {
    ..original,
    shared_mock: Some({
      provider,
      limits,
      publication_retained: 0L,
      publication_execution: 0L,
      publication_planning: 0,
    }),
  }
  let before = @resources.ledger_usage(startup.ledger)
  let active = start_model_owned(
    rows,
    Provider(provider),
    "sha256:" + "a".repeat(64),
    limits,
    None,
    original_startup=Some(startup),
  ).unwrap()
  assert_true(physical_equal(active.state.ledger, startup.ledger))
  assert_true(physical_equal(active.state.limits, limits))
  assert_eq(@resources.ledger_limits(active.state.ledger), parent_limits.ledger)
  assert_eq(@resources.ledger_usage(active.state.ledger), before)
  let mut done = false
  for _ in 0..<8 {
    match advance_model_execution(active, 1).unwrap() {
      Failed(Ledger(@resources.AttemptLimit), _, _) => {
        done = true
        break
      }
      Continue(_, _) => ()
      _ => abort("expected original parent attempt refusal before provider")
    }
  }
  assert_true(done)
  assert_eq(sends.val, 0)
  // Refusal happened while reserving, before any actual provider attempt.
  // The original reserved slot stays charged until its owning cleanup.
  assert_eq(@resources.ledger_usage(startup.ledger).attempts, 0)
  assert_eq(@resources.ledger_usage(startup.ledger).reserved_attempts, 1)
  assert_true(@resources.capacity_reservation_open(startup.capacity))
  assert_true(cleanup_model_execution(active).unwrap())
  assert_eq(@resources.ledger_usage(startup.ledger).attempts, 0)
  assert_eq(@resources.ledger_usage(startup.ledger).reserved_attempts, 0)
}
