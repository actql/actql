///|
extern "C" fn page_bytes() -> Int64 = "actql_bootstrap_page_bytes"

///|
fn require(count : Ref[Int], condition : Bool, name : String) -> Unit {
  if !condition {
    abort("installed original channel conformance failed: " + name)
  }
  count.val += 1
  println("case:" + count.val.to_string() + ":" + name)
}

///|
// The only physical input is a fresh disposable 64-page FD on stdin. Invalid
// pipe descriptors deliberately acquire no process, VM, pipe or FD custody.
// Its explicit metadata retirement therefore acknowledges only this refusal.
fn main {
  let count = Ref(0)
  let page = page_bytes()
  let bytes = 64L * page
  let host = @control.prepare_installed_arena_host(
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
    bytes,
    {
      planning_work: 20,
      attempts: 8,
      holdings: 4,
      transfer_bytes: 30L,
      retained_bytes: 0L,
      execution_bytes: bytes,
    },
    65536L,
  ).unwrap()
  host.acquire_fd(0).unwrap()
  let other = @control.prepare_installed_arena_host(
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
    bytes,
    {
      planning_work: 20,
      attempts: 8,
      holdings: 4,
      transfer_bytes: 30L,
      retained_bytes: 0L,
      execution_bytes: bytes,
    },
    65536L,
  ).unwrap()
  let scope = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(scope).unwrap()
  let domain = match
    host
    .prepare_domain(scope, 0, 24L * page, {
      planning_work: 2,
      attempts: 1,
      holdings: 1,
      transfer_bytes: 3L,
      retained_bytes: 0L,
      execution_bytes: 24L * page,
    })
    .unwrap() {
    @control.PreparedDomain(value) => value
    @control.PendingDomain(_, issue) =>
      abort("original fixture domain unavailable: " + @debug.to_string(issue))
  }
  require(
    count,
    @control.prepare_installed_arena_live_channel_reply(
      host, domain, 1, -1, -1, 7L,
    ).issue_family() ==
    1,
    "untransferred installed domain cannot capture a channel",
  )
  host.transfer_domain(domain).unwrap()
  host.leave_backing_borrow_scope(scope).unwrap()
  let foreign = @control.prepare_installed_arena_live_channel_reply(
    other, domain, 1, -1, -1, 7L,
  )
  require(
    count,
    foreign.issue_family() == 2 &&
    physical_equal(foreign.original_host(), host) &&
    physical_equal(foreign.original_domain(), domain) &&
    foreign.original_channel() is None,
    "foreign target retains actual original Host and domain without capture",
  )
  let captured = @control.prepare_installed_arena_live_channel_reply(
    host, domain, 1, -1, -1, 7L,
  )
  let channel = captured.original_channel().unwrap()
  require(
    count,
    captured.operation_tag() == 1 &&
    captured.issue_family() == 6 &&
    physical_equal(captured.original_host(), host) &&
    physical_equal(captured.original_domain(), domain),
    "failed physical capture retains the same original partial channel",
  )
  let duplicate = @control.prepare_installed_arena_live_channel_reply(
    host, domain, 1, -1, -1, 7L,
  )
  require(
    count,
    duplicate.issue_family() == 3 && duplicate.original_channel() is None,
    "lost failed-capture reply cannot issue another channel",
  )
  let observed = @control.operate_installed_arena_live_channel_reply(
    host, domain, channel, 4,
  )
  let limits = @control.operate_installed_arena_live_channel_reply(
    host, domain, channel, 5,
  )
  require(
    count,
    observed.issue_family() == 1 &&
    observed.state_tag() == -1 &&
    limits.issue_family() == 1 &&
    limits.limit(0) == -1L &&
    limits.limit(5) == -1L &&
    limits.limit(6) == -1L,
    "pending channel projects neither an admitted state nor zero-valued limits",
  )
  let capacities = @control.operate_installed_arena_live_channel_reply(
    host, domain, channel, 9,
  )
  require(
    count,
    capacities.operation_tag() == 9 &&
    capacities.issue_family() == 1 &&
    capacities.limit(6) == -1L &&
    capacities.limit(7) == -1L &&
    capacities.limit(0) == -1L,
    "pending channel cannot project a baseline or infer capacity from payload",
  )
  let foreign_capacity = @control.operate_installed_arena_live_channel_reply(
    other, domain, channel, 9,
  )
  require(
    count,
    foreign_capacity.issue_family() == 2 &&
    foreign_capacity.limit(6) == -1L &&
    foreign_capacity.limit(7) == -1L &&
    physical_equal(foreign_capacity.original_host(), host),
    "foreign Host cannot acquire the original baseline coverage",
  )
  let binding = @control.bind_installed_arena_live_channel_reply(
    host, domain, channel, 7L, 0L, 16777216L,
  )
  let rebound = @control.bind_installed_arena_live_channel_reply(
    host, domain, channel, 7L, 0L, 16777216L,
  )
  require(
    count,
    binding.operation_tag() == 2 &&
    binding.issue_family() == 6 &&
    rebound.issue_family() == 3 &&
    physical_equal(binding.original_channel().unwrap(), channel),
    "failed original VM binding is retained and cannot be repeated",
  )
  let admission = @control.operate_installed_arena_live_channel_reply(
    host, domain, channel, 3,
  )
  let report = @control.report_installed_arena_live_channel_reply(
    host, domain, channel, 0, 0, 0, 0L, 0L, 0L, 0L, 0L, 0L, 0L, 0, 0, 0,
  )
  let stop = @control.operate_installed_arena_live_channel_reply(
    host, domain, channel, 7,
  )
  require(
    count,
    admission.issue_family() == 1 &&
    report.issue_family() == 1 &&
    stop.issue_family() == 1,
    "pending physical channel cannot admit report or acknowledge child stop",
  )
  let invalid = @control.operate_installed_arena_live_channel_reply(
    host, domain, channel, 6,
  )
  require(
    count,
    invalid.operation_tag() == -1 &&
    invalid.issue_family() == 1 &&
    physical_equal(invalid.original_channel().unwrap(), channel),
    "report requires its typed callback rather than a scalar operation tag",
  )
  require(
    count,
    host.close_domain_after_owner_ack(domain) is Err(@bootstrap.Accounting(_)) &&
    host.try_close() is Err(_),
    "pending channel retains original domain and Host cleanup responsibility",
  )
  let foreign_cleanup = @control.operate_installed_arena_live_channel_reply(
    other, domain, channel, 8,
  )
  require(
    count,
    foreign_cleanup.issue_family() == 2 &&
    physical_equal(foreign_cleanup.original_host(), host),
    "foreign Host cannot retire partial custody after logical closing",
  )
  let retired = @control.operate_installed_arena_live_channel_reply(
    host, domain, channel, 8,
  )
  require(
    count,
    retired.operation_tag() == 8 &&
    retired.issue_family() == 0 &&
    physical_equal(retired.original_channel().unwrap(), channel),
    "original pending metadata retires after closing without claiming worker or FD stop",
  )
  let again = @control.operate_installed_arena_live_channel_reply(
    host, domain, channel, 8,
  )
  require(
    count,
    again.issue_family() == 2,
    "retired handle cannot acknowledge or retire the same metadata twice",
  )
  let cleanup = host.close_domain_after_owner_ack(domain)
  println("original_cleanup:" + @debug.to_string(cleanup))
  require(
    count,
    cleanup is Err(@bootstrap.Bootstrap(@bootstrap.ReadersPending)),
    "original backing borrower still fences physical allocation retirement",
  )
  host.return_backing_borrow(scope).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
  other.try_close().unwrap()
  require(
    count,
    host.require_current() is Err(@bootstrap.Closing),
    "original domain loan and Host retire separately after channel metadata",
  )
  println(
    "{\"success\":true,\"discovered\":16,\"executed\":16,\"passed\":16,\"failed\":0,\"VM\":0,\"public_e2e\":0}",
  )
}
