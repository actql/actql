///|
fn lookup_test_empty_controller(
  database : InstalledArenaSqliteDatabase,
) -> InstalledArenaSqliteLookup {
  { database, original: None, failed: false, closed: false, }
}

///|
test "registered pending read blocks ordinary Database calls without invoking callbacks" {
  let host = domain_test_host()
  let domain = sqlite_test_pending_domain(host)
  let library = sqlite_test_empty_record(domain)
  domain.sqlite_library = Some(library)
  let database = sqlite_test_empty_database(library)
  library.database = Some(database)
  let child = lookup_test_empty_controller(database)
  database.lookup = Some(child)
  let mut calls = 0
  assert_true(
    host.call_sqlite_database(database, _ => {
      calls += 1
      Ok(())
    })
    is RefusedDatabaseCall(
      Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending))
    ),
  )
  assert_eq(calls, 0)
  assert_true(host.prepare_sqlite_lookup(database) is Err(_))
  assert_true(
    database.lookup is Some(original) && physical_equal(original, child),
  )
  host.close_sqlite_lookup(child).unwrap()
  host.close_sqlite_lookup(child).unwrap()
  assert_true(child.closed)
  assert_true(database.lookup is None)
  host.close_sqlite_database(database).unwrap()
  host.close_sqlite_library(library).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
}

///|
test "foreign Host copied read controller and missing original cannot gain read permission" {
  let host = domain_test_host()
  let other = domain_test_host()
  let domain = sqlite_test_pending_domain(host)
  let library = sqlite_test_empty_record(domain)
  domain.sqlite_library = Some(library)
  let database = sqlite_test_empty_database(library)
  library.database = Some(database)
  let original = lookup_test_empty_controller(database)
  let copy = lookup_test_empty_controller(database)
  database.lookup = Some(original)
  let mut calls = 0
  for child in [copy, original] {
    assert_true(
      other.call_sqlite_lookup(child, _ => {
        calls += 1
        Ok(())
      })
      is RefusedDatabaseCall(
        Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))
      ),
    )
  }
  assert_true(
    host.call_sqlite_lookup(copy, _ => {
      calls += 1
      Ok(())
    })
    is RefusedDatabaseCall(
      Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))
    ),
  )
  assert_true(
    host.call_sqlite_lookup(original, _ => {
      calls += 1
      Ok(())
    })
    is RefusedDatabaseCall(_),
  )
  assert_true(host.finish_sqlite_lookup(copy) is RefusedDatabaseCall(_))
  assert_true(
    host.close_sqlite_lookup(copy)
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
  )
  assert_eq(calls, 0)
  assert_false(original.closed)
  host.close_sqlite_database(database).unwrap()
  assert_true(original.closed)
  host.close_sqlite_library(library).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
  other.try_close().unwrap()
}

///|
test "callback reentry cannot clean read child or its parent and full cleanup is child first" {
  let host = domain_test_host()
  let domain = sqlite_test_pending_domain(host)
  let library = sqlite_test_empty_record(domain)
  domain.sqlite_library = Some(library)
  let database = sqlite_test_empty_database(library)
  library.database = Some(database)
  let child = lookup_test_empty_controller(database)
  database.lookup = Some(child)
  database.calling = true
  assert_true(
    host.close_sqlite_lookup(child)
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending))),
  )
  assert_true(
    host.close_sqlite_database(database)
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending))),
  )
  assert_false(child.closed || database.closed)
  database.calling = false
  host.close_sqlite_database(database).unwrap()
  assert_true(child.closed && database.closed)
  assert_true(database.lookup is None)
  host.close_sqlite_lookup(child).unwrap()
  host.close_sqlite_library(library).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
}

///|
test "failed or stale read controller cannot be reused as a new observation or cleanup alias" {
  let host = domain_test_host()
  let domain = sqlite_test_pending_domain(host)
  let library = sqlite_test_empty_record(domain)
  domain.sqlite_library = Some(library)
  let database = sqlite_test_empty_database(library)
  library.database = Some(database)
  let old = lookup_test_empty_controller(database)
  database.lookup = Some(old)
  old.failed = true
  let mut calls = 0
  assert_true(
    host.call_sqlite_lookup(old, _ => {
      calls += 1
      Ok(())
    })
    is RefusedDatabaseCall(_),
  )
  assert_true(host.finish_sqlite_lookup(old) is RefusedDatabaseCall(_))
  host.close_sqlite_lookup(old).unwrap()
  let fresh = lookup_test_empty_controller(database)
  database.lookup = Some(fresh)
  assert_true(
    host.close_sqlite_lookup(old)
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
  )
  assert_true(
    host.call_sqlite_lookup(old, _ => {
      calls += 1
      Ok(())
    })
    is RefusedDatabaseCall(_),
  )
  assert_false(fresh.closed)
  assert_eq(calls, 0)
  host.close_sqlite_database(database).unwrap()
  assert_true(fresh.closed)
  host.close_sqlite_library(library).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
}
