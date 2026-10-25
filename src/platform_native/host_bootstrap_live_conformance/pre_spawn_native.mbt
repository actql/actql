///|
extern "C" fn prepare_fixture_pipes_ffi() -> Int = "actql_live_fixture_prepare_pipes"

///|
fn prepare_fixture_pipes() -> Result[Unit, Int] {
  let status = prepare_fixture_pipes_ffi()
  if status == 0 {
    Ok(())
  } else {
    Err(status)
  }
}

///|
extern "C" fn fixture_pipe(ordinal : Int) -> Int = "actql_live_fixture_pipe"

///|
extern "C" fn fixture_pid() -> Int = "actql_live_fixture_pid"

///|
extern "C" fn close_fixture_pipes_ffi() -> Int = "actql_live_fixture_close_pipes"

///|
fn close_fixture_pipes() -> Result[Unit, Int] {
  let status = close_fixture_pipes_ffi()
  if status == 0 {
    Ok(())
  } else {
    Err(status)
  }
}

///|
/// Actual borrowed pipes enter the same Native/Common issuer before spawn.
/// No process, child mapping or VM is launched or admitted by this fixture.
fn exercise_pre_spawn_channel(
  count : Ref[Int],
  host : @bootstrap.NativeHostBootstrap[LiveOriginal],
  original : LiveOriginal,
  page : Int64,
  scope : @bootstrap.NativeBootstrapBorrow[LiveOriginal],
) -> Unit {
  let child : LiveChild = { marker: 3, }
  let foreign : LiveChild = { marker: 3, }
  let allocation = host.allocate(original, 24L * page).unwrap()
  let region : @bootstrap.NativeBackedExecutionRegion[LiveOriginal, LiveChild] = host
    .issue_backed_region(original, allocation)
    .unwrap()
  host.enter_borrow_scope(original, scope).unwrap()
  let loan = match
    host
    .lend_backed_region(
      original,
      region,
      scope,
      child,
      {
        offset: 0L,
        length: 24L * page,
        payload_offset: page,
        payload_length: 16L * page,
      },
      @resources.ExclusiveWrite,
      {
        planning_work: 2,
        attempts: 1,
        holdings: 1,
        transfer_bytes: 3L,
        retained_bytes: 0L,
        execution_bytes: 16L * page,
      },
      0L,
      0L,
    )
    .unwrap() {
    Lent(value) => value
    _ => abort("same original channel fixture loan unavailable")
  }
  let view = match host.map_backed_view(original, loan, child, 0).unwrap() {
    Mapped(value) => value
    _ => abort("same original channel fixture view unavailable")
  }
  let domain = match
    host.acquire_backed_domain(original, view, child).unwrap() {
    DomainReady(value) => value
    _ => abort("same original channel fixture domain unavailable")
  }
  host.leave_borrow_scope(original, scope).unwrap()
  require(
    count,
    host.prepare_backed_live_channel_before_spawn(
      original, domain, child, -1, -1, 7L,
    )
    is Err(Bootstrap(Unavailable)),
    "untransferred physical channel cannot issue a live access",
  )
  host.transfer_backed_domain(original, domain, child).unwrap()
  require(
    count,
    host.prepare_backed_live_channel_before_spawn(
      original, domain, foreign, -1, -1, 7L,
    )
    is Err(Bootstrap(ForeignOriginal)),
    "equal-valued foreign child cannot capture the same channel",
  )
  prepare_fixture_pipes().unwrap()
  let read_fd = fixture_pipe(0)
  let write_fd = fixture_pipe(1)
  let before = host.usage()
  let channel = match
    host
    .prepare_backed_live_channel_before_spawn(
      original, domain, child, read_fd, write_fd, 7L,
    )
    .unwrap() {
    PreparedLiveChannel(value) => value
    _ => abort("same original pre-spawn channel unavailable")
  }
  require(
    count,
    host.usage() == before,
    "pre-spawn access retains the same ticket without another parent reservation",
  )
  require(
    count,
    host.prepare_backed_original_channel_ledger({ marker: 1, }, channel)
    is Err(Domain(Bootstrap(ForeignOriginal))) &&
    host.usage() == before,
    "equal-valued foreign Host cannot obtain an original channel Ledger",
  )
  let frame = host
    .prepare_backed_original_channel_ledger(original, channel)
    .unwrap()
  require(
    count,
    @resources.take_imported_original_child_ledger(frame) is Err(Unavailable) &&
    host.usage() == before,
    "prepared same-ticket frame is not started and adds no parent reservation",
  )
  require(
    count,
    host.prepare_backed_original_channel_ledger(original, channel)
    is Err(Domain(Bootstrap(AlreadyConsumed))) &&
    host.usage() == before,
    "lost frame reply cannot issue another nominal child or allowance",
  )
  @resources.start_imported_child_ledger(frame).unwrap()
  let ledger = @resources.take_imported_original_child_ledger(frame).unwrap()
  require(
    count,
    @resources.ledger_usage(ledger).reserved_execution_bytes == 0L &&
    @resources.ledger_limits(ledger).execution_bytes == 16L * page &&
    @resources.take_imported_child_ledger(frame) is Err(Unavailable) &&
    host.usage() == before,
    "same original child has inherited limits but no seeded VM or Host capacities",
  )
  require(
    count,
    @resources.start_imported_child_ledger(frame) is Err(AlreadyConsumed) &&
    @resources.take_imported_original_child_ledger(frame)
    is Err(AlreadyConsumed),
    "frame start and original Ledger take remain one-shot",
  )
  require(
    count,
    @resources.reserve_shared_capacity(ledger, 17L * page)
    is Err(ExecutionLimit) &&
    host.usage() == before &&
    @resources.ledger_usage(ledger).attempts == 0,
    "child cannot widen inherited bytes or consume another parent allowance",
  )
  let child_capacity = @resources.reserve_shared_capacity(ledger, page).unwrap()
  require(
    count,
    @resources.ledger_usage(ledger).reserved_execution_bytes == page &&
    @resources.ledger_usage(ledger).attempts == 0 &&
    @resources.ledger_usage(ledger).reserved_attempts == 1 &&
    @resources.ledger_usage(ledger).live_reservations == 1 &&
    host.usage() == before,
    "child reservation subaccounts original backing without parent double charge",
  )
  @resources.report_imported_child_ledger(frame).unwrap()
  let reported = host.usage()
  require(
    count,
    reported ==
    {
      ..before,
      reserved_attempts: before.reserved_attempts + 1,
      live_reservations: before.live_reservations + 1,
    },
    "actual child snapshot reports live reservation without consuming an attempt",
  )
  @resources.report_imported_child_ledger(frame).unwrap()
  require(
    count,
    host.usage() == reported,
    "duplicate cumulative child report cannot recharge original backing or quota",
  )
  require(
    count,
    host.prepare_backed_live_channel_before_spawn(
      original, domain, child, read_fd, write_fd, 7L,
    )
    is Err(Bootstrap(AlreadyConsumed)),
    "lost prepare reply cannot recapture original pipes or issue another access",
  )
  require(
    count,
    host.admit_backed_live_channel(original, channel)
    is Err(Bootstrap(Unavailable)),
    "actual pre-spawn access does not admit child VM",
  )
  require(
    count,
    host.backed_live_channel_limits(original, channel)
    is Err(Bootstrap(Physical(-3))),
    "pre-spawn pipes alone do not supply admitted child limits",
  )
  require(
    count,
    host.close_backed_domain(original, domain, child)
    is Err(Accounting(@resources.CleanupPending)),
    "prepared access fences domain retirement before original cleanup ACK",
  )
  require(
    count,
    host.bind_backed_live_channel_child(original, channel, fixture_pid())
    is Err(Bootstrap(Physical(-1))),
    "actual parent PID refuses before child admission",
  )
  require(
    count,
    host.bind_backed_live_channel_child(original, channel, 1)
    is Err(Bootstrap(AlreadyConsumed)),
    "failed child bind retains original one-shot custody",
  )
  @resources.stop_imported_child_ledger(frame).unwrap()
  require(
    count,
    @resources.reserve_capacity(ledger, 0L, 1L) is Err(ClosedReservation) &&
    host.usage() == reported,
    "logical child stop denies new work without physical retirement or refund",
  )
  @resources.close_shared_capacity(child_capacity).unwrap()
  @resources.settle_shared_capacity(child_capacity).unwrap()
  @resources.report_imported_child_ledger(frame).unwrap()
  let cleaned = host.usage()
  require(
    count,
    @resources.ledger_usage(ledger).reserved_execution_bytes == 0L &&
    cleaned == before,
    "same original cleanup returns live counts without changing parent physical reservation",
  )
  require(
    count,
    host.stop_backed_live_channel_transport_use({ marker: 1, }, channel)
    is Err(Domain(Bootstrap(ForeignOriginal))) &&
    host.usage() == cleaned,
    "foreign original cannot end another channel's transport use",
  )
  host.stop_backed_live_channel_transport_use(original, channel).unwrap()
  require(
    count,
    host.usage() == cleaned,
    "transport closing issues no physical retirement or quota return",
  )
  host.stop_backed_live_channel_transport_use(original, channel).unwrap()
  require(
    count,
    host.usage() == cleaned,
    "same original repeated transport stop preserves cumulative accounting",
  )
  require(
    count,
    host.prepare_backed_original_channel_ledger(original, channel)
    is Err(Domain(Bootstrap(Closing))),
    "transport closing prevents another frame before examining physical pipes",
  )
  require(
    count,
    host.bind_backed_live_channel_child(original, channel, 1)
    is Err(Bootstrap(Closing)),
    "transport closing refuses fresh child binding without touching original pipes",
  )
  require(
    count,
    host.bind_backed_live_channel_vm(original, channel, 7L, page, 16777216L)
    is Err(Bootstrap(Closing)),
    "transport closing refuses VM observation without converting it to permission",
  )
  require(
    count,
    host.backed_live_channel_state(original, channel) is Err(Bootstrap(Closing)),
    "transport closing fences physical observation before descriptor return",
  )
  close_fixture_pipes().unwrap()
  host.report_backed_channel_ledger(original, channel, frame).unwrap()
  require(
    count,
    host.backed_live_channel_state(original, channel) is Err(Bootstrap(Closing)) &&
    host.usage() == cleaned,
    "closed endpoints cannot be reobserved while same-original cleanup report remains available",
  )
  // No spawn occurred. The fixture has now confirmed its exact pipe closes;
  // metadata retirement neither closes the domain nor settles its parent loan.
  host.retire_backed_live_channel_after_owner_ack(original, channel).unwrap()
  require(
    count,
    host.bind_backed_live_channel_child(original, channel, 1)
    is Err(Bootstrap(ForeignOriginal)) &&
    host.usage() == cleaned,
    "retired channel cannot regain identity or return the parent allowance",
  )
  require(
    count,
    @resources.reserve_capacity(ledger, 0L, 1L) is Err(ForeignOwner) &&
    host.prepare_backed_original_channel_ledger(original, channel)
    is Err(Domain(Bootstrap(ForeignOriginal))) &&
    host.usage() == cleaned,
    "owner ACK retirement invalidates escaped Ledger without another child or refund",
  )
  host.close_backed_domain(original, domain, child).unwrap()
  host.close_backed_view(original, view, child).unwrap()
  host
  .settle_backed_region_after_owner_ack(original, loan, child, None)
  .unwrap()
  require(
    count,
    host.close_backed_region(original, region).unwrap(),
    "same original domain loan and allocation retire separately",
  )
}
