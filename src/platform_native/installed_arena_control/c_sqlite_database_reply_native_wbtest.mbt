///|
test "unavailable original Store acquisition keeps true Library and no physical callback fact" {
  let host = domain_test_host()
  let domain = sqlite_test_pending_domain(host)
  let library = sqlite_test_empty_record(domain)
  domain.sqlite_library = Some(library)
  let reply = restore_installed_sqlite_database_reply(
    host, library, "/missing/original.sqlite3", 1024L,
  )
  assert_eq(reply.operation_tag(), 1)
  assert_eq(reply.stage_tag(), 0)
  assert_true(reply.issue_family() != 0)
  assert_eq(reply.after_issue_family(), 0)
  assert_true(physical_equal(reply.original_host(), host))
  assert_true(physical_equal(reply.original_library(), library))
  assert_true(reply.original_database() is None)
  assert_eq(reply.has_row(), 0)
  assert_eq(reply.revision(), -1L)
  assert_eq(reply.body_bound(), -1L)
  host.close_sqlite_library(library).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
}

///|
test "empty stored row differs from no row and original post-call fence stays separate" {
  let host = domain_test_host()
  let domain = sqlite_test_pending_domain(host)
  let library = sqlite_test_empty_record(domain)
  domain.sqlite_library = Some(library)
  let database = sqlite_test_empty_database(library)
  library.database = Some(database)
  let reply : InstalledArenaSqliteDatabaseReply = {
    operation: 4,
    host,
    library,
    original: Some(database),
    stage: 2,
    issue: None,
    after: Some(Domain(@bootstrap.Bootstrap(@bootstrap.Closing))),
    value: Some(DatabaseRow("original", 0L, b"")),
  }
  assert_eq(reply.has_row(), 1)
  assert_eq(reply.body(), b"")
  assert_eq(reply.revision(), 0L)
  assert_eq(reply.stage_tag(), 2)
  assert_eq(reply.issue_family(), 0)
  assert_eq(reply.after_issue_family(), 4)
  assert_eq(reply.body_bound(), 1024L)
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
test "transaction selector is closed before existing callback and empty cleanup is original only" {
  let host = domain_test_host()
  let domain = sqlite_test_pending_domain(host)
  let library = sqlite_test_empty_record(domain)
  domain.sqlite_library = Some(library)
  let database = sqlite_test_empty_database(library)
  library.database = Some(database)
  let fence = fence_installed_sqlite_database_reply(host, database)
  assert_eq(fence.operation_tag(), 11)
  assert_eq(fence.stage_tag(), 0)
  assert_true(fence.issue_family() != 0)
  assert_eq(fence.after_issue_family(), 0)
  for operation in [-1, 0, 1, 6, 10, 2147483647] {
    let reply = transaction_installed_sqlite_database_reply(
      host, database, operation,
    )
    assert_eq(reply.stage_tag(), 0)
    assert_eq(reply.issue_family(), 10)
    assert_eq(reply.after_issue_family(), 0)
    assert_false(database.closed)
  }
  let reply = close_installed_sqlite_database_reply(host, database)
  assert_eq(reply.operation_tag(), 10)
  assert_eq(reply.stage_tag(), 3)
  assert_eq(reply.issue_family(), 0)
  assert_true(database.closed && !library.closed && !domain.closed)
  host.close_sqlite_library(library).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
}

///|
test "scan refuses unavailable and foreign originals before callback and keeps cursor data distinct" {
  let host = domain_test_host()
  let other = domain_test_host()
  let domain = sqlite_test_pending_domain(host)
  let library = sqlite_test_empty_record(domain)
  domain.sqlite_library = Some(library)
  let database = sqlite_test_empty_database(library)
  library.database = Some(database)
  for caller in [host, other] {
    let reply = scan_installed_sqlite_database_reply(
      caller, database, "original", "", 64L,
    )
    assert_eq(reply.operation_tag(), 12)
    assert_eq(reply.stage_tag(), 0)
    assert_true(reply.issue_family() != 0)
    assert_eq(reply.has_row(), 0)
    assert_eq(reply.row_key_bytes(), b"")
    assert_true(physical_equal(reply.original_host(), host))
    assert_true(
      reply.original_database() is Some(value) &&
      physical_equal(value, database),
    )
  }
  host.close_sqlite_database(database).unwrap()
  let closed = scan_installed_sqlite_database_reply(
    host, database, "original", "", 64L,
  )
  assert_true(closed.issue_family() != 0)
  assert_eq(closed.has_row(), 0)
  host.close_sqlite_library(library).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
  other.try_close().unwrap()
}

///|
test "bounded scan row preserves exact decomposed key binary body and separate postcheck refusal" {
  let host = domain_test_host()
  let domain = sqlite_test_pending_domain(host)
  let library = sqlite_test_empty_record(domain)
  domain.sqlite_library = Some(library)
  let database = sqlite_test_empty_database(library)
  library.database = Some(database)
  let reply : InstalledArenaSqliteDatabaseReply = {
    operation: 12,
    host,
    library,
    original: Some(database),
    stage: 2,
    issue: None,
    after: Some(Domain(@bootstrap.Bootstrap(@bootstrap.Closing))),
    value: Some(DatabaseRow("e\u0301/😀", 7L, b"\x00\xff\r\n")),
  }
  assert_eq(reply.operation_tag(), 12)
  assert_eq(reply.has_row(), 1)
  assert_eq(reply.row_key_bytes(), b"e\xcc\x81/\xf0\x9f\x98\x80")
  assert_eq(reply.body(), b"\x00\xff\r\n")
  assert_eq(reply.revision(), 7L)
  assert_eq(reply.after_issue_family(), 4)
  host.close_sqlite_database(database).unwrap()
  host.close_sqlite_library(library).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
}

///|
test "capacity callbacks preserve original refusal and never supply change or usage facts" {
  let host = domain_test_host()
  let other = domain_test_host()
  let domain = sqlite_test_pending_domain(host)
  let library = sqlite_test_empty_record(domain)
  domain.sqlite_library = Some(library)
  let database = sqlite_test_empty_database(library)
  library.database = Some(database)
  for caller in [host, other] {
    for
      reply in [
        reserve_installed_sqlite_capacity_reply(
          caller, database, "original", "one", 8L, 1L, 64L, 2L,
        ),
        observe_installed_sqlite_capacity_reply(caller, database, "original"),
        release_installed_sqlite_capacity_reply(
          caller, database, "original", "one", 8L, 1L,
        ),
      ] {
      assert_true(reply.operation_tag() >= 13 && reply.operation_tag() <= 15)
      assert_eq(reply.stage_tag(), 0)
      assert_true(reply.issue_family() != 0)
      assert_eq(reply.capacity_changed(), -1)
      assert_eq(reply.reserved_bytes(), -1L)
      assert_eq(reply.reserved_objects(), -1L)
      assert_eq(reply.has_row(), 0)
      assert_true(physical_equal(reply.original_host(), host))
    }
  }
  host.close_sqlite_database(database).unwrap()
  host.close_sqlite_library(library).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
  other.try_close().unwrap()
}

///|
test "capacity physical observations distinguish unchanged zero absent and postcheck refusal" {
  let host = domain_test_host()
  let domain = sqlite_test_pending_domain(host)
  let library = sqlite_test_empty_record(domain)
  domain.sqlite_library = Some(library)
  let database = sqlite_test_empty_database(library)
  library.database = Some(database)
  for
    value in [
      CapacityChanged(false),
      CapacityChanged(true),
      CapacityUsage(0L, 0L),
      CapacityUsage(8L, 1L),
    ] {
    let reply : InstalledArenaSqliteDatabaseReply = {
      operation: 14,
      host,
      library,
      original: Some(database),
      stage: 2,
      issue: None,
      after: Some(Domain(@bootstrap.Bootstrap(@bootstrap.Closing))),
      value: Some(value),
    }
    assert_eq(reply.stage_tag(), 2)
    assert_eq(reply.after_issue_family(), 4)
    assert_eq(reply.has_row(), 0)
    match value {
      CapacityChanged(changed) => {
        assert_eq(reply.capacity_changed(), if changed { 1 } else { 0 })
        assert_eq(reply.reserved_bytes(), -1L)
      }
      CapacityUsage(bytes, objects) => {
        assert_eq(reply.capacity_changed(), -1)
        assert_eq(reply.reserved_bytes(), bytes)
        assert_eq(reply.reserved_objects(), objects)
      }
      _ => fail("unexpected independent capacity fixture")
    }
  }
  host.close_sqlite_database(database).unwrap()
  host.close_sqlite_library(library).unwrap()
  host.close_domain_after_owner_ack(domain).unwrap()
  host.try_close().unwrap()
}
