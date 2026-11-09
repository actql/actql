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
  mut fail_cleanup_sql : Bool
  mut cleanup_sql_recoveries : Int
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
      if receiver.cleanup && receiver.fail_cleanup_sql {
        receiver.fail_cleanup_sql = false
        return 55
      }
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
      if receiver.cleanup &&
        receiver.active &&
        receiver.sql &&
        !receiver.return_ack_pending &&
        store_wal_entered(receiver) {
        // This selected component's SQL heap is in the SAME entered Read.
        // Reobserve that physical frame before returning its failed SQL flight.
        receiver.cleanup_sql_recoveries += 1
        if receiver.cleanup_sql_recoveries == 1 {
          // A refused first recovery retains the same attempted SQL flight.
          return 56
        }
        receiver.sql = false
        return 0
      }
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
  // This exact selected original uses the legacy three-argument constructor.
  // It retains normal Read/SQL routing without opting into an unfunded chunk
  // accumulator. Each requested64-byte delivery still yields one original row.
  let delivery_request = @payload.prepare_publication_payload_request(
    authority,
    "sha256:" + "9".repeat(64),
    "sha256:" + "a".repeat(64),
    "sha256:" + "4".repeat(64),
    "sha256:" + "5".repeat(64),
    "sha256:" + "6".repeat(64),
    "sha256:" + "7".repeat(64),
    "sha256:" + "8".repeat(64),
    32L,
    2L,
  ).unwrap()
  let delivery_writer = store.begin_payload(delivery_request).unwrap()
  delivery_writer.append(b"[{\"n\":0},{\"n\":1}]").unwrap()
  let delivery_info = delivery_writer.seal().unwrap()
  let delivery = store
    .open_payload_delivery(
      delivery_info.material_generation_cid,
      "jsonl",
      "{\"n\":{\"nullable\":false,\"type\":\"integer\"}}",
      ["n"],
      64,
      64,
      16,
      4,
      128L,
    )
    .unwrap()
  let first_row = delivery.next(64).unwrap()
  let second_row = delivery.next(64).unwrap()
  let end = delivery.next(64).unwrap()
  let summary = delivery.finish().unwrap()
  let legacy_delivery = first_row.bytes == b"{\"n\":0}\n" &&
    !first_row.eof &&
    second_row.bytes == b"{\"n\":1}\n" &&
    !second_row.eof &&
    end.bytes.length() == 0 &&
    end.eof &&
    summary.rows == 2L &&
    summary.bytes == 16L
  store.reclaim_payload(delivery_info.material_generation_cid).unwrap()
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
  legacy_delivery &&
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
    fail_cleanup_sql: false,
    cleanup_sql_recoveries: 0,
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
  } else if open_probe == 6 {
    journal_existing_original_work(host, sqlite, root + "/store")
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
    fail_cleanup_sql: false,
    cleanup_sql_recoveries: 0,
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
  } else if probe == 2 {
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
    let unentered_close_refused = retained_database.close_checked() is Err(_)
    original.close_checked().unwrap()
    held_before && pending && held_after && unentered_close_refused
  } else if probe == 3 {
    original.enter_store().unwrap()
    let database = library
      .open_original_remote_database_with_custody(
        original,
        path + "/cleanup-sql.sqlite3",
        4096L,
      )
      .unwrap()
    original.leave_store().unwrap()
    original.enter_cleanup().unwrap()
    receiver.fail_cleanup_sql = true
    assert_true(
      database.capacity_usage("cleanup")
      is Err(@sqlite.OperationRoutingBefore(55)),
    )
    assert_true(original.pending_scope().unwrap())
    assert_true(original.leave_store() is Err(_))
    assert_true(original.enter_store() is Err(_))
    // Only failed+SQL can reach the original recovery. It acknowledges no DB.
    assert_true(original.enter_cleanup() is Err(@sqlite.Physical(_)))
    assert_true(original.pending_scope().unwrap())
    assert_true(receiver.active && receiver.sql)
    assert_eq(original.cleanup_code(), 56)
    original.enter_cleanup().unwrap()
    assert_eq(receiver.cleanup_sql_recoveries, 2)
    assert_eq(original.primary_code(), 55)
    assert_true(original.enter_cleanup() is Err(_))
    assert_true(original.close_checked() is Err(_))
    database.close_checked().unwrap()
    original.leave_store().unwrap()
    // Keep the original Database DATA alias through the return ACK. Its last
    // use before leave would correctly refuse finalization with flight=true.
    let unentered_close_refused = database.close_checked() is Err(_)
    assert_true(library.close_checked() is Err(_))
    original.close_checked().unwrap()
    receiver.cleanup_sql_recoveries == 2 &&
    original.primary_code() == 55 &&
    original.cleanup_code() == 56 &&
    unentered_close_refused
  } else if probe == 6 {
    store_result_return_work(library, original, receiver, path)
  } else if probe == 5 {
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
    writer.append(b"same-original").unwrap()
    let info = writer.seal().unwrap()
    let reader = store
      .open_payload_reader(info.material_generation_cid)
      .unwrap()
    receiver.fail_normal_return = true
    assert_true(store.capacity_usage() is Err(@store.OperationRouting(_, _)))
    let sql_before = receiver.sql_entries
    let normal_before = receiver.normal_entries
    // The first cleanup return is also lost. This cannot clear the Store's
    // mirror or close the retained Reader/Database in place of its own ACK.
    receiver.fail_cleanup_return = true
    assert_true(
      store.reconcile_original_return() is Err(@store.OperationRouting(_, _)),
    )
    assert_true(reader.close() is Err(@store.CleanupPending))
    assert_eq(receiver.sql_entries, sql_before)
    assert_eq(receiver.normal_entries, normal_before)
    assert_true(store.reconcile_original_return().unwrap())
    assert_false(store.reconcile_original_return().unwrap())
    assert_eq(receiver.sql_entries, sql_before)
    assert_eq(receiver.normal_entries, normal_before)
    assert_eq(store_wal_library_children(library), 1)
    assert_true(original.close_checked() is Err(_))
    assert_true(store.capacity_usage() is Err(_))
    reader.close().unwrap()
    assert_eq(receiver.sql_entries, sql_before)
    assert_true(store.close().unwrap())
    original.close_checked().unwrap()
    original.primary_code() == 33 &&
    original.cleanup_code() == 44 &&
    receiver.normal_entries == normal_before
  } else {
    let store = @store.open_original_local_store_with_custody(
      library,
      original,
      path,
      "sha256:" + "1".repeat(64),
      128L,
      4L,
      4096L,
      diagnostic_ceiling=Some(256),
    ).unwrap()
    let foreign_receiver = { ..receiver, }
    let foreign = store_wal_prepare_original(library, foreign_receiver, fn(
      receiver,
      library,
      tag,
    ) {
      store_wal_route(receiver, library, tag)
    })
    let normal_entries = receiver.normal_entries
    let sql_entries = receiver.sql_entries
    assert_true(store.matches_original_operation(original))
    assert_false(store.matches_original_operation(foreign))
    assert_eq(store.custody_location().unwrap().0, "sha256:" + "1".repeat(64))
    assert_eq(receiver.normal_entries, normal_entries)
    assert_eq(receiver.sql_entries, sql_entries)
    original.enter_store().unwrap()
    assert_true(store.matches_original_operation(original))
    assert_eq(store.custody_location().unwrap().0, "sha256:" + "1".repeat(64))
    assert_eq(receiver.normal_entries, normal_entries + 1)
    assert_eq(receiver.sql_entries, sql_entries)
    original.leave_store().unwrap()
    foreign.close_checked().unwrap()
    store.close().unwrap() |> ignore
    // A closed Store can still retain the same association. Metadata is not
    // permission to revive it, and retiring the original makes the match false.
    assert_true(store.matches_original_operation(original))
    original.close_checked().unwrap()
    assert_false(store.matches_original_operation(original))
    let entries_after_close = receiver.normal_entries
    let sql_after_close = receiver.sql_entries
    assert_true(store.capacity_usage() is Err(_))
    receiver.normal_entries == entries_after_close &&
    receiver.sql_entries == sql_after_close
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

///|
test "failed cleanup SQL entry reaches same-original cleanup recovery" {
  store_wal_physical_case(false, open_probe=3)
}

///|
test "Store original association metadata neither reenters nor revives its scope" {
  store_wal_physical_case(false, open_probe=4)
}

///|
test "Store return-only reconciliation precedes retained Reader cleanup without SQL replay" {
  store_wal_physical_case(false, open_probe=5)
}

///|
// This selected physical fixture leaves SQL between calls. Its outer frame is
// test control, not the CLI's separate retained Read or an approval authority.
fn journal_existing_route(
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
    0 | 4 => {
      if receiver.active || receiver.sql {
        return 12
      }
      receiver.cleanup = tag == 4
      receiver.active = true
      0
    }
    1 => {
      if !receiver.active || receiver.sql {
        return 13
      }
      let entered = if receiver.cleanup {
        receiver.host.enter_domain_read_cleanup(receiver.domain)
      } else {
        receiver.host.enter_domain_read(receiver.domain)
      }
      if entered is Err(_) {
        return 14
      }
      receiver.sql = true
      receiver.sql_entries += 1
      0
    }
    2 => {
      if !receiver.sql ||
        receiver.host.leave_domain_read(receiver.domain) is Err(_) {
        return 15
      }
      receiver.sql = false
      0
    }
    3 => {
      if !receiver.active || receiver.sql {
        return 16
      }
      receiver.active = false
      0
    }
    _ => 17
  }
}

///|
fn journal_existing_original_work(
  host : InstalledArenaHost,
  sqlite : InstalledArenaSqliteLibrary,
  path : String,
) -> Bool raise {
  let library = sqlite.library.unwrap()
  host
  .enter_domain_read(sqlite.domain)
  .retained_execution_value("already-open Journal stage 2")
  let database = library
    .open_database(path + "/existing-journal.sqlite3", 4096L)
    .retained_execution_value("already-open Journal stage 3")
  host
  .leave_domain_read(sqlite.domain)
  .retained_execution_value("already-open Journal stage 5")
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
    fail_normal_return: false,
    return_ack_pending: false,
    fail_cleanup_sql: false,
    cleanup_sql_recoveries: 0,
  }
  let original = store_wal_prepare_original(library, receiver, fn(
    receiver,
    library,
    tag,
  ) {
    journal_existing_route(receiver, library, tag)
  })
  assert_true(database.bind_original_store_operation(original) is Err(_))
  original.activate().retained_execution_value("already-open Journal stage 6")
  assert_true(database.bind_original_store_operation(original) is Err(_))
  original
  .enter_store()
  .retained_execution_value("already-open Journal stage 7")
  database
  .bind_original_store_operation(original)
  .retained_execution_value("already-open Journal stage 8")
  assert_eq(receiver.sql_entries, 0)
  assert_true(database.matches_original_store_operation(original))
  assert_true(database.bind_original_store_operation(original) is Err(_))
  database
  .insert("original", "key", b"same-journal")
  .retained_execution_value("already-open Journal stage 9")
  |> ignore
  assert_eq(
    database
    .read("original", "key")
    .retained_execution_value("already-open Journal stage 10").body,
    b"same-journal",
  )
  assert_eq(receiver.sql_entries, 2)
  assert_false(receiver.sql)
  original
  .leave_store()
  .retained_execution_value("already-open Journal stage 11")
  let entries = receiver.sql_entries
  assert_true(
    database.read("original", "key") is Err(@sqlite.OperationRoutingBefore(_)),
  )
  assert_eq(receiver.sql_entries, entries)
  // A returned Read flight does not retire the still-open original Database.
  assert_true(original.close_checked() is Err(_))
  original
  .enter_cleanup()
  .retained_execution_value("already-open Journal stage 12")
  database
  .close_checked()
  .retained_execution_value("already-open Journal stage 13")
  assert_eq(receiver.sql_entries, entries + 1)
  original
  .leave_store()
  .retained_execution_value("already-open Journal stage 14")
  assert_true(database.matches_original_store_operation(original))
  original
  .close_checked()
  .retained_execution_value("already-open Journal stage 15")
  assert_false(database.matches_original_store_operation(original))
  assert_true(database.bind_original_store_operation(original) is Err(_))
  // Keep the Database shell until its original coordinator's return ACK.
  assert_true(
    database.close_checked() is Err(@sqlite.OperationRoutingBefore(_)),
  )
  original.primary_code() == 0 && original.cleanup_code() == 0
}

///|
test "already-open Journal binds once and routes each SQL call through its original coordinator" {
  store_wal_physical_case(false, open_probe=6)
}
