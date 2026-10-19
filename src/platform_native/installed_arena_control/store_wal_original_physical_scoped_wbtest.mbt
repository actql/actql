///|
/// This receiver selects one actual Read and the selected SQLite Library's
/// own heap. It does not emulate the CLI's distinct business continuation.
struct StoreWalReceiver {
  host : InstalledArenaHost
  domain : InstalledArenaDomain
  library : @sqlite.Library
  mut active : Bool
  mut cleanup : Bool
  mut sql : Bool
  mut sql_entries : Int
}

///|
#borrow(library)
extern "C" fn store_wal_library_children(library : @sqlite.Library) -> Int = "actql_native_sqlite_test_library_database_children"

///|
#borrow(library, receiver)
extern "C" fn store_wal_prepare_original(
  library : @sqlite.Library,
  receiver : StoreWalReceiver,
  route : FuncRef[(StoreWalReceiver, @sqlite.Library, Int) -> Int],
) -> @sqlite.NativeStoreOperationOriginal = "actql_native_sqlite_test_prepare_store_wal_operation"

///|
fn store_wal_entered(receiver : StoreWalReceiver) -> Bool {
  let domain = receiver.domain
  guard domain.domain is Some(original) else { return false }
  if receiver.cleanup {
    domain.backing.require_backed_read_cleanup_entered(
      receiver.host,
      original,
      domain,
    )
    is Ok(_)
  } else {
    domain.backing.require_backed_read_context_entered(
      receiver.host,
      original,
      domain,
    )
    is Ok(_)
  }
}

///|
fn store_wal_route(
  receiver : StoreWalReceiver,
  library : @sqlite.Library,
  tag : Int,
) -> Int {
  if !physical_equal(receiver.library, library) {
    return 10
  }
  match tag {
    -1 =>
      if receiver.host.require_domain_read_current(receiver.domain) is Ok(_) {
        0
      } else {
        11
      }
    0 => {
      if receiver.active ||
        receiver.cleanup ||
        receiver.host.enter_domain_read(receiver.domain) is Err(_) {
        return 12
      }
      receiver.active = true
      0
    }
    1 => {
      if !receiver.active || receiver.sql || !store_wal_entered(receiver) {
        return 13
      }
      // The selected adapter checks the exact Library/current context, and
      // the component performs each allocation in its original private heap.
      receiver.sql = true
      receiver.sql_entries += 1
      0
    }
    2 => {
      if !receiver.sql || !store_wal_entered(receiver) {
        return 14
      }
      receiver.sql = false
      0
    }
    3 => {
      if !receiver.active ||
        receiver.sql ||
        receiver.host.leave_domain_read(receiver.domain) is Err(_) {
        return 15
      }
      receiver.active = false
      0
    }
    4 => {
      if receiver.active ||
        receiver.sql ||
        receiver.host.enter_domain_read_cleanup(receiver.domain) is Err(_) {
        return 16
      }
      receiver.cleanup = true
      receiver.active = true
      0
    }
    _ => 17
  }
}

///|
fn store_wal_payload_work(
  library : @sqlite.Library,
  original : @sqlite.NativeStoreOperationOriginal,
  path : String,
) -> Bool {
  let authority = "sha256:" + "1".repeat(64)
  let store = @store.open_original_local_store_with_custody(
    library,
    original,
    path,
    authority,
    128L,
    4L,
    4096L,
    diagnostic_ceiling=Some(256),
  ).unwrap()
  let request = @payload.prepare_publication_payload_request(
    authority,
    "sha256:" + "2".repeat(64),
    "sha256:" + "3".repeat(64),
    "sha256:" + "4".repeat(64),
    "sha256:" + "5".repeat(64),
    "sha256:" + "6".repeat(64),
    "sha256:" + "7".repeat(64),
    "sha256:" + "8".repeat(64),
    16L,
    1L,
  ).unwrap()
  let writer = store.begin_payload(request).unwrap()
  let busy_writer = store.close() is Err(@store.CleanupPending)
  writer.append(b"same-original").unwrap()
  let info = writer.seal().unwrap()
  let reader = store.open_payload_reader(info.material_generation_cid).unwrap()
  let busy_reader = store.close() is Err(@store.CleanupPending)
  let same_bytes = reader.next(32).unwrap().bytes == b"same-original"
  reader.finish().unwrap()
  store.reclaim_payload(info.material_generation_cid).unwrap()
  let usage = store.capacity_usage().unwrap()
  // Routing metadata cannot acknowledge the still-open original Database.
  let original_busy = original.close_checked() is Err(_)
  let first_close = store.close().unwrap()
  let second_close = store.close().unwrap()
  original.close_checked().unwrap()
  busy_writer &&
  busy_reader &&
  same_bytes &&
  original_busy &&
  usage.reserved_bytes == 0L &&
  first_close &&
  !second_close
}

///|
fn store_wal_original_work(
  host : InstalledArenaHost,
  sqlite : InstalledArenaSqliteLibrary,
  path : String,
) -> Bool {
  let library = sqlite.library.unwrap()
  let receiver : StoreWalReceiver = {
    host,
    domain: sqlite.domain,
    library,
    active: false,
    cleanup: false,
    sql: false,
    sql_entries: 0,
  }
  let original = store_wal_prepare_original(library, receiver, fn(
    receiver,
    library,
    tag,
  ) {
    store_wal_route(receiver, library, tag)
  })
  original.activate().unwrap()
  let result = store_wal_payload_work(library, original, path)
  result &&
  receiver.sql_entries > 0 &&
  !receiver.active &&
  !receiver.sql &&
  receiver.cleanup &&
  original.primary_code() == 0 &&
  original.cleanup_code() == 0
}

///|
test "selected original Store WAL payload and separate physical cleanup" {
  let root = @env.get_env_var("ACTQL_TEST_INSTALLED_PROCESS_ROOT").unwrap()
  let component = @env.get_env_var("ACTQL_TEST_SQLITE_COMPONENT").unwrap()
  let page = domain_page_bytes()
  let descriptor = process_test_open(@utf8.encode(root + "/backing\u{0}"), 2)
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
  ).retained_execution_value("Store WAL Host")
  host.acquire_fd(descriptor).retained_execution_value("Store WAL descriptor")
  let backing = host
    .borrow_backing()
    .retained_execution_value("Store WAL backing")
  host
  .enter_backing_borrow_scope(backing)
  .retained_execution_value("Store WAL backing entry")
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
    .retained_execution_value("Store WAL domain") {
    PreparedDomain(value) => value
    PendingDomain(_, _) => fail("original Store WAL domain pending")
  }
  host
  .transfer_domain(domain)
  .retained_execution_value("Store WAL domain transfer")
  host
  .leave_backing_borrow_scope(backing)
  .retained_execution_value("Store WAL backing leave")
  host
  .return_backing_borrow(backing)
  .retained_execution_value("Store WAL backing return")
  host.prepare_domain_read(domain).retained_execution_value("Store WAL Read")
  let sqlite = match
    host
    .prepare_sqlite_library(domain, component, 32L * page, 128)
    .retained_execution_value("Store WAL Library") {
    ReadySqlite(value) => value
    PendingSqlite(_, _) => fail("original Store WAL Library pending")
  }
  let result = store_wal_original_work(host, sqlite, root + "/store")
  let children = store_wal_library_children(sqlite.library.unwrap())
  match host.close_sqlite_library(sqlite) {
    Ok(_) => ()
    Err(Library(_)) =>
      fail("Store WAL Library ACK pending; Database children=\{children}")
    Err(Domain(@bootstrap.Bootstrap(@bootstrap.Physical(code)))) =>
      fail(
        "Store WAL Library scope cleanup code=\{code}; Database children=\{children}",
      )
    Err(Domain(_)) =>
      fail(
        "Store WAL Library domain cleanup pending; Database children=\{children}",
      )
  }
  host
  .close_domain_after_owner_ack(domain)
  .retained_execution_value("Store WAL domain ACK")
  host.try_close().retained_execution_value("Store WAL Host ACK")
  assert_eq(process_test_close(descriptor), 0)
  assert_true(result)
}
