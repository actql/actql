///|
#borrow(database)
extern "C" fn extent_result_storage_empty(database : @sqlite.Database) -> Bool = "actql_native_sqlite_test_result_storage_empty"

///|
#borrow(database)
extern "C" fn extent_fail_close(
  database : @sqlite.Database,
  failures : Int,
) -> Unit = "actql_native_sqlite_test_fail_close"

///|
fn owned_extent_case_0(library : @sqlite.Library, path : String) -> Unit raise {
  let selected = path + "/owned-body-extent.sqlite3"
  let database = library.open_database(selected, 4L).unwrap()
  let body = b"e\xcc\x81\r\n"
  assert_true(database.insert("original", "input", body) is Err(BodyTooLarge))
  assert_true(
    database.insert_with_body_extent("original", "input", body, 6L)
    is Err(InvalidLimit),
  )
  assert_eq(
    database.insert_with_body_extent("original", "input", body, 5L).unwrap(),
    0L,
  )
  assert_true(database.read("original", "input") is Err(Physical(_)))
  assert_true(database.read_header("original", "input") is Err(Physical(_)))
  assert_true(
    database.read_with_body_limit("original", "input", 5L) is Err(Physical(_)),
  )
  let header = database.observe_body_extent("original", "input").unwrap()
  assert_eq((header.revision, header.body_bytes), (0L, 5L))
  assert_true(extent_result_storage_empty(database))
  let returned = database
    .read_exact_body_extent("original", "input", header)
    .unwrap()
  assert_eq(returned.body, body)
  assert_eq(returned.revision, header.revision)
  assert_true(database.insert("original", "other", body) is Err(BodyTooLarge))
  database.close_checked().unwrap()
  let reopened = library.open_existing_database(selected, 4L).unwrap()
  let same = reopened.observe_body_extent("original", "input").unwrap()
  assert_eq(
    (same.revision, same.body_bytes),
    (header.revision, header.body_bytes),
  )
  assert_eq(
    reopened.read_exact_body_extent("original", "input", same).unwrap().body,
    body,
  )
  assert_true(reopened.read("original", "input") is Err(Physical(_)))
  reopened.close_checked().unwrap()
  assert_eq(returned.body, body)
}

///|
fn owned_extent_case_1(library : @sqlite.Library, path : String) -> Unit raise {
  let database = library
    .open_database(path + "/owned-body-cas.sqlite3", 4L)
    .unwrap()
  database.insert_with_body_extent("original", "input", b"12345", 5L).unwrap()
  |> ignore
  let before = database.observe_body_extent("original", "input").unwrap()
  assert_eq(
    database
    .compare_exchange_with_body_extent("original", "input", 0L, b"1234567", 7L)
    .unwrap(),
    1L,
  )
  assert_true(
    database.read_exact_body_extent("original", "input", before)
    is Err(Collision),
  )
  assert_true(extent_result_storage_empty(database))
  let changed = database.observe_body_extent("original", "input").unwrap()
  assert_true(
    database.read_exact_body_extent("original", "input", {
      ..changed,
      revision: 4294967297L,
    })
    is Err(Collision),
  )
  assert_true(extent_result_storage_empty(database))
  assert_true(
    database.read_exact_body_extent("original", "input", {
      ..changed,
      body_bytes: 6L,
    })
    is Err(Collision),
  )
  assert_true(extent_result_storage_empty(database))
  assert_true(
    database.compare_exchange_with_body_extent(
      "original", "input", 0L, b"stale", 5L,
    )
    is Err(Collision),
  )
  assert_eq(
    database.read_exact_body_extent("original", "input", changed).unwrap().body,
    b"1234567",
  )
  assert_true(
    database.compare_exchange("original", "input", 1L, b"12345")
    is Err(BodyTooLarge),
  )
  database.close_checked().unwrap()
}

///|
fn owned_extent_case_2(library : @sqlite.Library, path : String) -> Unit raise {
  let database = library
    .open_database(path + "/owned-body-cleanup.sqlite3", 4L)
    .unwrap()
  database.begin_immediate().unwrap()
  database.insert_with_body_extent("original", "input", b"12345", 5L).unwrap()
  |> ignore
  database.rollback().unwrap()
  assert_true(
    database.observe_body_extent("original", "input") is Err(NotFound),
  )
  database.insert_with_body_extent("original", "input", b"12345", 5L).unwrap()
  |> ignore
  let header = database.observe_body_extent("original", "input").unwrap()
  let returned = database
    .read_exact_body_extent("original", "input", header)
    .unwrap()
  extent_fail_close(database, 1)
  assert_true(database.close_checked() is Err(Physical(_)))
  assert_false(extent_result_storage_empty(database))
  assert_eq(returned.body, b"12345")
  database.close_checked().unwrap()
  assert_true(extent_result_storage_empty(database))
  assert_eq(returned.body, b"12345")
  assert_true(
    database.observe_body_extent("original", "input") is Err(DatabaseClosed),
  )
  assert_true(
    database.read_exact_body_extent("original", "input", header)
    is Err(DatabaseClosed),
  )
}

///|
// The existing selected-provider consumer owns this physical test. No raw
// SQLite fallback, provider import, forged context or capacity ACK is used.
fn owned_extent_physical_case(index : Int) -> Unit raise {
  let root = @env.get_env_var("ACTQL_TEST_INSTALLED_PROCESS_ROOT").unwrap()
  let component = @env.get_env_var("ACTQL_TEST_SQLITE_COMPONENT").unwrap()
  let page = domain_page_bytes()
  let descriptor = process_test_open(
    @utf8.encode(root + "/extent-backing-" + index.to_string() + "\u{0}"),
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
  ).retained_execution_value("extent physical Host")
  host.acquire_fd(descriptor).retained_execution_value("extent original FD")
  let backing = host
    .borrow_backing()
    .retained_execution_value("extent backing borrow")
  host
  .enter_backing_borrow_scope(backing)
  .retained_execution_value("extent backing enter")
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
    .retained_execution_value("extent original domain") {
    PreparedDomain(value) => value
    PendingDomain(_, _) => fail("extent physical domain pending")
  }
  host
  .transfer_domain(domain)
  .retained_execution_value("extent domain transfer")
  host
  .leave_backing_borrow_scope(backing)
  .retained_execution_value("extent backing leave")
  host
  .return_backing_borrow(backing)
  .retained_execution_value("extent backing return")
  host
  .prepare_domain_read(domain)
  .retained_execution_value("extent original context")
  let sqlite = match
    host
    .prepare_sqlite_library(domain, component, 32L * page, 128)
    .retained_execution_value("extent current component") {
    ReadySqlite(value) => value
    PendingSqlite(_, _) => fail("extent selected Library pending")
  }
  owned_extent_dispatch(host, domain, sqlite, index, root)
  // The call returns only after every Database/readback alias has retired.
  host
  .close_sqlite_library(sqlite)
  .retained_execution_value("extent Library ACK")
  host
  .close_domain_after_owner_ack(domain)
  .retained_execution_value("extent domain ACK")
  host.try_close().retained_execution_value("extent Host ACK")
  assert_eq(process_test_close(descriptor), 0)
}

///|
fn owned_extent_dispatch(
  host : InstalledArenaHost,
  domain : InstalledArenaDomain,
  sqlite : InstalledArenaSqliteLibrary,
  index : Int,
  root : String,
) -> Unit raise {
  let library = host
    .current_sqlite_library(sqlite)
    .retained_execution_value("extent same Library")
  host.enter_domain_read(domain).retained_execution_value("extent actual enter")
  match index {
    0 => owned_extent_case_0(library, root)
    1 => owned_extent_case_1(library, root)
    _ => owned_extent_case_2(library, root)
  }
  host.leave_domain_read(domain).retained_execution_value("extent actual leave")
}

///|
test "selected SQLite body extent keeps default boundary and exact cold bytes" {
  owned_extent_physical_case(0)
}

///|
test "selected SQLite body extent preserves Int64 CAS and rejects stale metadata before copy" {
  owned_extent_physical_case(1)
}

///|
test "selected SQLite body extent retains rollback and failed physical cleanup" {
  owned_extent_physical_case(2)
}
