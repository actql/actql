///|
/// No process/channel is launched by this Native conformance. Invalid borrowed
/// descriptors test original partial custody, not a physical VM positive.
fn exercise_channel_partial(
  count : Ref[Int],
  host : @bootstrap.NativeHostBootstrap[LiveOriginal],
  original : LiveOriginal,
  page : Int64,
  scope : @bootstrap.NativeBootstrapBorrow[LiveOriginal],
) -> Unit {
  let child : LiveChild = { marker: 2, }
  let foreign : LiveChild = { marker: 2, }
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
    host.prepare_backed_live_channel(original, domain, child, 1, -1, -1, 7L)
    is Err(Bootstrap(Unavailable)),
    "untransferred physical channel cannot issue a live access",
  )
  host.transfer_backed_domain(original, domain, child).unwrap()
  require(
    count,
    host.prepare_backed_live_channel(original, domain, foreign, 1, -1, -1, 7L)
    is Err(Bootstrap(ForeignOriginal)),
    "equal-valued foreign child cannot capture the same channel",
  )
  let before = host.usage()
  let channel = match
    host
    .prepare_backed_live_channel(original, domain, child, 1, -1, -1, 7L)
    .unwrap() {
    PendingLiveChannel(value, Bootstrap(Physical(-1))) => value
    _ => abort("invalid descriptors must retain an original pending carrier")
  }
  require(
    count,
    host.usage() == before,
    "failed channel capture creates no reservation or replacement allowance",
  )
  require(
    count,
    host.close_backed_domain(original, domain, child)
    is Err(Accounting(@resources.CleanupPending)),
    "pending physical channel keeps domain cleanup fenced",
  )
  require(
    count,
    host.prepare_backed_live_channel(original, domain, child, 1, -1, -1, 7L)
    is Err(Bootstrap(AlreadyConsumed)),
    "failed original channel capture cannot start another capture",
  )
  require(
    count,
    host.admit_backed_live_channel(original, channel)
    is Err(Bootstrap(Unavailable)),
    "pending physical channel has no child admission authority",
  )
  require(
    count,
    host.bind_backed_live_channel_vm(original, channel, 7L, page, 16777216L)
    is Err(Bootstrap(Physical(-1))),
    "original VM binding refuses failed physical capture",
  )
  require(
    count,
    host.bind_backed_live_channel_vm(original, channel, 7L, page, 16777216L)
    is Err(Bootstrap(AlreadyConsumed)),
    "failed VM binding cannot silently reissue on the same channel",
  )
  // No descriptors or child were acquired in this negative fixture. The
  // existing caller can therefore acknowledge only this metadata retirement.
  host.retire_backed_live_channel_after_owner_ack(original, channel).unwrap()
  require(
    count,
    host.prepare_backed_live_channel(original, domain, child, 1, -1, -1, 7L)
    is Err(Bootstrap(AlreadyConsumed)) &&
    host.usage() == before,
    "metadata retirement does not reset the original channel generation",
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
