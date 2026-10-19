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
  mut normal_entries : Int
  mut fail_cleanup_return : Bool
  mut fail_normal_return : Bool
  mut return_ack_pending : Bool
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
      receiver.normal_entries += 1
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
      if receiver.return_ack_pending {
        // Retry confirms only the SAME physical leave already observed below.
        if receiver.active || receiver.sql || !receiver.cleanup {
          return 18
        }
        receiver.return_ack_pending = false
        return 0
      }
      if !receiver.active ||
        receiver.sql ||
        receiver.host.leave_domain_read(receiver.domain) is Err(_) {
        return 15
      }
      receiver.active = false
      if !receiver.cleanup && receiver.fail_normal_return {
        receiver.fail_normal_return = false
        receiver.return_ack_pending = true
        return 33
      }
      if receiver.cleanup && receiver.fail_cleanup_return {
        receiver.fail_cleanup_return = false
        receiver.return_ack_pending = true
        return 44
      }
      0
    }
    4 => {
      if receiver.active ||
        receiver.sql ||
        receiver.host.enter_domain_read_cleanup(receiver.domain) is Err(_) {
        return 16
      }
      receiver.cleanup = true
      // Only the actual same original leave ACK captured by this receiver is
      // consumed. Recovery enters cleanup, never a normal or replacement use.
      receiver.return_ack_pending = false
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
  receiver : StoreWalReceiver,
  path : String,
  normal_probe : Bool,
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
  let retained_alias = store
  let first_close_pending = if normal_probe {
    receiver.fail_normal_return = true
    let pending = store.capacity_usage() is Err(@store.OperationRouting(_, _))
    pending && store.capacity_usage() is Err(@store.CleanupPending)
  } else {
    store.close() is Err(@store.OperationRouting(_, _))
  }
  let sql_after_first = receiver.sql_entries
  let normal_after_first = receiver.normal_entries
  let second_close = store.close().unwrap()
  let third_close = store.close().unwrap()
  // Normal failed-return recovery performs ONLY necessary cleanup SQL, not
  // the failed capacity read again or any business/payload operation.
  let no_replay = if normal_probe {
    receiver.cleanup &&
    !receiver.return_ack_pending &&
    receiver.normal_entries == normal_after_first
  } else {
    receiver.sql_entries == sql_after_first
  }
  // The separately retained closed carrier still owns its Database DATA shell.
  let library_busy = library.close_checked() is Err(_)
  let alias_closed = retained_alias.close().unwrap()
  original.close_checked().unwrap()
  busy_writer &&
  busy_reader &&
  same_bytes &&
  original_busy &&
  usage.reserved_bytes == 0L &&
  first_close_pending &&
  second_close &&
  !third_close &&
  no_replay &&
  library_busy &&
  !alias_closed
}

///|
fn store_wal_original_work(
  host : InstalledArenaHost,
  sqlite : InstalledArenaSqliteLibrary,
  path : String,
  normal_probe : Bool,
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
    normal_entries: 0,
    fail_cleanup_return: !normal_probe,
    fail_normal_return: false,
    return_ack_pending: false,
  }
  let original = store_wal_prepare_original(library, receiver, fn(
    receiver,
    library,
    tag,
  ) {
    store_wal_route(receiver, library, tag)
  })
  original.activate().unwrap()
  let result = store_wal_payload_work(
    library, original, receiver, path, normal_probe,
  )
  result &&
  receiver.sql_entries > 0 &&
  !receiver.active &&
  !receiver.sql &&
  receiver.cleanup &&
  !receiver.return_ack_pending &&
  original.primary_code() == (if normal_probe { 33 } else { 44 })
}

///|
fn store_wal_physical_case(
  normal_probe : Bool,
  open_probe? : Int = 0,
) -> Unit raise {
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
  let result = if open_probe == 0 {
    store_wal_original_work(host, sqlite, root + "/store", normal_probe)
  } else {
    store_failed_open_original_work(host, sqlite, root + "/store", open_probe)
  }
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

///|
test "selected original Store WAL payload and separate physical cleanup" {
  store_wal_physical_case(false)
}

///|
test "normal Store return failure reaches same-original cleanup without normal revival" {
  store_wal_physical_case(true)
}

///|
fn store_failed_open_original_work(
  host : InstalledArenaHost,
  sqlite : InstalledArenaSqliteLibrary,
  path : String,
  probe : Int,
) -> Bool raise {
  let library = sqlite.library.unwrap()
  let receiver : StoreWalReceiver = {
    host,
    domain: sqlite.domain,
    library,
    active: false,
    cleanup: false,
    sql: false,
    sql_entries: 0,
    normal_entries: 0,
    fail_cleanup_return: false,
    fail_normal_return: probe == 1,
    return_ack_pending: false,
  }
  let original = store_wal_prepare_original(library, receiver, fn(
    receiver,
    library,
    tag,
  ) {
    store_wal_route(receiver, library, tag)
  })
  original.activate().unwrap()
  let result = if probe == 1 {
    // The physical constructor succeeds, but its original return is lost.
    // Cleanup must keep the Database DATA alias through a second lost return.
    let failure = match
      @store.open_original_local_store_with_custody(
        library,
        original,
        path,
        "sha256:" + "1".repeat(64),
        128L,
        4L,
        4096L,
        diagnostic_ceiling=Some(256),
      ) {
      Err(@store.CleanupRequired(value)) => value
      _ => abort("constructor return loss did not retain original custody")
    }
    assert_true(original.pending_scope().unwrap())
    receiver.fail_cleanup_return = true
    let pending = failure.retry_cleanup() is Err(@store.OperationRouting(_, _))
    let sql_count = receiver.sql_entries
    let held = library.close_checked() is Err(_)
    assert_true(original.pending_scope().unwrap())
    failure.retry_cleanup().unwrap()
    failure.retry_cleanup().unwrap()
    let no_replay = receiver.sql_entries == sql_count
    original.close_checked().unwrap()
    pending && held && no_replay && original.primary_code() == 33
  } else {
    // The generic Remote entrance preserves open-existing refusal. This is a
    // fresh missing path, not a replay or corruption of an earlier fixture.
    original.enter_store().unwrap()
    let failure = match
      library.open_original_remote_database_with_custody(
        original,
        path + "/missing.sqlite3",
        4096L,
        existing=true,
      ) {
      Err(value) => value
      Ok(_) => abort("missing Remote original was created")
    }
    original.leave_store().unwrap()
    let retained_database = failure
      .borrow_original_database_cleanup(original)
      .unwrap()
      .unwrap()
    let held_before = library.close_checked() is Err(_)
    original.enter_cleanup().unwrap()
    failure.retry_cleanup().unwrap()
    let pending = original.close_checked() is Err(_)
    original.leave_store().unwrap()
    let held_after = library.close_checked() is Err(_)
    // Retaining this typed same-original DATA is distinct from both ACKs.
    let same_alias_closed = retained_database.close_checked() is Ok(_)
    original.close_checked().unwrap()
    held_before && pending && held_after && same_alias_closed
  }
  result && !receiver.active && !receiver.sql && !receiver.return_ack_pending
}

///|
test "failed Store constructor retains DATA through original cleanup return ACK" {
  store_wal_physical_case(false, open_probe=1)
}

///|
test "generic Remote failed open retains same DATA through physical and scope ACKs" {
  store_wal_physical_case(false, open_probe=2)
}
