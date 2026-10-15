///|
extern "C" fn page_bytes() -> Int64 = "actql_bootstrap_page_bytes"

///|
fn require(count : Ref[Int], condition : Bool, name : String) -> Unit {
  if !condition {
    abort("installed parent-read conformance failed: " + name)
  }
  count.val += 1
  println("case:" + count.val.to_string() + ":" + name)
}

///|
fn retain_scoped_alias(
  host : @control.InstalledArenaHost,
  record : @control.InstalledArenaOriginalRead,
  slot : Ref[Bytes?],
) -> Unit {
  host.enter_domain_original_read(record).unwrap()
  slot.val = Some(Bytes::make(16, 73))
  host.leave_domain_original_read(record).unwrap()
}

///|
/// One fresh disposable 64-page FD on stdin. The selected derived runtime
/// supplies the same provider/TLS for this parent context and managed alias.
/// These diagnostic declarations are not an installed numerical profile.
fn main {
  let count = Ref(0)
  let page = page_bytes()
  let bytes = 64L * page
  let host_limits : @resources.LedgerLimits = {
    planning_work: 20,
    attempts: 8,
    holdings: 4,
    transfer_bytes: 30L,
    retained_bytes: 0L,
    execution_bytes: bytes,
  }
  let host = @control.prepare_installed_arena_host(
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
    bytes,
    host_limits,
    65536L,
  ).unwrap()
  host.acquire_fd(0).unwrap()
  let scope = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(scope).unwrap()
  let child_limits : @resources.LedgerLimits = {
    planning_work: 2,
    attempts: 2,
    holdings: 1,
    transfer_bytes: 3L,
    retained_bytes: 2L * page,
    execution_bytes: 16L * page,
  }
  let domain = match
    host.prepare_domain(scope, 0, 48L * page, child_limits).unwrap() {
    PreparedDomain(domain) => domain
    _ => abort("original FD domain unavailable")
  }
  host.transfer_domain(domain).unwrap()
  host.prepare_domain_read(domain).unwrap()
  host.leave_backing_borrow_scope(scope).unwrap()
  let budget : @control.InstalledArenaOriginalReadBudget = {
    bootstrap_retained: page,
    bootstrap_execution: page,
    workspace_execution: 8L * page,
    read_retained: page,
    read_execution: 4L * page,
  }
  let record = match
    host.prepare_domain_original_read(domain, budget).unwrap() {
    ReadyOriginalRead(record) => record
    _ => abort("same original child read preparation failed")
  }
  require(
    count,
    host.borrow_domain_original_read(record) is Ok(_),
    "same C context issues the joined census workspace and read",
  )
  require(
    count,
    host.prepare_domain_original_read(domain, budget)
    is Err(Domain(@bootstrap.Bootstrap(AlreadyConsumed))),
    "same original context cannot issue another attempt",
  )
  require(
    count,
    host.close_domain_read(domain) is Err(@bootstrap.Bootstrap(ReadersPending)),
    "generic context close cannot bypass original read custody",
  )
  require(
    count,
    host.prepare_sqlite_library(domain, "/not-loaded", page, 128)
    is Err(Domain(@bootstrap.Bootstrap(AlreadyConsumed))),
    "another SQLite purpose cannot consume the same original read domain",
  )
  let escaped : Ref[Bytes?] = Ref(None)
  retain_scoped_alias(host, record, escaped)
  require(
    count,
    escaped.val is Some(value) && value[0] == 73,
    "real managed alias remains valid after scope leave",
  )
  require(
    count,
    host.close_domain_original_read(record)
    is Err(Domain(@bootstrap.Bootstrap(Physical(_)))),
    "escaped physical alias keeps original cleanup pending",
  )
  require(
    count,
    host.borrow_domain_original_read(record) is Err(_),
    "logical closing refuses another read while retaining original cleanup",
  )
  escaped.val = None
  host.close_domain_original_read(record).unwrap()
  host.close_domain_original_read(record).unwrap()
  require(
    count,
    host.borrow_domain_original_read(record) is Err(_),
    "last alias ACK closes the same carrier once without reissuance",
  )
  host.return_backing_borrow(scope).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
  println(
    "{\"success\":true,\"discovered\":8,\"executed\":8,\"passed\":8,\"failed\":0,\"all_originals_closed\":true,\"VM\":0,\"public_e2e\":0}",
  )
}
