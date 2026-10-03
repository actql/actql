///|
test "provider work includes terminal deltas and cleanup cannot double charge" {
  let index = Ref(0)
  let reclaimed = Ref(false)
  let create : (
    (Int) -> Result[ManagedProviderPoll, @connector.FixedComputeIssue],
    () -> Bool,
    () -> Bool,
    () -> Result[Bool, @connector.FixedComputeIssue],
  ) -> ManagedProviderExecution = managed_provider_execution
  let owner = create(
    fn(_) {
      index.val += 1
      match index.val {
        1 => Ok(managed_provider_continue(0L, 1L))
        2 => Ok(managed_provider_failed(@connector.InvalidLimits, 0L, 1L))
        _ => Err(@connector.InvalidLimits)
      }
    },
    fn() { false },
    fn() { index.val >= 2 },
    fn() {
      reclaimed.val = true
      Ok(true)
    },
  )
  assert_eq(managed_provider_cumulative_work(owner), Ok(0L))
  advance_managed_provider(owner, 1).unwrap() |> ignore
  advance_managed_provider(owner, 1).unwrap() |> ignore
  assert_eq(managed_provider_cumulative_work(owner), Ok(2L))
  assert_true(advance_managed_provider(owner, 1) is Err(_))
  cleanup_managed_provider(owner).unwrap() |> ignore
  cleanup_managed_provider(owner).unwrap() |> ignore
  assert_true(reclaimed.val)
  assert_eq(managed_provider_cumulative_work(owner), Ok(2L))
}

///|
test "provider work overflow is sticky while stop and cleanup remain possible" {
  let cancelled = Ref(false)
  let stopped = Ref(false)
  let cleanup_count = Ref(0)
  let productive = Ref(0)
  let owner = managed_provider_execution(
    fn(_) {
      if stopped.val {
        return Err(@connector.InvalidLimits)
      }
      if cancelled.val {
        stopped.val = true
        Ok(managed_provider_stopped_poll(0L, 1L))
      } else {
        productive.val += 1
        Ok(managed_provider_continue(0L, 1L))
      }
    },
    fn() {
      let changed = !cancelled.val
      cancelled.val = true
      changed
    },
    fn() { stopped.val },
    fn() {
      if !stopped.val {
        return Ok(false)
      }
      if cleanup_count.val >= 3 {
        return Ok(true)
      }
      cleanup_count.val += 1
      match cleanup_count.val {
        1 => Ok(false)
        2 => Err(@connector.InvalidLimits)
        _ => Ok(true)
      }
    },
  )
  // Boundary injection into the SAME private owner, not a second ledger or
  // billions of productive calls. The next two deltas cross Int64::max.
  owner.reported_work = Ok(9223372036854775806L)
  advance_managed_provider(owner, 1).unwrap() |> ignore
  assert_eq(managed_provider_cumulative_work(owner), Ok(9223372036854775807L))
  advance_managed_provider(owner, 1).unwrap() |> ignore
  assert_eq(managed_provider_cumulative_work(owner), Err(CounterOverflow))
  assert_true(cancelled.val)
  assert_false(cleanup_managed_provider(owner).unwrap())
  assert_true(
    advance_managed_provider(owner, 1).unwrap() is Stopped(work=1L, ..),
  )
  assert_eq(productive.val, 2)
  assert_false(cleanup_managed_provider(owner).unwrap())
  assert_true(cleanup_managed_provider(owner) is Err(_))
  assert_true(cleanup_managed_provider(owner).unwrap())
  assert_true(cleanup_managed_provider(owner).unwrap())
  assert_eq(cleanup_count.val, 3)
  assert_eq(managed_provider_cumulative_work(owner), Err(CounterOverflow))
}

///|
test "invalid provider work cannot become a normal cumulative total" {
  let cancelled = Ref(false)
  let owner = managed_provider_execution(
    _ => Ok(managed_provider_continue(0L, 2L)),
    fn() {
      cancelled.val = true
      true
    },
    fn() { false },
    fn() { Ok(false) },
  )
  advance_managed_provider(owner, 1).unwrap() |> ignore
  assert_eq(managed_provider_cumulative_work(owner), Err(InvalidReport))
  assert_true(cancelled.val)
}

///|
test "snapshot handoff work uses the provider total and reads cleanup do not charge" {
  let owner = managed_provider_execution(
    _ => Ok(managed_provider_failed(@connector.InvalidLimits, 0L, 1L)),
    () => true,
    () => true,
    () => Ok(true),
  )
  advance_managed_provider(owner, 1).unwrap() |> ignore
  managed_provider_record_handoff_work(owner, 2L).unwrap()
  managed_provider_record_handoff_work(owner, 0L).unwrap()
  assert_eq(managed_provider_cumulative_work(owner), Ok(3L))
  cleanup_managed_provider(owner).unwrap() |> ignore
  cleanup_managed_provider(owner).unwrap() |> ignore
  assert_eq(managed_provider_cumulative_work(owner), Ok(3L))
  assert_eq(managed_provider_cumulative_work(owner), Ok(3L))
}

///|
test "snapshot handoff invalid delta and overflow stay errors through cleanup" {
  for overflow in [false, true] {
    let cancelled = Ref(false)
    let owner = managed_provider_execution(
      _ => Ok(managed_provider_stopped_poll(0L, 0L)),
      fn() {
        cancelled.val = true
        true
      },
      () => true,
      () => Ok(true),
    )
    if overflow {
      owner.reported_work = Ok(9223372036854775807L)
    }
    let expected = if overflow { CounterOverflow } else { InvalidReport }
    assert_eq(
      managed_provider_record_handoff_work(
        owner,
        if overflow {
          1L
        } else {
          -1L
        },
      ),
      Err(expected),
    )
    assert_true(cancelled.val)
    assert_eq(managed_provider_record_handoff_work(owner, 0L), Err(expected))
    cleanup_managed_provider(owner).unwrap() |> ignore
    assert_eq(managed_provider_cumulative_work(owner), Err(expected))
  }
}
