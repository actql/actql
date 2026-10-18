///|
// Actual selected provider/components are required. The existing Runtime
// conformance declarations are unchanged; this is not an installer profile.
test "actual original Host pair binds Crypto and retains separate Library Read and domain ACKs" {
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
  ).unwrap()
  host.acquire_fd(descriptor).unwrap()
  let backing = host.borrow_backing().unwrap()
  host.enter_backing_borrow_scope(backing).unwrap()
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
    .unwrap() {
    PreparedDomain(value) => value
    PendingDomain(_, _) => fail("phase=Read domain Pending")
  }
  host.transfer_domain(read_domain).unwrap()
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
    .unwrap() {
    PreparedDomain(value) => value
    PendingDomain(_, _) => fail("phase=SQLite domain Pending")
  }
  host.transfer_domain(sqlite_domain).unwrap()
  host.leave_backing_borrow_scope(backing).unwrap()
  host.return_backing_borrow(backing).unwrap()
  host.prepare_domain_read(read_domain).unwrap()
  host.prepare_domain_read(sqlite_domain).unwrap()
  let read = match
    host
    .prepare_domain_original_read(read_domain, {
      bootstrap_retained: 16L * page,
      bootstrap_execution: 16L * page,
      workspace_execution: 4096L * page,
      read_retained: 16L * page,
      read_execution: 1024L * page,
    })
    .unwrap() {
    ReadyOriginalRead(value) => value
    PendingOriginalRead(_, _) => fail("phase=original Read Pending")
  }
  let sqlite = match
    host
    .prepare_sqlite_library(sqlite_domain, sqlite_path, 32L * page, 128)
    .unwrap() {
    ReadySqlite(value) => value
    PendingSqlite(_, _) => fail("phase=SQLite Library Pending")
  }
  let pair = host.bind_local_host_resources(read, sqlite).unwrap()
  let consumer = host
    .prepare_domain_original_read_consumer(read, 16L * page, 1024L * page)
    .unwrap()
  host.enter_local_host_phase(pair, HostRead).unwrap()
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
  assert_true(read_domain.crypto_component is None)
  let component = match
    host
    .prepare_local_host_read_crypto(pair, read, crypto_path, 32L * page, 128)
    .unwrap() {
    ReadyCrypto(value) => value
    PendingCrypto(_, _) => fail("phase=original Crypto Pending")
  }
  let original = host.current_crypto_component(component).unwrap()
  let outer = match original.new_library().unwrap() {
    @signature.ReadyCryptoLibrary(value) => value
    @signature.PendingCryptoLibrary(_, _) => fail("phase=outer Library Pending")
  }
  let inner = match original.new_library().unwrap() {
    @signature.ReadyCryptoLibrary(value) => value
    @signature.PendingCryptoLibrary(_, _) => fail("phase=inner Library Pending")
  }
  let key = @utf8.encode("key")
  let data = @utf8.encode("The quick brown fox jumps over the lazy dog")
  let digest = inner.hmac_sha256(key, data).unwrap()
  assert_eq(
    digest.to_unchecked_hex(),
    "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8",
  )
  assert_true(outer.verify_hmac_sha256(key, data, digest).unwrap())
  host.leave_local_host_phase(pair).unwrap()
  host.enter_local_host_phase(pair, HostSqlite).unwrap()
  assert_true(inner.hmac_sha256(key, data) is Err(_))
  host.leave_local_host_phase(pair).unwrap()
  host.enter_local_host_phase(pair, HostRead).unwrap()
  assert_true(host.close_domain_original_read(read) is Err(_))
  assert_true(
    host.close_crypto_component(component)
    is Err(Signature(@signature.CleanupPending)),
  )
  assert_false(component.closed || read.closed || read.closing)
  inner.close_checked().unwrap()
  outer.close_checked().unwrap()
  host.close_crypto_component(component).unwrap()
  assert_true(component.closed && component.component is None)
  host.leave_local_host_phase(pair).unwrap()
  assert_true(consumer.scope == ConsumerScopeLeft)
  host.close_local_host_resources(pair).unwrap()
  assert_true(pair.closed && read.closed && sqlite.closed)
  host.close_domain_after_owner_ack(read_domain).unwrap()
  host.close_domain_after_owner_ack(sqlite_domain).unwrap()
  host.try_close().unwrap()
  assert_eq(process_test_close(descriptor), 0)
}
