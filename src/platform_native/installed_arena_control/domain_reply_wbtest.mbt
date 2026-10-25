///|
extern "C" fn domain_page_bytes() -> Int64 = "actql_bootstrap_page_bytes"

///|
fn domain_test_host() -> InstalledArenaHost {
  let bytes = 64L * domain_page_bytes()
  let host = prepare_installed_arena_host(
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
    bytes,
    {
      planning_work: 20,
      attempts: 8,
      holdings: 4,
      transfer_bytes: 30L,
      retained_bytes: 0L,
      execution_bytes: bytes,
    },
    65536L,
  ).unwrap()
  host.acquire().unwrap()
  host
}

///|
fn domain_test_prepare(
  host : InstalledArenaHost,
  scope : InstalledArenaBackingBorrow,
  bytes : Int64,
) -> InstalledArenaDomainReply {
  prepare_installed_arena_domain_reply(
    host, scope, 2147483647, bytes, 2, 1, 1, 3L, 0L, bytes,
  )
}

///|
test "pending physical domain reply keeps original host record and rejects current success" {
  let host = domain_test_host()
  let scope = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(scope).unwrap()
  // The anonymous parent is not an FD region. No physical child was published;
  // its logical reservation still belongs to the original pending record.
  let reply = domain_test_prepare(host, scope, 16L * domain_page_bytes())
  assert_eq(reply.operation_tag(), 1)
  assert_eq(reply.issue_family(), 6)
  assert_true(physical_equal(reply.original_host(), host))
  let domain = reply.original_domain().unwrap()
  assert_true(physical_equal(domain.host, host))
  assert_eq(
    current_installed_arena_domain_reply(host, domain).issue_family(),
    1,
  )
  assert_true(
    host.project_prepared_domain(domain)
    is Err(@bootstrap.Bootstrap(@bootstrap.Unavailable)),
  )
  let material = project_installed_arena_domain_reply(host, domain)
  assert_eq(material.operation_tag(), 7)
  assert_eq(material.issue_family(), 1)
  assert_eq(material.material_scalar(0), -1L)
  assert_eq(material.material_source(), "")
  assert_eq(material.material_recipe().length(), 0)
  assert_true(host.try_close() is Err(@bootstrap.ReadersPending))
  host.leave_backing_borrow_scope(scope).unwrap()
  host.return_backing_borrow(scope).unwrap()
  assert_eq(close_installed_arena_domain_reply(host, domain).issue_family(), 0)
  assert_true(domain.closed)
  assert_eq(close_installed_arena_domain_reply(host, domain).issue_family(), 0)
  host.try_close().unwrap()
  assert_true(host.closed && host.domains.is_empty())
}

///|
test "foreign target retains actual domain host and cannot release original cleanup" {
  let host = domain_test_host()
  let other = domain_test_host()
  let scope = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(scope).unwrap()
  let domain = domain_test_prepare(host, scope, 16L * domain_page_bytes())
    .original_domain()
    .unwrap()
  let denied = close_installed_arena_domain_reply(other, domain)
  assert_eq(denied.operation_tag(), 6)
  assert_eq(denied.issue_family(), 2)
  assert_true(physical_equal(denied.original_host(), host))
  assert_false(domain.closed)
  assert_true(
    other.project_prepared_domain(domain)
    is Err(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal)),
  )
  let material = project_installed_arena_domain_reply(other, domain)
  assert_true(physical_equal(material.original_host(), host))
  assert_true(
    material.original_domain() is Some(value) && physical_equal(value, domain),
  )
  assert_eq(material.issue_family(), 2)
  assert_eq(material.material_scalar(0), -1L)
  host.leave_backing_borrow_scope(scope).unwrap()
  host.return_backing_borrow(scope).unwrap()
  assert_eq(close_installed_arena_domain_reply(host, domain).issue_family(), 0)
  host.try_close().unwrap()
  other.try_close().unwrap()
}

///|
test "material getters preserve exact Int64 DATA and never infer empty material" {
  let host = domain_test_host()
  let reply : InstalledArenaDomainReply = {
    operation: ProjectDomain,
    host,
    domain: None,
    issue: None,
    material: Some({
      extent: {
        source: "0123456789012345678901234567890123456789",
        recipe: Bytes::make(32, 31),
        generation: 9007199254740993L,
        device: 2L,
        inode: 3L,
        capacity: 4L,
        mapping_offset: 5L,
        mapping_length: 6L,
        payload_offset: 7L,
        payload_length: 8L,
        writable: true,
      },
      limits: {
        planning_work: 9,
        attempts: 10,
        holdings: 11,
        transfer_bytes: 12L,
        retained_bytes: 0L,
        execution_bytes: 14L,
      },
    }),
  }
  // Getter-only fixture, deliberately not a valid prepared loan or permit.
  let expected = [
    9007199254740993L, 2L, 3L, 4L, 5L, 6L, 7L, 8L, 1L, 9L, 10L, 11L, 12L, 0L, 14L,
  ]
  for index = 0; index < expected.length(); index = index + 1 {
    assert_eq(reply.material_scalar(index), expected[index])
  }
  assert_eq(reply.material_scalar(-1), -1L)
  assert_eq(reply.material_scalar(15), -1L)
  assert_eq(reply.material_source(), "0123456789012345678901234567890123456789")
  assert_eq(reply.material_recipe(), Bytes::make(32, 31))
  host.try_close().unwrap()
}

///|
test "pre-reservation domain refusal never fabricates a domain handle" {
  let host = domain_test_host()
  let scope = host.borrow_backing().unwrap()
  let reply = domain_test_prepare(host, scope, 0L)
  assert_eq(reply.operation_tag(), 1)
  assert_eq(reply.issue_family(), 1)
  assert_true(reply.original_domain() is None)
  assert_eq(host.domains.length(), 0)
  host.return_backing_borrow(scope).unwrap()
  host.try_close().unwrap()
}

///|
test "foreign backing scope is refused before domain record registration" {
  let host = domain_test_host()
  let other = domain_test_host()
  let scope = other.borrow_backing().unwrap()
  let reply = domain_test_prepare(host, scope, 16L * domain_page_bytes())
  assert_eq(reply.issue_family(), 2)
  assert_true(reply.original_domain() is None)
  assert_eq(host.domains.length(), 0)
  other.return_backing_borrow(scope).unwrap()
  host.try_close().unwrap()
  other.try_close().unwrap()
}
