///|
fn[T, E] Result::crypto_pair_value(
  self : Result[T, E],
  stage : String,
) -> T raise {
  match self {
    Ok(value) => value
    Err(_) => fail(stage)
  }
}

///|
// Actual selected provider/components are required. The existing Runtime
// conformance declarations are unchanged; this is not an installer profile.
fn local_host_crypto_physical_case(retain_closed : Bool) -> Unit raise {
  let root = @env.get_env_var("ACTQL_TEST_INSTALLED_PROCESS_ROOT").unwrap()
  let crypto_path = @env.get_env_var("ACTQL_TEST_CRYPTO_COMPONENT").unwrap()
  let sqlite_path = @env.get_env_var("ACTQL_TEST_SQLITE_COMPONENT").unwrap()
  let page = domain_page_bytes()
  let descriptor = process_test_open(@utf8.encode(root + "/backing\u{0}"), 2)
  assert_true(descriptor >= 0)
  let host = prepare_installed_arena_host(
    "0123456789012345678901234567890123456789",
    Bytes::make(32, 17),
    1L,
    8192L * page,
    {
      planning_work: 20,
      attempts: 8,
      holdings: 4,
      transfer_bytes: 30L,
      retained_bytes: 0L,
      execution_bytes: 8192L * page,
    },
    65536L,
  ).crypto_pair_value("original operation 1")
  host.acquire_fd(descriptor).crypto_pair_value("original operation 2")
  let backing = host.borrow_backing().crypto_pair_value("original operation 3")
  host
  .enter_backing_borrow_scope(backing)
  .crypto_pair_value("original operation 4")
  let read_domain = match
    host
    .prepare_domain(backing, descriptor, 7168L * page, {
      planning_work: 2,
      attempts: 2,
      holdings: 2,
      transfer_bytes: 3L,
      retained_bytes: 32L * page,
      execution_bytes: 6144L * page,
    })
    .crypto_pair_value("original operation 5") {
    PreparedDomain(value) => value
    PendingDomain(_, _) => fail("phase=Read domain Pending")
  }
  host.transfer_domain(read_domain).crypto_pair_value("original operation 6")
  let sqlite_domain = match
    host
    .prepare_domain(backing, descriptor, 48L * page, {
      planning_work: 2,
      attempts: 2,
      holdings: 1,
      transfer_bytes: 3L,
      retained_bytes: 0L,
      execution_bytes: 48L * page,
    })
    .crypto_pair_value("original operation 7") {
    PreparedDomain(value) => value
    PendingDomain(_, _) => fail("phase=SQLite domain Pending")
  }
  host.transfer_domain(sqlite_domain).crypto_pair_value("original operation 8")
  host
  .leave_backing_borrow_scope(backing)
  .crypto_pair_value("original operation 9")
  host.return_backing_borrow(backing).crypto_pair_value("original operation 10")
  host
  .prepare_domain_read(read_domain)
  .crypto_pair_value("original operation 11")
  host
  .prepare_domain_read(sqlite_domain)
  .crypto_pair_value("original operation 12")
  let read = match
    host
    .prepare_domain_original_read(read_domain, {
      bootstrap_retained: 16L * page,
      bootstrap_execution: 16L * page,
      workspace_execution: 4096L * page,
      read_retained: 16L * page,
      read_execution: 1024L * page,
    })
    .crypto_pair_value("original operation 13") {
    ReadyOriginalRead(value) => value
    PendingOriginalRead(_, _) => fail("phase=original Read Pending")
  }
  let sqlite = match
    host
    .prepare_sqlite_library(sqlite_domain, sqlite_path, 32L * page, 128)
    .crypto_pair_value("original operation 14") {
    ReadySqlite(value) => value
    PendingSqlite(_, _) => fail("phase=SQLite Library Pending")
  }
  let pair = host
    .bind_local_host_resources(read, sqlite)
    .crypto_pair_value("original operation 15")
  let consumer = host
    .prepare_domain_original_read_consumer(read, 16L * page, 1024L * page)
    .crypto_pair_value("original operation 16")
  // A different actual entered context must not become the registration's
  // allocator merely because the pair's logical phase is still empty.
  host
  .enter_domain_read(sqlite_domain)
  .crypto_pair_value("foreign physical Read entry")
  assert_true(
    host.prepare_local_host_read_crypto_control(pair, read)
    is Err(Crypto(Domain(@bootstrap.Bootstrap(@bootstrap.Physical(-1))))),
  )
  assert_true(read_domain.crypto_component is None && pair.active is None)
  host
  .leave_domain_read(sqlite_domain)
  .crypto_pair_value("foreign physical Read leave")
  let foreign = domain_test_host()
  let control = host
    .prepare_local_host_read_crypto_control(pair, read)
    .crypto_pair_value("original outer control registration")
  let retained : Ref[@signature.OriginalCryptoComponent?] = Ref(None)
  assert_false(control.attempted || control.closed)
  assert_true(
    foreign.close_crypto_component(control)
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
  )
  assert_true(
    host.close_crypto_component({ ..control, })
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
  )
  foreign.try_close().crypto_pair_value("foreign unacquired cleanup")
  assert_true(host.prepare_local_host_read_crypto_control(pair, read) is Err(_))
  host
  .enter_local_host_phase(pair, HostRead)
  .crypto_pair_value("original operation 17")
  assert_true(host.prepare_local_host_read_crypto_control(pair, read) is Err(_))
  assert_true(
    host.prepare_local_host_read_crypto(
      pair,
      read,
      crypto_path,
      1024L * page + 1L,
      128,
    )
    is Err(
      Resources(Read(Read(@resources.Resource(@resources.ExecutionLimit))))
    ),
  )
  assert_true(
    read_domain.crypto_component is Some(original) &&
    physical_equal(original, control) &&
    !control.attempted,
  )
  let component = match
    host
    .prepare_local_host_read_crypto(pair, read, crypto_path, 32L * page, 128)
    .crypto_pair_value("original operation 18") {
    ReadyCrypto(value) => value
    PendingCrypto(_, _) => fail("phase=original Crypto Pending")
  }
  assert_true(physical_equal(control, component) && component.attempted)
  assert_true(
    host.prepare_local_host_read_crypto(
      pair,
      read,
      crypto_path,
      32L * page,
      128,
    )
    is Err(Crypto(Domain(@bootstrap.Bootstrap(@bootstrap.AlreadyConsumed)))),
  )
  let original = host
    .current_crypto_component(component)
    .crypto_pair_value("original operation 19")
  if retain_closed {
    retained.val = Some(original)
  }
  let outer = match
    original.new_library().crypto_pair_value("original operation 20") {
    @signature.ReadyCryptoLibrary(value) => value
    @signature.PendingCryptoLibrary(_, _) => fail("phase=outer Library Pending")
  }
  let inner = match
    original.new_library().crypto_pair_value("original operation 21") {
    @signature.ReadyCryptoLibrary(value) => value
    @signature.PendingCryptoLibrary(_, _) => fail("phase=inner Library Pending")
  }
  let key = @utf8.encode("key")
  let data = @utf8.encode("The quick brown fox jumps over the lazy dog")
  let digest = inner
    .hmac_sha256(key, data)
    .crypto_pair_value("original operation 22")
  assert_eq(
    digest,
    Bytes::from_array([
      0xf7, 0xbc, 0x83, 0xf4, 0x30, 0x53, 0x84, 0x24, 0xb1, 0x32, 0x98, 0xe6, 0xaa,
      0x6f, 0xb1, 0x43, 0xef, 0x4d, 0x59, 0xa1, 0x49, 0x46, 0x17, 0x59, 0x97, 0x47,
      0x9d, 0xbc, 0x2d, 0x1a, 0x3c, 0xd8,
    ]),
  )
  assert_true(
    outer
    .verify_hmac_sha256(key, data, digest)
    .crypto_pair_value("original operation 23"),
  )
  host.leave_local_host_phase(pair).crypto_pair_value("original operation 24")
  host
  .enter_local_host_phase(pair, HostSqlite)
  .crypto_pair_value("original operation 25")
  assert_true(inner.hmac_sha256(key, data) is Err(_))
  host.leave_local_host_phase(pair).crypto_pair_value("original operation 26")
  host
  .enter_local_host_phase(pair, HostRead)
  .crypto_pair_value("original operation 27")
  assert_true(host.close_domain_original_read(read) is Err(_))
  assert_true(
    host.close_crypto_component(component)
    is Err(Signature(@signature.CleanupPending)),
  )
  assert_false(component.closed || read.closed || read.closing)
  inner.close_checked().crypto_pair_value("original operation 28")
  outer.close_checked().crypto_pair_value("original operation 29")
  host
  .close_crypto_component(component)
  .crypto_pair_value("original operation 30")
  assert_true(component.closed && component.component is None)
  assert_true(
    host.close_crypto_component({ ..component, })
    is Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
  )
  host
  .close_crypto_component(control)
  .crypto_pair_value("original repeated closed cleanup")
  original
  .close_checked()
  .crypto_pair_value("original closed physical carrier cleanup")
  host.leave_local_host_phase(pair).crypto_pair_value("original operation 31")
  assert_true(consumer.scope == ConsumerScopeLeft)
  if retain_closed {
    assert_true(
      host.close_local_host_resources(pair)
      is Err(Read(Domain(@bootstrap.Bootstrap(@bootstrap.Physical(-3))))),
    )
    assert_false(read.closed || pair.closed)
    retained.val = None
  }
  match host.close_local_host_resources(pair) {
    Ok(_) => ()
    Err(Read(Domain(issue))) => fail("Read domain: " + @debug.to_string(issue))
    Err(Read(Read(issue))) => fail("Read resource: " + @debug.to_string(issue))
    Err(Domain(issue)) => fail("pair domain: " + @debug.to_string(issue))
    Err(Sqlite(Domain(issue))) =>
      fail("SQLite domain: " + @debug.to_string(issue))
    Err(_) => fail("original operation 32: other original issue")
  }
  assert_true(pair.closed && read.closed && sqlite.closed)
  host
  .close_domain_after_owner_ack(read_domain)
  .crypto_pair_value("original operation 33")
  host
  .close_domain_after_owner_ack(sqlite_domain)
  .crypto_pair_value("original operation 34")
  host.try_close().crypto_pair_value("original operation 35")
  assert_eq(process_test_close(descriptor), 0)
}

///|
test "actual original pair Crypto closes with no external closed carrier alias" {
  local_host_crypto_physical_case(false)
}

///|
test "actual original pair keeps a closed physical Crypto carrier alias busy until release" {
  local_host_crypto_physical_case(true)
}
