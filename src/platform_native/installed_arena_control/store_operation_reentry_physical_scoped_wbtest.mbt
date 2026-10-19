///|
struct StoreReentryReceiver {
  host : InstalledArenaHost
  domain : InstalledArenaDomain
  library : @sqlite.Library
  original : Ref[@sqlite.NativeStoreOperationOriginal?]
  mut active : Bool
  mut probe : Int
  mut nested_refused : Bool
}

///|
#borrow(library, receiver)
extern "C" fn reentry_prepare_store_operation(
  library : @sqlite.Library,
  receiver : StoreReentryReceiver,
  route : FuncRef[(StoreReentryReceiver, @sqlite.Library, Int) -> Int],
) -> @sqlite.NativeStoreOperationOriginal = "actql_native_sqlite_prepare_store_operation"

///|
fn store_reentry_route(
  receiver : StoreReentryReceiver,
  library : @sqlite.Library,
  tag : Int,
) -> Int {
  if !physical_equal(library, receiver.library) {
    return 10
  }
  let host = receiver.host
  let domain = receiver.domain
  match tag {
    -1 => if host.require_domain_read_current(domain) is Ok(_) { 0 } else { 11 }
    0 => {
      if receiver.active || host.enter_domain_read(domain) is Err(_) {
        return 12
      }
      receiver.active = true
      if receiver.probe == 0 {
        receiver.nested_refused = receiver.original.val.unwrap().enter_store()
          is Err(_)
      }
      0
    }
    3 => {
      if !receiver.active || host.leave_domain_read(domain) is Err(_) {
        return 13
      }
      receiver.active = false
      if receiver.probe == 3 {
        receiver.nested_refused = receiver.original.val.unwrap().leave_store()
          is Err(_)
      }
      0
    }
    4 => {
      if receiver.active {
        if host.leave_domain_read(domain) is Err(_) {
          return 14
        }
        receiver.active = false
      }
      if host.enter_domain_read_cleanup(domain) is Err(_) {
        return 15
      }
      receiver.active = true
      0
    }
    _ => 16
  }
}

///|
fn store_reentry_original_call(
  host : InstalledArenaHost,
  sqlite : InstalledArenaSqliteLibrary,
  probe : Int,
) -> Bool raise {
  let library = sqlite.library.unwrap()
  let receiver : StoreReentryReceiver = {
    host,
    domain: sqlite.domain,
    library,
    original: Ref(None),
    active: false,
    probe,
    nested_refused: false,
  }
  let original = reentry_prepare_store_operation(
    library, receiver, store_reentry_route,
  )
  // Only this finite counter holds a temporary backlink for the nested call.
  // Release it explicitly; it is not an issuer, registry or retirement proof.
  receiver.original.val = Some(original)
  original.activate().unwrap()
  let outer = if probe == 0 {
    original.enter_store()
  } else {
    original.enter_store().unwrap()
    original.leave_store()
  }
  let refused = outer is Err(_)
  assert_true(receiver.nested_refused)
  assert_eq(original.primary_code(), -2)
  assert_true(original.enter_store() is Err(_))
  receiver.probe = -1
  receiver.original.val = None
  // Old failed=true must not forbid real same-original cleanup recovery.
  original.enter_cleanup().unwrap()
  assert_true(receiver.active)
  original.leave_store().unwrap()
  assert_false(receiver.active)
  assert_eq(original.primary_code(), -2)
  original.close_checked().unwrap()
  refused
}

///|
fn store_reentry_physical_case(probe : Int) -> Unit raise {
  let root = @env.get_env_var("ACTQL_TEST_INSTALLED_PROCESS_ROOT").unwrap()
  let component = @env.get_env_var("ACTQL_TEST_SQLITE_COMPONENT").unwrap()
  let page = domain_page_bytes()
  let descriptor = process_test_open(
    @utf8.encode(root + "/backing-" + probe.to_string() + "\u{0}"),
    2,
  )
  assert_true(descriptor >= 0)
  let host = prepare_installed_arena_host(
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
    256L * page,
    {
      planning_work: 20,
      attempts: 8,
      holdings: 4,
      transfer_bytes: 65536L,
      retained_bytes: 0L,
      execution_bytes: 256L * page,
    },
    65536L,
  ).unwrap()
  host.acquire_fd(descriptor).unwrap()
  let backing = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(backing).unwrap()
  let domain = match
    host
    .prepare_domain(backing, descriptor, 128L * page, {
      planning_work: 8,
      attempts: 4,
      holdings: 2,
      transfer_bytes: 4096L,
      retained_bytes: 0L,
      execution_bytes: 128L * page,
    })
    .unwrap() {
    PreparedDomain(value) => value
    PendingDomain(_, _) => fail("original SQLite domain pending")
  }
  host.transfer_domain(domain).unwrap()
  host.leave_backing_borrow_scope(backing).unwrap()
  host.return_backing_borrow(backing).unwrap()
  host.prepare_domain_read(domain).unwrap()
  let sqlite = match
    host.prepare_sqlite_library(domain, component, 32L * page, 128).unwrap() {
    ReadySqlite(value) => value
    PendingSqlite(_, _) => fail("original selected SQLite Library pending")
  }
  let refused = store_reentry_original_call(host, sqlite, probe)
  host.close_sqlite_library(sqlite).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
  assert_eq(process_test_close(descriptor), 0)
  // Assert the transition result only AFTER the actual original cleanup ACKs.
  assert_true(refused)
}

///|
test "same original receiver cannot ACK enter after nested refusal" {
  store_reentry_physical_case(0)
}

///|
test "same original receiver cannot ACK leave after nested refusal" {
  store_reentry_physical_case(3)
}
