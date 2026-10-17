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
  close_fixture_pipes().unwrap()
  // No spawn occurred. The fixture has now confirmed its exact pipe closes;
  // metadata retirement neither closes the domain nor settles its parent loan.
  host.retire_backed_live_channel_after_owner_ack(original, channel).unwrap()
  require(
    count,
    host.bind_backed_live_channel_child(original, channel, 1)
    is Err(Bootstrap(ForeignOriginal)) &&
    host.usage() == before,
    "retired channel cannot regain identity or return the parent allowance",
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
