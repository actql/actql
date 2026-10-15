///|
fn sqlite_test_empty_database(
  library : InstalledArenaSqliteLibrary,
) -> InstalledArenaSqliteDatabase {
  {
    library,
    max_body_bytes: 1024L,
    database: None,
    failure: None,
    failed: false,
    scope_open: false,
    calling: false,
    closed: false,
  }
}

///|
test "registered original Database blocks parent Library and callback reentry cleanup" {
  let host = domain_test_host()
  let domain = sqlite_test_pending_domain(host)
  let library = sqlite_test_empty_record(domain)
  domain.sqlite_library = Some(library)
  let database = sqlite_test_empty_database(library)
  library.database = Some(database)
  assert_true(
    host.close_sqlite_library(library)
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending))),
  )
  assert_false(library.closed || database.closed)
  // A physically active callback must not be mistaken for a failed leave to
  // retry. Empty fixture only: no external Database is fabricated here.
  database.calling = true
  assert_true(
    host.close_sqlite_database(database)
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending))),
  )
  assert_false(database.closed)
  database.calling = false
  host.close_sqlite_database(database).unwrap()
  host.close_sqlite_database(database).unwrap()
  assert_true(database.closed)
  assert_true(
    library.database is Some(original) && physical_equal(original, database),
  )
  host.close_sqlite_library(library).unwrap()
  assert_true(library.database is None)
  assert_true(
    host.close_sqlite_database(database)
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
  )
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
}

///|
test "foreign and substituted Database cannot call or retire the original" {
  let host = domain_test_host()
  let other = domain_test_host()
  let domain = sqlite_test_pending_domain(host)
  let library = sqlite_test_empty_record(domain)
  domain.sqlite_library = Some(library)
  let original = sqlite_test_empty_database(library)
  let copy = sqlite_test_empty_database(library)
  library.database = Some(original)
  assert_true(
    other.close_sqlite_database(original)
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
  )
  assert_true(
    host.close_sqlite_database(copy)
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
  )
  let mut called = 0
  assert_true(
    host.call_sqlite_database(copy, _ => {
      called += 1
      Ok(())
    })
    is RefusedDatabaseCall(_),
  )
  assert_eq(called, 0)
  assert_false(original.closed || copy.closed)
  host.close_sqlite_database(original).unwrap()
  host.close_sqlite_library(library).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
  other.try_close().unwrap()
}

///|
test "unavailable database preparation does not acquire a replacement or invoke callback" {
  let host = domain_test_host()
  let domain = sqlite_test_pending_domain(host)
  let library = sqlite_test_empty_record(domain)
  domain.sqlite_library = Some(library)
  assert_true(
    host.prepare_sqlite_database(
      library,
      "/missing/original.sqlite3",
      1024L,
      ExistingSqliteDatabase,
    )
    is Err(_),
  )
  assert_true(library.database is None)
  let database = sqlite_test_empty_database(library)
  library.database = Some(database)
  database.failed = true
  let mut called = 0
  assert_true(
    host.call_sqlite_database(database, _ => {
      called += 1
      Ok(())
    })
    is RefusedDatabaseCall(_),
  )
  assert_eq(called, 0)
  host.close_sqlite_database(database).unwrap()
  host.close_sqlite_library(library).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
}
