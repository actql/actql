///|
test "unavailable lookup start projects no child while preserving true Database and operation" {
  let host = domain_test_host()
  let domain = sqlite_test_pending_domain(host)
  let library = sqlite_test_empty_record(domain)
  domain.sqlite_library = Some(library)
  let database = sqlite_test_empty_database(library)
  library.database = Some(database)
  let reply = start_installed_sqlite_lookup_reply(host, database)
  assert_eq(reply.operation_tag(), 22)
  assert_eq(reply.stage_tag(), 0)
  assert_true(reply.issue_family() != 0)
  assert_true(reply.original_lookup() is None)
  assert_true(database.lookup is None)
  assert_true(
    reply.original_database() is Some(original) &&
    physical_equal(original, database),
  )
  host.close_sqlite_database(database).unwrap()
  host.close_sqlite_library(library).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
}

///|
test "saved lookup row retains exact controller but cannot grant copy current after retirement" {
  let host = domain_test_host()
  let domain = sqlite_test_pending_domain(host)
  let library = sqlite_test_empty_record(domain)
  domain.sqlite_library = Some(library)
  let database = sqlite_test_empty_database(library)
  library.database = Some(database)
  let child = lookup_test_empty_controller(database)
  database.lookup = Some(child)
  let reply : InstalledArenaSqliteDatabaseReply = {
    operation: 24,
    host,
    library,
    original: Some(database),
    lookup: Some(child),
    stage: 2,
    issue: None,
    after: None,
    value: Some(DatabaseRow("原", 2L, b"saved")),
  }
  assert_true(
    reply.original_lookup() is Some(original) && physical_equal(original, child),
  )
  let refused = reply.revalidate_copy()
  assert_eq(refused.operation_tag(), 23)
  assert_eq(refused.stage_tag(), 0)
  assert_true(refused.issue_family() != 0)
  let closed = close_installed_sqlite_lookup_reply(host, child)
  assert_eq(closed.operation_tag(), 31)
  assert_eq(closed.stage_tag(), 3)
  assert_eq(closed.issue_family(), 0)
  assert_true(database.lookup is None)
  let retired = reply.revalidate_copy()
  assert_eq(retired.stage_tag(), 0)
  assert_true(retired.issue_family() != 0)
  assert_true(
    finish_installed_sqlite_lookup_reply(host, child).issue_family() != 0,
  )
  host.close_sqlite_database(database).unwrap()
  host.close_sqlite_library(library).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
}
